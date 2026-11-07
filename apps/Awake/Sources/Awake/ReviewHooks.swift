import AppKit
import AwakeCore
import SlopKit

/// Diagnostics for reviewing the real UI on screen without touching the Mac:
///
/// - `AWAKE_DEMO=1`: fake system state (on battery at 64%, three running apps, no external
///   display, unlocked) and a power assertion that holds nothing. Screenshots then never show
///   the owner's apps and never change how the Mac sleeps. With `AWAKE_DEMO_BATTERY=15` the
///   battery starts at that level instead (`none`: a desktop Mac); `AWAKE_DEMO_AC=1` puts it on
///   the power adapter.
/// - `AWAKE_SHOW=menu|until|duration|settings|settings:triggers|about|hud`: opens that surface
///   right after launch. `menu` pops the status item's own menu up under the menu bar on the
///   right, for when the icon itself is hidden (a crowded menu bar, or macOS's
///   "Allow in the Menu Bar" switched off). `hud` presses the global shortcut.
@MainActor
enum ReviewHooks {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var isDemo: Bool { environment["AWAKE_DEMO"] != nil }

    static let demoApps = [
        AppRef(bundleID: "com.apple.Safari", name: "Safari"),
        AppRef(bundleID: "com.apple.TextEdit", name: "TextEdit"),
        AppRef(bundleID: "com.apple.Terminal", name: "Terminal"),
    ]

    static func demoMonitors() -> SystemMonitors {
        let battery = environment["AWAKE_DEMO_BATTERY"]
        let power = battery == "none"
            ? PowerState.desktop
            : PowerState(isOnAC: environment["AWAKE_DEMO_AC"] != nil, batteryPercent: battery.flatMap(Int.init) ?? 64)
        return SystemMonitors(
            power: StaticMonitor(power),
            externalDisplays: StaticMonitor(0),
            runningApps: StaticMonitor(demoApps),
            screenLocked: StaticMonitor(false)
        )
    }

    /// Runs `AWAKE_SHOW` once the app is up. Several surfaces, comma-separated, open in
    /// order (the last one ends up in front), e.g. `until,settings` for an inactive window.
    static func showIfAsked(_ app: AppController) {
        guard let value = environment["AWAKE_SHOW"] else { return }
        for (index, surface) in value.lowercased().split(separator: ",").enumerated() {
            let parts = surface.split(separator: ":").map(String.init)
            // Run-loop timers so the status item and SwiftUI scenes exist first.
            Timer.scheduledTimer(withTimeInterval: 0.6 + Double(index) * 0.8, repeats: false) { _ in
                MainActor.assumeIsolated { show(parts, app: app) }
            }
        }
    }

    private static func show(_ parts: [String], app: AppController) {
        switch parts.first {
        case "menu": app.statusItem.popUpMenuForReview()
        case "until": app.perform(.until)
        case "duration": app.perform(.customDuration)
        case "about": app.perform(.about)
        case "hud": app.toggleFromShortcut()
        case "settings":
            let tabs: [String: SettingsTab] = ["general": .general, "triggers": .triggers,
                                               "shortcuts": .shortcuts, "advanced": .advanced, "about": .about]
            app.showSettings(tab: parts.count > 1 ? tabs[parts[1]] ?? .general : .general)
        default: break
        }
    }
}
