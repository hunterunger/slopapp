import AppKit

/// Standard app delegate. Add to every app:
///
///     @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
///
/// - Menu bar apps (`LSUIElement`): opening the app again (Finder, Spotlight, Raycast)
///   brings back a hidden menu bar icon.
/// - Window apps: closing the last window quits, like other single-window utilities.
@MainActor
public final class SlopAppDelegate: NSObject, NSApplicationDelegate {
    public var isMenuBarApp: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isMenuBarApp {
            MenuBarIcon.isVisible = true
        }
        return true
    }

    /// macOS doesn't always send "reopen" to a background (LSUIElement) app, but opening it
    /// again does activate it. With no windows open, activation can only mean the user
    /// launched it again, so bring the icon back.
    public func applicationDidBecomeActive(_ notification: Notification) {
        guard isMenuBarApp, !MenuBarIcon.isVisible else { return }
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
        if !hasVisibleWindow {
            MenuBarIcon.isVisible = true
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isMenuBarApp
    }
}

/// Whether the menu bar icon is shown. Bind `MenuBarExtra(isInserted:)` to it with
/// `@AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true`.
public enum MenuBarIcon {
    public static let storageKey = "showMenuBarIcon"

    public static var isVisible: Bool {
        get { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}
