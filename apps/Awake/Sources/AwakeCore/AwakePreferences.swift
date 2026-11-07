import Foundation
import Observation

/// What a left click on the menu bar icon does. The other click (right-click, or
/// Control/Option-click) does the opposite.
public enum ClickAction: String, CaseIterable, Sendable {
    /// Turn on with the default duration, or off if on.
    case toggle
    case openMenu
}

/// Every setting, persisted in `UserDefaults`. Changing one calls `onChange` so the
/// controller can re-evaluate (e.g. a new trigger may apply right away).
@MainActor
@Observable
public final class AwakePreferences {
    enum Key {
        static let keepDisplayOn = "keepDisplayOn"
        static let defaultDuration = "defaultDurationSeconds"
        static let activateAtLaunch = "activateAtLaunch"
        static let leftClick = "leftClickAction"
        static let allowSleepWhenLocked = "allowSleepWhenLocked"
        static let stopOnBattery = "stopOnSwitchToBattery"
        static let lowBatteryEnabled = "stopOnLowBattery"
        static let lowBatteryThreshold = "lowBatteryThreshold"
        static let dimIconWhenOff = "dimIconWhenOff"
        static let showTimeInMenuBar = "showTimeInMenuBar"
        static let triggersEnabled = "triggersEnabled"
        static let triggerApps = "triggerApps"
        static let triggerOnPower = "triggerOnPowerAdapter"
        static let triggerOnDisplay = "triggerOnExternalDisplay"
    }

    public static let lowBatteryChoices = [5, 10, 15, 20, 25, 30, 40, 50]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    /// Keep the screen on too (the default). Off = "Allow display sleep".
    public var keepDisplayOn: Bool { didSet { save(keepDisplayOn, Key.keepDisplayOn) } }
    /// Used by a click on the icon, the global shortcut, "Turn On" and activate-at-launch.
    public var defaultDuration: AwakeDuration {
        didSet { save(defaultDuration.seconds ?? -1, Key.defaultDuration) }
    }
    public var activateAtLaunch: Bool { didSet { save(activateAtLaunch, Key.activateAtLaunch) } }
    public var leftClick: ClickAction { didSet { save(leftClick.rawValue, Key.leftClick) } }
    /// Let the Mac sleep while the screen is locked; the session resumes on unlock.
    public var allowSleepWhenLocked: Bool { didSet { save(allowSleepWhenLocked, Key.allowSleepWhenLocked) } }
    /// End the session when the power adapter is unplugged.
    public var stopOnSwitchToBattery: Bool { didSet { save(stopOnSwitchToBattery, Key.stopOnBattery) } }
    /// End the session (and hold off triggers) when on battery at or below the threshold.
    public var stopOnLowBattery: Bool { didSet { save(stopOnLowBattery, Key.lowBatteryEnabled) } }
    public var lowBatteryThreshold: Int { didSet { save(lowBatteryThreshold, Key.lowBatteryThreshold) } }
    public var dimIconWhenOff: Bool { didSet { save(dimIconWhenOff, Key.dimIconWhenOff) } }
    public var showTimeInMenuBar: Bool { didSet { save(showTimeInMenuBar, Key.showTimeInMenuBar) } }

    /// Master switch for the automatic triggers below.
    public var triggersEnabled: Bool { didSet { save(triggersEnabled, Key.triggersEnabled) } }
    /// Keep awake while any of these apps is running.
    public var triggerApps: [AppRef] {
        didSet { save(try? JSONEncoder().encode(triggerApps), Key.triggerApps) }
    }
    public var triggerOnPowerAdapter: Bool { didSet { save(triggerOnPowerAdapter, Key.triggerOnPower) } }
    public var triggerOnExternalDisplay: Bool { didSet { save(triggerOnExternalDisplay, Key.triggerOnDisplay) } }

    /// True when at least one trigger is set up (whether or not triggers are switched on).
    public var hasTriggers: Bool { !triggerApps.isEmpty || triggerOnPowerAdapter || triggerOnExternalDisplay }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keepDisplayOn = defaults.object(forKey: Key.keepDisplayOn) as? Bool ?? true
        let seconds = defaults.object(forKey: Key.defaultDuration) as? Double ?? -1
        defaultDuration = seconds > 0 ? AwakeDuration(seconds: seconds) : .indefinitely
        activateAtLaunch = defaults.bool(forKey: Key.activateAtLaunch)
        leftClick = defaults.string(forKey: Key.leftClick).flatMap(ClickAction.init(rawValue:)) ?? .toggle
        allowSleepWhenLocked = defaults.bool(forKey: Key.allowSleepWhenLocked)
        stopOnSwitchToBattery = defaults.bool(forKey: Key.stopOnBattery)
        stopOnLowBattery = defaults.bool(forKey: Key.lowBatteryEnabled)
        let threshold = defaults.integer(forKey: Key.lowBatteryThreshold)
        lowBatteryThreshold = (1...99).contains(threshold) ? threshold : 20
        dimIconWhenOff = defaults.bool(forKey: Key.dimIconWhenOff)
        showTimeInMenuBar = defaults.bool(forKey: Key.showTimeInMenuBar)
        triggersEnabled = defaults.object(forKey: Key.triggersEnabled) as? Bool ?? true
        triggerApps = defaults.data(forKey: Key.triggerApps)
            .flatMap { try? JSONDecoder().decode([AppRef].self, from: $0) } ?? []
        triggerOnPowerAdapter = defaults.bool(forKey: Key.triggerOnPower)
        triggerOnExternalDisplay = defaults.bool(forKey: Key.triggerOnDisplay)
    }

    public func addTriggerApp(_ app: AppRef) {
        guard !triggerApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        triggerApps.append(app)
        triggerApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func removeTriggerApp(bundleID: String) {
        triggerApps.removeAll { $0.bundleID == bundleID }
    }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
