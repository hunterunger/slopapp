import AppKit
import ShorthandCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility + library window (the snippet library). See
// docs/design-system.md, section 2a and 2c.

@main
struct ShorthandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Shorthand")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            ShorthandMenu(model: model, info: info)
        } label: {
            MenuBarLabel(status: model.status)
        }
        .menuBarExtraStyle(.menu)

        Window("Snippets", id: LibraryWindow.id) {
            LibraryWindow(model: model)
        }
        .defaultSize(width: 920, height: 580)
        .windowToolbarStyle(.unified)
        .commands {
            LibraryCommands(model: model)
            HelpCommands(info: info)
        }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// The menu bar icon: normal, paused or blocked, each named for VoiceOver. It exists from
/// launch, so it's where SwiftUI's window action is captured for code outside views.
struct MenuBarLabel: View {
    let status: ExpansionStatus
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: status.symbol)
            .accessibilityLabel(status.accessibilityLabel)
            .onAppear { LibraryOpener.action = { openWindow(id: LibraryWindow.id) } }
    }
}

/// Opens the library from code that isn't a SwiftUI view (reopen, test hooks).
@MainActor
enum LibraryOpener {
    static var action: (() -> Void)?
    /// What the library should do once it's open (select a new snippet...).
    static var pendingRequest: LibraryRequest?

    static func open(activate: Bool = true, request: LibraryRequest? = nil) {
        if let request { pendingRequest = request }
        if activate { AppActivation.activate() }
        if let action {
            action()
        } else {
            // The icon (where the action is captured) may be hidden: use the Window menu.
            for item in NSApp.mainMenu?.items ?? [] {
                guard let menu = item.submenu, let index = menu.items.firstIndex(where: { $0.title == "Snippets" }) else { continue }
                menu.performActionForItem(at: index)
                break
            }
        }
        NotificationCenter.default.post(name: .libraryRequest, object: nil)
    }
}

enum LibraryRequest: Equatable {
    case newSnippet
    case importReplacements
}

extension Notification.Name {
    static let libraryRequest = Notification.Name("app.slopapp.shorthand.libraryRequest")
}

/// Status line → main actions → options → footer (Settings…, About, Report a Problem…, Quit).
struct ShorthandMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.status.line)
        switch model.status {
        case .needsPermission:
            Button("Allow Shorthand to Expand…") { openLibrary() }
        case .noSnippets:
            EmptyView()
        default:
            EmptyView()
        }
        if model.tapGaveUp {
            Button("Try Expanding Again") { model.retryAfterGivingUp() }
        }
        if model.pastedWithoutRestore && model.pasteboardPrivacy != .allowed {
            Button("Allow Paste from Other Apps…") { PasteboardPrivacy.openSettings() }
        }
        Divider()

        Button("New Snippet…") { openLibrary(.newSnippet) }
            .keyboardShortcut("n")
        Button("Open Snippets") { openLibrary() }
            .keyboardShortcut("o")
        Divider()

        pauseButton

        MenuFooter(info: info)
    }

    @ViewBuilder private var pauseButton: some View {
        let button = Button(model.isEnabled ? "Pause Expansion" : "Resume Expansion") { model.togglePause() }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePause), let key = shortcut.menuKey {
            button.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            button
        }
    }

    private func openLibrary(_ request: LibraryRequest? = nil) {
        LibraryOpener.action = { openWindow(id: LibraryWindow.id) }
        LibraryOpener.open(request: request)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        standard.applicationWillFinishLaunching(notification)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One Shorthand at a time: two taps would expand everything twice.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty, !Diagnostics.isTestMode {
            others.first?.activate()
            NSApp.terminate(nil)
            return
        }
        let model = AppModel.shared
        if Snapshots.runIfAsked(model: model) { return }
        model.start()
        KeyboardShortcuts.onKeyDown(for: .togglePause) { AppModel.shared.togglePause() }
        if Diagnostics.testHooks { TestHooks.install() }
        // First launch: show the library once (its empty state explains what to do).
        if !Diagnostics.isSmokeTest, !model.defaults.bool(forKey: AppModel.Keys.openedLibrary) {
            model.defaults.set(true, forKey: AppModel.Keys.openedLibrary)
            DispatchQueue.main.async { LibraryOpener.open(activate: !Diagnostics.isTestMode) }
        }
        if let replay = Diagnostics.replayFile {
            Task { await model.replay(replay) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    /// Reopening the app (Finder, Spotlight) opens the library, the place to manage snippets.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarIcon.isVisible = true
        if !flag { LibraryOpener.open() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
        AppModel.shared.refreshPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
