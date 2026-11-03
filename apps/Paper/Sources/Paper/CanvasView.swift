import AppKit
import PDFKit
import PaperCore

@MainActor
protocol CanvasDelegate: AnyObject {
    var model: DocumentModel { get }
    var editor: DocumentEditor { get }
    func canvasSelectionChanged()
    func canvasBeginTextEditing(_ annotation: PDFAnnotation, isNew: Bool)
    func canvasEditNote(_ annotation: PDFAnnotation, isNew: Bool)
    func canvasShowSignatureMenu(at point: NSPoint)
    func canvasNeedsOverlay()
    func canvasFormMayHaveChanged()
    func canvasSetTool(_ tool: Tool)
}

/// What the overlay draws while a drag is in progress, in page space.
enum CanvasPreview {
    case box(page: PDFPage, rect: CGRect, oval: Bool)
    case marquee(page: PDFPage, rect: CGRect)
    case line(page: PDFPage, from: CGPoint, to: CGPoint, arrow: Bool)
    case ink(page: PDFPage, points: [CGPoint])
}

/// PDFView plus Paper's tools. Text selection, links, form fields and scrolling stay
/// PDFKit's; everything else (placing, selecting, moving, resizing) is handled here.
@MainActor
final class PaperPDFView: PDFView {
    weak var canvasDelegate: CanvasDelegate?
    private(set) var preview: CanvasPreview?

    private enum Drag {
        case none
        case passThrough
        case textSelection
        case move(PDFAnnotation, start: CGRect, origin: CGPoint, moved: Bool)
        case resize(PDFAnnotation, handle: Int, start: CGRect)
        case shape(PDFPage, start: CGPoint, current: CGPoint)
        case ink(PDFPage, points: [CGPoint])
        case marquee(PDFPage, start: CGPoint, current: CGPoint)
    }

    private var drag: Drag = .none
    static let handleSize: CGFloat = 8

    private var model: DocumentModel? { canvasDelegate?.model }
    private var editor: DocumentEditor? { canvasDelegate?.editor }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Hit testing

    func pagePoint(for event: NSEvent) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    /// The topmost annotation Paper can select at a point (not form fields or links).
    func editableAnnotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        let tolerance = 3 / max(scaleFactor, 0.1)
        return page.annotations.reversed().first { annotation in
            AnnotationGeometry.isEditable(annotation) && annotation.shouldDisplay
                && annotation.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    /// Whether a character is under the point. `characterIndex(at:)` alone returns the
    /// nearest character even over an image, so check that character's box too.
    func isOverText(_ point: CGPoint, on page: PDFPage) -> Bool {
        let index = page.characterIndex(at: point)
        guard index >= 0, let bounds = page.selection(for: NSRange(location: index, length: 1))?.bounds(for: page) else { return false }
        return bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    /// Corner handles of the selected annotation in view coordinates.
    func handleRects(for annotation: PDFAnnotation) -> [NSRect] {
        guard let page = annotation.page else { return [] }
        let rect = convert(annotation.bounds, from: page)
        let size = Self.handleSize
        // Order matches AnnotationGeometry.dragging: bottom-left, bottom-right, top-left, top-right.
        return [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
                NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)]
            .map { NSRect(x: $0.x - size / 2, y: $0.y - size / 2, width: size, height: size) }
    }

    // MARK: Mouse
    //
    // PDFKit's own document view receives clicks on the page, so PDFView's mouseDown isn't
    // called, and AppKit's split view and title bar click recognizers delay quick clicks to
    // sibling views. So the window's event monitor asks `claims(_:)` on mouse-down and, when a
    // tool needs the click, sends the whole down/drag/up sequence here. Everything else (text
    // selection, links, form fields) reaches PDFKit untouched.

    /// Whether the overlay should take a click at `viewPoint` (PDFView coordinates).
    func claims(_ viewPoint: NSPoint) -> Bool {
        guard let model, !model.isLocked, let page = page(for: viewPoint, nearest: false) else { return false }
        let point = convert(viewPoint, to: page)
        switch model.isReadOnly ? .select : model.tool {
        case .select:
            if let selected = model.selectedAnnotation, selected.page != nil, !model.isReadOnly, AnnotationGeometry.isResizable(selected),
               handleRects(for: selected).contains(where: { $0.insetBy(dx: -3, dy: -3).contains(viewPoint) }) {
                return true
            }
            return editableAnnotation(at: point, on: page) != nil
        case .highlight:
            return false
        case .redact:
            return !isOverText(point, on: page)
        case .draw, .shape, .text, .note, .sign:
            return true
        }
    }

    func toolMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let model, let (page, point) = pagePoint(for: event) else { return }
        let tool = model.isReadOnly ? .select : model.tool
        switch tool {
        case .select:
            mouseDownSelecting(event, page: page, point: point)
        case .highlight:
            drag = .none
        case .redact:
            select(nil)
            drag = .marquee(page, start: point, current: point)
        case .draw:
            select(nil)
            drag = .ink(page, points: [point])
        case .shape:
            select(nil)
            drag = .shape(page, start: point, current: point)
        case .text:
            select(nil)
            drag = .none
            createTextBox(on: page, at: point)
        case .note:
            select(nil)
            drag = .none
            guard let editor else { return }
            let note = model.authorFactory.note("", at: point)
            editor.add(note, to: page, name: "Add Note")
            canvasDelegate?.canvasEditNote(note, isNew: true)
        case .sign:
            select(nil)
            drag = .none
            if let signature = model.pendingSignature {
                placeSignature(signature, on: page, at: point)
            } else {
                canvasDelegate?.canvasShowSignatureMenu(at: convert(event.locationInWindow, from: nil))
            }
        }
        updatePreview()
    }

