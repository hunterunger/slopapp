import AppKit
import FocusCore
import SlopKit

/// SlopKit's standard behaviour plus the moments Focus must look at the clock again.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch TestHooks.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppModel.controller
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default

        // Timers don't run while the Mac sleeps; the end date says what really happened.
        observe(workspace, NSWorkspace.didWakeNotification) { controller.refresh() }
        // Clock, time zone and day changes move "now" and "today".
        observe(local, .NSSystemClockDidChange) { controller.refresh() }
        observe(local, .NSSystemTimeZoneDidChange) { controller.refresh() }
        observe(local, .NSCalendarDayChanged) { controller.refresh() }
        DockPresence.start()
        AppModel.breakScreen.start()
        if TestHooks.openWindowAtLaunch { FocusWindow.show() }
        PanelTestWindow.showIfAsked()
        if Snapshots.runIfAsked() {
            NSApp.terminate(nil)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }

    /// Opening Focus again (Finder, Spotlight, the Dock) brings up its window, like the original.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let handled = standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
        if !flag { FocusWindow.show() }
        return handled
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
        Task { await AppModel.controller.refreshPermission() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
