import AppKit
import SlopKit

/// Like SlopKit's delegate for window apps (closing the window quits), except when a
/// show/hide shortcut is set: then Tally stays running so the shortcut can bring it back.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // TALLY_APPEARANCE=light|dark forces an appearance (screenshots and tests).
        switch ProcessInfo.processInfo.environment["TALLY_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        WindowToggler.install()
        MenuBarController.shared.update()
        if Snapshots.runIfAsked() || PerfSimulation.runIfAsked() { return }
        if !Pref.isDockIconShown {
            // Menu bar only: start with just the icon.
            DispatchQueue.main.async { WindowToggler.mainWindow?.close() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !WindowToggler.hasShortcut && !MenuBarController.shared.isShown && !Snapshots.isRunning
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowToggler.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SheetModel.shared.saveNow()
    }

    func applicationDidResignActive(_ notification: Notification) {
        SheetModel.shared.saveNow()
    }
}

extension KeyboardShortcuts.Name {
    /// Show or hide the Tally window from anywhere. Unset by default.
    static let toggleWindow = Self("toggleWindow")
}

/// The global show/hide shortcut.
@MainActor
enum WindowToggler {
    static var openMain: (() -> Void)?

    static var hasShortcut: Bool { KeyboardShortcuts.getShortcut(for: .toggleWindow) != nil }

    static func install() {
        KeyboardShortcuts.onKeyUp(for: .toggleWindow) {
            Task { @MainActor in toggle() }
        }
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == WindowID.main }
    }

    static func toggle() {
        // Menu bar only: the shortcut drops down the panel instead.
        if !Pref.isDockIconShown, MenuBarController.shared.isShown {
            MenuBarController.shared.togglePanel()
            return
        }
        if NSApp.isActive, let window = mainWindow, window.isVisible, window.isKeyWindow {
            NSApp.hide(nil)
        } else {
            show()
        }
    }

    static func show() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
    }
}
