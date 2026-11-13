import AppKit
import PDFKit
import PaperCore
import SlopKit

/// Actions added in the parity pass: tool-group choices, scale, Find and Highlight, OCR,
/// Copy Text from Page, Export as Images, protected copies, sharing, the editing bar and
/// the inspector.
extension PaperWindowController {
    // MARK: Tool groups

    @objc func chooseDrawing(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String else { return }
        if let kind = ShapeKind(rawValue: raw) {
            model.shapeKind = kind
            model.drawUsesShape = true
            setTool(.shape)
        } else {
            model.drawUsesShape = false
            setTool(.draw)
        }
    }

    @objc func chooseComment(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let tool = Tool(rawValue: raw) else { return }
        model.commentUsesNote = tool == .note
        setTool(tool)
    }

    /// Remembers which tool of a group was used last, so the group's button repeats it.
    func rememberGroupChoice(_ tool: Tool) {
        switch tool {
        case .draw: model.drawUsesShape = false
        case .shape: model.drawUsesShape = true
        case .text: model.commentUsesNote = false
        case .note: model.commentUsesNote = true
        case .edit: model.editUsesCrop = false
        case .crop: model.editUsesCrop = true
        default: break
        }
    }

    // MARK: Zoom

    func setScale(_ factor: CGFloat) {
        zoomMode = nil
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(factor, pdfView.minScaleFactor), pdfView.maxScaleFactor)
        toolbarController.refresh()
    }

    // MARK: Find and Highlight

    @objc func findAndHighlight(_ sender: Any?) {
        focusSearch(sender)
        HUD.show("Search, then choose Highlight All", systemImage: "highlighter")
    }

    /// Highlights every current search result with the current markup style and color, as one
    /// undo step.
    @objc func highlightSearchResults(_ sender: Any?) {
        guard !model.searchHits.isEmpty, !model.isReadOnly else { return }
        let made = TextMarkup.annotations(for: model.searchHits, in: model.pdf, style: model.markupStyle,
                                          color: model.highlightColor.nsColor, factory: model.authorFactory)
        let name = made.count == 1 ? "Highlight 1 Result" : "Highlight \(made.count) Results"
        editor.group(name) {
            for item in made { editor.add(item.annotation, to: item.page, name: name) }
        }
        HUD.show(made.count == 1 ? "Highlighted 1 result" : "Highlighted \(made.count) results", systemImage: "highlighter")
    }

    @objc func removeMarkupFromSelection(_ sender: Any?) {
        guard let selection = pdfView.currentSelection, !model.isReadOnly else { return }
        var found: [(PDFPage, PDFAnnotation)] = []
        for page in selection.pages {
            let rects = selection.selectionsByLine().map { $0.bounds(for: page) }.filter { !$0.isEmpty }
            found += TextMarkup.markup(on: page, overlapping: rects.isEmpty ? [selection.bounds(for: page)] : rects).map { (page, $0) }
        }
        guard !found.isEmpty else {
            HUD.show("No highlights in the selection", systemImage: "info.circle")
            return
        }
        editor.group("Remove Markup") {
            for (page, annotation) in found { editor.remove(annotation, from: page, name: "Remove Markup") }
        }
        pdfView.setCurrentSelection(nil, animate: false)
    }

    // MARK: OCR and Copy Text

    @objc func recognizeText(_ sender: Any?) {
        guard let window, !model.isReadOnly else { return }
        commitEditing()
        OCRFlow.start(controller: self, window: window)
    }

    @objc func copyTextFromPage(_ sender: Any?) {
        guard let page = pdfView.currentPage else { return }
        let index = model.pdf.index(for: page)
        if !OCR.needsText(page), let text = page.string {
            Clipboard.write(text)
            HUD.show("Copied the text of page \(index + 1)", systemImage: "doc.on.doc")
            return
        }
        // A scan: read it with Vision off the main thread. Rendering happens here (PDFKit
        // pages aren't thread-safe), recognition in the background.
        guard let image = OCR.displayImage(of: page) else { return }
        HUD.show("Reading page \(index + 1)…", systemImage: "text.viewfinder")
        let recognizer = OCRFlow.recognizer
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { OCR.readingOrder(try recognizer.recognize(image)).map(\.text).joined(separator: "\n") }
            }.value
            switch result {
            case .success(let text) where !text.isEmpty:
                Clipboard.write(text)
                HUD.show("Copied the text of page \(index + 1)", systemImage: "doc.on.doc")
            case .success:
                HUD.show("No text found on page \(index + 1)", systemImage: "info.circle")
            case .failure(let error):
                if let window { NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil) }
            }
        }
    }

    // MARK: Headers and footers

    @objc func addHeadersFooters(_ sender: Any?) {
        guard let window, !model.isReadOnly else { return }
        commitEditing()
        HeadersFootersSheet.present(controller: self, window: window)
    }

    // MARK: Export

    @objc func exportImages(_ sender: Any?) {
        guard let window, let document = paperDocument else { return }
        commitEditing()
        ExportImagesSheet.present(on: window, document: document, model: model)
    }

    @objc func saveProtectedCopy(_ sender: Any?) {
        showInspector(.security)
    }

    // MARK: Sharing

    /// What the Share button and menu hand to the share sheet: the saved file, or for an
    /// untitled or edited document, a fresh copy of what's on screen.
    ///
    /// The toolbar item asks for these whenever AppKit validates the toolbar, so asking
    /// mustn't end text editing (`finishEditing: false`); form entries are still picked up.
    func shareItems(finishEditing: Bool = true) -> [Any] {
        if finishEditing { commitEditing() } else { canvasFormMayHaveChanged() }
        guard let document = paperDocument else { return [] }
        if let url = document.fileURL, !document.isDocumentEdited { return [url] }
        // The same copy until the document changes, however often the toolbar asks.
        if let cached = shareCopy, cached.revision == model.annotationsRevision &* 1_000 &+ model.infoRevision, FileManager.default.fileExists(atPath: cached.url.path) {
            return [cached.url]
        }
        guard let data = try? document.data(ofType: "com.adobe.pdf"),
              let url = ShareFiles.write(data, name: Exporting.baseName(document) + ".pdf") else { return [] }
        shareCopy = (model.annotationsRevision &* 1_000 &+ model.infoRevision, url)
        return [url]
    }

    @objc func shareDocument(_ sender: Any?) {
        showSharePicker(items: shareItems())
    }

    @objc func shareFlattenedCopy(_ sender: Any?) {
        guard let document = paperDocument, let source = document.pdf.dataRepresentation() else { return }
        commitEditing()
        let name = Exporting.baseName(document) + " (flattened).pdf"
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try Flattener.flatten(source) } }.value
            switch result {
            case .success(let data):
                guard let url = ShareFiles.write(data, name: name) else { return }
                showSharePicker(items: [url])
            case .failure(let error):
                if let window { NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil) }
            }
        }
    }

    private func showSharePicker(items: [Any]) {
        guard !items.isEmpty, let content = window?.contentView else { return }
        let picker = NSSharingServicePicker(items: items)
        // Under the toolbar's right side, where the Share button sits.
        let anchor = NSRect(x: content.bounds.maxX - 120, y: content.safeAreaRect.maxY - 2, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: content, preferredEdge: .minY)
    }

    // MARK: Editing bar and inspector

    @objc func toggleEditingBar(_ sender: Any?) {
        model.showsEditingBar.toggle()
    }

    @objc func showDocumentInspector(_ sender: Any?) { showInspector(.document) }
    @objc func showSecurityInspector(_ sender: Any?) { showInspector(.security) }
    @objc func showSelectionInspector(_ sender: Any?) { showInspector(.selection) }

    func showInspector(_ tab: InspectorTab) {
        model.inspectorTab = tab
        guard inspectorItem.isCollapsed else { return }
        if Snapshots.isActive { inspectorItem.isCollapsed = false } else { inspectorItem.animator().isCollapsed = false }
    }

    @objc func paperToggleInspector(_ sender: Any?) {
        inspectorItem.animator().isCollapsed.toggle()
    }

    func validateParityItem(_ item: NSMenuItem) -> Bool? {
        let editable = !model.isReadOnly
        switch item.action {
        case #selector(chooseDrawing(_:)):
            let raw = item.representedObject as? String
            item.state = (model.tool == .shape && raw == model.shapeKind.rawValue) || (model.tool == .draw && raw == "freehand") ? .on : .off
            return editable
        case #selector(chooseComment(_:)):
            item.state = (item.representedObject as? String) == model.tool.rawValue ? .on : .off
            return editable
        case #selector(highlightSearchResults(_:)):
            return editable && !model.searchHits.isEmpty
        case #selector(removeMarkupFromSelection(_:)):
            return editable && !(pdfView.currentSelection?.string ?? "").isEmpty
        case #selector(findAndHighlight(_:)):
            return editable
        case #selector(addHeadersFooters(_:)):
            return editable && !model.isLocked
        case #selector(recognizeText(_:)):
            return editable && !model.isLocked
        case #selector(copyTextFromPage(_:)):
            return !model.isLocked && model.facts.allowsCopying
        case #selector(exportImages(_:)), #selector(shareFlattenedCopy(_:)), #selector(saveProtectedCopy(_:)):
            return !model.isLocked && model.facts.allowsCopying
        case #selector(shareDocument(_:)):
            return !model.isLocked
        case #selector(toggleEditingBar(_:)):
            item.title = model.showsEditingBar ? "Hide Editing Bar" : "Show Editing Bar"
            return !model.isLocked
        case #selector(paperToggleInspector(_:)):
            item.title = inspectorItem.isCollapsed ? "Show Inspector" : "Hide Inspector"
            return !model.isLocked
        case #selector(showDocumentInspector(_:)), #selector(showSecurityInspector(_:)), #selector(showSelectionInspector(_:)):
            let tab: InspectorTab = item.action == #selector(showDocumentInspector(_:)) ? .document
                : item.action == #selector(showSecurityInspector(_:)) ? .security : .selection
            item.state = !inspectorItem.isCollapsed && model.inspectorTab == tab ? .on : .off
            return !model.isLocked
        default:
            return nil
        }
    }
}

/// Copies for sharing go in a private temporary folder, cleared at the next launch.
enum ShareFiles {
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Paper Share", isDirectory: true)
    }

    static func write(_ data: Data, name: String) -> URL? {
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func clearOld() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// The pasteboard Paper writes to. PAPER_PASTEBOARD names a private one for tests, so test
/// runs never touch the real clipboard.
@MainActor
enum Clipboard {
    static var board: NSPasteboard {
        ProcessInfo.processInfo.environment["PAPER_PASTEBOARD"].map { NSPasteboard(name: .init($0)) } ?? .general
    }

    static func write(_ text: String) {
        board.clearContents()
        board.setString(text, forType: .string)
    }
}
