import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// The panel's result list. An `NSTableView` rather than a SwiftUI list: it reuses a dozen
/// cells for any number of clips, so 10,000 results cost no more memory or time than 10.
/// The search field keeps keyboard focus; the panel's key handler drives the selection.
struct ClipTable: NSViewRepresentable {
    let state: PanelState
    let actions: PanelActions

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, actions: actions)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.style = .inset
        table.rowHeight = PanelMetrics.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = .clear
        table.refusesFirstResponder = true
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setAccessibilityLabel("Clips")
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Reading these registers observation, so SwiftUI calls us again when they change.
        context.coordinator.sync(
            resultsVersion: state.resultsVersion,
            selectedID: state.selectedID,
            scrollRequest: state.scrollRequest,
            now: state.now
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        let state: PanelState
        let actions: PanelActions
        weak var table: NSTableView?
        private var resultsVersion = -1
        private var scrollRequest = -1
        private var now = Date()
        private var isSyncing = false

        init(state: PanelState, actions: PanelActions) {
            self.state = state
            self.actions = actions
        }

        func sync(resultsVersion: Int, selectedID: UUID?, scrollRequest: Int, now: Date) {
            guard let table else { return }
            isSyncing = true
            defer { isSyncing = false }
            if resultsVersion != self.resultsVersion || now != self.now {
                self.resultsVersion = resultsVersion
                self.now = now
                refreshRows(in: table)
            }
            if let index = state.selectedIndex {
                if table.selectedRow != index {
                    table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                }
            } else if table.selectedRow != -1 {
                table.deselectAll(nil)
            }
            if scrollRequest != self.scrollRequest {
                self.scrollRequest = scrollRequest
                if let index = state.selectedIndex { table.scrollRowToVisible(index) }
                if state.selectedIndex == 0 { table.scroll(.zero) }
            }
        }

        /// Re-fills the cells that exist instead of `reloadData()`, which throws every cell away
        /// and rebuilds it (most of a keystroke's cost at 5,000 clips).
        private func refreshRows(in table: NSTableView) {
            if table.numberOfRows != state.results.count {
                table.noteNumberOfRowsChanged()
            }
            let results = state.results
            table.enumerateAvailableRowViews { rowView, row in
                guard results.indices.contains(row), let cell = rowView.view(atColumn: 0) as? ClipCellView else { return }
                cell.configure(clip: results[row], number: row < 9 ? row + 1 : nil, now: now, query: state.query)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            state.results.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("row")
            return tableView.makeView(withIdentifier: id, owner: nil) as? ClipRowView ?? {
                let view = ClipRowView()
                view.identifier = id
                return view
            }()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard state.results.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ClipCellView ?? {
                let view = ClipCellView(style: .compact)
                view.identifier = id
                return view
            }()
            cell.configure(clip: state.results[row], number: row < 9 ? row + 1 : nil, now: now, query: state.query)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing, let table else { return }
            let row = table.selectedRow
            guard state.results.indices.contains(row) else { return }
            state.selectedID = state.results[row].id
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard state.results.indices.contains(row) else { return }
            actions.choose(state.results[row], false)
        }

        // Right-click menu.
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, state.results.indices.contains(table.clickedRow) else { return }
            let clip = state.results[table.clickedRow]
            state.selectedID = clip.id
            let label = AppModel.shared.willPasteDirectly(into: state.target) ? "Paste" : "Copy"
            menu.addItem(ClosureMenuItem(label) { [actions] in actions.choose(clip, false) })
            if clip.kind != .image, clip.kind != .file {
                menu.addItem(ClosureMenuItem("\(label) as Plain Text") { [actions] in actions.choose(clip, true) })
            }
            menu.addItem(ClosureMenuItem("Copy") { [actions] in actions.copy(clip) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(clip.isPinned ? "Unpin" : "Pin") { [actions] in actions.togglePin(clip) })
            menu.addItem(ClosureMenuItem("Delete") { [actions] in actions.delete(clip) })
        }
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

/// Selection always drawn in the accent color: the search field has focus, but the list
/// is what the keyboard moves through.
final class ClipRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

