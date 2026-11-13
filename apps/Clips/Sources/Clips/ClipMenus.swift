import AppKit
import ClipsCore

/// The actions for one or more clips, shared by a card's right-click menu and the strip's ⋯
/// menu. Text only, except board colour dots (Golden Gate menus).
@MainActor
enum ClipMenus {
    static func addItems(for clips: [Clip], to menu: NSMenu, model: AppModel, state: PanelState, actions: PanelActions) {
        guard let first = clips.first else { return }
        let paste = model.willPasteDirectly(into: state.target)
        let verb = paste ? "Paste" : "Copy"
        if clips.count > 1 {
            let what = ClipJoin.describe(clips)
            menu.addItem(ClosureMenuItem("\(verb) \(what)", key: "\r", modifiers: []) { actions.choose(clips, false) })
            menu.addItem(ClosureMenuItem("Paste One by One", key: "c", modifiers: [.command, .shift]) { actions.pasteStack(clips) })
            if paste { menu.addItem(ClosureMenuItem("Copy \(what)", key: "c") { actions.copy(clips) }) }
        } else {
            let pasteTitle = paste ? state.targetName.map { "Paste in \($0)" } ?? "Paste" : "Copy"
            menu.addItem(ClosureMenuItem(pasteTitle, key: "\r", modifiers: []) { actions.choose(clips, false) })
            if first.kind != .image, first.kind != .file {
                menu.addItem(ClosureMenuItem("\(verb) as Plain Text", key: "\r", modifiers: .shift) { actions.choose(clips, true) })
            }
            if paste { menu.addItem(ClosureMenuItem("Copy", key: "c") { actions.copy(clips) }) }
            menu.addItem(ClosureMenuItem("Preview", key: " ", modifiers: []) { actions.preview(first) })
            if first.kind == .link || first.kind == .file {
                menu.addItem(ClosureMenuItem(first.kind == .link ? "Open Link" : "Open", key: "o") { actions.open(first) })
            }
            if first.kind == .file {
                menu.addItem(ClosureMenuItem("Show in Finder") { actions.reveal(first) })
            }
            if first.imageText != nil {
                menu.addItem(ClosureMenuItem("Copy Text in Image") { actions.copyImageText(first) })
            }
            menu.addItem(.separator())
            if ClipEdit.canEditText(first) {
                menu.addItem(ClosureMenuItem("Edit…", key: "e") { actions.edit(first, false) })
            }
            menu.addItem(ClosureMenuItem(first.label == nil ? "Add Title…" : "Rename…", key: "r") { actions.edit(first, true) })
        }
        menu.addItem(.separator())
        let allPinned = clips.allSatisfy(\.isPinned)
        menu.addItem(ClosureMenuItem(allPinned ? "Unpin" : "Pin", key: "p") { actions.togglePin(clips) })
        menu.addItem(boardsItem(for: clips, model: model, actions: actions))
        menu.addItem(.separator())
        let delete = clips.count > 1 ? "Delete \(ClipJoin.describe(clips))" : "Delete"
        menu.addItem(ClosureMenuItem(delete, key: "\u{8}") { actions.delete(clips) })
    }

    /// "Pin to ▸": every board (⌥⌘1–9, a check on the one they're all on), then New Board….
    static func boardsItem(for clips: [Clip], model: AppModel, actions: PanelActions) -> NSMenuItem {
        let item = NSMenuItem(title: "Pin to", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = Set(clips.map(\.boardID))
        for (index, board) in model.boards.all.enumerated() {
            let on = current == [board.id]
            let entry = ClosureMenuItem(board.name, key: index < 9 ? "\(index + 1)" : "", modifiers: [.command, .option]) {
                actions.pin(clips, on ? nil : board.id)
            }
            entry.image = BoardSwatch.image(board.color)
            entry.state = on ? .on : .off
            submenu.addItem(entry)
        }
        if !model.boards.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(ClosureMenuItem("New Board…") { actions.newBoard(clips) })
        item.submenu = submenu
        return item
    }
}
