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
            window.isVisible && window.styleMask.contains(.titled) && window.level == .normal
                && !(window.contentView is TestPatternView)
        }
    }

    static func update() {
        let wanted: NSApplication.ActivationPolicy = hasRegularWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular { NSApp.activate() }
    }
}
