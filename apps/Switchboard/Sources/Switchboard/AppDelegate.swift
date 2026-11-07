import AppKit
import SlopKit
import SwitchboardCore

/// Receives links from macOS. Wraps SlopKit's standard delegate (menu bar icon restore etc.).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // Register before launch finishes, or the link that launched us is lost.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        LinkRouter.shared.startTrackingActiveApp()
        // Draw the picker once off-screen so the first link doesn't pay for it.
        DispatchQueue.main.async {
            LinkRouter.shared.picker.prewarm(targets: model.config.pickerTargets, size: model.config.pickerSize)
        }
        if let scene = Showcase.scene {
            ShowcaseScenes.run(scene, model: model)
        } else if Diagnostics.initialSettingsTab != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { SettingsWindow.open() }
        }
        if let delay = Diagnostics.appearanceFlipDelay {
            // Test hook: switch light ↔ dark while running, to check every surface follows.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                NSApp.appearance = NSAppearance(named: isDark ? .aqua : .darkAqua)
                Diagnostics.record("appearance flipped to \(isDark ? "light" : "dark")")
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.refreshDefaultStatus() }
        }
        // Re-check default status whenever any of our menus opens (cheap, no polling).
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.refreshDefaultStatus() }
        }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        let receivedAt = Diagnostics.now()
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text) else {
            Diagnostics.record("getURL without a readable URL")
            return
        }
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        LinkRouter.shared.receive(url, senderPID: pid, receivedAt: receivedAt)
    }

    /// Local HTML files opened with Switchboard (Finder, "Open With").
    func application(_ application: NSApplication, open urls: [URL]) {
        let receivedAt = Diagnostics.now()
        let pid = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        for url in urls {
            LinkRouter.shared.receive(url, senderPID: pid, receivedAt: receivedAt)
        }
    }

    // MARK: - SlopKit standard behavior

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
        AppModel.shared.refreshDefaultStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveNow()
    }
}
