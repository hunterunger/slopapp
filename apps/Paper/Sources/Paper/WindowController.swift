import AppKit
import PDFKit
import PaperCore
import SecurityInterface
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// One document window: sidebar, canvas, toolbar, and every document action in the menus.
@MainActor
final class PaperWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, CanvasDelegate {
    let model: DocumentModel
    let editor: DocumentEditor
    let pdfView = PaperPDFView()
    let canvas: CanvasController
    let splitController = NSSplitViewController()
    private var sidebarItem: NSSplitViewItem!
    private(set) var inspectorItem: NSSplitViewItem!
    let toolbarController: ToolbarController
    private var searchTask: Task<Void, Never>?
    private var lastPageSave: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var awaitingMouseUp = false
    /// A tool owns the current mouse-down/drag/up sequence.
    private var toolTracking = false
    private let lastPages = LastPageMemory(store: UserDefaultsStore(Prefs.defaults))
    /// The last temporary copy made for sharing, and the edit revision it shows.
    var shareCopy: (revision: Int, url: URL)?
    /// The fit mode the zoom follows, or nil after a manual zoom.
    var zoomMode: ZoomPreference? = Prefs.zoom

    /// `document` is only set after `addWindowController`, so keep our own reference for init.
    private weak var owningDocument: PaperDocument?
    var paperDocument: PaperDocument? { (document as? PaperDocument) ?? owningDocument }

