import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// The commit list with its graph, streamed in.
struct HistoryColumn: View {
    @Bindable var model: RepoModel

    var body: some View {
        let _ = model.historyRevision
        ZStack {
            HistoryTable(model: model, revision: model.historyRevision)
            if model.status.branch.isUnborn && model.sidebarSelection == .history {
                ContentUnavailableView {
                    Label("No Commits Yet", systemImage: "clock")
                } description: {
                    Text("Your first commit will appear here.")
                } actions: {
                    Button("Go to Changes") { model.sidebarSelection = .changes }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            } else if let failed = model.history.failed {
                ContentUnavailableView("Couldn't Load History", systemImage: "exclamationmark.triangle", description: Text(failed))
                    .background(Color(nsColor: .controlBackgroundColor))
            } else if !model.history.isLoading, model.history.filtered?.isEmpty == true {
                ContentUnavailableView.search(text: model.searchText)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }
}

/// Lane colours: system colours, adjusted to keep 3:1 against the list in both modes.
enum LanePalette {
    static let base: [NSColor] = [.systemBlue, .systemPurple, .systemOrange, .systemTeal, .systemPink, .systemGreen, .systemIndigo, .systemBrown]

    static let colors: [NSColor] = base.map { .readable($0, on: .controlBackgroundColor, target: ReadableColor.symbolTarget) }

    static func color(_ index: UInt8) -> NSColor { colors[Int(index) % colors.count] }
}

struct HistoryTable: NSViewRepresentable {
    let model: RepoModel
    let revision: Int

    func makeCoordinator() -> HistoryCoordinator { HistoryCoordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = HistoryNSTableView()
        table.style = .inset
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 4, height: 0)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        // Two columns, no header: the graph, and the commit (subject and labels, then author,
        // date and hash). Fits the middle column at any width.
        for (id, title, width, min) in [("graph", "Graph", 40.0, 16.0), ("subject", "Commit", 300.0, 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = min
            table.addTableColumn(column)
        }
        table.headerView = nil
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.coordinator = context.coordinator
        table.setAccessibilityLabel("History")
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        table.target = context.coordinator
        table.doubleAction = #selector(HistoryCoordinator.doubleClicked(_:))
        // Commits can be dragged onto the current branch in the sidebar (cherry-pick), or into
        // any text field as their hashes.
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        context.coordinator.table = table
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.sync()
    }
}

@MainActor
final class HistoryCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    weak var table: HistoryNSTableView?
    var model: RepoModel
    private var shownRows = 0
    private var shownScope: HistoryScope?
    private var shownFilter: [Int]?
    private var shownUncommitted = false
    private var applyingSelection = false
    private let relativeNow = Date()

    init(model: RepoModel) {
        self.model = model
    }

    private var history: HistoryStore { model.history }
    private var hasUncommittedRow: Bool { model.showsUncommittedRow && history.filtered == nil }

    /// Reloads only what changed: appended rows are added without disturbing scroll or selection.
    func sync() {
        guard let table else { return }
        let count = history.filtered?.count ?? history.rows.count
        let uncommitted = hasUncommittedRow
        let graphColumn = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("graph"))
        graphColumn?.isHidden = history.filtered != nil
        if shownScope != history.scope || shownFilter != history.filtered || uncommitted != shownUncommitted || count < shownRows {
            shownScope = history.scope
            shownFilter = history.filtered
            shownUncommitted = uncommitted
            shownRows = count
            table.reloadData()
            sizeGraphColumn()
        } else if count > shownRows {
            let start = shownRows + (uncommitted ? 1 : 0)
            table.insertRows(at: IndexSet(start..<(count + (uncommitted ? 1 : 0))), withAnimation: [])
            shownRows = count
            sizeGraphColumn()
        } else if uncommitted, let view = table.view(atColumn: table.column(withIdentifier: NSUserInterfaceItemIdentifier("subject")), row: 0, makeIfNecessary: false) as? CommitCellView {
            view.configure(subject: uncommittedTitle, labels: [], details: "Not committed yet", italic: true)
        }
        syncSelection()
    }

    private func sizeGraphColumn() {
        guard let table, let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("graph")) else { return }
        let lanes = min(GraphCellView.maxDrawnLanes, max(1, history.layout.lanes(in: 0..<min(history.rows.count, 2000))))
        let width = CGFloat(lanes) * GraphCellView.laneWidth + Spacing.s
        if abs(column.width - width) > 1 { column.width = width }
    }

