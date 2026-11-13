import AppKit
import ApplicationServices
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
        TestInbox.startIfRequested()
        if let probe = Diagnostics.menuProbeBundleID { Self.probeMenu(of: probe) }
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

    /// `SWITCHBOARD_MENU_PROBE`: log a running app's File menu as Accessibility reads it, and
    /// what the Safari matcher would press there. Reads only; presses nothing.
    private static func probeMenu(of bundleID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                Diagnostics.record("menu probe: \(bundleID) isn't running")
                return
            }
            guard AXIsProcessTrusted(), let bar = AXMenuReader.menuBar(of: app.processIdentifier), bar.count > 2 else {
                Diagnostics.record("menu probe: no menu bar (accessibility=\(AXIsProcessTrusted()))")
                return
            }
            // The File menu as the Safari opener finds it; without one, the menu after the
            // app menu, which still shows titles, shortcuts and modifiers come through.
            let file = AXMenuReader.fileMenuItems(in: bar)
            Diagnostics.record("menu probe: file menu \(file == nil ? "not found, showing menu 3" : "found")")
            let snapshot = AXMenuReader.snapshot(file ?? AXMenuReader.items(ofMenuBarItem: bar[2]))
            for line in AXMenuReader.describe(snapshot) { Diagnostics.record("menu probe: \(line)") }
            Diagnostics.record("menu probe: private window item path=\(SafariMenu.path(for: .privateWindow, inFileMenu: snapshot).map { "\($0)" } ?? "none")")
            Diagnostics.record("menu probe: windows=\(AXMenuReader.windowCount(of: app.processIdentifier))")
        }
    }

    // MARK: - SlopKit standard behavior

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshDefaultStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.saveNow()
    }
}
