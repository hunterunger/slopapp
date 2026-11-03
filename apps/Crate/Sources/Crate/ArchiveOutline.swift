import AppKit
import CrateCore
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// The archive's contents in an `NSOutlineView`: fast with 100k rows, sortable columns,
/// ←/→ to collapse and expand, Space for Quick Look, double-click to open, and rows that
/// drag out to Finder as file promises.
struct ArchiveOutline: NSViewRepresentable {
    let model: BrowseModel
    let tree: ArchiveTree
    /// Expand everything (while filtering, so matches show).
    let expandAll: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = ArchiveOutlineView()
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.allowsColumnReordering = true
        outline.allowsColumnResizing = true
        outline.autosaveExpandedItems = false
        outline.style = .inset
        outline.rowSizeStyle = .default
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.onSpace = { [weak coordinator = context.coordinator] in coordinator?.model.toggleQuickLook() }
        outline.quickLook = model.quickLook
        model.quickLook.outline = outline
        outline.setAccessibilityLabel("Archive contents")

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.minWidth
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            if column == .size { tableColumn.headerCell.alignment = .right }
            outline.addTableColumn(tableColumn)
            if column == .name { outline.outlineTableColumn = tableColumn }
        }
        outline.autosaveName = "ArchiveColumns"
        outline.autosaveTableColumns = true
        outline.menu = context.coordinator.makeMenu()

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        context.coordinator.outline = outline
        context.coordinator.show(tree, expandAll: expandAll)
        // Fit the columns to the window: the name column takes up the difference.
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll, let name = outline.tableColumns.first(where: { $0.identifier == Column.name.identifier }) else { return }
            let others = outline.tableColumns.filter { $0 !== name }.reduce(0) { $0 + $1.width + outline.intercellSpacing.width }
            let available = scroll.contentSize.width - others - outline.intercellSpacing.width - 24
            if available > name.minWidth, abs(name.width - available) > 1 { name.width = available }
        }
        DispatchQueue.main.async { outline.window?.makeFirstResponder(outline) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.show(tree, expandAll: expandAll)
    }

    enum Column: String, CaseIterable {
        case name, size, modified, kind
        var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }
        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Size"
            case .modified: "Date Modified"
            case .kind: "Kind"
            }
        }
        var width: CGFloat {
            switch self {
            case .name: 220
            case .size: 72
            case .modified: 165
            case .kind: 110
            }
        }
        var minWidth: CGFloat {
            switch self {
            case .name: 140
            case .size: 64
            case .modified: 110
            case .kind: 80
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var model: BrowseModel
        weak var outline: ArchiveOutlineView?
        private var tree: ArchiveTree = .empty
        private var roots: [ArchiveNode] = []
        private var sortedChildren: [ObjectIdentifier: [ArchiveNode]] = [:]
        private var sort = NSSortDescriptor(key: Column.name.rawValue, ascending: true)
        private var isUpdatingSelection = false
        private let promises = PromiseDelegate()

        init(model: BrowseModel) {
            self.model = model
        }

        func show(_ newTree: ArchiveTree, expandAll: Bool) {
            guard let outline else { return }
            let same = newTree.roots.count == tree.roots.count && zip(newTree.roots, tree.roots).allSatisfy { $0 === $1 }
            guard !same else { return }
            tree = newTree
            sortedChildren = [:]
            roots = sorted(newTree.roots)
            outline.reloadData()
            if expandAll, newTree.itemCount < 5_000 {
                outline.expandItem(nil, expandChildren: true)
            } else if roots.count == 1, roots[0].isFolder {
                // A single top folder opens, so the first view shows real contents.
                outline.expandItem(roots[0])
            }
        }

        private func children(of item: Any?) -> [ArchiveNode] {
            guard let node = item as? ArchiveNode else { return roots }
            let key = ObjectIdentifier(node)
            if let cached = sortedChildren[key] { return cached }
            let result = sorted(node.children ?? [])
            sortedChildren[key] = result
            return result
        }

        private func sorted(_ nodes: [ArchiveNode]) -> [ArchiveNode] {
            let ascending = sort.ascending
            let key = Column(rawValue: sort.key ?? "") ?? .name
            return nodes.sorted { a, b in
                if a.isFolder != b.isFolder, key == .name { return a.isFolder }
                let order: ComparisonResult = switch key {
                case .name: a.name.localizedStandardCompare(b.name)
                case .size: a.size == b.size ? a.name.localizedStandardCompare(b.name) : (a.size < b.size ? .orderedAscending : .orderedDescending)
                case .modified:
                    (a.modified ?? .distantPast) == (b.modified ?? .distantPast) ? a.name.localizedStandardCompare(b.name)
                        : ((a.modified ?? .distantPast) < (b.modified ?? .distantPast) ? .orderedAscending : .orderedDescending)
                case .kind: Self.kind(of: a).localizedStandardCompare(Self.kind(of: b))
                }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? ArchiveNode)?.children?.isEmpty == false
        }

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let first = outlineView.sortDescriptors.first else { return }
            sort = first
            sortedChildren = [:]
            roots = sorted(tree.roots)
            let selected = model.selection
            outlineView.reloadData()
            let rows = IndexSet(selected.map { outlineView.row(forItem: $0) }.filter { $0 >= 0 })
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        }

        // MARK: Cells

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? ArchiveNode, let id = tableColumn?.identifier,
                  let column = Column(rawValue: id.rawValue) else { return nil }
            let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? ArchiveCell) ?? ArchiveCell(column: column)
            cell.identifier = id
            switch column {
            case .name:
                cell.configureName(node.name, originalName: node.originalName, icon: Self.icon(for: node),
                                   encrypted: node.isEncrypted && !node.isFolder, label: Self.accessibilityLabel(for: node))
            case .size:
                cell.configureText((node.isFolder && node.size == 0) || node.kind == .symlink || !node.sizeKnown ? "--"
                                   : ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file),
                                   alignment: .right, secondary: true)
            case .modified:
                cell.configureText(node.modified.map { Self.dateFormatter.string(from: $0) } ?? "--",
                                   alignment: .left, secondary: true)
            case .kind:
                cell.configureText(Self.kind(of: node), alignment: .left, secondary: true)
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outline else { return }
            model.selection = outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? ArchiveNode }
        }

        // MARK: Actions

        @objc func doubleClicked(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let node = sender.item(atRow: row) as? ArchiveNode else { return }
            if node.isFolder {
                sender.isItemExpanded(node) ? sender.collapseItem(node) : sender.expandItem(node)
            } else {
                model.open(node)
            }
        }

        // MARK: Dragging out

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let node = item as? ArchiveNode, let context = model.promiseContext else { return nil }
            let type = node.isFolder ? UTType.folder : (UTType(filenameExtension: (node.name as NSString).pathExtension) ?? .data)
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: promises)
            provider.userInfo = PromiseItem(context: context, path: node.archivePath, name: node.originalName ?? node.name)
            return provider
        }

        // MARK: Menu

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, outline.clickedRow >= 0 else { return }
            if !outline.selectedRowIndexes.contains(outline.clickedRow) {
                outline.selectRowIndexes([outline.clickedRow], byExtendingSelection: false)
            }
            let node = outline.item(atRow: outline.clickedRow) as? ArchiveNode
            func add(_ title: String, _ action: @escaping @MainActor () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
                let target = MenuAction(action)
                item.target = target
                item.representedObject = target
                item.isEnabled = model.canExtract
                menu.addItem(item)
            }
            if let node, !node.isFolder {
                add("Open") { [weak self] in self?.model.open(node) }
                add("Quick Look") { [weak self] in self?.model.toggleQuickLook() }
                menu.addItem(.separator())
            }
            let count = model.selection.count
            add(count == 1 ? "Extract" : "Extract \(count) Items") { [weak self] in self?.model.extractSelection() }
            add("Extract To…") { [weak self] in self?.model.extractSelectionTo() }
        }

        // MARK: Labels

        /// "Today at 9:41 AM", "3/3/24, 10:02 AM": short enough for a narrow column.
        static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }()

        private static var iconCache: [String: NSImage] = [:]

        static func icon(for node: ArchiveNode) -> NSImage {
            let key: String
            let type: UTType
            if node.isFolder {
                key = "/folder"
                type = .folder
            } else if node.kind == .symlink {
                key = "/link"
                type = .symbolicLink
            } else {
                let ext = (node.name as NSString).pathExtension.lowercased()
                key = ext
                type = UTType(filenameExtension: ext) ?? .data
            }
            if let cached = iconCache[key] { return cached }
            let image = NSWorkspace.shared.icon(for: type)
            iconCache[key] = image
            return image
        }

        private static var kindCache: [String: String] = [:]

        static func kind(of node: ArchiveNode) -> String {
            if node.isFolder {
                return node.itemCount == 1 ? "Folder, 1 item" : "Folder, \(node.itemCount.formatted()) items"
            }
            if node.kind == .symlink { return "Link" }
            let ext = (node.name as NSString).pathExtension.lowercased()
            if let cached = kindCache[ext] { return cached }
            var kind = UTType(filenameExtension: ext)?.localizedDescription ?? "Document"
            if let first = kind.first, first.isLowercase { kind = first.uppercased() + kind.dropFirst() }
            kindCache[ext] = kind
            return kind
        }

        static func accessibilityLabel(for node: ArchiveNode) -> String {
            var parts = [node.name]
            if node.isFolder {
                parts.append(node.itemCount == 1 ? "folder, 1 item" : "folder, \(node.itemCount) items")
            } else if node.sizeKnown {
                parts.append(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
            } else {
                parts.append("size unknown")
            }
            if node.isEncrypted && !node.isFolder { parts.append("encrypted") }
            if let original = node.originalName { parts.append("renamed from \(original), another item has that name") }
            return parts.joined(separator: ", ")
        }
    }
}