    private func syncSelection() {
        guard let table else { return }
        // A multiple selection made in the table stays as it is.
        if table.selectedRowIndexes.count > 1, model.selectedCommits.count > 1 { return }
        let wanted: Int?
        if model.historySelection == nil {
            wanted = nil
        } else if let id = model.historySelection, let index = rowIndex(of: id) {
            wanted = index
        } else {
            wanted = nil
        }
        let current = table.selectedRow >= 0 ? table.selectedRow : nil
        if wanted != current, let wanted {
            applyingSelection = true
            table.selectRowIndexes([wanted], byExtendingSelection: false)
            applyingSelection = false
        }
    }

    private func rowIndex(of id: ObjectID) -> Int? {
        let offset = hasUncommittedRow ? 1 : 0
        if let filtered = history.filtered {
            return filtered.firstIndex { history.rows[$0].id == id }.map { $0 + offset }
        }
        return history.rows.firstIndex { $0.id == id }.map { $0 + offset }
    }

    /// Table row → history row index (nil for the Uncommitted Changes row).
    func historyIndex(ofTableRow row: Int) -> Int? {
        let offset = hasUncommittedRow ? 1 : 0
        if row < offset { return nil }
        let r = row - offset
        if let filtered = history.filtered { return filtered.indices.contains(r) ? filtered[r] : nil }
        return history.rows.indices.contains(r) ? r : nil
    }

    var uncommittedTitle: String { "Uncommitted Changes (\(model.status.changedCount))" }

    func numberOfRows(in tableView: NSTableView) -> Int {
        (history.filtered?.count ?? history.rows.count) + (hasUncommittedRow ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        guard let index = historyIndex(ofTableRow: row) else {
            // The Uncommitted Changes row.
            switch id {
            case "graph":
                let cell = tableView.makeView(withIdentifier: GraphCellView.identifier, owner: nil) as? GraphCellView ?? GraphCellView()
                cell.configureUncommitted(nextColumn: history.rows.isEmpty ? 0 : history.layout.column(of: 0))
                return cell
            default:
                let cell = commitCell(tableView)
                cell.configure(subject: uncommittedTitle, labels: [], details: "Not committed yet", italic: true)
                return cell
            }
        }
        let commit = history.rows[index]
        switch id {
        case "graph":
            let cell = tableView.makeView(withIdentifier: GraphCellView.identifier, owner: nil) as? GraphCellView ?? GraphCellView()
            cell.configure(layout: history.layout, row: index, hasRowAbove: index > 0 || hasUncommittedRow, isMerge: commit.isMerge)
            return cell
        default:
            let cell = commitCell(tableView)
            let details = [history.authors.name(commit.author), RelativeDate.string(for: commit.date, now: relativeNow), commit.id.short]
            cell.configure(subject: commit.subject, labels: commit.refLabels, details: details.joined(separator: " · "), italic: false)
            cell.toolTip = "\(commit.subject)\n\(history.authors.name(commit.author)), \(commit.date.formatted(date: .complete, time: .shortened))\n\(commit.id.hex)"
            return cell
        }
    }

    private func commitCell(_ tableView: NSTableView) -> CommitCellView {
        tableView.makeView(withIdentifier: CommitCellView.identifier, owner: nil) as? CommitCellView ?? CommitCellView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applyingSelection, let table else { return }
        let ids = table.selectedRowIndexes.compactMap { historyIndex(ofTableRow: $0) }.map { history.rows[$0].id }
        model.selectedCommits = ids
        let row = table.selectedRow
        guard row >= 0 else { return }
        if ids.count > 1 {
            model.historySelection = ids.first
        } else if let index = historyIndex(ofTableRow: row) {
            model.historySelection = history.rows[index].id
        } else {
            model.historySelection = nil
        }
    }

    // Dragging commits out: each row carries its hash as text.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard let index = historyIndex(ofTableRow: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(history.rows[index].id.hex, forType: .string)
        return item
    }

    @objc func doubleClicked(_ sender: Any?) {
        guard let table, table.clickedRow >= 0 else { return }
        if historyIndex(ofTableRow: table.clickedRow) == nil { model.sidebarSelection = .changes }
    }

    func selectedCommit() -> CommitRow? {
        guard let table, table.selectedRow >= 0, let index = historyIndex(ofTableRow: table.selectedRow) else { return nil }
        return history.rows[index]
    }

