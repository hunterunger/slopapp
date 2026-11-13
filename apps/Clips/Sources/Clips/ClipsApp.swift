import AppKit
import ClipsCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility + overlay (the search panel) + library window (History).
// See docs/design-system.md, section 2.

extension KeyboardShortcuts.Name {
    /// ⇧⌥V by default: clear of ⇧⌘V (Paste and Match Style, and Paste's own shortcut) and
    /// ⌥⌘V (Finder's Move).
    static let showClips = Self("showClips", default: .init(.v, modifiers: [.option, .shift]))
    /// Starts or stops a paste stack from any app. No default: common combos (⇧⌘C) already
    /// mean something in many apps, and the strip's ⇧⌘C is always there.
    static let pasteStack = Self("pasteStack")
}

/// Starts Clips, or (with `--recognize-text`) the helper that reads text in images for it.
@main
enum ClipsMain {
    static func main() {
        // A helper that quit mid-write must fail the write, not end Clips.
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.contains(TextHelper.argument) { TextHelper.run() }
        ClipsApp.main()
    }
}

struct ClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Clips")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ClipsMenu(model: model, info: info)
        } label: {
            MenuBarLabel(isPaused: model.isPaused, isStacking: model.stack.isActive)
        }
        .menuBarExtraStyle(.menu)

        Window("Clip History", id: HistoryWindow.id) {
            HistoryWindow(model: model)
        }
        .defaultSize(width: 860, height: 560)
        .windowToolbarStyle(.unified)
        .commands { HistoryCommands(model: model, info: info) }

        Window("Clips Help", id: HelpWindow.id) {
            HelpWindow()
        }
        .defaultSize(width: 480, height: 620)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// The menu bar icon. It exists from launch, so it's where SwiftUI's window actions are
/// captured for code outside views (the panel's ⌘Y and ⌘,).
struct MenuBarLabel: View {
    let isPaused: Bool
    let isStacking: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: isStacking ? "square.stack.3d.up" : (isPaused ? "clipboard" : "list.clipboard"))
            .accessibilityLabel(isStacking ? "Clips, paste stack on" : (isPaused ? "Clips, recording paused" : "Clips"))
            .onAppear {
                SettingsOpener.action = { openSettings() }
                HistoryOpener.action = { openWindow(id: HistoryWindow.id) }
                HelpOpener.action = { openWindow(id: HelpWindow.id) }
            }
    }
}

/// Opens the History window from code that isn't a SwiftUI view.
@MainActor
enum HistoryOpener {
    static var action: (() -> Void)?

    /// `activate: false` is for test hooks (opens it behind whatever is in front).
    static func open(activate: Bool = true) {
        if activate { NSApp.activate() }
        if let action {
            action()
            return
        }
        // The menu bar icon (where the action is captured) may be hidden: use the Window
        // menu's command instead.
        for item in NSApp.mainMenu?.items ?? [] {
            guard let menu = item.submenu, let index = menu.items.firstIndex(where: { $0.title == "Clip History" }) else { continue }
            menu.performActionForItem(at: index)
            return
        }
    }
}

/// Status line → main actions → options → footer (Settings…, About, Report a Problem…, Quit).
struct ClipsMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(statusLine)
        Divider()

        showClipsButton
        Button("Open History") {
            HistoryOpener.action = { openWindow(id: HistoryWindow.id) }
            HistoryOpener.open()
        }
        .keyboardShortcut("y")
        Divider()

        if model.isPaused {
            Button("Resume Recording") { model.resume() }
        } else {
            Menu("Pause Recording") {
                Button("For 15 Minutes") { model.pause(for: 15 * 60) }
                Button("For 1 Hour") { model.pause(for: 3_600) }
                Button("Until I Resume") { model.pause(for: nil) }
            }
        }
        Toggle("Ignore Next Copy", isOn: $model.ignoreNextCopy)
            .disabled(model.isPaused)
        stackButton
        if model.clipboardAccess != .allowed {
            Button("Allow Clipboard Access…") { ClipboardAccess.openSettings() }
        }
        Button("Clear History…") { ClearHistory.confirm(model: model) }
            .disabled(model.history.clips.allSatisfy(\.isPinned))

        MenuFooter(info: info)
            .onAppear { SettingsOpener.action = { openSettings() } }
    }

    @ViewBuilder private var stackButton: some View {
        let title = model.stack.isActive ? "Stop Paste Stack" : "Start Paste Stack"
        let button = Button(title) {
            if model.stack.isActive { model.stack.cancel() } else { model.stack.start() }
        }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .pasteStack), let key = shortcut.menuKey {
            button.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }

    private var statusLine: String {
        if let stack = model.stack.stack {
            return stack.remaining == 0 ? "Paste stack on · copy to add" : "Paste stack · \(stack.remaining) to paste"
        }
        if let paused = model.pauseDescription { return paused }
        switch model.clipboardAccess {
        case .denied: return "Clipboard access is off"
        case .asks: return "macOS asks before each copy is recorded"
        case .allowed: break
        }
        let count = model.history.clips.count
        return count == 1 ? "Recording · 1 clip" : "Recording · \(count.formatted()) clips"
    }

    @ViewBuilder private var showClipsButton: some View {
        let button = Button("Show Clips") { AppDelegate.panel?.showFromMenu() }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .showClips), let key = shortcut.menuKey {
            button.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }
}

