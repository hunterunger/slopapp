import AppKit
import PDFKit
import PaperCore
import SwiftUI

/// The right side of the window: info bars and the style strip on top, the PDF below,
/// with the overlay, text-box editor and selection bar floating over it.
@MainActor
final class CanvasController: NSViewController, NSTextViewDelegate, NSPopoverDelegate {
    let model: DocumentModel
    let pdfView: PaperPDFView
    weak var delegate: PaperWindowController?
    private let overlay = CanvasOverlay()
    private let pdfContainer = NSView()
    private var header: NSHostingView<CanvasHeader>!
    private var lockedHost: NSHostingView<LockedView>?
    private var selectionBar: NSHostingView<SelectionBar>?
    private var textEditor: NSTextView?
    private var editingAnnotation: PDFAnnotation?
    private var editingIsNew = false
    private var notePopover: NSPopover?
    private var scrollObserver: NSObjectProtocol?
    private var headerObserver: NSObjectProtocol?
    private var headerHeight: CGFloat = 0
    /// Set once the document is positioned; before that, bars appearing shouldn't scroll.
    var keepsContentStill = false

    init(model: DocumentModel, pdfView: PaperPDFView) {
        self.model = model
        self.pdfView = pdfView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSView()
        header = NSHostingView(rootView: CanvasHeader(model: model, actions: headerActions()))
        header.sizingOptions = [.intrinsicContentSize]
        header.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pdfContainer)
        root.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pdfContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            pdfContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pdfContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pdfContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        pdfView.frame = pdfContainer.bounds
        pdfView.autoresizingMask = [.width, .height]
        PDFViewTuning.disableAutomaticAnalysis(pdfView)
        pdfView.setAccessibilityLabel("Document")
        pdfContainer.addSubview(pdfView)
        overlay.frame = pdfContainer.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.pdfView = pdfView
        overlay.model = model
        pdfContainer.addSubview(overlay)
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if headerObserver == nil {
            header.postsFrameChangedNotifications = true
            headerHeight = header.frame.height
            headerObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: header, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.headerResized() }
            }
        }
        guard scrollObserver == nil, let clip = pdfView.documentView?.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didScroll() }
        }
    }

    /// An info bar or the style strip appeared or went away. The page area's top edge moved;
    /// scroll by the same amount so the page doesn't jump under the pointer.
    private func headerResized() {
        let delta = header.frame.height - headerHeight
        headerHeight = header.frame.height
        guard delta != 0, keepsContentStill, let scroll = pdfView.documentView?.enclosingScrollView else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        origin.y += clip.isFlipped ? delta : -delta
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }

    private func didScroll() {
        refreshOverlay()
        positionTextEditor()
        positionSelectionBar()
    }

    func refreshOverlay() {
        overlay.needsDisplay = true
        drawFieldHighlights()
    }

    private func drawFieldHighlights() {
        overlay.fieldRects = model.highlightFields ? widgetRects() : []
    }

    private func widgetRects() -> [(PDFPage, CGRect)] {
        var rects: [(PDFPage, CGRect)] = []
        for page in pdfView.visiblePages {
            for annotation in page.annotations where annotation.type == "Widget" { rects.append((page, annotation.bounds)) }
        }
        return rects
    }

    // MARK: Header actions

    private func headerActions() -> HeaderActions {
        HeaderActions(
            applyRedactions: { [weak self] in self?.delegate?.applyRedactions(nil) },
            removeMarks: { [weak self] in self?.delegate?.removeAllMarks(nil) },
            setColor: { [weak self] color in self?.applyColor(color) },
            setLineWidth: { [weak self] width in
                guard let self else { return }
                self.model.lineWidth = width
                if let annotation = self.model.selectedAnnotation { self.delegate?.editor.setLineWidth(annotation, width) }
            },
            setFontSize: { [weak self] size in
                guard let self else { return }
                self.model.fontSize = size
                if let annotation = self.model.selectedAnnotation, annotation.type == "FreeText" {
                    self.delegate?.editor.setFontSize(annotation, size)
                    self.refreshOverlay()
                }
            },
            setFill: { [weak self] fill in
                guard let self else { return }
                self.model.fillShapes = fill
                if let annotation = self.model.selectedAnnotation, ["Square", "Circle"].contains(annotation.type ?? "") {
                    let color = annotation.color.withAlphaComponent(0.25)
                    self.delegate?.editor.setFill(annotation, fill ? color : nil)
                }
            },
            setMarkupStyle: { [weak self] style in self?.model.markupStyle = style },
            setShape: { [weak self] kind in self?.model.shapeKind = kind },
            deleteSelection: { [weak self] in self?.delegate?.deleteSelectedAnnotation(nil) },
            editSelection: { [weak self] in self?.delegate?.editSelectedAnnotation(nil) },
            toggleFields: { [weak self] in self?.delegate?.toggleFieldHighlight(nil) },
            duplicate: { [weak self] in self?.delegate?.paperDocument?.duplicate(nil) },
            recognizeText: { [weak self] in self?.delegate?.recognizeText(nil) }
        )
    }

    private func applyColor(_ color: InkColor) {
        if let annotation = model.selectedAnnotation {
            delegate?.editor.setColor(annotation, color.nsColor)
            if annotation.type == "FreeText" { model.textColor = color }
            else if AnnotationGeometry.isMarkup(annotation) { model.highlightColor = color }
            else { model.inkColor = color }
            return
        }
        switch model.tool {
        case .highlight: model.highlightColor = color
        case .text: model.textColor = color
        default: model.inkColor = color
        }
    }

    // MARK: Locked documents

    func showLocked(_ locked: Bool, name: String, unlock: @escaping (String) -> Bool) {
        lockedHost?.removeFromSuperview()
        lockedHost = nil
        guard locked else { return }
        let host = NSHostingView(rootView: LockedView(name: name, unlock: unlock))
        host.frame = pdfContainer.bounds
        host.autoresizingMask = [.width, .height]
        pdfContainer.addSubview(host)
        lockedHost = host
    }

    // MARK: Text boxes

    func beginTextEditing(_ annotation: PDFAnnotation, isNew: Bool) {
        PaperPDFView.debug("beginTextEditing new=\(isNew) page=\(annotation.page != nil)")
        endTextEditing()
        guard let page = annotation.page else { return }
        editingAnnotation = annotation
        editingIsNew = isNew
        model.selectedAnnotation = nil
        annotation.shouldDisplay = false
        pdfView.annotationsChanged(on: page)
        let editor = NSTextView()
        editor.delegate = self
        editor.isRichText = false
        editor.drawsBackground = true
        // The editor sits on the page, which is white in dark mode too: a dark text background
        // here put the box's black text on dark grey.
        editor.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        editor.appearance = NSAppearance(named: .aqua)
        editor.textContainerInset = NSSize(width: 2, height: 2)
        editor.textContainer?.lineFragmentPadding = 2
        editor.isHorizontallyResizable = true
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 10_000, height: 10_000)
        editor.textColor = annotation.fontColor ?? .black
        editor.insertionPointColor = .controlAccentColor
        editor.string = annotation.contents ?? ""
        editor.setAccessibilityLabel("Text box")
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.borderWidth = 1
        pdfContainer.addSubview(editor)
        textEditor = editor
        positionTextEditor()
        view.window?.makeFirstResponder(editor)
        editor.selectAll(nil)
    }

    private func positionTextEditor() {
        guard let editor = textEditor, let annotation = editingAnnotation, let page = annotation.page else { return }
        let scale = pdfView.scaleFactor
        let font = NSFont.systemFont(ofSize: (annotation.font?.pointSize ?? model.fontSize) * scale)
        editor.font = font
        let rect = pdfContainer.convert(pdfView.convert(annotation.bounds, from: page), from: pdfView)
        let size = TextBoxLayout.size(for: editor.string, font: font)
        editor.frame = NSRect(x: rect.minX, y: rect.maxY - size.height - 4, width: max(size.width + 12, rect.width), height: size.height + 4)
    }

    func textDidChange(_ notification: Notification) { positionTextEditor() }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endTextEditing()
            view.window?.makeFirstResponder(pdfView)
            return true
        }
        return false
    }

    func textDidEndEditing(_ notification: Notification) { endTextEditing() }

    func endTextEditing() {
        guard let editor = textEditor, let annotation = editingAnnotation else { return }
        PaperPDFView.debug("endTextEditing text=\(editor.string) firstResponder=\(String(describing: view.window?.firstResponder))")
        textEditor = nil
        editingAnnotation = nil
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : editor.string
        editor.removeFromSuperview()
        annotation.shouldDisplay = true
        guard let page = annotation.page, let documentEditor = delegate?.editor else { return }
        if text.isEmpty {
            if editingIsNew {
                // A text box that was never typed into disappears without an undo step.
                page.removeAnnotation(annotation)
                delegate?.paperDocument?.undoManager?.undo()
            } else {
                documentEditor.remove(annotation, from: page, name: "Delete Text Box")
            }
        } else if editingIsNew {
            annotation.contents = text
            if let font = annotation.font {
                let size = TextBoxLayout.size(for: text, font: font)
                annotation.bounds = CGRect(x: annotation.bounds.minX, y: annotation.bounds.maxY - size.height, width: size.width, height: size.height)
            }
            pdfView.annotationsChanged(on: page)
            model.touch(page)
            model.annotationsRevision += 1
        } else {
            documentEditor.setContents(annotation, text)
        }
        pdfView.annotationsChanged(on: page)
        refreshOverlay()
    }

    // MARK: Notes

    func editNote(_ annotation: PDFAnnotation, isNew: Bool) {
        notePopover?.close()
        guard let page = annotation.page else { return }
        let state = NoteState(text: annotation.contents ?? "")
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: NoteEditor(state: state, onDelete: { [weak self, weak popover] in
            state.deleted = true
            popover?.close()
            _ = self
        }, onDone: { [weak popover] in popover?.close() }))
        notePopover = popover
        noteState = (annotation, state, isNew)
        let rect = pdfContainer.convert(pdfView.convert(annotation.bounds, from: page), from: pdfView)
        popover.show(relativeTo: rect, of: pdfContainer, preferredEdge: .maxX)
    }

    private var noteState: (PDFAnnotation, NoteState, Bool)?

    func popoverDidClose(_ notification: Notification) {
        guard let (annotation, state, isNew) = noteState, let page = annotation.page, let editor = delegate?.editor else { return }
        noteState = nil
        notePopover = nil
        let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.deleted || (isNew && text.isEmpty) {
            editor.remove(annotation, from: page, name: "Delete Note")
        } else if isNew {
            annotation.contents = text
            model.annotationsRevision += 1
            pdfView.annotationsChanged(on: page)
        } else {
            editor.setContents(annotation, text, name: "Edit Note")
        }
        view.window?.makeFirstResponder(pdfView)
    }

    // MARK: Selection bar

    func showSelectionBarIfNeeded() {
        guard model.tool == .select, !model.isReadOnly, let selection = pdfView.currentSelection,
              !(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hideSelectionBar()
            return
        }
        if selectionBar == nil {
            let bar = NSHostingView(rootView: SelectionBar(actions: selectionActions()))
            bar.sizingOptions = [.intrinsicContentSize]
            pdfContainer.addSubview(bar)
            selectionBar = bar
        }
        positionSelectionBar()
    }

    func selectionMoved() {
        if pdfView.currentSelection == nil || (pdfView.currentSelection?.string ?? "").isEmpty { hideSelectionBar() }
    }

    private func hideSelectionBar() {
        selectionBar?.removeFromSuperview()
        selectionBar = nil
    }

    private func positionSelectionBar() {
        guard let bar = selectionBar, let selection = pdfView.currentSelection, let page = selection.pages.first else { return }
        let rect = pdfContainer.convert(pdfView.convert(selection.bounds(for: page), from: page), from: pdfView)
        let size = bar.fittingSize
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 8)
        if origin.y + size.height > pdfContainer.bounds.maxY - 4 { origin.y = rect.minY - size.height - 8 }
        origin.x = min(max(origin.x, 8), pdfContainer.bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, 8), pdfContainer.bounds.maxY - size.height - 4)
        bar.frame = NSRect(origin: origin, size: size)
    }

    private func selectionActions() -> SelectionActions {
        SelectionActions(
            highlight: { [weak self] color in self?.markupSelection(.highlight, color) },
            underline: { [weak self] in self?.markupSelection(.underline, nil) },
            strike: { [weak self] in self?.markupSelection(.strikeOut, nil) },
            note: { [weak self] in self?.noteOnSelection() },
            redact: { [weak self] in
                guard let self, let selection = self.pdfView.currentSelection else { return }
                self.pdfView.markForRedaction(selection)
                self.clearSelection()
            },
            copy: { [weak self] in
                guard let text = self?.pdfView.currentSelection?.string else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self?.clearSelection()
            }
        )
    }

    private func markupSelection(_ style: MarkupStyle, _ color: InkColor?) {
        guard let selection = pdfView.currentSelection else { return }
        let ink = color ?? (style == .highlight ? model.highlightColor : .red)
        if let color { model.highlightColor = color }
        pdfView.markup(selection, style: style, color: ink)
        clearSelection()
    }

    private func noteOnSelection() {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first, let editor = delegate?.editor else { return }
        let bounds = selection.bounds(for: page)
        let note = model.authorFactory.note("", at: CGPoint(x: min(bounds.maxX + 12, page.bounds(for: .cropBox).maxX - 12), y: bounds.maxY - 6))
        editor.add(note, to: page, name: "Add Note")
        clearSelection()
        editNote(note, isNew: true)
    }

    private func clearSelection() {
        pdfView.setCurrentSelection(nil, animate: false)
        hideSelectionBar()
    }
}

@Observable
@MainActor
final class NoteState {
    var text: String
    var deleted = false
    init(text: String) { self.text = text }
}
