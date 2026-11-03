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
}

@main
struct ClipsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Clips")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ClipsMenu(model: model, info: info)
        } label: {
            MenuBarLabel(isPaused: model.isPaused)
        }
        .menuBarExtraStyle(.menu)

        Window("Clip History", id: HistoryWindow.id) {
            HistoryWindow(model: model)
        }
        .defaultSize(width: 860, height: 560)
        .windowToolbarStyle(.unified)
        .commands { HistoryCommands(model: model) }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// The menu bar icon. It exists from launch, so it's where SwiftUI's window actions are
/// captured for code outside views (the panel's ⌘Y and ⌘,).
struct MenuBarLabel: View {
    let isPaused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: isPaused ? "clipboard" : "list.clipboard")
            .accessibilityLabel(isPaused ? "Clips, recording paused" : "Clips")
            .onAppear {
                SettingsOpener.action = { openSettings() }
                HistoryOpener.action = { openWindow(id: HistoryWindow.id) }
            }
    }
}

/// Opens the History window from code that isn't a SwiftUI view.
@MainActor
enum HistoryOpener {
    static var action: (() -> Void)?

    static func open() {
        NSApp.activate()
        action?()
    }
}

/// Status line → main actions → options → footer (Settings…, About, Quit).
struct ClipsMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(statusLine)
        Divider()

        showClipsButton
        Button("Open History…") {
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
        if model.clipboardAccess != .allowed {
            Button("Allow Clipboard Access…") { ClipboardAccess.openSettings() }
        }
        Button("Clear History…") { ClearHistory.confirm(model: model) }
            .disabled(model.history.clips.allSatisfy(\.isPinned))

        MenuFooter(info: info)
            .onAppear { SettingsOpener.action = { openSettings() } }
    }

    private var statusLine: String {
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
        let button = Button("Show Clips") { AppDelegate.panel?.show() }
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
        KeyboardShortcuts.onKeyDown(for: .showClips) {
            Self.panel?.toggle(trigger: Diagnostics.now())
        }
        if Diagnostics.testHooks { installTestHooks(panel) }
        DispatchQueue.main.async {
            panel.prewarm()
            if Diagnostics.showPanelAtLaunch { panel.show() }
        }
    }

    private func installTestHooks(_ panel: PanelController) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.clips.test."
        center.addObserver(forName: .init(prefix + "show"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { panel.show() }
        }
        center.addObserver(forName: .init(prefix + "hide"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { panel.dismiss() }
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
        standard.applicationDidBecomeActive(notification)
        AppModel.shared.refreshPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