    // Context menu for the clicked row.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table, table.clickedRow >= 0 else { return }
        guard let index = historyIndex(ofTableRow: table.clickedRow) else {
            menu.addItem(withTitle: "Show Changes", action: #selector(showChanges), keyEquivalent: "").target = self
            return
        }
        let commit = history.rows[index]
        // Right-clicking inside a multiple selection acts on all of it.
        let clickedInSelection = table.selectedRowIndexes.contains(table.clickedRow)
        let targets = clickedInSelection && model.selectedCommits.count > 1 ? model.selectedCommits : [commit.id]
        let branch = model.currentBranchName
        func add(_ title: String, _ action: Selector, _ object: Any?, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: enabled ? action : nil, keyEquivalent: "")
            item.representedObject = object
            item.target = self
            item.isEnabled = enabled
        }
        add(targets.count > 1 ? "Cherry-pick \(targets.count) Commits onto \(branch)" : "Cherry-pick onto \(branch)",
            #selector(cherryPick(_:)), targets.map(\.hex), enabled: model.canIntegrate)
        if targets.count == 1 {
            add("Revert Commit", #selector(revert(_:)), commit.id.hex, enabled: model.canIntegrate)
            add("Edit History from Here…", #selector(editHistory(_:)), commit.id.hex, enabled: model.canIntegrateOnBranch)
            menu.addItem(.separator())
            add("New Branch Here…", #selector(newBranch(_:)), commit.id.hex)
            add("New Tag Here…", #selector(newTag(_:)), commit.id.hex)
            menu.addItem(.separator())
            add("Copy Hash", #selector(copyHash(_:)), commit.id.hex)
            add("Copy Subject", #selector(copySubject(_:)), commit.id.hex)
        }
    }

    @objc private func cherryPick(_ item: NSMenuItem) {
        let ids = (item.representedObject as? [String] ?? []).compactMap(ObjectID.init(hex:))
        model.cherryPick(ids)
    }

    @objc private func revert(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.revert(id) }
    }

    @objc private func editHistory(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.editHistory(from: id) }
    }

    @objc private func newTag(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.showNewTag(at: id) }
    }

    @objc private func showChanges() { model.sidebarSelection = .changes }

    @objc private func copyHash(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.copyHash(id) }
    }

    @objc private func copySubject(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.copySubject(id) }
    }

    @objc private func newBranch(_ item: NSMenuItem) {
        if let hex = item.representedObject as? String, let id = ObjectID(hex: hex) { model.showNewBranch(from: id) }
    }
}

/// ⌘C copies the selected commit's hash; Return on the Uncommitted row opens Changes.
final class HistoryNSTableView: NSTableView {
    weak var coordinator: HistoryCoordinator?

    @objc func copy(_ sender: Any?) {
        guard let commit = coordinator?.selectedCommit() else { NSSound.beep(); return }
        coordinator?.model.copyHash(commit.id)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return coordinator?.selectedCommit() != nil }
        return super.validateUserInterfaceItem(item)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, selectedRow >= 0, coordinator?.historyIndex(ofTableRow: selectedRow) == nil {
            coordinator?.model.sidebarSelection = .changes
            return
        }
        super.keyDown(with: event)
    }
}

/// Subject with ref labels on the first line; author, date and hash on the second.
final class CommitCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("CommitCell")
    private let labels = NSStackView()
    private let subject = NSTextField(labelWithString: "")
    private let details = NSTextField(labelWithString: "")

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        labels.orientation = .horizontal
        labels.spacing = Spacing.xs
        labels.setHuggingPriority(.required, for: .horizontal)
        subject.lineBreakMode = .byTruncatingTail
        subject.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        details.lineBreakMode = .byTruncatingTail
        details.font = NSFont.preferredFont(forTextStyle: .callout)
        details.textColor = .secondaryLabelColor
        details.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [labels, subject])
        top.orientation = .horizontal
        top.spacing = Spacing.xs
        top.alignment = .centerY
        let column = NSStackView(views: [top, details])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        textField = subject
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.xs),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(subject text: String, labels refs: [RefLabel], details detailText: String, italic: Bool) {
        let body = NSFont.preferredFont(forTextStyle: .body)
        subject.font = italic ? body.withTraits(.italic) : body
        subject.textColor = italic ? .secondaryLabelColor : .labelColor
        subject.stringValue = text
        details.stringValue = detailText
        labels.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for ref in refs.prefix(3) { labels.addArrangedSubview(RefChip(ref: ref)) }
        if refs.count > 3 {
            let more = RefChip(text: "+\(refs.count - 3)", kind: .tag, current: false)
            more.toolTip = refs.dropFirst(3).map(\.name).joined(separator: ", ")
            labels.addArrangedSubview(more)
        }
        labels.isHidden = refs.isEmpty
        let names = refs.map { ref -> String in
            switch ref.kind {
            case .tag: "tag \(ref.name)"
            case .head: "detached HEAD"
            default: ref.isCurrent ? "\(ref.name), current branch" : ref.name
            }
        }
        setAccessibilityLabel(([text] + names + [detailText]).joined(separator: ", "))
    }
}