/// Space opens Quick Look; everything else is the standard outline behaviour. Takes
/// control of the Quick Look panel while it's the first responder.
final class ArchiveOutlineView: NSOutlineView {
    var onSpace: (() -> Void)?
    weak var quickLook: QuickLookController?

    // The panel calls these on the main thread.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { quickLook != nil }
    }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { if let panel { quickLook?.take(panel) } }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { if let panel { quickLook?.release(panel) } }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}

/// A row cell: icon + name (+ lock) for the name column, plain text for the others.
final class ArchiveCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let lock = NSImageView()

    init(column: ArchiveOutline.Column) {
        super.init(frame: .zero)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        if column == .name {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.setAccessibilityElement(false)
            addSubview(icon)
            imageView = icon
            lock.translatesAutoresizingMaskIntoConstraints = false
            lock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Encrypted")
            lock.contentTintColor = .secondaryLabelColor
            lock.symbolConfiguration = .init(scale: .small)
            lock.setAccessibilityElement(false)
            addSubview(lock)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                lock.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
                lock.centerYAnchor.constraint(equalTo: centerYAnchor),
                lock.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configureName(_ name: String, originalName: String?, icon image: NSImage, encrypted: Bool, label accessibility: String) {
        if let originalName {
            // "readme 2  was “readme”": the name it will get, and why.
            let text = NSMutableAttributedString(string: name, attributes: [.foregroundColor: NSColor.labelColor])
            text.append(NSAttributedString(string: "  was “\(originalName)”", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]))
            label.attributedStringValue = text
            toolTip = "Another item in the archive is also called “\(originalName)”, so this one is extracted as “\(name)”. Nothing is overwritten."
        } else {
            label.stringValue = name
            label.textColor = .labelColor
            toolTip = nil
        }
        icon.image = image
        lock.isHidden = !encrypted
        setAccessibilityLabel(accessibility)
        label.setAccessibilityLabel(accessibility)
    }

    func configureText(_ text: String, alignment: NSTextAlignment, secondary: Bool) {
        label.stringValue = text
        label.alignment = alignment
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.font = alignment == .right
            ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
    }
}

/// A closure as a menu item target.
final class MenuAction: NSObject {
    private let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor @objc func run() { action() }
}

/// What one dragged row needs to be written out.
struct PromiseItem: Sendable {
    let context: PromiseContext
    let path: String
    let name: String
}

/// Writes dragged rows into the Finder folder they're dropped on, off the main thread.
final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? PromiseItem)?.name ?? "Item"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping ((any Error)?) -> Void) {
        guard let item = filePromiseProvider.userInfo as? PromiseItem else {
            completionHandler(CrateError.unreadableSource(name: url.lastPathComponent))
            return
        }
        do {
            _ = try Extractor().extract(
                item.context.source, to: url.deletingLastPathComponent(),
                options: ExtractionOptions(password: item.context.password, selection: [item.path], layout: .loose)
            )
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }
}
