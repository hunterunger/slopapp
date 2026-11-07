import AppKit
import PDFKit
import PaperCore
import SlopKit

extension NSToolbarItem.Identifier {
    static let page = NSToolbarItem.Identifier("page")
    static let zoom = NSToolbarItem.Identifier("zoom")
    static let fitWidth = NSToolbarItem.Identifier("fitWidth")
    static let scale = NSToolbarItem.Identifier("scale")
    static let search = NSToolbarItem.Identifier("search")
    static let share = NSToolbarItem.Identifier("share")
    static let applyRedactions = NSToolbarItem.Identifier("applyRedactions")
    static func group(_ group: ToolGroup) -> NSToolbarItem.Identifier { NSToolbarItem.Identifier("group." + group.rawValue) }
}

/// The toolbar's tool groups. Each is a button and a dropdown: the button repeats the last
/// tool used from the group, the dropdown lists them all (the original's layout, research §2).
enum ToolGroup: String, CaseIterable {
    case select, highlight, draw, comment, sign, redact

    var label: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .draw: "Draw"
        case .comment: "Comment"
        case .sign: "Sign"
        case .redact: "Redact"
        }
    }

    func contains(_ tool: Tool) -> Bool {
        switch self {
        case .select: tool == .select
        case .highlight: tool == .highlight
        case .draw: tool == .draw || tool == .shape
        case .comment: tool == .text || tool == .note
        case .sign: tool == .sign
        case .redact: tool == .redact
        }
    }

    var hasMenu: Bool { self != .select }

    @MainActor
    func tool(in model: DocumentModel) -> Tool {
        switch self {
        case .select: .select
        case .highlight: .highlight
        case .draw: model.drawUsesShape ? .shape : .draw
        case .comment: model.commentUsesNote ? .note : .text
        case .sign: .sign
        case .redact: .redact
        }
    }

    @MainActor
    func symbol(in model: DocumentModel) -> String {
        switch self {
        case .highlight:
            switch model.markupStyle {
            case .highlight: return "highlighter"
            case .underline: return "underline"
            case .strikeOut: return "strikethrough"
            }
        case .draw:
            guard model.drawUsesShape else { return Tool.draw.symbol }
            switch model.shapeKind {
            case .rectangle: return "rectangle"
            case .oval: return "circle"
            case .line: return "line.diagonal"
            case .arrow: return "arrow.up.right"
            }
        default:
            return tool(in: model).symbol
        }
    }

    @MainActor
    func help(in model: DocumentModel) -> String {
        let tool = tool(in: model)
        switch self {
        case .highlight: return "\(model.markupStyle.title) (⌘\(tool.shortcut))"
        case .draw where model.drawUsesShape: return "\(model.shapeKind.title) (⌘\(tool.shortcut))"
        default: return "\(tool.title) (⌘\(tool.shortcut))"
        }
    }
}

