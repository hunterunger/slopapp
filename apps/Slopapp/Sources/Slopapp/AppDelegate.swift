import AppKit
import SlopKit

/// Window + menu bar app: the Dock icon shows only while the library window is open. With
/// the menu bar item hidden, closing the window quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Settings opens on General each launch (SwiftUI otherwise reopens the last tab).
        UserDefaults.standard.removeObject(forKey: "com_apple_SwiftUI_Settings_selectedTabIndex")
        switch Store.shared.config.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.start()
        if let scene = Showcase.scene {
            ShowcaseScenes.run(scene, store: .shared, navigation: .shared)
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { _ = Task<Void, Never> { @MainActor in await Store.shared.checkIfDue() } }
        }
        // Apps come and go behind our back (Finder, other installers): re-scan when they launch
        // or quit and whenever Slopapp comes to the front. Cheap, and no polling.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated {
                    if let id, Store.shared.items.contains(where: { $0.app.bundleId == id }) { Store.shared.rescan() }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard window?.identifier?.rawValue.hasPrefix(WindowID.main) == true else { return }
                if MenuBarIcon.isVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Store.shared.rescan()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Navigation.shared.bringWindowForward() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarIcon.isVisible
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Store.shared.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop installing and quit?"
        alert.informativeText = "Apps that are still downloading won't be installed. Nothing already installed is affected."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
