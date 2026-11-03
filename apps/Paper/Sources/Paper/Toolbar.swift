import AppKit
import PDFKit
import PaperCore

extension NSToolbarItem.Identifier {
    static let page = NSToolbarItem.Identifier("page")
    static let zoom = NSToolbarItem.Identifier("zoom")
    static let tools = NSToolbarItem.Identifier("tools")
    static let search = NSToolbarItem.Identifier("search")
    static let applyRedactions = NSToolbarItem.Identifier("applyRedactions")
}

/// One toolbar row: sidebar, page field, zoom, the tools, search.
@MainActor
final class ToolbarController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate, NSTextFieldDelegate {
    let model: DocumentModel
    weak var owner: PaperWindowController?
    private let toolOrder: [Tool] = [.select, .highlight, .draw, .text, .note, .shape, .sign, .redact]
    private let tools = NSSegmentedControl()
    private let zoom = NSSegmentedControl()
    private let pageField = NSTextField()
    private let pageCountLabel = NSTextField(labelWithString: "")
    private var searchItem: NSSearchToolbarItem?

    init(model: DocumentModel) {
        self.model = model
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "PaperDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        configureTools()
        configureZoom()
        configurePageField()
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .page, .zoom, .flexibleSpace, .tools, .flexibleSpace, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .page, .zoom, .tools, .search, .applyRedactions, .print, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .page:
            let stack = NSStackView(views: [pageField, pageCountLabel])
            stack.spacing = 4
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = stack
            item.label = "Page"
            item.paletteLabel = "Page"
            item.toolTip = "Go to page (⌥⌘G)"
            return item
        case .zoom:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = zoom
            item.label = "Zoom"
            item.paletteLabel = "Zoom"
            return item
        case .tools:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = tools
            item.label = "Tools"
            item.paletteLabel = "Tools"
            return item
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.searchField.placeholderString = "Search"
            item.searchField.sendsWholeSearchString = true
            item.searchField.sendsSearchStringImmediately = false
            item.searchField.delegate = self
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            item.searchField.setAccessibilityLabel("Search document")
            item.label = "Search"
            item.preferredWidthForSearchField = 200
            searchItem = item
            return item
        case .applyRedactions:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "checkmark.rectangle", accessibilityDescription: "Apply Redactions")
            item.label = "Apply Redactions"
            item.paletteLabel = "Apply Redactions"
            item.action = #selector(PaperWindowController.applyRedactions(_:))
            return item
        default:
            return NSToolbarItem(itemIdentifier: id)
        }
    }

    // MARK: Controls

    private func configureTools() {
        tools.segmentCount = toolOrder.count
        tools.trackingMode = .selectOne
        tools.segmentStyle = .separated
        for (index, tool) in toolOrder.enumerated() {
            tools.setImage(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title), forSegment: index)
            tools.setToolTip("\(tool.title) (⌘\(tool.shortcut))", forSegment: index)
            tools.setWidth(32, forSegment: index)
            switch tool {
            case .highlight:
                tools.setMenu(highlightMenu(), forSegment: index)
                tools.setShowsMenuIndicator(true, forSegment: index)
            case .shape:
                tools.setMenu(shapeMenu(), forSegment: index)
                tools.setShowsMenuIndicator(true, forSegment: index)
            default:
                break
            }
        }
        tools.target = self
        tools.action = #selector(toolClicked(_:))
        tools.setAccessibilityLabel("Tools")
    }

    private func highlightMenu() -> NSMenu {
        let menu = NSMenu()
        for style in MarkupStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(PaperWindowController.chooseMarkupStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for color in InkColor.highlighters {
            let item = NSMenuItem(title: color.title, action: #selector(PaperWindowController.chooseHighlightColor(_:)), keyEquivalent: "")
            item.representedObject = color.rawValue
            item.image = ColorSwatch.image(color.nsColor)
            menu.addItem(item)
        }
        return menu
    }

    private func shapeMenu() -> NSMenu {
        let menu = NSMenu()
        for kind in ShapeKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(PaperWindowController.chooseShape(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func configureZoom() {
        zoom.segmentCount = 2
        zoom.trackingMode = .momentary
        zoom.setImage(NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom Out"), forSegment: 0)
        zoom.setImage(NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom In"), forSegment: 1)
        zoom.setToolTip("Zoom Out (⌘−)", forSegment: 0)
        zoom.setToolTip("Zoom In (⌘+)", forSegment: 1)
        zoom.target = self
        zoom.action = #selector(zoomClicked(_:))
        zoom.setAccessibilityLabel("Zoom")
    }

    private func configurePageField() {
        pageField.alignment = .right
        pageField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        pageField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        pageField.target = self
        pageField.action = #selector(pageEntered(_:))
        pageField.delegate = self
        pageField.setAccessibilityLabel("Page number")
        pageCountLabel.textColor = .secondaryLabelColor
        pageCountLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    func refresh() {
        let count = model.pdf.pageCount
        if pageField.currentEditor() == nil {
            pageField.stringValue = model.isLocked || count == 0 ? "" : "\(model.currentPageIndex + 1)"
        }
        pageCountLabel.stringValue = model.isLocked ? "" : "of \(count)"
        pageField.isEnabled = !model.isLocked
        if let index = toolOrder.firstIndex(of: model.tool) { tools.selectedSegment = index }
        for (index, tool) in toolOrder.enumerated() {
            tools.setEnabled(!model.isLocked && (!model.isReadOnly || tool == .select), forSegment: index)
        }
        zoom.isEnabled = !model.isLocked
        searchItem?.searchField.isEnabled = !model.isLocked
    }

    @objc private func toolClicked(_ sender: NSSegmentedControl) {
        let tool = toolOrder[sender.selectedSegment]
        owner?.setTool(tool)
    }

    /// Pops the Sign menu under its toolbar segment. Nil when the toolbar isn't showing it.
    @discardableResult
    func showSignatureMenu() -> Void? {
        guard let owner, tools.window != nil, let index = toolOrder.firstIndex(of: .sign) else { return nil }
        var x: CGFloat = 0
        for segment in 0..<index { x += tools.width(forSegment: segment) + 4 }
        let menu = SignatureMenu.build(target: owner)
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: tools.bounds.maxY + 6), in: tools)
        return ()
    }

    @objc private func zoomClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { owner?.paperZoomOut(nil) } else { owner?.paperZoomIn(nil) }
    }

    @objc private func pageEntered(_ sender: NSTextField) {
        guard let number = Int(sender.stringValue.trimmingCharacters(in: .whitespaces)), number >= 1 else {
            refresh()
            return
        }
        owner?.goToPage(min(number, model.pdf.pageCount) - 1)
        owner?.window?.makeFirstResponder(owner?.pdfView)
        refresh()
    }

    func focusPageField() {
        pageField.window?.makeFirstResponder(pageField)
        pageField.selectText(nil)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        owner?.search(sender.stringValue)
    }

    func focusSearch() {
        guard let searchItem else { return }
        searchItem.beginSearchInteraction()
    }

    func setSearchText(_ text: String) {
        searchItem?.searchField.stringValue = text
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if control === searchItem?.searchField {
                searchItem?.searchField.stringValue = ""
                owner?.clearSearch()
                owner?.window?.makeFirstResponder(owner?.pdfView)
                return true
            }
            if control === pageField {
                refresh()
                owner?.window?.makeFirstResponder(owner?.pdfView)
                return true
            }
        }
        if selector == #selector(NSResponder.insertNewline(_:)), control === searchItem?.searchField {
            let text = searchItem?.searchField.stringValue ?? ""
            if !text.isEmpty, text == model.searchedQuery, !model.searchHits.isEmpty {
                owner?.findNext(nil)
                return true
            }
        }
        return false
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        owner?.clearSearch()
    }
}

/// The Sign menu: saved signatures, a new one, today's date, and deleting old ones.
@MainActor
enum SignatureMenu {
    static func build(target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: "Sign")
        let signatures = SignatureLibraryStore.shared.signatures
        for (offset, signature) in signatures.enumerated() {
            let kind = signature.kind == .initials ? "Initials" : "Signature"
            let item = NSMenuItem(title: "\(kind) \(offset + 1)", action: #selector(PaperWindowController.placeSignature(_:)), keyEquivalent: "")
            item.representedObject = signature.id
            item.image = SignatureImage.image(signature, height: 28)
            item.target = target
            item.setAccessibilityLabel("\(kind) \(offset + 1), saved \(signature.created.formatted(date: .abbreviated, time: .omitted))")
            menu.addItem(item)
        }
        if !signatures.isEmpty { menu.addItem(.separator()) }
        let new = NSMenuItem(title: "New Signature…", action: #selector(PaperWindowController.newSignature(_:)), keyEquivalent: "")
        new.target = target
        menu.addItem(new)
        let date = NSMenuItem(title: "Add Today's Date", action: #selector(PaperWindowController.insertTodaysDate(_:)), keyEquivalent: "")
        date.target = target
        menu.addItem(date)
        if !signatures.isEmpty {
            let delete = NSMenuItem(title: "Delete Signature", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (offset, signature) in signatures.enumerated() {
                let kind = signature.kind == .initials ? "Initials" : "Signature"
                let item = NSMenuItem(title: "\(kind) \(offset + 1)", action: #selector(PaperWindowController.deleteSignature(_:)), keyEquivalent: "")
                item.representedObject = signature.id
                item.image = SignatureImage.image(signature, height: 20)
                item.target = target
                submenu.addItem(item)
            }
            delete.submenu = submenu
            menu.addItem(delete)
        }
        return menu
    }
}

/// Renders a saved signature for menus and previews.
enum SignatureImage {
    static func image(_ signature: Signature, height: CGFloat) -> NSImage {
        let width = min(height * max(signature.aspect, 0.5), height * 5)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.labelColor.setStroke()
            for stroke in signature.strokes(fitting: rect.insetBy(dx: 2, dy: 2)) {
                let path = InkSmoothing.path(through: stroke, lineWidth: 1.3)
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = signature.kind == .initials ? "Initials" : "Signature"
        return image
    }
}