/// One toolbar row, labeled like the original's: sidebar, zoom, fit width, scale, page;
/// the tool groups; search, share and the inspector.
@MainActor
final class ToolbarController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate, NSTextFieldDelegate,
    NSComboBoxDelegate, NSSharingServicePickerToolbarItemDelegate {
    let model: DocumentModel
    weak var owner: PaperWindowController?
    private var groups: [ToolGroup: NSSegmentedControl] = [:]
    private let zoom = NSSegmentedControl()
    private let scale = NSComboBox()
    private let pageField = NSTextField()
    private let pageCountLabel = NSTextField(labelWithString: "")
    private var searchItem: NSSearchToolbarItem?
    nonisolated static let scales = [25, 50, 75, 100, 125, 150, 200, 300, 400]

    init(model: DocumentModel) {
        self.model = model
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        // "3": the default set changed in 0.1's polish pass (Fit Width moved into the zoom
        // menu, search and share sit over the inspector), so saved layouts start fresh.
        let toolbar = NSToolbar(identifier: "PaperDocumentToolbar3")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        // Test runs (PAPER_DEFAULTS_SUITE) don't write the toolbar layout into the real domain.
        toolbar.autosavesConfiguration = !Prefs.isTestSuite
        for group in ToolGroup.allCases { groups[group] = makeGroup(group) }
        configureZoom()
        configureScale()
        configurePageField()
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Fit Width is in the zoom menu (and View > Zoom to Width, ⌥⌘9); it stays available in
        // Customize Toolbar. Search and Share sit after the inspector separator, over the
        // inspector when it's open, so the tool groups keep the canvas's width.
        [.toggleSidebar, .sidebarTrackingSeparator, .zoom, .scale, .page, .flexibleSpace]
            + ToolGroup.allCases.map(NSToolbarItem.Identifier.group)
            + [.flexibleSpace, .inspectorTrackingSeparator, .search, .share, .toggleInspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .zoom, .fitWidth, .scale, .page, .search, .share, .applyRedactions,
         .print, .toggleInspector, .inspectorTrackingSeparator, .flexibleSpace, .space]
            + ToolGroup.allCases.map(NSToolbarItem.Identifier.group)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if let group = ToolGroup.allCases.first(where: { NSToolbarItem.Identifier.group($0) == id }) {
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = flag ? groups[group] : makeGroup(group)
            item.label = group.label
            item.paletteLabel = group.label
            // When the window is narrow, zoom and page controls go to the overflow menu first:
            // they have keyboard shortcuts and gestures, the tools don't.
            item.visibilityPriority = .high
            return item
        }
        switch id {
        case .page:
            let stack = NSStackView(views: [pageField, pageCountLabel])
            stack.spacing = Spacing.xs
            stack.alignment = .firstBaseline
            // The item's capsule hugs the stack: keep "of N" off its right edge, as the
            // field's own text inset does on the left.
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: Spacing.m)
            let item = viewItem(id, stack, label: "Page", help: "Go to page (⌥⌘G)")
            item.visibilityPriority = .low
            return item
        case .zoom:
            let item = viewItem(id, zoom, label: "Zoom", help: nil)
            item.visibilityPriority = .low
            return item
        case .scale:
            let item = viewItem(id, scale, label: "Scale", help: "Zoom percentage")
            item.visibilityPriority = .low
            return item
        case .fitWidth:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: "Fit Width")
            item.label = "Fit Width"
            item.paletteLabel = "Fit Width"
            item.toolTip = "Zoom to Width (⌥⌘9)"
            item.action = #selector(PaperWindowController.zoomToWidth(_:))
            item.isBordered = true
            item.visibilityPriority = .low
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
            item.preferredWidthForSearchField = 180
            searchItem = item
            return item
        case .share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: id)
            item.delegate = self
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share this document"
            item.visibilityPriority = .low
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

    private func viewItem(_ id: NSToolbarItem.Identifier, _ view: NSView, label: String, help: String?) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = view
        item.label = label
        item.paletteLabel = label
        item.toolTip = help
        return item
    }

    // MARK: Sharing

    nonisolated func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        // Share items are file URLs, which are Sendable.
        let urls: [URL] = MainActor.assumeIsolated { owner?.shareItems().compactMap { $0 as? URL } ?? [] }
        return urls
    }

    // MARK: Tool groups

    private func makeGroup(_ group: ToolGroup) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = group.hasMenu ? 2 : 1
        control.trackingMode = .selectAny
        control.segmentStyle = .separated
        control.setWidth(30, forSegment: 0)
        if group.hasMenu {
            control.setImage(NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "\(group.label) options")?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold)), forSegment: 1)
            control.setWidth(14, forSegment: 1)
            control.setToolTip("\(group.label) options", forSegment: 1)
        }
        control.target = self
        control.action = #selector(groupClicked(_:))
        control.setAccessibilityLabel(group.label)
        control.identifier = NSUserInterfaceItemIdentifier(group.rawValue)
        return control
    }

    @objc private func groupClicked(_ sender: NSSegmentedControl) {
        guard let raw = sender.identifier?.rawValue, let group = ToolGroup(rawValue: raw) else { return }
        let segment = sender.selectedSegment
        // selectAny toggles segments on click; the model decides what's selected.
        refresh()
        if segment == 1 || group == .sign {
            showMenu(for: group)
        } else {
            owner?.setTool(group.tool(in: model))
        }
    }

    func showMenu(for group: ToolGroup) {
        guard let owner, let control = groups[group], control.window != nil else {
            if group == .sign, let owner {
                owner.canvasShowSignatureMenu(at: NSPoint(x: owner.pdfView.bounds.midX, y: owner.pdfView.bounds.midY))
            }
            return
        }
        let menu = group == .sign ? SignatureMenu.build(target: owner) : ToolMenus.menu(for: group)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: control.bounds.maxY + 4), in: control)
    }

    /// Pops the Sign menu under its toolbar group. Nil when the toolbar isn't showing it.
    @discardableResult
    func showSignatureMenu() -> Void? {
        guard let control = groups[.sign], control.window != nil else { return nil }
        showMenu(for: .sign)
        return ()
    }

    // MARK: Zoom, scale, page

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

    private func configureScale() {
        scale.addItems(withObjectValues: ScaleChoice.allCases.map(\.title))
        scale.numberOfVisibleItems = ScaleChoice.allCases.count
        scale.completes = false
        scale.alignment = .right
        scale.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Room for "1600%" beside the dropdown button without clipping.
        scale.widthAnchor.constraint(equalToConstant: 92).isActive = true
        scale.target = self
        scale.action = #selector(scaleEntered(_:))
        scale.delegate = self
        scale.setAccessibilityLabel("Zoom percentage")
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
        if scale.currentEditor() == nil {
            scale.stringValue = model.isLocked ? "" : "\(Int(((owner?.pdfView.scaleFactor ?? 1) * 100).rounded()))%"
        }
        scale.isEnabled = !model.isLocked
        for (group, control) in groups {
            let tool = group.tool(in: model)
            control.setImage(NSImage(systemSymbolName: group.symbol(in: model), accessibilityDescription: group.label), forSegment: 0)
            control.setToolTip(group.help(in: model), forSegment: 0)
            control.setSelected(group.contains(model.tool), forSegment: 0)
            if group.hasMenu { control.setSelected(false, forSegment: 1) }
            let enabled = !model.isLocked && (!model.isReadOnly || tool == .select)
            for segment in 0..<control.segmentCount { control.setEnabled(enabled, forSegment: segment) }
        }
        zoom.isEnabled = !model.isLocked
        searchItem?.searchField.isEnabled = !model.isLocked
    }

    @objc private func zoomClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { owner?.paperZoomOut(nil) } else { owner?.paperZoomIn(nil) }
    }

    @objc private func scaleEntered(_ sender: NSComboBox) {
        let digits = sender.stringValue.filter(\.isNumber)
        if let percent = Int(digits), percent > 0 {
            owner?.setScale(CGFloat(min(max(percent, 10), 1600)) / 100)
        }
        owner?.window?.makeFirstResponder(owner?.pdfView)
        refresh()
    }

    nonisolated func comboBoxSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            let index = scale.indexOfSelectedItem
            guard index >= 0, index < ScaleChoice.allCases.count else { return }
            switch ScaleChoice.allCases[index] {
            case .fit(let zoom): owner?.applyZoom(zoom)
            case .percent(let percent): owner?.setScale(CGFloat(percent) / 100)
            }
            // The list item's title stays in the field otherwise ("Fit Width").
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
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
            if control === pageField || control === scale {
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

/// The zoom dropdown: the fit modes, then fixed percentages.
enum ScaleChoice: CaseIterable {
    case fit(ZoomPreference)
    case percent(Int)

    static var allCases: [ScaleChoice] {
        [.fit(.actualSize), .fit(.fitPage), .fit(.fitWidth)] + ToolbarController.scales.map { .percent($0) }
    }

    var title: String {
        switch self {
        case .fit(let zoom): zoom.title
        case .percent(let percent): "\(percent)%"
        }
    }
}

/// The dropdown menus of the tool groups (the Sign group uses `SignatureMenu`).
@MainActor
enum ToolMenus {
    typealias W = PaperWindowController

    static func menu(for group: ToolGroup) -> NSMenu {
        let menu = NSMenu(title: group.label)
        // Text only, as menus are on macOS 27; the colour items keep their swatches (the
        // colour is the information).
        func add(_ title: String, _ action: Selector, _ object: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.representedObject = object
            menu.addItem(item)
        }
        switch group {
        case .select, .sign:
            break
        case .highlight:
            for style in MarkupStyle.allCases {
                add(style.title, #selector(W.chooseMarkupStyle(_:)), style.rawValue)
            }
            menu.addItem(.separator())
            for color in InkColor.highlighters {
                let item = NSMenuItem(title: color.title, action: #selector(W.chooseHighlightColor(_:)), keyEquivalent: "")
                item.representedObject = color.rawValue
                item.image = ColorSwatch.image(color.nsColor)
                menu.addItem(item)
            }
            menu.addItem(.separator())
            add("Highlight All Search Results", #selector(W.highlightSearchResults(_:)))
            add("Remove Markup from Selection", #selector(W.removeMarkupFromSelection(_:)))
        case .draw:
            add("Freehand", #selector(W.chooseDrawing(_:)), "freehand")
            for kind in ShapeKind.allCases {
                add(kind.title, #selector(W.chooseDrawing(_:)), kind.rawValue)
            }
        case .comment:
            add("Text Box", #selector(W.chooseComment(_:)), Tool.text.rawValue)
            add("Note", #selector(W.chooseComment(_:)), Tool.note.rawValue)
            menu.addItem(.separator())
            add("Add Today's Date", #selector(W.insertTodaysDate(_:)))
        case .redact:
            add("Mark for Redaction", #selector(W.chooseTool(_:)), Tool.redact.rawValue)
            add("Find and Redact…", #selector(W.showFindAndRedact(_:)))
            menu.addItem(.separator())
            add("Apply Redactions…", #selector(W.applyRedactions(_:)))
            add("Remove All Marks", #selector(W.removeAllMarks(_:)))
        }
        return menu
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
        let fromImage = NSMenuItem(title: "New Signature from Image…", action: #selector(PaperWindowController.newSignatureFromImage(_:)), keyEquivalent: "")
        fromImage.target = target
        menu.addItem(fromImage)
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
    static func image(_ signature: Signature, height: CGFloat, template: Bool = true) -> NSImage {
        let width = min(height * max(signature.aspect, 0.5), height * 5)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            (template ? NSColor.labelColor : NSColor.black).setStroke()
            let area = rect.insetBy(dx: 2, dy: 2)
            let fit = Signature.fitted(aspect: signature.aspect, in: area)
            let lineWidth = signature.lineWidth.map { $0 * fit.width } ?? 1.3
            for stroke in signature.strokes(fitting: area) {
                InkSmoothing.path(through: stroke, lineWidth: lineWidth).stroke()
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = signature.kind == .initials ? "Initials" : "Signature"
        return image
    }
}
