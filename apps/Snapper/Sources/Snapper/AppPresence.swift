import SlopKit
import AppKit

/// Snapper is a menu bar app, but while one of its regular windows is open (an editor,
/// Settings, About, the permission window) it shows in the Dock and gets a menu bar, so
/// every command (captures included) is reachable from the app's menus too, even when the
/// status item is hidden by the notch.
@MainActor
enum AppPresence {
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // After the close finishes, so the closing window no longer counts.
                DispatchQueue.main.async { MainActor.assumeIsolated { update() } }
            })
        }
    }

    /// Titled, normal-level windows other than the test scene count as "a window is open".
    static var hasRegularWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
                && (window.level == .normal || EditorWindowController.owns(window))
                && !TestScene.owns(window)
        }
    }

    static func update() {
        let wanted: NSApplication.ActivationPolicy = hasRegularWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular { NSApp.activate() }
    }
}

/// When the menu bar has no room (a full bar beside the notch), macOS leaves a new icon off
/// every screen. Say so once, with the way in: opening Snapper again shows Settings and its
/// menus (`applicationShouldHandleReopen`).
@MainActor
enum HiddenIconHint {
    private static let key = "hiddenMenuBarIconHintShown"

    static func checkSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard Preferences.store.object(forKey: MenuBarIcon.storageKey) as? Bool ?? true,
                  !Preferences.store.bool(forKey: key), isHidden else { return }
            Preferences.store.set(true, forKey: key)
            Diagnostics.record("menu bar icon hidden by a full menu bar")
            HUD.show("The menu bar is full. Open Snapper again to get its menus.", systemImage: "menubar.rectangle", duration: .seconds(6))
        }
    }

    /// The status item's window is on no screen.
    static var isHidden: Bool {
        let windows = NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }
        return !windows.isEmpty && windows.allSatisfy { $0.screen == nil }
    }
}
