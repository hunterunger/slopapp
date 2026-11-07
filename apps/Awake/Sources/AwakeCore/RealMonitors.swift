import AppKit
import CoreGraphics
import IOKit.ps

// The real monitors. All are event-driven (no polling), so Awake costs nothing while idle.

extension SystemMonitors {
    /// The live system.
    public static func live() -> SystemMonitors {
        SystemMonitors(
            power: IOKitPowerMonitor(),
            externalDisplays: ExternalDisplayMonitor(),
            runningApps: RunningAppsMonitor(),
            screenLocked: ScreenLockMonitor()
        )
    }
}

/// Shared plumbing: a current value plus handlers, notified only on real changes.
@MainActor
public class ChangeNotifier<Value: Equatable & Sendable> {
    public private(set) var current: Value
    private var handlers: [@MainActor (Value) -> Void] = []

    init(_ value: Value) {
        current = value
    }

    func addHandler(_ handler: @escaping @MainActor (Value) -> Void) -> Bool {
        handlers.append(handler)
        return handlers.count == 1
    }

    func update(_ value: Value) {
        guard value != current else { return }
        current = value
        for handler in handlers { handler(value) }
    }
}

/// Power source and battery level, from IOKit's power-source notifications.
@MainActor
public final class IOKitPowerMonitor: ChangeNotifier<PowerState>, Monitor {
    private var source: CFRunLoopSource?

    public init() {
        super.init(Self.read())
    }

    public func observe(_ handler: @escaping @MainActor (PowerState) -> Void) {
        guard addHandler(handler) else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<IOKitPowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.update(IOKitPowerMonitor.read()) }
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    static func read() -> PowerState {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .desktop }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        var percent: Int?
        let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            percent = Int((Double(current) / Double(max) * 100).rounded())
        }
        return PowerState(isOnAC: providing != kIOPSBatteryPowerValue, batteryPercent: percent)
    }
}

/// Counts connected displays that aren't built in (mirrored and sleeping ones count).
@MainActor
public final class ExternalDisplayMonitor: ChangeNotifier<Int>, Monitor {
    public init() {
        super.init(Self.count())
    }

    public func observe(_ handler: @escaping @MainActor (Int) -> Void) {
        guard addHandler(handler) else { return }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(ExternalDisplayMonitor.count()) }
        }
    }

    static func count() -> Int {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return 0 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return 0 }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count
    }
}

/// Regular (Dock) apps that are running, from NSWorkspace launch/quit notifications.
@MainActor
public final class RunningAppsMonitor: ChangeNotifier<[AppRef]>, Monitor {
    public init() {
        super.init(Self.read())
    }

    public func observe(_ handler: @escaping @MainActor ([AppRef]) -> Void) {
        guard addHandler(handler) else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(RunningAppsMonitor.read()) }
            }
        }
    }

    static func read() -> [AppRef] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { return nil }
            return AppRef(bundleID: id, name: app.localizedName ?? id)
        }
    }
}

/// Whether the screen is locked, from the system's lock/unlock broadcasts.
@MainActor
public final class ScreenLockMonitor: ChangeNotifier<Bool>, Monitor {
    public init() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        super.init(session?["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }

    public func observe(_ handler: @escaping @MainActor (Bool) -> Void) {
        guard addHandler(handler) else { return }
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(locked) }
            }
        }
    }
}