extension KeyboardShortcuts.Shortcut {
    /// The shortcut as a SwiftUI key equivalent, so the menu shows it. Letters and digits only.
    var menuKey: KeyEquivalent? {
        guard let last = description.last, last.isLetter || last.isNumber else { return nil }
        return KeyEquivalent(Character(last.lowercased()))
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

/// "Clear History…" confirmation. Clearing can't be undone, so it asks first.
@MainActor
enum ClearHistory {
    static func confirm(model: AppModel) {
        let count = model.history.clips.filter { !$0.isPinned }.count
        guard count > 0 else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        let pinned = model.history.clips.count - count
        alert.informativeText = "This removes \(count == 1 ? "1 clip" : "\(count.formatted()) clips")"
            + (pinned > 0 ? ". Pinned clips are kept." : ".") + " You can't undo this."
        alert.alertStyle = .warning
        let clear = alert.addButton(withTitle: "Clear History")
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearHistory()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()
    static private(set) var panel: PanelController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        let panel = PanelController(model: model)
        Self.panel = panel
        model.start()
        if !Diagnostics.noHotkey {
            KeyboardShortcuts.onKeyDown(for: .showClips) {
                Self.panel?.toggle(trigger: Diagnostics.now())
            }
            KeyboardShortcuts.onKeyDown(for: .pasteStack) {
                let stack = AppModel.shared.stack
                if stack.isActive { stack.cancel() } else { stack.start() }
            }
        }
        if Diagnostics.testHooks { installTestHooks(panel) }
        if Diagnostics.isSecondCopy {
            Diagnostics.logger.notice("Another Clips is running: this copy keeps a separate, temporary history and doesn't take the shortcut.")
        }
        // Render the chosen sounds (first launch of a version only) and create their IDs in
        // the background now, so the first copy plays without a delay.
        model.soundPlayer.prepare(model.soundChoice)
        DispatchQueue.main.async {
            panel.prewarm()
            if Diagnostics.showPanelAtLaunch { panel.show() }
        }
    }

    private func installTestHooks(_ panel: PanelController) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.clips.test."
        // object "passive": show without taking the keyboard (screenshots while someone may
        // be typing in another app).
        center.addObserver(forName: .init(prefix + "show"), object: nil, queue: .main) { note in
            let passive = note.object as? String == "passive"
            MainActor.assumeIsolated { panel.show(takesKeyboard: !passive) }
        }
        // object = card index: select it.
        center.addObserver(forName: .init(prefix + "select"), object: nil, queue: .main) { note in
            let index = (note.object as? String).flatMap(Int.init) ?? 0
            MainActor.assumeIsolated { panel.state.select(index: index) }
        }
        // object "1" / "0": open or close the preview.
        center.addObserver(forName: .init(prefix + "preview"), object: nil, queue: .main) { note in
            let open = note.object as? String == "1"
            MainActor.assumeIsolated { panel.testSetQuickLook(open) }
        }
        // object = tab index (All, Pinned, Text, Links, Images, Files).
        center.addObserver(forName: .init(prefix + "tab"), object: nil, queue: .main) { note in
            let index = (note.object as? String).flatMap(Int.init) ?? 0
            MainActor.assumeIsolated {
                let tabs = panel.state.tabs
                panel.state.filter = tabs[min(max(index, 0), tabs.count - 1)]
            }
        }
        // object "pause" / "resume" / "pin" (toggles the selected clip) / "delete" (the selected
        // clip; a pinned one asks for a second delete) / "cards" / "search" (keyboard focus).
        center.addObserver(forName: .init(prefix + "do"), object: nil, queue: .main) { note in
            let full = note.object as? String ?? ""
            // "name:argument", e.g. "board-new:Work", "select-add:3".
            let parts = full.split(separator: ":", maxSplits: 1).map(String.init)
            let action = parts.first ?? ""
            let argument = parts.count > 1 ? parts[1] : ""
            let number = Int(argument) ?? 0
            MainActor.assumeIsolated {
                switch action {
                case "select-add": panel.state.testSelect(indexes: [number], adding: true)
                case "select-range": panel.state.extendSelection(by: number)
                case "undo": _ = AppModel.shared.undoDelete(); panel.state.refresh()
                case "select-all": panel.state.selectAll()
                case "select-none": panel.state.collapseSelection()
                case "board-new": panel.testNewBoard(named: argument.isEmpty ? nil : argument)
                case "board-rename":
                    if let board = AppModel.shared.boards.all.dropFirst(number).first {
                        panel.state.beginRenaming(board, isNew: false)
                    }
                case "board-color":
                    let bits = argument.split(separator: ",").map(String.init)
                    if bits.count == 2, let index = Int(bits[0]), let color = BoardColor(rawValue: bits[1]),
                       let board = AppModel.shared.boards.all.dropFirst(index).first {
                        AppModel.shared.setColor(color, ofBoard: board.id)
                    }
                case "board-move":
                    let bits = argument.split(separator: ",").compactMap { Int($0) }
                    if bits.count == 2, let board = AppModel.shared.boards.all.dropFirst(bits[0]).first {
                        AppModel.shared.moveBoard(board.id, by: bits[1])
                    }
                case "board-delete": panel.testRequestBoardDelete(number)
                case "board-delete-confirm": panel.testConfirmBoardDelete()
                case "pin-to": panel.testPin(toBoard: number)
                case "drop-on-tab": panel.testDropOnTab(number)
                case "edit": panel.testEdit(inTitle: false)
                case "rename": panel.testEdit(inTitle: true)
                case "edit-text": panel.testSetEditorText(argument)
                case "edit-title": panel.testSetEditorTitle(argument)
                case "edit-save": panel.testFinishEditing(save: true)
                case "edit-cancel": panel.testFinishEditing(save: false)
                case "stack": panel.testPasteStack()
                case "stack-start": AppModel.shared.stack.start()
                case "stack-stop": AppModel.shared.stack.cancel()
                case "pause": AppModel.shared.pause(for: nil)
                case "resume": AppModel.shared.resume()
                case "pin": panel.testTogglePinSelected()
                case "copy": panel.testCopySelected()
                case "delete": panel.testDeleteSelected()
                case "cards": panel.state.cardsFocused = true
                case "search": panel.state.cardsFocused = false
                case "history": HistoryOpener.open()
                case "settings": SettingsOpener.open()
                // Without activating Clips: the window can't take anyone's typing.
                case "history-passive": HistoryOpener.open(activate: false)
                case "settings-passive": SettingsOpener.open(activate: false)
                case "help-passive": HelpOpener.action?()
                case "history-new-board": AppModel.shared.boardToName = AppModel.shared.createBoard().id
                case "backdrop": panel.testSetBackdrop(true)
                case "nobackdrop": panel.testSetBackdrop(false)
                default: break
                }
            }
        }
        center.addObserver(forName: .init(prefix + "hide"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { panel.dismiss() }
        }
        // Shows the cards' ⌘-numbers as if ⌘ were held ("1"), or hides them.
        center.addObserver(forName: .init(prefix + "numbers"), object: nil, queue: .main) { note in
            let on = note.object as? String == "1"
            MainActor.assumeIsolated { panel.state.commandHeld = on }
        }
        center.addObserver(forName: .init(prefix + "search"), object: nil, queue: .main) { note in
            let query = note.object as? String ?? ""
            MainActor.assumeIsolated { panel.state.query = query }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
