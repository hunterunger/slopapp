import AppKit
import IOKit.ps
import Network
import TriggersCore

/// The Mac's state for conditions, read only when a trigger with conditions fires or a
/// sequence waits. All public APIs, no permission: running apps (`NSWorkspace`), the network
/// path (`NWPathMonitor`: no traffic, it only reads the routing state), displays (`NSScreen`),
/// the power source (IOKit power sources) and the appearance.
///
/// Not offered: the Wi-Fi network's name (macOS only gives it to apps with Location access)
/// and Focus / Do Not Disturb (no public way for a Mac app to read it: `INFocusStatusCenter`
/// only says "a Focus is on" to messaging apps with the Communication Notifications
/// capability).
@MainActor
final class LiveSystemState: SystemStateReader {
    private var monitor: NWPathMonitor?
    private var path = NetworkState(isOnline: true)

    func isRunning(bundleID: String) -> Bool {
        if Diagnostics.fakeApps, FakeCatalog.apps.contains(where: { $0.bundleID == bundleID }), bundleID != FakeCatalog.testTarget.bundleID {
            return false
        }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// The monitor starts the first time a condition asks, then follows changes.
    var network: NetworkState {
        if monitor == nil { startMonitor() }
        return path
    }

    private func startMonitor() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        // The first update arrives almost at once; until then, ask the current path directly.
        path = Self.state(of: monitor.currentPath)
        monitor.pathUpdateHandler = { [weak self] newPath in
            let state = LiveSystemState.state(of: newPath)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.path = state } }
        }
        monitor.start(queue: DispatchQueue(label: "app.slopapp.triggers.network", qos: .utility))
    }

    nonisolated private static func state(of path: NWPath) -> NetworkState {
        NetworkState(isOnline: path.status == .satisfied, usesWiFi: path.usesInterfaceType(.wifi),
                     usesWired: path.usesInterfaceType(.wiredEthernet))
    }

    var displays: [DisplayInfo] {
        if Diagnostics.fakeApps { return FakeCatalog.displays }
        return NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let builtIn = number.map { CGDisplayIsBuiltin(CGDirectDisplayID($0.uint32Value)) != 0 } ?? false
            return DisplayInfo(name: screen.localizedName, isBuiltIn: builtIn)
        }
    }

    var power: PowerSourceKind {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return .unknown }
        switch type {
        case kIOPSACPowerValue: return .charger
        case kIOPSBatteryPowerValue: return .battery
        default: return .unknown
        }
    }

    var now: Date { Date() }
    var calendar: Calendar { .current }
    var modifiers: Modifiers { SystemModifiers().current() }
    /// The system's appearance (not Triggers' own, which a test may override).
    var isDarkMode: Bool {
        (CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String) == "Dark"
    }
}

/// Sequence delays and waits on the main queue.
@MainActor
final class MainScheduler: Scheduler {
    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        let item = Item()
        let block = DispatchWorkItem { MainActor.assumeIsolated { if !item.isCancelled { work() } } }
        item.block = block
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
        return item
    }

    final class Item: ScheduledWork {
        var isCancelled = false
        var block: DispatchWorkItem?

        func cancel() {
            isCancelled = true
            block?.cancel()
        }
    }
}
