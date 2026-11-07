import AppKit
import AwakeCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility (docs/design-system.md 2a). The status item is AppKit's, not a
// `MenuBarExtra`, because a left click turns Awake on or off and a right-click (or
// Control/Option-click) opens the menu, which a `MenuBarExtra` can't tell apart.

extension KeyboardShortcuts.Name {
    /// Turns Awake on (default duration) or off from anywhere. Unset by default, like the
    /// originals: every obvious combo is taken by some app.
    static let toggleAwake = Self("toggleAwake")
}

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppController.shared

    var body: some Scene {
        // Never inserted: the real status item is StatusItemController's. Without a
        // non-window scene first, SwiftUI would open Settings at launch.
        MenuBarExtra("Awake", systemImage: "cup.and.saucer", isInserted: .constant(false)) {
            EmptyView()
        }

        Settings {
            AwakeSettingsView(app: app, controller: app.controller, preferences: app.preferences)
                .onOpenSettingsAvailable()
        }
    }
}

/// `SlopAppDelegate`'s behaviour (bring back a hidden icon on reopen) plus launch wiring and
/// the URL scheme.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Settings always opens on General (SwiftUI would restore the last tab).
        UserDefaults.standard.removeObject(forKey: "com_apple_SwiftUI_Settings_selectedTabIndex")
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshots.runIfAsked() { return }
        AppController.shared.start()
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        AppController.shared.open(url)
    }

    /// Opening Awake again (Finder, Spotlight, a launcher) brings back a hidden icon and shows
    /// Settings: the way in when the icon is out of sight, whether hidden by Awake's own
    /// setting, a crowded menu bar or macOS's per-app menu bar setting.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
        if !flag { AppController.shared.showSettings(tab: .general) }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Opens the Settings window from AppKit code (the status item menu). Candidate for SlopKit:
/// Dropper and Zones carry the same helper.
@MainActor
enum SettingsOpener {
    /// Set by a view that has SwiftUI's `openSettings` action.
    static var action: (() -> Void)?

    static func open() {
        AppActivation.activate()
        if let action {
            action()
        } else if let item = settingsMenuItem(in: NSApp.mainMenu), let menu = item.menu {
            // SwiftUI's own "Settings…" item in the (hidden) app menu works before any
            // SwiftUI view has appeared, where `showSettingsWindow:` no longer does.
            menu.performActionForItem(at: menu.index(of: item))
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        SettingsWindow.bringToFront()
    }

    private static func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let appMenu = menu?.items.first?.submenu else { return nil }
        return appMenu.items.first { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }
    }
}

private struct CaptureOpenSettings: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear { SettingsOpener.action = { openSettings() } }
    }
}

extension View {
    /// Captures SwiftUI's `openSettings` action for `SettingsOpener`.
    func onOpenSettingsAvailable() -> some View {
        modifier(CaptureOpenSettings())
    }
}
