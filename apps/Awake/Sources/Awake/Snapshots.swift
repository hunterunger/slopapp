import AppKit
import AwakeCore
import SlopKit
import SwiftUI

/// Diagnostics: `AWAKE_SNAPSHOT_DIR=/tmp/x` renders Settings (every tab), the Keep Awake
/// window and the menu bar icon offscreen to PNGs in light and dark, writes the status item
/// menu for several states as text, then quits. For reviewing the design when the screen
/// can't be driven (locked, or on CI). Uses fake system monitors, a no-op power assertion
/// and throwaway settings, so it never touches the real ones or the Mac's sleep.
@MainActor
enum Snapshots {
    static func runIfAsked() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["AWAKE_SNAPSHOT_DIR"] else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A path suite: nothing lands in ~/Library/Preferences.
        let suite = (NSTemporaryDirectory() as NSString).appendingPathComponent("awake-snapshot-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: suite)!
        let apps = [
            AppRef(bundleID: "com.apple.Safari", name: "Safari"),
            AppRef(bundleID: "com.apple.TextEdit", name: "TextEdit"),
            AppRef(bundleID: "com.apple.Terminal", name: "Terminal"),
        ]
        let power = StaticMonitor(PowerState(isOnAC: false, batteryPercent: 64))
        let displays = StaticMonitor(0)
        let running = StaticMonitor(apps)
        let monitors = SystemMonitors(power: power, externalDisplays: displays, runningApps: running,
                                      screenLocked: StaticMonitor(false))
        let app = AppController(preferences: AwakePreferences(defaults: defaults), assertion: NoopAssertion(), monitors: monitors)
        let controller = app.controller
        let preferences = app.preferences

        // Menus, as text.
        var menus: [(String, String)] = []
        func dumpMenu(_ name: String) {
            menus.append((name, MenuContent.dump(MenuContent.entries(for: controller, appName: app.info.name))))
        }
        dumpMenu("idle")
        controller.start(.hours(2))
        dumpMenu("on for 2 hours")
        controller.start(.until(Date().addingTimeInterval(3 * 3600)))
        dumpMenu("on until a time")
        controller.start(.whileRunning(apps[1]))
        dumpMenu("on while TextEdit runs")
        controller.stop()
        preferences.addTriggerApp(apps[2])
        dumpMenu("trigger holding (Terminal running)")
        running.send(Array(apps.prefix(2)))
        preferences.stopOnLowBattery = true
        controller.start(.indefinitely)
        power.send(PowerState(isOnAC: false, batteryPercent: 15))
        dumpMenu("turned off by low battery")
        let text = menus.map { "## \($0.0)\n\($0.1)\n" }.joined(separator: "\n")
        try? text.write(to: directory.appendingPathComponent("menus.txt"), atomically: true, encoding: .utf8)
        power.send(PowerState(isOnAC: false, batteryPercent: 64))
        running.send(apps)

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for (tab, file) in [(SettingsTab.general, "general"), (.triggers, "triggers"), (.shortcuts, "shortcuts"),
                                (.advanced, "advanced"), (.about, "about")] {
                app.settingsTab = tab
                render(AwakeSettingsView(app: app, controller: controller, preferences: preferences),
                       to: directory.appendingPathComponent("settings-\(file)-\(name).png"))
            }
            let state = CustomSessionState()
            for mode in CustomSessionState.Mode.allCases {
                state.reset(mode: mode, now: Date())
                render(CustomSessionView(state: state) { _ in },
                       to: directory.appendingPathComponent("keep-awake-\(mode == .until ? "until" : "for")-\(name).png"))
            }
            render(IconStrip(), to: directory.appendingPathComponent("menubar-icons-\(name).png"))
        }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
        NSApp.terminate(nil)
        return true
    }

    private static func render<V: View>(_ view: V, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        // Paint the window background first: materials don't render offscreen.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        hosting.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        hosting.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}

/// The menu bar glyph in each state, as it would sit in the menu bar.
private struct IconStrip: View {
    var body: some View {
        HStack(spacing: Spacing.xl) {
            cell("Off", active: false)
            cell("On", active: true)
            cell("Off, dimmed", active: false, dimmed: true)
            cell("On, time left", active: true, time: "1h 05m")
        }
        .padding(Spacing.l)
    }

    private func cell(_ label: String, active: Bool, dimmed: Bool = false, time: String? = nil) -> some View {
        VStack(spacing: Spacing.s) {
            // Laid out like the status item: the glyph, then the time in the menu bar's font.
            HStack(spacing: Spacing.xs) {
                if let image = StatusIcon.image(active: active) {
                    Image(nsImage: image).renderingMode(.template)
                }
                if let time {
                    Text(time)
                        .font(Font(NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)))
                        .fixedSize()
                }
            }
            .opacity(dimmed ? 0.4 : 1)
            .padding(.horizontal, Spacing.s)
            .frame(height: Spacing.xxl)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.s))
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize()
        }
    }
}

/// Never holds anything. For snapshots.
@MainActor
final class NoopAssertion: PowerAssertion {
    var isHeld = false
    func hold(keepDisplayOn: Bool, reason: String) throws { isHeld = true }
    func release() { isHeld = false }
}