    private func mouseDownSelecting(_ event: NSEvent, page: PDFPage, point: CGPoint) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        defer { Self.debug("select down at \(viewPoint) handles=\(model?.selectedAnnotation.map { handleRects(for: $0).map { NSStringFromRect($0) } } ?? []) drag=\(drag)") }
        if let selected = model?.selectedAnnotation, selected.page != nil, !(model?.isReadOnly ?? true),
           AnnotationGeometry.isResizable(selected),
           let handle = handleRects(for: selected).firstIndex(where: { $0.insetBy(dx: -3, dy: -3).contains(viewPoint) }) {
            drag = .resize(selected, handle: handle, start: selected.bounds)
            return
        }
        if let annotation = editableAnnotation(at: point, on: page) {
            if event.clickCount >= 2 {
                drag = .none
                if annotation.type == "FreeText" { canvasDelegate?.canvasBeginTextEditing(annotation, isNew: false) }
                if annotation.type == "Text" { canvasDelegate?.canvasEditNote(annotation, isNew: false) }
                return
            }
            select(annotation)
            setCurrentSelection(nil, animate: false)
            drag = model?.isReadOnly == true ? .none : .move(annotation, start: annotation.bounds, origin: point, moved: false)
            return
        }
        select(nil)
        drag = .none
    }

    static let debugEvents = ProcessInfo.processInfo.environment["PAPER_DEBUG_EVENTS"] != nil
    static func debug(_ message: @autoclosure () -> String) {
        guard debugEvents else { return }
        debugLine(message())
    }

    nonisolated static func debugLine(_ message: String) {
        guard ProcessInfo.processInfo.environment["PAPER_DEBUG_EVENTS"] != nil else { return }
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paper-events.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    func toolMouseDragged(with event: NSEvent) {
        guard let (page, rawPoint) = pagePoint(for: event) else { return }
        switch drag {
        case .none, .passThrough, .textSelection:
            return
        case .move(let annotation, let start, let origin, _):
            guard let annotationPage = annotation.page else { return }
            let point = annotationPage === page ? rawPoint : convert(convert(event.locationInWindow, from: nil), to: annotationPage)
            AnnotationGeometry.move(annotation, by: CGVector(dx: point.x - origin.x - (annotation.bounds.minX - start.minX),
                                                             dy: point.y - origin.y - (annotation.bounds.minY - start.minY)))
            drag = .move(annotation, start: start, origin: origin, moved: true)
            annotationsChanged(on: annotationPage)
        case .resize(let annotation, let handle, let start):
            guard let annotationPage = annotation.page else { return }
            let point = convert(convert(event.locationInWindow, from: nil), to: annotationPage)
            let keepAspect = event.modifierFlags.contains(.shift) || annotation.type == "Ink"
            let target = AnnotationGeometry.dragging(handle: handle, of: start, to: point, keepAspect: keepAspect)
            AnnotationGeometry.resize(annotation, to: target)
            annotationsChanged(on: annotationPage)
        case .shape(let shapePage, let start, _):
            let point = shapePage === page ? rawPoint : convert(convert(event.locationInWindow, from: nil), to: shapePage)
            let end = event.modifierFlags.contains(.shift)
                ? AnnotationGeometry.constrained(from: start, to: point, kind: model?.shapeKind ?? .rectangle) : point
            drag = .shape(shapePage, start: start, current: end)
        case .ink(let inkPage, var points):
            let point = inkPage === page ? rawPoint : convert(convert(event.locationInWindow, from: nil), to: inkPage)
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 0.8 / max(scaleFactor, 0.1) { return }
            points.append(point)
            drag = .ink(inkPage, points: points)
        case .marquee(let markPage, let start, _):
            let point = markPage === page ? rawPoint : convert(convert(event.locationInWindow, from: nil), to: markPage)
            drag = .marquee(markPage, start: start, current: point)
        }
        updatePreview()
    }

    func toolMouseUp(with event: NSEvent) {
        let finished = drag
        drag = .none
        defer { updatePreview() }
        guard let model, let editor else { return }
        switch finished {
        case .none, .passThrough, .textSelection:
            return
        case .move(let annotation, let start, _, let moved):
            guard moved else { return }
            let end = annotation.bounds
            annotation.bounds = start
            editor.setBounds(annotation, end, name: "Move")
        case .resize(let annotation, _, let start):
            let end = annotation.bounds
            AnnotationGeometry.resize(annotation, to: start)
            editor.setBounds(annotation, end, name: "Resize")
        case .shape(let page, let start, let end):
            guard hypot(end.x - start.x, end.y - start.y) * scaleFactor > 4 else { return }
            let fill = model.fillShapes && (model.shapeKind == .rectangle || model.shapeKind == .oval)
                ? model.inkColor.nsColor.withAlphaComponent(0.25) : nil
            let shape = model.authorFactory.shape(model.shapeKind, from: start, to: end, color: model.inkColor.nsColor,
                                                  fill: fill, lineWidth: model.lineWidth)
            editor.add(shape, to: page, name: "Add \(model.shapeKind.title)")
        case .ink(let page, let points):
            guard points.count > 1,
                  let ink = model.authorFactory.ink([points], color: model.inkColor.nsColor, lineWidth: model.lineWidth)
            else { return }
            editor.add(ink, to: page, name: "Draw")
        case .marquee(let page, let start, let end):
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            guard rect.width * scaleFactor > 3, rect.height * scaleFactor > 3 else { return }
            editor.add(RedactionMarks.makeMark(bounds: rect), to: page, name: "Mark for Redaction")
        }
    }

    /// Highlight or Redact tool: the text just selected gets the tool's treatment. Called after
    /// PDFKit finishes a text drag (the window's mouse-up monitor).
    func applyToolToSelection() {
        guard let model, let editor, let selection = currentSelection,
              !(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch model.tool {
        case .highlight:
            markup(selection, style: model.markupStyle, color: model.highlightColor)
        case .redact:
            markForRedaction(selection)
        default:
            break
        }
        _ = editor
        setCurrentSelection(nil, animate: false)
    }

    func markup(_ selection: PDFSelection, style: MarkupStyle, color: InkColor) {
        guard let model, let editor else { return }
        editor.group(style.title) {
            for page in selection.pages {
                let rects = PDFSearch.lineRects(for: selection, on: page)
                guard let annotation = model.authorFactory.markup(style, color: color.nsColor, lineRects: rects) else { continue }
                editor.add(annotation, to: page, name: style.title)
            }
        }
    }

    func markForRedaction(_ selection: PDFSelection) {
        guard let editor else { return }
        editor.group("Mark for Redaction") {
            for page in selection.pages {
                for rect in PDFSearch.lineRects(for: selection, on: page) {
                    editor.add(RedactionMarks.makeMark(bounds: rect.insetBy(dx: -0.5, dy: -1)), to: page, name: "Mark for Redaction")
                }
            }
        }
    }

    private func createTextBox(on page: PDFPage, at point: CGPoint) {
        guard let model, let editor else { return }
        // The click is where the first line's baseline-ish middle goes, so the text lands on
        // the form line the person clicked.
        let font = NSFont.systemFont(ofSize: model.fontSize)
        let top = CGPoint(x: point.x - 4, y: point.y + (font.ascender - font.descender) / 2 + 3)
        let box = model.authorFactory.textBox("", topLeft: top, fontSize: model.fontSize, color: model.textColor.nsColor)
        editor.add(box, to: page, name: "Add Text Box")
        canvasDelegate?.canvasBeginTextEditing(box, isNew: true)
    }

    func placeSignature(_ signature: Signature, on page: PDFPage, at point: CGPoint) {
        guard let model, let editor else { return }
        let width: CGFloat = signature.kind == .initials ? 70 : 170
        guard let ink = signature.annotation(centeredAt: point, width: width, color: NSColor(srgbRed: 0.05, green: 0.1, blue: 0.35, alpha: 1),
                                             factory: model.authorFactory) else { return }
        editor.add(ink, to: page, name: "Add Signature")
        model.pendingSignature = nil
        canvasDelegate?.canvasSetTool(.select)
        select(ink)
    }

    func select(_ annotation: PDFAnnotation?) {
        guard let model, model.selectedAnnotation !== annotation else { return }
        model.selectedAnnotation = annotation
        canvasDelegate?.canvasNeedsOverlay()
    }

    private func updatePreview() {
        switch drag {
        case .shape(let page, let start, let end):
            let kind = model?.shapeKind ?? .rectangle
            if kind == .line || kind == .arrow {
                preview = .line(page: page, from: start, to: end, arrow: kind == .arrow)
            } else {
                preview = .box(page: page, rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                                        width: abs(end.x - start.x), height: abs(end.y - start.y)), oval: kind == .oval)
            }
        case .ink(let page, let points):
            preview = .ink(page: page, points: points)
        case .marquee(let page, let start, let end):
            preview = .marquee(page: page, rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                                        width: abs(end.x - start.x), height: abs(end.y - start.y)))
        default:
            preview = nil
        }
        canvasDelegate?.canvasNeedsOverlay()
    }

    // MARK: Cursor

    func updateCursor(for event: NSEvent) {
        guard let model, !model.isReadOnly else { return }
        switch model.tool {
        case .draw, .shape, .note, .sign:
            NSCursor.crosshair.set()
        case .text:
            NSCursor.iBeam.set()
        case .redact:
            if let (page, point) = pagePoint(for: event), !isOverText(point, on: page) { NSCursor.crosshair.set() }
        case .select, .highlight:
            break
        }
    }

    // MARK: Keyboard

    /// Keys for the canvas, called by the window's key monitor when the PDF (not a text field
    /// or a form field editor) has focus. Returns true when handled.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let model, let editor else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let characters = event.charactersIgnoringModifiers ?? ""
        if event.keyCode == 53, flags.isEmpty { // Esc
            cancelCurrent()
            return true
        }
        if characters == "v", flags.isEmpty, model.tool != .select {
            canvasDelegate?.canvasSetTool(.select)
            return true
        }
        guard let selected = model.selectedAnnotation, let page = selected.page, !model.isReadOnly,
              flags.subtracting(.shift).isEmpty else { return false }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            editor.remove(selected, from: page)
            canvasDelegate?.canvasNeedsOverlay()
            return true
        case 123, 124, 125, 126: // arrows nudge 1 pt, 10 with Shift
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            let delta: CGVector = switch event.keyCode {
            case 123: CGVector(dx: -step, dy: 0)
            case 124: CGVector(dx: step, dy: 0)
            case 125: CGVector(dx: 0, dy: -step)
            default: CGVector(dx: 0, dy: step)
            }
            editor.setBounds(selected, selected.bounds.offsetBy(dx: delta.dx, dy: delta.dy), name: "Move")
            canvasDelegate?.canvasNeedsOverlay()
            return true
        case 36, 76: // return: edit text
            if selected.type == "FreeText" { canvasDelegate?.canvasBeginTextEditing(selected, isNew: false); return true }
            if selected.type == "Text" { canvasDelegate?.canvasEditNote(selected, isNew: false); return true }
            return false
        default:
            return false
        }
    }

    /// Esc: stop a drag in progress, else leave the tool, else deselect, else clear the text
    /// selection. Tools stay active until this (or V).
    func cancelCurrent() {
        if case .none = drag {} else {
            drag = .none
            updatePreview()
            return
        }
        guard let model else { return }
        if model.tool != .select {
            canvasDelegate?.canvasSetTool(.select)
        } else if model.selectedAnnotation != nil {
            select(nil)
        } else if currentSelection != nil {
            setCurrentSelection(nil, animate: false)
            canvasDelegate?.canvasSelectionChanged()
        }
    }

    override func cancelOperation(_ sender: Any?) { cancelCurrent() }

    // MARK: Context menu

    func annotationMenu(for event: NSEvent) -> NSMenu? {
        guard let model, let (page, point) = pagePoint(for: event),
              let annotation = editableAnnotation(at: point, on: page) else {
            return nil
        }
        select(annotation)
        let menu = NSMenu()
        if annotation.type == "FreeText" {
            menu.addItem(withTitle: "Edit Text", action: #selector(PaperWindowController.editSelectedAnnotation(_:)), keyEquivalent: "")
        } else if annotation.type == "Text" {
            menu.addItem(withTitle: "Edit Note", action: #selector(PaperWindowController.editSelectedAnnotation(_:)), keyEquivalent: "")
        }
        if !RedactionMarks.isMark(annotation) {
            let colors = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for color in InkColor.allCases {
                let item = NSMenuItem(title: color.title, action: #selector(PaperWindowController.setAnnotationColor(_:)), keyEquivalent: "")
                item.representedObject = color.rawValue
                item.image = ColorSwatch.image(color.nsColor)
                submenu.addItem(item)
            }
            colors.submenu = submenu
            menu.addItem(colors)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: RedactionMarks.isMark(annotation) ? "Remove Mark" : "Delete",
                     action: #selector(PaperWindowController.deleteSelectedAnnotation(_:)), keyEquivalent: "")
        _ = model
        return menu
    }
}

/// Small color swatch images for menus.
enum ColorSwatch {
    static func image(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
        image.accessibilityDescription = "Color"
        return image
    }
}

/// Draws selection handles and in-progress shapes over the PDF view. Lets every click through.
@MainActor
final class CanvasOverlay: NSView {
    weak var pdfView: PaperPDFView?
    weak var model: DocumentModel?
    /// Form fields to tint when "Highlight Form Fields" is on.
    var fieldRects: [(PDFPage, CGRect)] = [] { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    /// Never takes clicks itself: the window's event monitor sends tool clicks to the canvas
    /// (see PaperWindowController.handleMonitored), everything else reaches PDFKit.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { pdfView?.updateCursor(for: event) }

    override func draw(_ dirtyRect: NSRect) {
        guard let pdfView, let model else { return }
        let accent = NSColor.controlAccentColor
        for (page, rect) in fieldRects {
            let local = convert(pdfView.convert(rect, from: page), from: pdfView)
            accent.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: local, xRadius: 2, yRadius: 2).fill()
            accent.withAlphaComponent(0.6).setStroke()
            NSBezierPath(roundedRect: local, xRadius: 2, yRadius: 2).stroke()
        }
        if let annotation = model.selectedAnnotation, let page = annotation.page, page.document === model.pdf {
            let rect = convert(pdfView.convert(annotation.bounds, from: page), from: pdfView)
            let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
            outline.lineWidth = 1.5
            accent.setStroke()
            outline.stroke()
            if AnnotationGeometry.isResizable(annotation), !model.isReadOnly {
                for handle in pdfView.handleRects(for: annotation) {
                    let local = convert(handle, from: pdfView)
                    let path = NSBezierPath(ovalIn: local)
                    NSColor.white.setFill()
                    path.fill()
                    path.lineWidth = 1.5
                    accent.setStroke()
                    path.stroke()
                }
            }
        }
        guard let preview = pdfView.preview else { return }
        let scale = pdfView.scaleFactor
        func point(_ p: CGPoint, _ page: PDFPage) -> NSPoint { convert(pdfView.convert(p, from: page), from: pdfView) }
        switch preview {
        case .box(let page, let rect, let oval):
            let local = convert(pdfView.convert(rect, from: page), from: pdfView)
            let path = oval ? NSBezierPath(ovalIn: local) : NSBezierPath(rect: local)
            path.lineWidth = model.lineWidth * scale
            model.inkColor.nsColor.setStroke()
            path.stroke()
        case .marquee(let page, let rect):
            let local = convert(pdfView.convert(rect, from: page), from: pdfView)
            NSColor.systemRed.withAlphaComponent(0.15).setFill()
            NSBezierPath(rect: local).fill()
            let path = NSBezierPath(rect: local)
            path.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.systemRed.setStroke()
            path.stroke()
        case .line(let page, let from, let to, let arrow):
            let path = NSBezierPath()
            let a = point(from, page), b = point(to, page)
            path.move(to: a)
            path.line(to: b)
            if arrow {
                let angle = atan2(b.y - a.y, b.x - a.x)
                let length = max(10, model.lineWidth * scale * 4)
                for side in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                    path.move(to: b)
                    path.line(to: NSPoint(x: b.x + cos(angle + side) * length, y: b.y + sin(angle + side) * length))
                }
            }
            path.lineWidth = model.lineWidth * scale
            path.lineCapStyle = .round
            model.inkColor.nsColor.setStroke()
            path.stroke()
        case .ink(let page, let points):
            let path = InkSmoothing.path(through: points.map { point($0, page) }, lineWidth: model.lineWidth * scale)
            model.inkColor.nsColor.setStroke()
            path.stroke()
        }
    }
}
