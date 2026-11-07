import Foundation

/// Something in the system Awake watches (power source, displays, running apps, screen lock).
/// Each has a current value and calls back when it changes. Injected so tests never touch
/// the real system: see `SystemMonitors.swift` for the real ones.
@MainActor
public protocol Monitor<Value>: AnyObject {
    associatedtype Value: Equatable & Sendable
    var current: Value { get }
    /// Starts watching. `handler` runs on the main actor after every change.
    func observe(_ handler: @escaping @MainActor (Value) -> Void)
}

/// Where the Mac's power comes from, and how full the battery is.
public struct PowerState: Equatable, Sendable {
    public var isOnAC: Bool
    /// 0–100, or nil on a Mac without a battery.
    public var batteryPercent: Int?

    public init(isOnAC: Bool, batteryPercent: Int?) {
        self.isOnAC = isOnAC
        self.batteryPercent = batteryPercent
    }

    public var hasBattery: Bool { batteryPercent != nil }

    /// A desktop Mac: always on AC, no battery.
    public static let desktop = PowerState(isOnAC: true, batteryPercent: nil)
}

/// An app, identified by bundle id, with a name for menus.
public struct AppRef: Hashable, Sendable, Codable, Identifiable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public var id: String { bundleID }
}

/// The real monitors (or fakes), bundled so the controller takes one argument.
@MainActor
public struct SystemMonitors {
    public let power: any Monitor<PowerState>
    /// How many external displays are connected (mirrored ones count).
    public let externalDisplays: any Monitor<Int>
    /// Regular (Dock) apps that are running, not including Awake.
    public let runningApps: any Monitor<[AppRef]>
    public let screenLocked: any Monitor<Bool>

    public init(
        power: any Monitor<PowerState>,
        externalDisplays: any Monitor<Int>,
        runningApps: any Monitor<[AppRef]>,
        screenLocked: any Monitor<Bool>
    ) {
        self.power = power
        self.externalDisplays = externalDisplays
        self.runningApps = runningApps
        self.screenLocked = screenLocked
    }
}

/// A monitor whose value never changes. Handy for previews, snapshots and tests.
@MainActor
public final class StaticMonitor<Value: Equatable & Sendable>: Monitor {
    public private(set) var current: Value
    private var handlers: [@MainActor (Value) -> Void] = []

    public init(_ value: Value) {
        current = value
    }

    public func observe(_ handler: @escaping @MainActor (Value) -> Void) {
        handlers.append(handler)
    }

    /// Changes the value and notifies observers (tests and diagnostics).
    public func send(_ value: Value) {
        guard value != current else { return }
        current = value
        for handler in handlers { handler(value) }
    }
}
