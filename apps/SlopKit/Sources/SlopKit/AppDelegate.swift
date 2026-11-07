import AppKit
internal import SlopKitLaunch

/// Standard app delegate. Add to every app:
///
///     @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
///
/// - Menu bar apps (`LSUIElement`): opening the app again (Finder, Spotlight, Raycast)
///   brings back a hidden menu bar icon and opens Settings. The icon can be out of sight for
///   reasons the app can't see (a full menu bar, or the app switched off in System Settings ›
///   Menu Bar), so Settings is the way back in. If the app's own reopen handler shows a
///   window first, Settings stays closed. Turn it off with `opensSettingsOnReopen = false`.
/// - Window apps: closing the last window quits, like other single-window utilities.
/// - Testing: `SLOP_APPEARANCE=light|dark` in the environment forces that appearance, so
///   screenshots can cover both without touching the system setting
///   (`scripts/drive launch <app> --env SLOP_APPEARANCE=dark`). This works in every app that
///   links SlopKit, with or without this delegate (a launch hook in `SlopKitLaunch` applies it).
@MainActor
public final class SlopAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch hook already did this; repeating it is harmless and keeps it explicit.
        if let name = SlopKitTestAppearanceName() {
            NSApp.appearance = NSAppearance(named: NSAppearance.Name(rawValue: name))
        }
    }

    public var isMenuBarApp: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
    }

    /// Menu bar apps: open Settings when the app is opened again with no window showing.
    /// Default true.
    public var opensSettingsOnReopen = true

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isMenuBarApp {
            MenuBarIcon.isVisible = true
            if opensSettingsOnReopen && !flag { openSettingsUnlessAWindowAppears() }
        }
        return true
    }

    /// On the next turn of the run loop, so an app delegate that wraps this one and shows its
    /// own window on reopen (Focus shows its timer window) wins and Settings stays closed.
    private func openSettingsUnlessAWindowAppears() {
        DispatchQueue.main.async {
            guard !Self.hasVisibleWindow else { return }
            SettingsWindow.open()
        }
    }

    /// A visible ordinary window (not a panel, menu or status item window).
    static var hasVisibleWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.level == .normal && !($0 is NSPanel) }
    }

    /// macOS doesn't always send "reopen" to a background (LSUIElement) app, but opening it
    /// again does activate it. With no windows open, activation can only mean the user
    /// launched it again, so bring the icon back.
    public func applicationDidBecomeActive(_ notification: Notification) {
        guard isMenuBarApp, !MenuBarIcon.isVisible else { return }
        if !Self.hasVisibleWindow {
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