/// A small rounded label for a branch or tag.
final class RefChip: NSTextField {
    convenience init(ref: RefLabel) {
        self.init(text: ref.name, kind: ref.kind, current: ref.isCurrent)
    }

    convenience init(text: String, kind: RefLabel.Kind, current: Bool) {
        self.init(labelWithString: text)
        alignment = .center
        font = NSFont.preferredFont(forTextStyle: .caption1).withWeight(current ? .semibold : .regular)
        lineBreakMode = .byTruncatingMiddle
        maximumNumberOfLines = 1
        wantsLayer = true
        layer?.cornerRadius = Radius.xs
        let tint: NSColor
        switch kind {
        case .tag: tint = .systemOrange
        case .remoteBranch: tint = .systemTeal
        default: tint = .controlAccentColor
        }
        textColor = .readable(tint, on: .controlBackgroundColor, target: ReadableColor.textTarget)
        chipTint = tint
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        widthAnchor.constraint(lessThanOrEqualToConstant: 140).isActive = true
        setAccessibilityLabel(kind == .tag ? "tag \(text)" : text)
    }

    private var chipTint: NSColor = .controlAccentColor

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: Radius.xs, yRadius: Radius.xs)
        chipTint.withAlphaComponent(0.14).setFill()
        path.fill()
        super.draw(dirtyRect)
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + Spacing.s, height: size.height + 2)
    }

}

/// Draws one row of the graph: lines through, into and out of the row's dot.
final class GraphCellView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("GraphCell")
    static let laneWidth: CGFloat = 12
    static let maxDrawnLanes = 12

    private var segments: [GraphSegment] = []
    private var column = 0
    private var nodeColor: UInt8 = 0
    private var isMerge = false
    private var uncommitted = false
    private var hasRowAbove = true

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
        setAccessibilityElement(false)
    }

    func configure(layout: GraphLayout, row: Int, hasRowAbove: Bool, isMerge: Bool) {
        segments = Array(layout.segments(of: row))
        column = layout.column(of: row)
        nodeColor = layout.nodeColor(of: row)
        self.isMerge = isMerge
        self.hasRowAbove = hasRowAbove
        uncommitted = false
        needsDisplay = true
    }

    func configureUncommitted(nextColumn: Int) {
        segments = []
        column = nextColumn
        uncommitted = true
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    private func x(_ lane: Int) -> CGFloat { Spacing.xs + CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2 }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height, mid = h / 2
        let cap = Self.maxDrawnLanes
        if uncommitted {
            guard column < cap else { return }
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x(column), y: mid))
            path.line(to: NSPoint(x: x(column), y: h))
            path.lineWidth = 1.5
            path.setLineDash([2, 2], count: 2, phase: 0)
            NSColor.secondaryLabelColor.setStroke()
            path.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: x(column) - 4, y: mid - 4, width: 8, height: 8))
            dot.lineWidth = 1.5
            NSColor.secondaryLabelColor.setStroke()
            dot.stroke()
            return
        }
        for segment in segments where Int(segment.lane) < cap {
            let lane = Int(segment.lane)
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            switch segment.kind {
            case .through:
                path.move(to: NSPoint(x: x(lane), y: 0))
                path.line(to: NSPoint(x: x(lane), y: h))
            case .intoNode:
                guard column < cap else { continue }
                path.move(to: NSPoint(x: x(lane), y: 0))
                if lane == column {
                    path.line(to: NSPoint(x: x(column), y: mid))
                } else {
                    path.curve(to: NSPoint(x: x(column), y: mid), controlPoint1: NSPoint(x: x(lane), y: mid * 0.6),
                               controlPoint2: NSPoint(x: x(column), y: mid * 0.4))
                }
            case .outOfNode:
                guard column < cap else { continue }
                path.move(to: NSPoint(x: x(column), y: mid))
                if lane == column {
                    path.line(to: NSPoint(x: x(lane), y: h))
                } else {
                    path.curve(to: NSPoint(x: x(lane), y: h), controlPoint1: NSPoint(x: x(column), y: mid + mid * 0.6),
                               controlPoint2: NSPoint(x: x(lane), y: mid + mid * 0.4))
                }
            }
            LanePalette.color(segment.color).setStroke()
            path.stroke()
        }
        guard column < cap else { return }
        let radius: CGFloat = isMerge ? 3 : 4
        let dot = NSBezierPath(ovalIn: NSRect(x: x(column) - radius, y: mid - radius, width: radius * 2, height: radius * 2))
        LanePalette.color(nodeColor).setFill()
        dot.fill()
        if isMerge {
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: x(column) - 1.5, y: mid - 1.5, width: 3, height: 3)).fill()
        }
    }
}

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
    }

    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
