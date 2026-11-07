import SlopKit
import AppKit
import SnapperCore
import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(model: model)
        model.canvas = view
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.needsDisplay = true
    }
}

/// The drawing surface: shows the capture fitted to the window and turns mouse drags into
/// annotations. Flipped, so view and image coordinates both run top-down.
@MainActor
final class CanvasView: NSView, NSTextFieldDelegate {
    static let padding: CGFloat = 24
    private unowned let model: EditorModel

    private enum Drag {
        case drawing(UUID, start: CGPoint)
        case moving(UUID, last: CGPoint)
        case handle(UUID, Annotation.Handle)
        case cropNew(start: CGPoint)
        case cropMove(start: CGPoint, original: CGRect)
        case cropHandle(Annotation.Handle, original: CGRect)
    }

    private var drag: Drag?
    /// The crop being dragged (image points), applied on mouse up.
    private var cropDraft: CGRect?
    private(set) var editingField: NSTextField?
    private var editingID: UUID?
    /// A small view at the top-right for anchoring the share menu.
    let shareAnchor = NSView(frame: .zero)

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        // macOS 14 stopped clipping views by default; a zoomed-in image must not spill
        // over the tool strip.
        clipsToBounds = true
        addSubview(shareAnchor)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Capture being annotated")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func layout() {
        super.layout()
        shareAnchor.frame = CGRect(x: bounds.maxX - 40, y: 0, width: 1, height: 1)
        positionEditingField()
        let percent = Int((zoom * 100).rounded())
        if model.zoomPercent != percent { DispatchQueue.main.async { [weak self] in self?.model.zoomPercent = percent } }
    }

    // MARK: Geometry

    private var document: AnnotationDocument { model.editor.document }

    /// The part of the image on show: everything while cropping, else the crop plus any
    /// background around it.
    private var shownRect: CGRect {
        model.tool == .crop ? document.imageBounds : document.outputRect
    }

    /// The zoom that fits the image in the padded view, never above 1:1.
    private var fitZoom: CGFloat {
        let shown = shownRect
        guard shown.width > 0, shown.height > 0 else { return 1 }
        let available = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        return max(0.05, min(1, available.width / shown.width, available.height / shown.height))
    }

    /// Set by Zoom In/Out/Actual Size; nil = zoom to fit.
    private var userZoom: CGFloat?
    /// How far a zoomed-in image is scrolled (view points).
    private var pan = CGPoint.zero

    /// View points per image point.
    private var zoom: CGFloat { userZoom ?? fitZoom }

    private var origin: CGPoint {
        let shown = shownRect, z = zoom
        let size = CGSize(width: shown.width * z, height: shown.height * z)
        func axis(_ view: CGFloat, _ content: CGFloat, _ offset: CGFloat) -> CGFloat {
            // Centered while it fits; otherwise scrolled, never past the edges.
            if content + Self.padding * 2 <= view { return ((view - content) / 2).rounded() }
            return min(Self.padding, max(view - content - Self.padding, Self.padding - offset)).rounded()
        }
        return CGPoint(x: axis(bounds.width, size.width, pan.x) - shown.minX * z,
                       y: axis(bounds.height, size.height, pan.y) - shown.minY * z)
    }

    // MARK: Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.1...8

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func zoomToActualSize() { setZoom(1) }

    func zoomToFit() {
        userZoom = nil
        pan = .zero
        zoomChanged()
    }

    private func setZoom(_ value: CGFloat, keeping anchor: CGPoint? = nil) {
        let anchorView = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let anchorImage = toImage(anchorView)
        userZoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        // Keep the point under the anchor still: solve the pan for it.
        let shown = shownRect, z = zoom
        pan = CGPoint(x: Self.padding - (anchorView.x - (anchorImage.x - shown.minX) * z),
                      y: Self.padding - (anchorView.y - (anchorImage.y - shown.minY) * z))
        zoomChanged()
    }

    private func zoomChanged() {
        needsLayout = true
        positionEditingField()
        needsDisplay = true
        model.zoomPercent = Int((zoom * 100).rounded())
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoom * (1 + event.magnification), keeping: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            setZoom(zoom * (event.scrollingDeltaY > 0 ? 1.06 : 1 / 1.06), keeping: convert(event.locationInWindow, from: nil))
            return
        }
        guard userZoom != nil else { return }
        pan.x -= event.scrollingDeltaX
        pan.y -= event.scrollingDeltaY
        let shown = shownRect, z = zoom
        pan.x = min(max(pan.x, 0), max(0, shown.width * z + Self.padding * 2 - bounds.width))
        pan.y = min(max(pan.y, 0), max(0, shown.height * z + Self.padding * 2 - bounds.height))
        positionEditingField()
        needsDisplay = true
    }

    private func toImage(_ point: CGPoint) -> CGPoint {
        let o = origin, z = zoom
        return CGPoint(x: (point.x - o.x) / z, y: (point.y - o.y) / z)
    }

    private func toView(_ point: CGPoint) -> CGPoint {
        let o = origin, z = zoom
        return CGPoint(x: point.x * z + o.x, y: point.y * z + o.y)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        let a = toView(rect.origin)
        return CGRect(x: a.x, y: a.y, width: rect.width * zoom, height: rect.height * zoom)
    }

    /// Hit slop in image points (a constant size on screen).
    private var tolerance: CGFloat { 6 / zoom }

    // MARK: Drawing

    /// Handle fill: the overlay palette's light (paper) colour made opaque, so the handle
    /// reads as solid over any capture without being a drawn pure white.
    private static let handleFill: CGColor = {
        let paper = OverlayPalette.paper
        return (paper.withAlphaComponent(1).usingColorSpace(.sRGB) ?? paper).cgColor
    }()

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let shown = shownRect
        let z = zoom, o = origin

        context.saveGState()
        context.translateBy(x: o.x, y: o.y)
        context.scaleBy(x: z, y: z)
        context.clip(to: shown)
        context.interpolationQuality = z < 1 ? .high : .none
        if model.tool == .crop {
            model.renderer.draw(document, in: context, skipping: editingID)
        } else {
            model.renderer.drawComposed(document, in: context, skipping: editingID)
        }
        context.restoreGState()

        if model.tool == .crop {
            drawCropOverlay(in: context)
        } else if let selected = model.editor.selected, selected.id != editingID {
            drawSelection(selected, in: context)
        }
    }

    private func drawSelection(_ annotation: Annotation, in context: CGContext) {
        // Whole points plus half a point: the 1 pt dashed line lands exactly on two device pixels.
        let box = toView(annotation.bounds()).insetBy(dx: -Spacing.xs, dy: -Spacing.xs).integral.insetBy(dx: 0.5, dy: 0.5)
        context.saveGState()
        context.setStrokeColor(selectionColor.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(box)
        context.restoreGState()
        for handle in annotation.handles {
            drawHandle(at: toView(annotation.position(of: handle)), in: context)
        }
    }

    /// The selection's colour: the accent in the key window, grey in a background one
    /// (Golden Gate greys selections in windows you aren't using).
    private var selectionColor: NSColor {
        window?.isKeyWindow == false ? .systemGray : .controlAccentColor
    }

    /// A round light handle with a ring and a soft shadow, snapped to the pixel grid so its
    /// ring stays crisp at any zoom. It sits on the capture (any colours), so it uses the
    /// overlay palette rather than the window's appearance.
    private func drawHandle(at point: CGPoint, in context: CGContext) {
        let scale = window?.backingScaleFactor ?? 2
        let snapped = CGPoint(x: (point.x * scale).rounded() / scale, y: (point.y * scale).rounded() / scale)
        let side: CGFloat = 9
        let rect = CGRect(x: snapped.x - side / 2, y: snapped.y - side / 2, width: side, height: side)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 2, color: OverlayPalette.ink.withAlphaComponent(0.4).cgColor)
        context.setFillColor(Self.handleFill)
        context.fillEllipse(in: rect)
        context.restoreGState()
        context.setStrokeColor(selectionColor.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))
    }

    private var currentCrop: CGRect { cropDraft ?? document.crop ?? document.imageBounds }

    private func drawCropOverlay(in context: CGContext) {
        let image = toView(document.imageBounds)
        let crop = toView(currentCrop)
        context.saveGState()
        let path = CGMutablePath()
        path.addRect(image)
        path.addRect(crop)
        context.addPath(path)
        // Over the capture's own colours: the overlay palette (the same in light and dark).
        context.setFillColor(OverlayPalette.ink.withAlphaComponent(0.55).cgColor)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(OverlayPalette.ring)
        context.setLineWidth(1)
        context.stroke(crop.insetBy(dx: 0.5, dy: 0.5))
        // Thirds, to help framing.
        context.setStrokeColor(OverlayPalette.paper.withAlphaComponent(0.3).cgColor)
        for i in 1...2 {
            let x = crop.minX + crop.width * CGFloat(i) / 3, y = crop.minY + crop.height * CGFloat(i) / 3
            context.strokeLineSegments(between: [CGPoint(x: x, y: crop.minY), CGPoint(x: x, y: crop.maxY),
                                                 CGPoint(x: crop.minX, y: y), CGPoint(x: crop.maxX, y: y)])
        }
        context.restoreGState()
        for corner in [CGPoint(x: crop.minX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.minY),
                       CGPoint(x: crop.minX, y: crop.maxY), CGPoint(x: crop.maxX, y: crop.maxY)] {
            drawHandle(at: corner, in: context)
        }
        let label = "\(Int((currentCrop.width * model.item.scale).rounded())) × \(Int((currentCrop.height * model.item.scale).rounded())) px — Return to apply"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .medium),
            .foregroundColor: NSColor(cgColor: OverlayPalette.badgeText) ?? OverlayPalette.paper,
        ]
        // The same dark badge as the capture overlay's size readout: `Spacing.s` at the
        // sides, `Spacing.xs` above and below, `Spacing.s` under the crop.
        let size = (label as NSString).size(withAttributes: attributes)
        let badgeSize = CGSize(width: ceil(size.width) + 2 * Spacing.s, height: ceil(size.height) + 2 * Spacing.xs)
        let badge = CGRect(x: crop.minX, y: max(crop.minY - badgeSize.height - Spacing.s, Spacing.xs), width: badgeSize.width, height: badgeSize.height)
        context.setFillColor(OverlayPalette.badgeFill)
        context.addPath(CGPath(roundedRect: badge, cornerWidth: Radius.s, cornerHeight: Radius.s, transform: nil))
        context.fillPath()
        (label as NSString).draw(at: CGPoint(x: badge.minX + Spacing.s, y: badge.minY + Spacing.xs), withAttributes: attributes)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if editingField != nil {
            endTextEditing()
            return
        }
        let p = toImage(convert(event.locationInWindow, from: nil))

        if model.tool == .crop {
            beginCropDrag(at: p)
            return
        }

        // A handle of the selected annotation?
        if let selected = model.editor.selected,
           let handle = selected.handles.first(where: { hypot(selected.position(of: $0).x - p.x, selected.position(of: $0).y - p.y) <= tolerance + 2 / zoom }) {
            model.editor.beginChange()
            drag = .handle(selected.id, handle)
            return
        }

        // An existing annotation?
        if let hit = model.editor.hit(p, tolerance: tolerance, loose: model.tool == .select) {
            if hit.kind == .text, model.tool == .text || event.clickCount == 2 {
                beginTextEditing(existing: hit, at: p)
                return
            }
            model.editor.selection = hit.id
            model.editor.beginChange()
            drag = .moving(hit.id, last: p)
            needsDisplay = true
            return
        }

        model.editor.selection = nil
        guard document.imageBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) || model.tool == .select else {
            needsDisplay = true
            return
        }
        switch model.tool {
        case .select, .crop:
            needsDisplay = true
        case .text:
            beginTextEditing(existing: nil, at: p)
        case .counter:
            model.editor.add(Annotation(kind: .counter, start: p, color: model.color.color, width: model.width.points))
            model.changed()
        default:
            guard let kind = model.drawingKind else { return }
            model.editor.beginChange()
            let annotation = Annotation(kind: kind, start: p, end: p, points: kind.isFreehand ? [p] : [],
                                        color: model.color.color, width: model.width.points)
            model.editor.add(annotation)
            drag = .drawing(annotation.id, start: p)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = toImage(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .drawing(let id, let start):
            guard var annotation = document.annotations.first(where: { $0.id == id }) else { return }
            if annotation.kind.isFreehand {
                if shift {
                    annotation.points = [start, Annotation.constrained(start: start, end: p, kind: .line)]
                } else {
                    annotation.points.append(p)
                }
                annotation.end = p
            } else {
                annotation.end = shift ? Annotation.constrained(start: start, end: p, kind: annotation.kind) : p
            }
            model.editor.update(annotation)
        case .moving(let id, let last):
            guard let annotation = document.annotations.first(where: { $0.id == id }) else { return }
            model.editor.update(annotation.moved(by: CGVector(dx: p.x - last.x, dy: p.y - last.y)))
            self.drag = .moving(id, last: p)
        case .handle(let id, let handle):
            guard let annotation = document.annotations.first(where: { $0.id == id }) else { return }
            model.editor.update(annotation.moving(handle, to: p))
        case .cropNew(let start):
            cropDraft = SelectionGeometry.snapped(CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                                                        width: abs(p.x - start.x), height: abs(p.y - start.y)))
                .intersection(document.imageBounds)
        case .cropMove(let start, let original):
            cropDraft = SelectionGeometry.moved(original, by: CGVector(dx: (p.x - start.x).rounded(), dy: (p.y - start.y).rounded()),
                                                within: document.imageBounds)
        case .cropHandle(let handle, let original):
            let box = Annotation(kind: .rectangle, start: original.origin, end: CGPoint(x: original.maxX, y: original.maxY))
            cropDraft = SelectionGeometry.snapped(box.moving(handle, to: p).rect).intersection(document.imageBounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        switch drag {
        case .drawing(let id, _):
            if document.annotations.first(where: { $0.id == id })?.isEmpty ?? true {
                model.editor.cancelChange()
                model.editor.selection = nil
            } else {
                if var stroke = document.annotations.first(where: { $0.id == id }), stroke.kind.isFreehand {
                    stroke.points = Freehand.thinned(stroke.points)
                    model.editor.update(stroke)
                }
                model.editor.commitChange()
            }
        case .moving, .handle:
            model.editor.commitChange()
        case .cropNew, .cropMove, .cropHandle:
            if let cropDraft, cropDraft.width >= 4, cropDraft.height >= 4 {
                model.editor.setCrop(cropDraft)
            }
            cropDraft = nil
        }
        model.changed()
    }

    private func beginCropDrag(at p: CGPoint) {
        let crop = currentCrop
        let corners: [(Annotation.Handle, CGPoint)] = [
            (.topLeft, CGPoint(x: crop.minX, y: crop.minY)), (.topRight, CGPoint(x: crop.maxX, y: crop.minY)),
            (.bottomLeft, CGPoint(x: crop.minX, y: crop.maxY)), (.bottomRight, CGPoint(x: crop.maxX, y: crop.maxY)),
        ]
        if let corner = corners.first(where: { hypot($0.1.x - p.x, $0.1.y - p.y) <= tolerance + 4 / zoom }) {
            drag = .cropHandle(corner.0, original: crop)
        } else if crop.contains(p), document.crop != nil {
            drag = .cropMove(start: p, original: crop)
        } else {
            drag = .cropNew(start: p)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at viewPoint: CGPoint) {
        let p = toImage(viewPoint)
        if model.tool == .select || model.editor.hit(p, tolerance: tolerance, loose: false) != nil {
            NSCursor.arrow.set()
        } else if model.tool == .text {
            NSCursor.iBeam.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 53: // Esc
            if model.tool == .crop {
                model.tool = .select
            } else if model.editor.selection != nil {
                model.editor.selection = nil
                needsDisplay = true
            }
            return
        case 36, 76: // Return
            if model.tool == .crop { model.tool = .select }
            return
        case 51, 117: // Delete
            model.deleteSelection()
            return
        default:
            break
        }
        if let arrow = ArrowKey(keyCode: event.keyCode), flags.subtracting(.shift).isEmpty, model.editor.selection != nil {
            let delta = SelectionGeometry.nudge(for: arrow, large: flags.contains(.shift))
            // Image y runs down; the nudge is in screen terms (up = +y).
            model.editor.moveSelection(by: CGVector(dx: delta.dx, dy: -delta.dy))
            model.changed()
            return
        }
        if flags.isEmpty, let char = event.charactersIgnoringModifiers?.first {
            if char == "b" || char == "B" { model.toggleBackground(); return }
            if let tool = Tool.forKey(char) { model.tool = tool; return }
            if char == "]" || char == "=" || char == "+" { model.stepWidth(1); return }
            if char == "[" || char == "-" { model.stepWidth(-1); return }
        }
        super.keyDown(with: event)
    }

    /// Edit ▸ Copy: the selected object (for Paste), or the whole annotated image.
    @objc func copy(_ sender: Any?) {
        model.copyObjectOrImage()
    }

    /// Edit ▸ Paste: an object copied in an editor.
    @objc func paste(_ sender: Any?) {
        model.pasteObject()
    }

    @objc func delete(_ sender: Any?) {
        model.deleteSelection()
    }

    func toolChanged(from old: Tool) {
        endTextEditing()
        if old == .crop { cropDraft = nil }
        if model.tool == .crop {
            model.editor.selection = nil
            model.showsBackground = false
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Text

    private func beginTextEditing(existing: Annotation?, at p: CGPoint) {
        model.editor.beginChange()
        let annotation: Annotation
        if let existing {
            annotation = existing
        } else {
            annotation = Annotation(kind: .text, start: CGPoint(x: p.x, y: p.y - TextMetrics.lineHeight(fontSize: model.width.fontSize) / 2),
                                    color: model.color.color, width: model.width.points)
            model.editor.add(annotation)
        }
        model.editor.selection = annotation.id
        editingID = annotation.id
        model.isEditingText = true

        let field = NSTextField(string: annotation.text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = false
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.textColor = NSColor(cgColor: annotation.color.cgColor)
        field.font = NSFont.boldSystemFont(ofSize: annotation.fontSize * zoom)
        field.delegate = self
        field.setAccessibilityLabel("Text annotation")
        addSubview(field)
        editingField = field
        positionEditingField()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: (annotation.text as NSString).length, length: 0)
        needsDisplay = true
    }

    private func positionEditingField() {
        guard let field = editingField, let id = editingID,
              let annotation = document.annotations.first(where: { $0.id == id }) else { return }
        let size = TextMetrics.size(of: annotation.text.isEmpty ? "M" : annotation.text, fontSize: annotation.fontSize)
        let origin = toView(annotation.start)
        field.font = NSFont.boldSystemFont(ofSize: annotation.fontSize * zoom)
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: max(size.width * zoom + 24, 80), height: size.height * zoom + 4)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = editingField, let id = editingID,
              var annotation = document.annotations.first(where: { $0.id == id }) else { return }
        annotation.text = field.stringValue
        model.editor.update(annotation.keptInside(document.visibleRect))
        positionEditingField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if NSEvent.modifierFlags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                endTextEditing()
            }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endTextEditing()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endTextEditing()
    }

    /// Commits the text being typed (an empty one disappears).
    func endTextEditing() {
        guard let field = editingField, let id = editingID else { return }
        editingField = nil
        editingID = nil
        field.delegate = nil
        if var annotation = document.annotations.first(where: { $0.id == id }) {
            annotation.text = field.stringValue
            if annotation.isEmpty {
                model.editor.remove(id: id)
            } else {
                model.editor.update(annotation.keptInside(document.visibleRect))
            }
        }
        model.editor.commitChange()
        field.removeFromSuperview()
        model.isEditingText = false
        window?.makeFirstResponder(self)
        model.changed()
    }
}
