import AppKit
import SwiftUI

/// The standard bottom of a Slopapp menu bar menu: Settings…, About, Report a Problem…, Quit.
/// Use inside a `MenuBarExtra` with `.menu` style.
public struct MenuFooter: View {
    let info: AppInfo
    @Environment(\.openSettings) private var openSettings

    public init(info: AppInfo) {
        self.info = info
    }

    public var body: some View {
        Divider()
        Button("Settings…") {
            AppActivation.activate()
            openSettings()
            SettingsWindow.bringToFront()
        }
        .keyboardShortcut(",")
        Button("About \(info.name)") {
            AboutWindow.show(info: info)
        }
        Button(IssueReport.Kind.problem.title) {
            IssueReport.open(.problem, info: info)
        }
        Divider()
        Button("Quit \(info.name)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Brings a menu bar app to the front for real.
///
/// A menu bar (accessory) app is never the active app, and macOS 14's cooperative
/// `NSApp.activate()` is only a request that the system may decline, which leaves a window it
/// just opened inactive behind the frontmost app: ⌘W, Undo and typing then go elsewhere.
/// The older `activate(ignoringOtherApps:)` still takes focus, which is right here because the
/// user just asked for the window from our own menu.
@MainActor
public enum AppActivation {
    public static func activate() {
        (NSApp as any ForcedActivation).activate(ignoringOtherApps: true)
    }
}

/// `activate(ignoringOtherApps:)` is deprecated in macOS 14 but is the only call that isn't
/// refused for accessory apps. Calling it through this protocol keeps the build warning-free.
@MainActor
private protocol ForcedActivation {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ForcedActivation {}

/// SwiftUI's Settings window, found by the identifier SwiftUI gives it.
@MainActor
public enum SettingsWindow {
    /// The Settings window, once SwiftUI has created it.
    public static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }
    }

    /// Opens the Settings window from anywhere, including AppKit code with no SwiftUI view
    /// around (an app delegate, a status item): activates the app, triggers SwiftUI's own
    /// Settings… command, and brings the window to the front. In a view, prefer
    /// `@Environment(\.openSettings)` followed by `bringToFront()`.
    public static func open() {
        AppActivation.activate()
        if let item = settingsMenuItem(in: NSApp.mainMenu), let menu = item.menu {
            // SwiftUI's "Settings…" item in the app menu (hidden in menu bar apps, but there)
            // works before any SwiftUI view has appeared, where `showSettingsWindow:` doesn't.
            menu.performActionForItem(at: menu.index(of: item))
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        bringToFront()
    }

    /// The app menu's ⌘, item.
    static func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let appMenu = menu?.items.first?.submenu else { return nil }
        return appMenu.items.first { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }
    }

    /// Activates the app and makes the Settings window key and frontmost. Call right after
    /// `openSettings()`: SwiftUI creates the window on a later turn of the run loop, so this
    /// retries for a moment until it exists.
    public static func bringToFront(attempts: Int = 20) {
        DispatchQueue.main.async {
            guard let window else {
                if attempts > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { bringToFront(attempts: attempts - 1) }
                }
                return
            }
            AppActivation.activate()
            window.makeKeyAndOrderFront(nil)
            // If activation was still declined, at least show it above other apps' windows.
            if !NSApp.isActive { window.orderFrontRegardless() }
        }
    }
}
