import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// The History window's clip list: an `NSTableView` with multiple selection. Like the
/// panel's list, it reuses a handful of cells, so search stays fast at any history size and
/// Accessibility sees only the rows on screen.
struct HistoryTable: NSViewRepresentable {
    struct Actions {
        let copy: (Set<UUID>) -> Void
        let copyPlain: (Set<UUID>) -> Void
        let togglePin: (Set<UUID>) -> Void
        let pin: (Set<UUID>, UUID?) -> Void
        let edit: (UUID) -> Void
        let rename: (UUID) -> Void
        let delete: (Set<UUID>) -> Void
    }

    let clips: [Clip]
    /// Changes whenever `clips` was recomputed.
    let version: Int
    let query: String
    let now: Date
    @Binding var selection: Set<UUID>
    /// Bump to put the keyboard in the list (selecting the first clip if none is).
    let focusRequest: Int
    let actions: Actions
    let boards: [Board]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = HistoryNSTableView()
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 40
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setAccessibilityLabel("Clips")
        table.coordinator = context.coordinator
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.actions = actions
        coordinator.boards = boards
        coordinator.setSelection = { selection = $0 }
        coordinator.sync(clips: clips, version: version, query: query, now: now, selection: selection)
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            if let table = coordinator.table {
                table.window?.makeFirstResponder(table)
                if selection.isEmpty, let first = clips.first { DispatchQueue.main.async { selection = [first.id] } }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        weak var table: NSTableView?
        var actions: Actions?
        var boards: [Board] = []
        var focusRequest = 0
        var setSelection: ((Set<UUID>) -> Void)?
        private(set) var clips: [Clip] = []
        private var version = -1
        private var query = ""
        private var now = Date()
        private var isSyncing = false

        func sync(clips: [Clip], version: Int, query: String, now: Date, selection: Set<UUID>) {
            guard let table else { return }
            isSyncing = true
            defer { isSyncing = false }
            if version != self.version || now != self.now {
                let countChanged = clips.count != self.clips.count
                self.clips = clips
                self.version = version
                self.query = query
                self.now = now
                if countChanged { table.noteNumberOfRowsChanged() }
                table.enumerateAvailableRowViews { rowView, row in
                    guard clips.indices.contains(row), let cell = rowView.view(atColumn: 0) as? ClipCellView else { return }
                    cell.configure(clip: clips[row], number: nil, now: now, query: query)
                }
            }
            let wanted = IndexSet(clips.indices.filter { selection.contains(clips[$0].id) })
            if table.selectedRowIndexes != wanted {
                table.selectRowIndexes(wanted, byExtendingSelection: false)
                if let first = wanted.first { table.scrollRowToVisible(first) }
            }
        }

        var selectedIDs: Set<UUID> {
            guard let table else { return [] }
            return Set(table.selectedRowIndexes.compactMap { clips.indices.contains($0) ? clips[$0].id : nil })
        }

        func numberOfRows(in tableView: NSTableView) -> Int { clips.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard clips.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("historyCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ClipCellView ?? {
                let view = ClipCellView(style: .detailed)
                view.identifier = id
                return view
            }()
            cell.configure(clip: clips[row], number: nil, now: now, query: query)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncing else { return }
            setSelection?(selectedIDs)
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard clips.indices.contains(sender.clickedRow) else { return }
            actions?.copy([clips[sender.clickedRow].id])
        }

        /// The clips a right-click acts on: the selection if the clicked row is in it.
        private func targetIDs() -> Set<UUID> {
            guard let table, clips.indices.contains(table.clickedRow) else { return selectedIDs }
            let clicked = clips[table.clickedRow].id
            let selected = selectedIDs
            return selected.contains(clicked) ? selected : [clicked]
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let ids = targetIDs()
            guard !ids.isEmpty, let actions else { return }
            let targets = clips.filter { ids.contains($0.id) }
            menu.addItem(ClosureMenuItem("Copy") { actions.copy(ids) })
            if targets.contains(where: { $0.kind != .image && $0.kind != .file }) {
                menu.addItem(ClosureMenuItem("Copy as Plain Text") { actions.copyPlain(ids) })
            }
            if targets.count == 1, let clip = targets.first {
                if let text = clip.imageText {
                    menu.addItem(ClosureMenuItem("Copy Text in Image") { AppModel.shared.copyText(text) })
                }
                menu.addItem(.separator())
                if ClipEdit.canEditText(clip) {
                    menu.addItem(ClosureMenuItem("Edit…", key: "e") { actions.edit(clip.id) })
                }
                menu.addItem(ClosureMenuItem(clip.label == nil ? "Add Title…" : "Rename…", key: "r") { actions.rename(clip.id) })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(targets.allSatisfy(\.isPinned) ? "Unpin" : "Pin", key: "p") { actions.togglePin(ids) })
            let pinTo = NSMenuItem(title: "Pin to", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let current = Set(targets.map(\.boardID))
            for (index, board) in boards.enumerated() {
                let on = current == [board.id]
                let item = ClosureMenuItem(board.name, key: index < 9 ? "\(index + 1)" : "", modifiers: [.command, .option]) {
                    actions.pin(ids, on ? nil : board.id)
                }
                item.image = BoardSwatch.image(board.color)
                item.state = on ? .on : .off
                sub.addItem(item)
            }
            pinTo.submenu = sub
            pinTo.isHidden = boards.isEmpty
            menu.addItem(pinTo)
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Delete", key: "\u{8}") { actions.delete(ids) })
        }

        // Keyboard, forwarded by the table.
        func copySelection() { actions?.copy(selectedIDs) }
        func deleteSelection() { actions?.delete(selectedIDs) }
    }
}

/// Handles ⌘C (Edit › Copy), Delete and Forward Delete for the selected rows.
final class HistoryNSTableView: NSTableView {
    weak var coordinator: HistoryTable.Coordinator?

    @objc func copy(_ sender: Any?) {
        coordinator?.copySelection()
    }

    @objc func delete(_ sender: Any?) {
        coordinator?.deleteSelection()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) || item.action == #selector(delete(_:)) {
            return selectedRow >= 0
        }
        return super.validateUserInterfaceItem(item)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            coordinator?.deleteSelection()
            return
        }
        if flags.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
            coordinator?.copySelection()
            return
        }
        super.keyDown(with: event)
    }
}