    init(document: PaperDocument) {
        model = DocumentModel(pdf: document.pdf)
        canvas = CanvasController(model: model, pdfView: pdfView)
        toolbarController = ToolbarController(model: model)
        editor = DocumentEditor(model: model, document: document)
        owningDocument = document
        let frame = Self.initialFrame()
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.minSize = NSSize(width: 560, height: 420)
        window.toolbarStyle = .unified
        window.tabbingMode = .automatic
        super.init(window: window)
        editor.onChange = { [weak self] page in self?.annotationsDidChange(page) }
        editor.onPagesChange = { [weak self] in self?.pagesDidChange() }
        editor.onFieldsChange = { [weak self] in self?.fieldsChanged() }
        editor.positionKeeper = { [weak self] in
            // Swapped pages keep their size, so the scroll offset itself is what to restore.
            guard let self, let scroll = self.pdfView.documentView?.enclosingScrollView else { return {} }
            let origin = scroll.contentView.bounds.origin, scale = self.pdfView.scaleFactor
            return { [weak self] in
                guard let self else { return }
                self.pdfView.layoutDocumentView()
                if abs(self.pdfView.scaleFactor - scale) > 0.001 { self.pdfView.scaleFactor = scale }
                guard let scroll = self.pdfView.documentView?.enclosingScrollView else { return }
                scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(NSRect(origin: origin, size: scroll.contentView.bounds.size)).origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        canvas.delegate = self
        pdfView.canvasDelegate = self
        toolbarController.owner = self
        buildLayout()
        window.setFrame(frame, display: false)
        window.delegate = self
        window.toolbar = toolbarController.makeToolbar()
        shouldCascadeWindows = true
        configureDocument(firstLoad: true)
        observe()
        installEventMonitor()
    }

    /// PDFKit handles clicks and keys inside its own views, so the canvas watches the window's
    /// events: after a mouse-up, finish the Highlight/Redact tool or show the selection bar;
    /// keys go to the canvas when the PDF (not a text or form field) has focus.
    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown, .keyUp]) { [weak self] event in
            // Monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self?.handleMonitored(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was handled and shouldn't go further.
    private func handleMonitored(_ event: NSEvent) -> Bool {
        guard event.window === window, window?.attachedSheet == nil else { return false }
        switch event.type {
        case .leftMouseDown:
            let point = pdfView.convert(event.locationInWindow, from: nil)
            if pdfView.bounds.contains(point), hitsPDF(event), !isOverScroller(event), pdfView.claims(point) {
                toolTracking = true
                pdfView.toolMouseDown(with: event)
                return true
            }
            // PDFKit tracks text drags in its own loop and swallows the mouse-up, so watch the
            // button and finish when it's released (whichever comes first, this or mouse-up).
            awaitingMouseUp = true
            Task { @MainActor [weak self] in
                while NSEvent.pressedMouseButtons & 1 != 0 {
                    try? await Task.sleep(for: .milliseconds(25))
                }
                guard let self, self.awaitingMouseUp else { return }
                self.afterMouseUp()
            }
        case .leftMouseDragged where toolTracking:
            pdfView.toolMouseDragged(with: event)
            return true
        case .leftMouseUp where toolTracking:
            toolTracking = false
            pdfView.toolMouseUp(with: event)
            canvasFormMayHaveChanged()
            return true
        case .leftMouseUp:
            Task { @MainActor [weak self] in
                guard let self, self.awaitingMouseUp else { return }
                self.afterMouseUp()
            }
        case .rightMouseDown:
            let point = pdfView.convert(event.locationInWindow, from: nil)
            if pdfView.bounds.contains(point), hitsPDF(event), let menu = pdfView.annotationMenu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: pdfView)
                return true
            }
        case .keyDown:
            return canvasHasKeyFocus && pdfView.handleKey(event)
        case .keyUp:
            Task { @MainActor [weak self] in self?.canvasFormMayHaveChanged() }
        default:
            break
        }
        return false
    }

    /// The click would land in the PDF itself, not on the text box editor, the selection bar
    /// or another view floating over it.
    private func hitsPDF(_ event: NSEvent) -> Bool {
        guard let frame = window?.contentView?.superview,
              let hit = frame.hitTest(frame.convert(event.locationInWindow, from: nil)) else { return false }
        return hit === pdfView || hit.isDescendant(of: pdfView)
    }

    private func isOverScroller(_ event: NSEvent) -> Bool {
        guard let scroller = pdfView.documentView?.enclosingScrollView?.verticalScroller, !scroller.isHidden else { return false }
        return scroller.bounds.contains(scroller.convert(event.locationInWindow, from: nil))
    }

    private var canvasHasKeyFocus: Bool {
        guard let responder = window?.firstResponder as? NSView, !(responder is NSText) else { return false }
        return responder === pdfView || responder.isDescendant(of: pdfView)
    }

    private func afterMouseUp() {
        awaitingMouseUp = false
        PaperPDFView.debug("afterMouseUp tool=\(model.tool.rawValue) sel=\(pdfView.currentSelection?.string ?? "nil")")
        guard !model.isLocked else { return }
        switch model.tool {
        case .highlight, .redact:
            pdfView.applyToolToSelection()
        case .select:
            canvas.showSelectionBarIfNeeded()
        default:
            break
        }
        canvasFormMayHaveChanged()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private static func initialFrame() -> NSRect {
        if let saved = Prefs.defaults.string(forKey: "documentWindowFrame") {
            let frame = NSRectFromString(saved)
            if frame.width >= 560, frame.height >= 420 { return frame }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let height = min(screen.height - 40, 900)
        // Wide enough for every default toolbar item without the overflow menu (macOS 26
        // gives toolbar controls a minimum size, so the row needs about 1,250 pt).
        let width = min(screen.width - 80, 1280)
        return NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
    }

    private func buildLayout() {
        let sidebar = NSHostingController(rootView: SidebarView(model: model, actions: sidebarActions()))
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 340
        sidebarItem.canCollapse = true
        let content = NSSplitViewItem(viewController: canvas)
        content.minimumThickness = 360
        let inspector = NSHostingController(rootView: InspectorView(model: model, actions: inspectorActions()))
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 360
        inspectorItem.canCollapse = true
        inspectorItem.isCollapsed = !Prefs.defaults.bool(forKey: "showsInspector")
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(content)
        splitController.addSplitViewItem(inspectorItem)
        splitController.splitView.autosaveName = Prefs.isTestSuite ? nil : "PaperSidebar"
        contentViewController = splitController
    }

    // MARK: Loading

    func documentDidReload() {
        configureDocument(firstLoad: false)
    }

    private func configureDocument(firstLoad: Bool) {
        guard let document = paperDocument else { return }
        model.pdf = document.pdf
        model.facts = document.facts
        model.importedRedactions = document.importedRedactions
        model.isLocked = document.pdf.isLocked
        model.hasTextLayer = document.facts.hasTextLayer
        model.fileURL = document.fileURL
        model.infoRevision += 1
        model.hasOutline = (document.pdf.outlineRoot?.numberOfChildren ?? 0) > 0
        model.formScripts = document.formScripts
        model.signatures = document.signatures
        model.imageTarget = nil
        model.cropDraft = nil
        if model.sidebarMode == .outline, !model.hasOutline { model.sidebarMode = .thumbnails }
        model.selectedAnnotation = nil
        model.searchHits = []
        model.redactHits = []
        model.refreshPages()
        canvas.showLocked(model.isLocked, name: document.displayName ?? "This document") { [weak self] password in
            guard let self, let document = self.paperDocument else { return false }
            guard document.unlock(with: password) else { return false }
            self.configureDocument(firstLoad: true)
            return true
        }
        guard !model.isLocked else {
            pdfView.document = nil
            // The tool groups get their symbols here; without it a locked window's groups are blank.
            toolbarController.refresh()
            return
        }
        pdfView.document = document.pdf
        // The canvas already sits below the toolbar; PDFView's own titlebar inset would hide
        // the top of the first page under it.
        if model.isReadOnly { model.tool = .select }
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        CanvasLook.apply(to: pdfView)
        if firstLoad {
            DispatchQueue.main.async { [weak self] in self?.applyInitialPosition() }
        }
        toolbarController.refresh()
        canvas.refreshOverlay()
    }

    private func applyInitialPosition() {
        applyZoom(Prefs.zoom)
        var index = 0
        if Prefs.defaults.bool(forKey: Prefs.reopenAtLastPage), let url = paperDocument?.fileURL,
           let page = lastPages.page(for: url), page > 0, page < model.pdf.pageCount {
            index = page
        }
        if let target = model.pdf.page(at: index) { CanvasLook.scroll(pdfView, toTopOf: target) }
        updateCurrentPage()
        canvas.keepsContentStill = true
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCurrentPage() }
        })
        pdfView.postsFrameChangedNotifications = true
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refit() }
        })
        observers.append(center.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forgetFitIfZoomedByHand()
                if let pdfView = self?.pdfView { CanvasLook.scaleChanged(pdfView) }
                self?.toolbarController.refresh()
                self?.canvas.refreshOverlay()
            }
        })
        observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.canvas.selectionMoved() }
        })
    }

    func updateCurrentPage() {
        guard let page = pdfView.currentPage else { return }
        let index = model.pdf.index(for: page)
        guard index != NSNotFound else { return }
        if model.currentPageIndex != index || model.selectedPages.isEmpty {
            model.currentPageIndex = index
            if model.selectedPages.count <= 1, index < model.pages.count {
                model.selectedPages = [model.pages[index].id]
            }
        }
        toolbarController.refresh()
        rememberPage(index)
    }

    private func rememberPage(_ index: Int) {
        guard let url = paperDocument?.fileURL else { return }
        lastPageSave?.cancel()
        lastPageSave = Task { [lastPages] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            lastPages.remember(page: index, for: url)
        }
    }

    func commitEditing() {
        canvas.endTextEditing()
        canvas.endContentEditing(commit: true)
        canvasFormMayHaveChanged()
    }

    private func annotationsDidChange(_ page: PDFPage?) {
        if let page { pdfView.annotationsChanged(on: page) }
        canvas.refreshOverlay()
    }

    private func pagesDidChange() {
        pdfView.invalidateContent()
        if let draft = model.cropDraft, model.pdf.index(for: draft.page) == NSNotFound { model.cropDraft = nil }
        if let target = model.imageTarget, model.pdf.index(for: target.page) == NSNotFound { model.imageTarget = nil }
        pdfView.layoutDocumentView()
        model.refreshPages()
        if model.hasTextLayer != PDFSearch.hasTextLayer(model.pdf) { textLayerChanged() }
        updateCurrentPage()
        canvas.refreshOverlay()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window { Prefs.defaults.set(NSStringFromRect(window.frame), forKey: "documentWindowFrame") }
        Prefs.defaults.set(!inspectorItem.isCollapsed, forKey: "showsInspector")
        if let url = paperDocument?.fileURL { lastPages.remember(page: model.currentPageIndex, for: url) }
        searchTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    func windowDidResize(_ notification: Notification) {
        refit()
        canvas.refreshOverlay()
    }

    /// A pinch or another zoom that isn't the fit's own: stop refitting on resize.
    private func forgetFitIfZoomedByHand() {
        guard zoomMode == .fitWidth, let page = pdfView.currentPage else { return }
        if abs(pdfView.scaleFactor - CanvasLook.fitWidthScale(for: page, in: pdfView)) > 0.01 { zoomMode = nil }
    }

    /// Keeps a fit zoom fitting when the canvas changes width (window, sidebar, inspector).
    func refit() {
        switch zoomMode {
        case .fitPage: applyZoom(.fitPage)
        case .fitWidth:
            guard let page = pdfView.currentPage else { return }
            let scale = CanvasLook.fitWidthScale(for: page, in: pdfView)
            if abs(pdfView.scaleFactor - scale) > 0.001 { pdfView.scaleFactor = scale }
            toolbarController.refresh()
        default: break
        }
    }

    // MARK: CanvasDelegate

    func canvasSelectionChanged() { canvas.showSelectionBarIfNeeded() }
    func canvasBeginTextEditing(_ annotation: PDFAnnotation, isNew: Bool) { canvas.beginTextEditing(annotation, isNew: isNew) }
    func canvasEditNote(_ annotation: PDFAnnotation, isNew: Bool) { canvas.editNote(annotation, isNew: isNew) }
    func canvasNeedsOverlay() { canvas.refreshOverlay() }

    func canvasShowSignatureMenu(at point: NSPoint) {
        let menu = SignatureMenu.build(target: self)
        menu.popUp(positioning: nil, at: point, in: pdfView)
    }

    func canvasFormMayHaveChanged() {
        guard let document = paperDocument, !document.formTracker.isEmpty else { return }
        // Calculated fields follow first, so their new values undo with the edit.
        recalculate()
        let changes = document.formTracker.changes()
        guard !changes.isEmpty else { return }
        editor.group("Fill Form") {
            for (annotation, old) in changes { editor.setFormValue(annotation, old: old) }
        }
    }

    func canvasSetTool(_ tool: Tool) { setTool(tool) }

    // MARK: Tools

    func setTool(_ tool: Tool) {
        guard !model.isReadOnly || tool == .select else { NSSound.beep(); return }
        canvas.endTextEditing()
        canvas.endContentEditing(commit: true)
        if tool != .sign { model.pendingSignature = nil; model.certificatePlan = nil }
        if tool != .edit { model.imageTarget = nil }
        if tool != .crop { model.cropDraft = nil }
        // Fields are selected with the Form Fields tool only.
        if tool != .form, model.selectedAnnotation?.type == "Widget" { model.selectedAnnotation = nil }
        rememberGroupChoice(tool)
        model.tool = tool
        if tool != .select { pdfView.select(nil) }
        toolbarController.refresh()
        canvas.refreshOverlay()
        window?.makeFirstResponder(pdfView)
        if tool == .sign, model.pendingSignature == nil, model.certificatePlan == nil {
            toolbarController.showSignatureMenu() ?? canvasShowSignatureMenu(at: NSPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY))
        }
    }

    @objc func chooseTool(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let tool = Tool(rawValue: raw) else { return }
        setTool(tool)
    }

    @objc func chooseMarkupStyle(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let style = MarkupStyle(rawValue: raw) else { return }
        model.markupStyle = style
        if let selection = pdfView.currentSelection, !(selection.string ?? "").isEmpty, model.tool == .select {
            pdfView.markup(selection, style: style, color: model.highlightColor)
            pdfView.setCurrentSelection(nil, animate: false)
        } else {
            setTool(.highlight)
        }
    }

    @objc func chooseHighlightColor(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let color = InkColor(rawValue: raw) else { return }
        model.highlightColor = color
        if let selection = pdfView.currentSelection, !(selection.string ?? "").isEmpty, model.tool == .select {
            pdfView.markup(selection, style: model.markupStyle, color: color)
            pdfView.setCurrentSelection(nil, animate: false)
        } else {
            setTool(.highlight)
        }
    }

    @objc func chooseShape(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let kind = ShapeKind(rawValue: raw) else { return }
        model.shapeKind = kind
        setTool(.shape)
    }

    @objc func placeSignature(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID,
              let signature = SignatureLibraryStore.shared.signatures.first(where: { $0.id == id }) else { return }
        model.pendingSignature = signature
        model.tool = .sign
        toolbarController.refresh()
        HUD.show("Click where the signature goes", systemImage: "signature")
    }

    @objc func newSignatureFromImage(_ sender: Any?) { presentSignatureSheet(.image) }

    @objc func newSignature(_ sender: Any?) { presentSignatureSheet(.draw) }

    private func presentSignatureSheet(_ source: SignatureSource) {
        guard let window else { return }
        SignatureSheet.present(on: window, source: source) { [weak self] signature in
            guard let self, let signature else { return }
            self.model.pendingSignature = signature
            self.model.tool = .sign
            self.toolbarController.refresh()
            self.window?.makeFirstResponder(self.pdfView)
        }
    }

    @objc func deleteSignature(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? UUID else { return }
        SignatureLibraryStore.shared.remove(id: id)
    }

    @objc func insertTodaysDate(_ sender: Any?) {
        guard let page = pdfView.currentPage, !model.isReadOnly else { return }
        let visible = pdfView.convert(pdfView.bounds, to: page)
        let text = Date().formatted(date: .long, time: .omitted)
        let box = model.authorFactory.textBox(text, topLeft: CGPoint(x: visible.midX - 60, y: visible.midY), fontSize: model.fontSize, color: model.textColor.nsColor)
        editor.add(box, to: page, name: "Add Date")
        model.tool = .select
        pdfView.select(box)
        toolbarController.refresh()
    }

    // MARK: Annotation actions

    @objc func deleteSelectedAnnotation(_ sender: Any?) {
        guard let annotation = model.selectedAnnotation, let page = annotation.page else { return }
        editor.remove(annotation, from: page, name: annotation.type == "Widget" ? "Delete Field" : "Delete")
    }

    /// Renames the selected field (every button of a radio group).
    func renameSelectedField(_ name: String) {
        guard let field = model.selectedAnnotation, let old = field.fieldName else { return }
        let new = FormNames.clean(name)
        guard !new.isEmpty, new != old else { return }
        let group = field.widgetControlType == .radioButtonControl
            ? FormFields.widgets(in: model.pdf).map(\.annotation).filter { $0.fieldName == old } : [field]
        editor.renameField(group, from: old, to: new)
        if field.widgetControlType == .radioButtonControl { model.lastRadioGroup = new }
    }

    @objc func editSelectedAnnotation(_ sender: Any?) {
        guard let annotation = model.selectedAnnotation else { return }
        if annotation.type == "FreeText" { canvas.beginTextEditing(annotation, isNew: false) }
        if annotation.type == "Text" { canvas.editNote(annotation, isNew: false) }
    }

    @objc func setAnnotationColor(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let color = InkColor(rawValue: raw),
              let annotation = model.selectedAnnotation else { return }
        editor.setColor(annotation, color.nsColor)
    }

    @objc func delete(_ sender: Any?) {
        if model.selectedAnnotation != nil { deleteSelectedAnnotation(sender) }
    }

    @objc func removeAllMarks(_ sender: Any?) {
        let marks = RedactionMarks.marks(in: model.pdf)
        guard !marks.isEmpty else { return }
        editor.group("Remove Redaction Marks") {
            for mark in marks {
                if let page = model.pdf.page(at: mark.pageIndex) { editor.remove(mark.annotation, from: page, name: "Remove Redaction Marks") }
            }
        }
    }

    @objc func resetForm(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear every form field?"
        alert.informativeText = "You can undo this."
        alert.addButton(withTitle: "Clear Fields")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn, let self, let document = self.paperDocument else { return }
                self.commitEditing()
                for index in 0..<self.model.pdf.pageCount {
                    for annotation in self.model.pdf.page(at: index)?.annotations ?? [] where annotation.type == "Widget" {
                        if annotation.widgetFieldType == .button { annotation.buttonWidgetState = .offState }
                        else if annotation.widgetFieldType == .text || annotation.widgetFieldType == .choice { annotation.widgetStringValue = "" }
                    }
                }
                let changes = document.formTracker.changes()
                self.editor.group("Clear Form") {
                    for (annotation, old) in changes { self.editor.setFormValue(annotation, old: old) }
                }
                self.pdfView.layoutDocumentView()
            }
        }
    }

    @objc func toggleFieldHighlight(_ sender: Any?) {
        model.highlightFields.toggle()
        canvas.refreshOverlay()
    }

    @objc func copyNotes(_ sender: Any?) {
        let items = NotesExport.items(in: model.pdf)
        guard !items.isEmpty else {
            HUD.show("No highlights or notes to copy", systemImage: "info.circle")
            return
        }
        let title = paperDocument?.displayName ?? "Notes"
        Clipboard.write(NotesExport.markdown(title: title, items: items))
        HUD.show("Copied \(items.count) highlights and notes", systemImage: "doc.on.doc")
    }

    // MARK: Zoom and view

    func applyZoom(_ zoom: ZoomPreference) {
        zoomMode = zoom
        switch zoom {
        case .fitWidth:
            // Computed here rather than with autoScales, so the sides get the same gap as the
            // space between pages (see CanvasLook).
            pdfView.autoScales = false
            if let page = pdfView.currentPage { pdfView.scaleFactor = CanvasLook.fitWidthScale(for: page, in: pdfView) }
        case .fitPage:
            pdfView.autoScales = false
            if let page = pdfView.currentPage {
                let bounds = page.bounds(for: pdfView.displayBox)
                let rotated = page.rotation % 180 == 0 ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
                let area = pdfView.bounds.insetBy(dx: PaperMetrics.pageGap, dy: PaperMetrics.pageGap).size
                pdfView.scaleFactor = max(0.1, min(area.width / rotated.width, area.height / rotated.height))
                pdfView.go(to: page)
            }
        case .actualSize:
            pdfView.autoScales = false
            pdfView.scaleFactor = 1
        }
        toolbarController.refresh()
    }

    @objc func paperZoomIn(_ sender: Any?) { zoomMode = nil; pdfView.autoScales = false; pdfView.zoomIn(sender) }
    @objc func paperZoomOut(_ sender: Any?) { zoomMode = nil; pdfView.autoScales = false; pdfView.zoomOut(sender) }
    @objc func zoomActualSize(_ sender: Any?) { applyZoom(.actualSize) }
    @objc func zoomToFit(_ sender: Any?) { applyZoom(.fitPage) }
    @objc func zoomToWidth(_ sender: Any?) { applyZoom(.fitWidth) }

    @objc func displaySinglePage(_ sender: Any?) { setDisplay(.singlePage) }
    @objc func displayContinuous(_ sender: Any?) { setDisplay(.singlePageContinuous) }
    @objc func displayTwoPages(_ sender: Any?) { setDisplay(.twoUpContinuous) }

    private func setDisplay(_ mode: PDFDisplayMode) {
        let page = pdfView.currentPage
        pdfView.displayMode = mode
        if let page { pdfView.go(to: page) }
        refit()
        canvas.refreshOverlay()
    }

    @objc func toggleBookMode(_ sender: Any?) {
        pdfView.displaysAsBook.toggle()
        canvas.refreshOverlay()
    }

    @objc func showSidebarMode(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let mode = SidebarMode(rawValue: raw) else { return }
        showSidebar(mode)
    }

    func showSidebar(_ mode: SidebarMode) {
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
        model.sidebarMode = mode
    }

    @objc func hideSidebar(_ sender: Any?) {
        sidebarItem.animator().isCollapsed.toggle()
    }

    // MARK: Go

    @objc func nextPage(_ sender: Any?) { pdfView.goToNextPage(sender) }
    @objc func previousPage(_ sender: Any?) { pdfView.goToPreviousPage(sender) }
    @objc func firstPage(_ sender: Any?) { pdfView.goToFirstPage(sender) }
    @objc func lastPage(_ sender: Any?) { pdfView.goToLastPage(sender) }
    @objc func paperGoBack(_ sender: Any?) { pdfView.goBack(sender) }
    @objc func paperGoForward(_ sender: Any?) { pdfView.goForward(sender) }
    @objc func goToPageField(_ sender: Any?) { toolbarController.focusPageField() }

    func goToPage(_ index: Int) {
        guard let page = model.pdf.page(at: index) else { return }
        CanvasLook.scroll(pdfView, toTopOf: page)
        updateCurrentPage()
    }

    // MARK: Search

    @objc func focusSearch(_ sender: Any?) { toolbarController.focusSearch() }

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        model.searchQuery = query
        guard !trimmed.isEmpty else { clearSearch(); return }
        showSidebar(.search)
        model.isSearching = true
        model.searchHits = []
        model.searchIndex = nil
        model.searchedQuery = trimmed
        let pdf = model.pdf
        searchTask = Task { [weak self] in
            var hits: [TextHit] = []
            for index in 0..<pdf.pageCount {
                if Task.isCancelled { return }
                if let page = pdf.page(at: index) {
                    hits += PDFSearch.hits(on: page, pageIndex: index, query: trimmed, options: MatchOptions())
                }
                if index % 20 == 19 {
                    self?.model.searchHits = hits
                    await Task.yield()
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.model.searchHits = hits
            self.model.isSearching = false
            self.highlightSearchHits()
            if !hits.isEmpty { self.selectSearchHit(0) }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        model.searchHits = []
        model.searchIndex = nil
        model.isSearching = false
        model.searchedQuery = ""
        pdfView.highlightedSelections = nil
        if model.sidebarMode == .search { model.sidebarMode = .thumbnails }
    }

    private func selection(for hit: TextHit) -> PDFSelection? {
        model.pdf.page(at: hit.pageIndex)?.selection(for: hit.range)
    }

    private func highlightSearchHits() {
        let selections = model.searchHits.prefix(2000).compactMap(selection(for:))
        for selection in selections { selection.color = NSColor.findHighlightColor.withAlphaComponent(0.5) }
        pdfView.highlightedSelections = selections
    }

    func selectSearchHit(_ index: Int) {
        guard model.searchHits.indices.contains(index), let selection = selection(for: model.searchHits[index]) else { return }
        model.searchIndex = index
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
        updateCurrentPage()
    }

    @objc func findNext(_ sender: Any?) { stepSearch(1) }
    @objc func findPrevious(_ sender: Any?) { stepSearch(-1) }

    private func stepSearch(_ step: Int) {
        guard !model.searchHits.isEmpty else {
            if !model.searchQuery.isEmpty { search(model.searchQuery) } else { focusSearch(nil) }
            return
        }
        let count = model.searchHits.count
        let next = ((model.searchIndex ?? (step > 0 ? -1 : 0)) + step + count) % count
        selectSearchHit(next)
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let text = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        toolbarController.setSearchText(text)
        search(text)
    }

    @objc func showFindAndRedact(_ sender: Any?) {
        if let text = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count < 200 {
            model.redactQuery = text
        }
        showSidebar(.redact)
    }

    func findForRedaction() {
        let query = model.redactQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let hits = PDFSearch.hits(in: model.pdf, query: query, options: model.redactOptions)
        model.redactHits = hits
        model.redactChecked = Set(hits.map(\.id))
        model.redactSearched = true
        if let first = hits.first { goToPage(first.pageIndex) }
    }

    func markRedactionHits() {
        let chosen = model.redactHits.filter { model.redactChecked.contains($0.id) }
        guard !chosen.isEmpty else { return }
        editor.group(chosen.count == 1 ? "Mark for Redaction" : "Mark \(chosen.count) Results") {
            for hit in chosen {
                guard let page = model.pdf.page(at: hit.pageIndex) else { continue }
                for rect in PDFSearch.lineRects(for: hit.range, on: page) {
                    editor.add(RedactionMarks.makeMark(bounds: rect.insetBy(dx: -0.5, dy: -1)), to: page, name: "Mark for Redaction")
                }
            }
        }
        HUD.show(chosen.count == 1 ? "Marked 1 result" : "Marked \(chosen.count) results", systemImage: "checkmark.circle")
        model.redactHits = []
        model.redactSearched = false
    }

    // MARK: Pages

    var pageSelection: IndexSet { model.selectedIndexes }

    @objc func rotateLeft(_ sender: Any?) { editor.rotate(pageSelection, by: -90) }
    @objc func rotateRight(_ sender: Any?) { editor.rotate(pageSelection, by: 90) }

    @objc func deletePages(_ sender: Any?) {
        let indexes = pageSelection
        guard indexes.count < model.pdf.pageCount else {
            HUD.show("A document needs at least one page", systemImage: "exclamationmark.circle")
            return
        }
        editor.delete(indexes)
    }

    @objc func movePagesUp(_ sender: Any?) {
        guard let order = PageOrder.movingUp(pageSelection, count: model.pdf.pageCount) else { return }
        editor.reorder(order, name: "Move Pages")
    }

    @objc func movePagesDown(_ sender: Any?) {
        guard let order = PageOrder.movingDown(pageSelection, count: model.pdf.pageCount) else { return }
        editor.reorder(order, name: "Move Pages")
    }

    func movePages(_ indexes: IndexSet, to destination: Int) {
        editor.reorder(PageOrder.moving(indexes, to: destination, count: model.pdf.pageCount), name: "Move Pages")
    }

    @objc func reversePages(_ sender: Any?) {
        editor.reorder(PageOrder.reversed(model.pdf.pageCount), name: "Reverse Order")
    }

    @objc func insertBlankPage(_ sender: Any?) {
        let index = min((pageSelection.last ?? model.currentPageIndex) + 1, model.pdf.pageCount)
        editor.insert(pages: [PageOps.blankPage(like: pdfView.currentPage)], at: index, name: "Insert Blank Page")
        goToPage(index)
    }

    @objc func insertFromFile(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf] + PaperDocumentController.imageTypes
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        panel.message = "Pages are inserted after the current page."
        if let folder = paperDocument?.fileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let self else { return }
                let index = min((self.pageSelection.last ?? self.model.currentPageIndex) + 1, self.model.pdf.pageCount)
                self.insertFiles(panel.urls, at: index)
            }
        }
    }

    /// Inserts PDFs and images at `index`. Used by Insert from File and Finder drops.
    func insertFiles(_ urls: [URL], at index: Int) {
        var pages: [PDFPage] = []
        var skipped: [String] = []
        for url in urls {
            if PaperDocumentController.isImage(url) {
                if let image = NSImage(contentsOf: url), let page = ImagePages.page(for: image) { pages.append(page) } else { skipped.append(url.lastPathComponent) }
            } else if let source = AnnotationTags.open(url: url), !source.isLocked {
                for pageIndex in 0..<source.pageCount {
                    if let page = source.page(at: pageIndex), let copy = AnnotationTags.copy(page) { pages.append(copy) }
                }
            } else {
                skipped.append(url.lastPathComponent)
            }
        }
        if !pages.isEmpty {
            editor.insert(pages: pages, at: index, name: pages.count == 1 ? "Insert Page" : "Insert Pages")
            goToPage(index)
        }
        if !skipped.isEmpty, let window {
            let alert = NSAlert()
            alert.messageText = skipped.count == 1 ? "Couldn't insert “\(skipped[0])”." : "Couldn't insert \(skipped.count) files."
            alert.informativeText = "Only PDFs and images can be inserted, and password-protected PDFs need to be unlocked first."
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    @objc func extractPages(_ sender: Any?) {
        let indexes = pageSelection
        let extracted = PageOps.extract(model.pdf, pages: indexes)
        let base = paperDocument?.displayName.map { ($0 as NSString).deletingPathExtension } ?? "Pages"
        let label = indexes.count == 1 ? "page \(indexes.first! + 1)" : "pages \(Self.rangeLabel(indexes))"
        (NSDocumentController.shared as? PaperDocumentController)?.openUntitled(extracted, name: "\(base) (\(label))")
    }

    static func rangeLabel(_ indexes: IndexSet) -> String {
        indexes.rangeView.map { range in
            range.count == 1 ? "\(range.lowerBound + 1)" : "\(range.lowerBound + 1)–\(range.upperBound)"
        }.joined(separator: ", ")
    }

    @objc func splitDocument(_ sender: Any?) {
        guard let window else { return }
        SplitSheet.present(on: window, pdf: model.pdf, name: paperDocument?.displayName ?? "Document",
                           folder: paperDocument?.fileURL?.deletingLastPathComponent())
    }

    // MARK: Export and redaction

    @objc func exportFlattened(_ sender: Any?) {
        guard let window, let document = paperDocument else { return }
        commitEditing()
        Exporting.exportFlattened(document: document, model: model, window: window)
    }

    @objc func exportText(_ sender: Any?) {
        guard let window, let document = paperDocument else { return }
        Exporting.exportText(document: document, window: window)
    }

    @objc func applyRedactions(_ sender: Any?) {
        guard let window, let document = paperDocument else { return }
        commitEditing()
        RedactionFlow.start(document: document, model: model, window: window)
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let answer = validateParityItem(item) { return answer }
        if let answer = validateEditingItem(item) { return answer }
        let locked = model.isLocked
        let editable = !model.isReadOnly
        switch item.action {
        case #selector(chooseTool(_:)):
            let tool = (item.representedObject as? String).flatMap(Tool.init(rawValue:))
            item.state = tool == model.tool ? .on : .off
            return !locked && (editable || tool == .select)
        case #selector(chooseMarkupStyle(_:)):
            item.state = (item.representedObject as? String) == model.markupStyle.rawValue ? .on : .off
            return editable
        case #selector(chooseHighlightColor(_:)):
            item.state = (item.representedObject as? String) == model.highlightColor.rawValue ? .on : .off
            return editable
        case #selector(chooseShape(_:)):
            item.state = (item.representedObject as? String) == model.shapeKind.rawValue ? .on : .off
            return editable
        case #selector(placeSignature(_:)), #selector(newSignature(_:)), #selector(newSignatureFromImage(_:)), #selector(insertTodaysDate(_:)):
            return editable
        case #selector(deleteSelectedAnnotation(_:)), #selector(delete(_:)), #selector(setAnnotationColor(_:)):
            return editable && model.selectedAnnotation != nil
        case #selector(editSelectedAnnotation(_:)):
            return editable && ["FreeText", "Text"].contains(model.selectedAnnotation?.type ?? "")
        case #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(insertBlankPage(_:)), #selector(insertFromFile(_:)):
            return editable
        case #selector(reversePages(_:)):
            return editable && model.pdf.pageCount > 1
        case #selector(deletePages(_:)):
            return editable && pageSelection.count < model.pdf.pageCount
        case #selector(movePagesUp(_:)):
            return editable && (pageSelection.first ?? 0) > 0
        case #selector(movePagesDown(_:)):
            return editable && (pageSelection.last ?? Int.max) < model.pdf.pageCount - 1
        case #selector(extractPages(_:)), #selector(splitDocument(_:)), #selector(exportFlattened(_:)), #selector(exportText(_:)):
            return !locked && model.facts.allowsCopying
        case #selector(applyRedactions(_:)):
            return editable && model.markSummary.markCount > 0
        case #selector(removeAllMarks(_:)):
            return editable && model.markSummary.markCount > 0
        case #selector(showFindAndRedact(_:)):
            return editable
        case #selector(resetForm(_:)):
            return editable && model.facts.formFieldCount > 0
        case #selector(toggleFieldHighlight(_:)):
            item.state = model.highlightFields ? .on : .off
            return model.facts.formFieldCount > 0
        case #selector(displaySinglePage(_:)):
            item.state = pdfView.displayMode == .singlePage ? .on : .off
            return !locked
        case #selector(displayContinuous(_:)):
            item.state = pdfView.displayMode == .singlePageContinuous ? .on : .off
            return !locked
        case #selector(displayTwoPages(_:)):
            item.state = pdfView.displayMode == .twoUpContinuous ? .on : .off
            return !locked
        case #selector(toggleBookMode(_:)):
            item.state = pdfView.displaysAsBook ? .on : .off
            return !locked && (pdfView.displayMode == .twoUp || pdfView.displayMode == .twoUpContinuous)
        case #selector(showSidebarMode(_:)):
            let mode = (item.representedObject as? String).flatMap(SidebarMode.init(rawValue:))
            item.state = mode == model.sidebarMode && !sidebarItem.isCollapsed ? .on : .off
            return mode != .outline || model.hasOutline
        case #selector(hideSidebar(_:)):
            item.title = sidebarItem.isCollapsed ? "Show Sidebar" : "Hide Sidebar"
            return true
        case #selector(nextPage(_:)), #selector(lastPage(_:)):
            return pdfView.canGoToNextPage
        case #selector(previousPage(_:)), #selector(firstPage(_:)):
            return pdfView.canGoToPreviousPage
        case #selector(paperGoBack(_:)):
            return pdfView.canGoBack
        case #selector(paperGoForward(_:)):
            return pdfView.canGoForward
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !locked && (!model.searchHits.isEmpty || !model.searchQuery.isEmpty)
        case #selector(useSelectionForFind(_:)):
            return !(pdfView.currentSelection?.string ?? "").isEmpty
        case #selector(copyNotes(_:)):
            return !locked
        case #selector(paperZoomIn(_:)):
            return !locked && pdfView.canZoomIn
        case #selector(paperZoomOut(_:)):
            return !locked && pdfView.canZoomOut
        case #selector(focusSearch(_:)), #selector(zoomActualSize(_:)), #selector(zoomToFit(_:)), #selector(zoomToWidth(_:)),
             #selector(goToPageField(_:)):
            return !locked
        default:
            return true
        }
    }

    // MARK: Inspector actions

    private func inspectorActions() -> InspectorActions {
        InspectorActions(
            setInfo: { [weak self] info in self?.editor.setInfo(info) },
            saveProtectedCopy: { [weak self] protection in
                guard let self, let window = self.window, let document = self.paperDocument else { return }
                self.commitEditing()
                Exporting.saveProtected(document: document, protection: protection, window: window)
            },
            editSelection: { [weak self] in self?.editSelectedAnnotation(nil) },
            deleteSelection: { [weak self] in self?.deleteSelectedAnnotation(nil) },
            setAuthor: { [weak self] name in
                guard let self, let annotation = self.model.selectedAnnotation else { return }
                self.editor.setAuthor(annotation, name)
            },
            renameField: { [weak self] name in self?.renameSelectedField(name) },
            setTooltip: { [weak self] text in
                guard let self, let field = self.model.selectedAnnotation else { return }
                self.editor.change([field], "Change Tooltip", get: FormFieldFactory.tooltip(of:), set: { FormFieldFactory.setTooltip($1, on: $0) }, to: text)
            },
            setFlag: { [weak self] flag, on in
                guard let self, let field = self.model.selectedAnnotation else { return }
                let fields = self.groupOf(field)
                self.editor.change(fields, "Change Field", get: { FormFieldFactory.has(flag, $0) }, set: { FormFieldFactory.set(flag, $1, on: $0) }, to: on)
            },
            setOptions: { [weak self] options in
                guard let self, let field = self.model.selectedAnnotation else { return }
                self.editor.change([field], "Change Choices", get: { $0.choices ?? [] }, set: { field, value in
                    field.choices = value
                    if let current = field.widgetStringValue, !current.isEmpty, !value.contains(current) { field.widgetStringValue = "" }
                }, to: options)
            },
            setExportValue: { [weak self] value in
                guard let self, let field = self.model.selectedAnnotation else { return }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed != "Off" else { return }
                self.editor.change([field], "Change Value", get: \.buttonWidgetStateString, set: { $0.buttonWidgetStateString = $1 }, to: trimmed)
            },
            setCalculation: { [weak self] calculation in
                guard let self, let name = self.model.selectedAnnotation?.fieldName else { return }
                self.editor.setCalculation(calculation, for: name)
                if calculation != nil, let field = self.model.selectedAnnotation, !FormFieldFactory.has(.readOnly, field) {
                    // A calculated field is read-only by default, as in other form tools.
                    self.editor.change([field], "Change Calculation", get: { FormFieldFactory.has(.readOnly, $0) }, set: { FormFieldFactory.set(.readOnly, $1, on: $0) }, to: true)
                }
                self.canvasFormMayHaveChanged()
            },
            showCertificate: { [weak self] status in self?.showCertificate(status) }
        )
    }

    /// Every widget of the field `field` belongs to (a radio group has several).
    func groupOf(_ field: PDFAnnotation) -> [PDFAnnotation] {
        guard let name = field.fieldName else { return [field] }
        let group = FormFields.widgets(in: model.pdf).map(\.annotation).filter { $0.fieldName == name }
        return group.isEmpty ? [field] : group
    }

    func showCertificate(_ status: SignatureStatus) {
        guard let window, let data = status.certificate, let certificate = SecCertificateCreateWithData(nil, data as CFData) else { return }
        SFCertificatePanel.shared().beginSheet(for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil,
                                               certificates: [certificate], showGroup: false)
    }

    /// OCR added (or undo removed) a text layer: search and Find and Redact can work again.
    func textLayerChanged() {
        let has = PDFSearch.hasTextLayer(model.pdf)
        model.hasTextLayer = has
        model.facts.hasTextLayer = has
        paperDocument?.updateTextLayer(has)
    }

    // MARK: Sidebar actions

    private func sidebarActions() -> SidebarActions {
        SidebarActions(
            goToPage: { [weak self] in self?.goToPage($0) },
            movePages: { [weak self] in self?.movePages($0, to: $1) },
            insertFiles: { [weak self] in self?.insertFiles($0, at: $1) },
            deletePages: { [weak self] in self?.deletePages(nil) },
            rotate: { [weak self] in self?.editor.rotate($0, by: $1) },
            extract: { [weak self] in self?.extractPages(nil) },
            selectHit: { [weak self] in self?.selectSearchHit($0) },
            closeSearch: { [weak self] in
                self?.clearSearch()
                self?.toolbarController.setSearchText("")
            },
            findForRedaction: { [weak self] in self?.findForRedaction() },
            markRedactionHits: { [weak self] in self?.markRedactionHits() },
            closeRedact: { [weak self] in self?.model.sidebarMode = .thumbnails },
            selectAnnotation: { [weak self] annotation in
                guard let self, let page = annotation.page else { return }
                self.setTool(.select)
                self.pdfView.go(to: annotation.bounds, on: page)
                self.pdfView.select(annotation)
                self.updateCurrentPage()
            },
            copyNotes: { [weak self] in self?.copyNotes(nil) },
            goToOutline: { [weak self] destination in
                self?.pdfView.go(to: destination)
                self?.updateCurrentPage()
            },
            highlightAll: { [weak self] in self?.highlightSearchResults(nil) },
            selectField: { [weak self] field in
                guard let self, let page = field.page else { return }
                if !self.model.isReadOnly { self.setTool(.form) }
                self.pdfView.go(to: field.bounds, on: page)
                self.pdfView.select(field)
                self.updateCurrentPage()
            },
            moveFields: { [weak self] pageIndex, source, destination in
                guard let self, let page = self.model.pdf.page(at: pageIndex) else { return }
                var order = page.annotations.filter { $0.type == "Widget" }
                order.move(fromOffsets: source, toOffset: destination)
                self.editor.reorderFields(on: page, to: order)
            },
            orderFieldsByPosition: { [weak self] in
                guard let self else { return }
                self.editor.group("Order Fields by Position") {
                    for index in 0..<self.model.pdf.pageCount {
                        guard let page = self.model.pdf.page(at: index) else { continue }
                        let fields = page.annotations.filter { $0.type == "Widget" }
                        guard fields.count > 1 else { continue }
                        self.editor.reorderFields(on: page, to: FormFields.positionOrder(fields))
                    }
                }
            }
        )
    }
}

/// Closures the SwiftUI sidebar calls back into the window controller with.
struct SidebarActions {
    var goToPage: (Int) -> Void
    var movePages: (IndexSet, Int) -> Void
    var insertFiles: ([URL], Int) -> Void
    var deletePages: () -> Void
    var rotate: (IndexSet, Int) -> Void
    var extract: () -> Void
    var selectHit: (Int) -> Void
    var closeSearch: () -> Void
    var findForRedaction: () -> Void
    var markRedactionHits: () -> Void
    var closeRedact: () -> Void
    var selectAnnotation: (PDFAnnotation) -> Void
    var copyNotes: () -> Void
    var goToOutline: (PDFDestination) -> Void
    var highlightAll: () -> Void
    var selectField: (PDFAnnotation) -> Void
    var moveFields: (Int, IndexSet, Int) -> Void
    var orderFieldsByPosition: () -> Void
}
