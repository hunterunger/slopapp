import Foundation
import Observation

/// The whole app's state: is the Mac being kept awake, why, until when, and with the display on?
///
/// Two things can keep the Mac awake:
/// - a **session** the person started (a duration, until a time, or while an app runs), and
/// - **triggers** (while an app runs, on the power adapter, with an external display), which
///   hold the Mac awake for as long as their condition is true.
///
/// Turning Awake off while a trigger holds pauses triggers until their conditions stop
/// being true, so "off" sticks. Battery rules end both.
@MainActor
@Observable
public final class AwakeController {
    /// How often the remaining-time text refreshes while a timed session runs.
    public static let refreshInterval: TimeInterval = 30
    /// What "Add 30 Minutes" adds.
    public static let extendStep: TimeInterval = 30 * 60
    static let reason = "Awake is keeping this Mac awake"

    public let preferences: AwakePreferences
    public private(set) var session: AwakeSession?
    /// Triggers whose condition is true right now (whether or not they're paused).
    public private(set) var activeTriggers: [TriggerReason] = []
    /// The person turned Awake off while a trigger held; triggers wait for their conditions to clear.
    public private(set) var triggersPaused = false
    public private(set) var power: PowerState
    public private(set) var externalDisplays: Int
    public private(set) var runningApps: [AppRef]
    public private(set) var screenLocked: Bool
    public private(set) var lastError: String?
    /// Why Awake last turned itself off, until the next session starts.
    public private(set) var lastEnd: EndReason?
    /// Updated on every tick so views showing remaining time re-render.
    public private(set) var now: Date

    @ObservationIgnored private let assertion: any PowerAssertion
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored let clock: @MainActor () -> Date
    @ObservationIgnored private let timeText: @MainActor (Date) -> String
    @ObservationIgnored private var pendingTick: (any Cancellable)?
    @ObservationIgnored private var heldDisplayOn: Bool?
    @ObservationIgnored private var lowBatteryLatched = false

    public init(
        assertion: any PowerAssertion,
        scheduler: any Scheduler,
        preferences: AwakePreferences,
        monitors: SystemMonitors,
        clock: @escaping @MainActor () -> Date = { Date() },
        timeText: @escaping @MainActor (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) {
        self.assertion = assertion
        self.scheduler = scheduler
        self.preferences = preferences
        self.clock = clock
        self.timeText = timeText
        now = clock()
        power = monitors.power.current
        externalDisplays = monitors.externalDisplays.current
        runningApps = monitors.runningApps.current
        screenLocked = monitors.screenLocked.current
        // Already low when Awake starts: don't report it as "turned off".
        lowBatteryLatched = isLowBattery

        monitors.power.observe { [weak self] in self?.powerChanged($0) }
        monitors.externalDisplays.observe { [weak self] in
            self?.externalDisplays = $0
            self?.reevaluate()
        }
        monitors.runningApps.observe { [weak self] in
            self?.runningApps = $0
            self?.reevaluate()
        }
        monitors.screenLocked.observe { [weak self] in
            self?.screenLocked = $0
            self?.reevaluate()
        }
        preferences.onChange = { [weak self] in self?.reevaluate() }
        reevaluate()
    }

    // MARK: State

    /// The Mac is being kept awake (by a session or a trigger).
    public var isActive: Bool { session != nil || isTriggerHolding }

    /// A trigger (not a session) is what's keeping the Mac awake.
    public var isTriggerHolding: Bool {
        triggerWouldHold && !triggersBlockedByBattery
    }

    /// Battery rules hold triggers off: low battery, or on battery with "Turn off when
    /// switching to battery". They resume by themselves once the Mac is plugged in.
    public var triggersBlockedByBattery: Bool {
        isLowBattery || (preferences.stopOnSwitchToBattery && !power.isOnAC)
    }

    private var triggerWouldHold: Bool {
        preferences.triggersEnabled && !activeTriggers.isEmpty && !triggersPaused
    }

    /// Active, but letting the Mac sleep because the screen is locked ("Allow sleep while
    /// the screen is locked"). The session carries on after unlocking.
    public var isPausedForLock: Bool {
        isActive && preferences.allowSleepWhenLocked && screenLocked
    }

    /// On battery at or below the threshold, with the low-battery rule on.
    public var isLowBattery: Bool {
        guard preferences.stopOnLowBattery, !power.isOnAC, let percent = power.batteryPercent else { return false }
        return percent <= preferences.lowBatteryThreshold
    }

    // MARK: Actions

    public func start(_ duration: AwakeDuration) {
        start(.duration(duration))
    }

    public func start(_ kind: SessionKind) {
        now = clock()
        if case .until(let date) = kind, date <= now { return }
        lastEnd = nil
        lastError = nil
        session = AwakeSession(kind: kind, startedAt: now)
        reevaluate()
    }

    /// Starts a session with the default duration.
    public func startDefault() {
        start(.duration(preferences.defaultDuration))
    }

    /// What a click on the icon and the global shortcut do.
    public func toggle() {
        if isActive { stop() } else { startDefault() }
    }

    /// Turns Awake off: ends the session and pauses any trigger that's holding.
    public func stop() {
        end(reason: nil, pauseTriggers: true)
    }

    /// Adds time to a session that ends on its own.
    public func extend(by seconds: TimeInterval = AwakeController.extendStep) {
        guard var session, let endsAt = session.endsAt else { return }
        session.endsAt = max(endsAt, clock()).addingTimeInterval(seconds)
        self.session = session
        reevaluate()
    }

    /// Re-checks the clock and every condition. Call after the Mac wakes, since timers
    /// don't count time spent asleep.
    public func refresh() {
        reevaluate()
    }

    // MARK: Text

    /// The menu's status line, or nil when there's nothing to say.
    public var statusText: String? {
        if let session {
            switch session.kind {
            case .duration where session.endsAt == nil:
                return "On until turned off"
            case .whileRunning(let app):
                return "On while \(app.name) is running"
            case .until, .duration:
                guard let endsAt = session.endsAt else { return nil }
                let remaining = RemainingTime.string(endsAt.timeIntervalSince(now))
                if case .until = session.kind { return "On until \(timeText(endsAt)), \(remaining)" }
                return remaining
            }
        }
        if isTriggerHolding, let first = activeTriggers.first {
            return "On while \(first.phrase)"
        }
        return lastEnd?.text
    }

    /// The HUD after the global shortcut: "Awake is on", "Awake is on until 5:30 PM",
    /// "Awake is on while Xcode is running", "Awake is off".
    public var confirmationText: String {
        guard isActive else { return "Awake is off" }
        if case .whileRunning(let app) = session?.kind { return "Awake is on while \(app.name) is running" }
        if let endsAt = session?.endsAt { return "Awake is on until \(timeText(endsAt))" }
        return "Awake is on"
    }

    /// Short time left for the menu bar ("1h 23m"), or nil when there's no end time.
    public var menuBarText: String? {
        guard let endsAt = session?.endsAt else { return nil }
        return RemainingTime.compact(endsAt.timeIntervalSince(now))
    }

    // MARK: Internals

    private func powerChanged(_ new: PowerState) {
        let wasActive = isActive
        let unplugged = power.isOnAC && !new.isOnAC
        power = new
        if unplugged, preferences.stopOnSwitchToBattery, wasActive {
            // Triggers stay blocked while on battery (see triggersBlockedByBattery), so
            // they don't need pausing; they come back when the Mac is plugged in.
            end(reason: .switchedToBattery, pauseTriggers: false)
        }
        reevaluate()
    }

    /// Ends the session. `pauseTriggers` (a manual Turn Off) also keeps a holding trigger
    /// from switching straight back on.
    private func end(reason: EndReason?, pauseTriggers: Bool) {
        pendingTick?.cancel()
        pendingTick = nil
        session = nil
        if pauseTriggers, preferences.triggersEnabled, !activeTriggers.isEmpty { triggersPaused = true }
        lastEnd = reason
        applyAssertion()
    }

    private func reevaluate() {
        now = clock()
        activeTriggers = currentTriggers()
        if activeTriggers.isEmpty || !preferences.triggersEnabled { triggersPaused = false }

        if let session {
            if case .whileRunning(let app) = session.kind,
               !runningApps.contains(where: { $0.bundleID == app.bundleID }) {
                end(reason: .appQuit(app.name), pauseTriggers: false)
            } else if session.isExpired(at: now) {
                end(reason: nil, pauseTriggers: false)
            }
        }

        let low = isLowBattery
        if low, !lowBatteryLatched {
            let triggerWasHolding = triggerWouldHold && !(preferences.stopOnSwitchToBattery && !power.isOnAC)
            if session != nil || triggerWasHolding {
                end(reason: .lowBattery(power.batteryPercent ?? 0), pauseTriggers: false)
            }
        }
        lowBatteryLatched = low

        applyAssertion()
        scheduleTick()
    }

    private func currentTriggers() -> [TriggerReason] {
        var reasons: [TriggerReason] = []
        let running = Set(runningApps.map(\.bundleID))
        for app in preferences.triggerApps where running.contains(app.bundleID) {
            reasons.append(.app(app))
        }
        if preferences.triggerOnPowerAdapter, power.isOnAC { reasons.append(.powerAdapter) }
        if preferences.triggerOnExternalDisplay, externalDisplays > 0 { reasons.append(.externalDisplay) }
        return reasons
    }

    private func applyAssertion() {
        guard isActive, !isPausedForLock else {
            assertion.release()
            heldDisplayOn = nil
            return
        }
        let displayOn = preferences.keepDisplayOn
        guard !assertion.isHeld || heldDisplayOn != displayOn else { return }
        do {
            try assertion.hold(keepDisplayOn: displayOn, reason: Self.reason)
            heldDisplayOn = displayOn
            lastError = nil
        } catch {
            lastError = String(describing: error)
            heldDisplayOn = nil
            pendingTick?.cancel()
            pendingTick = nil
            session = nil
            // Don't retry in a loop: wait for the trigger's condition to change.
            if !activeTriggers.isEmpty { triggersPaused = true }
        }
    }

    private func scheduleTick() {
        pendingTick?.cancel()
        pendingTick = nil
        guard let remaining = session?.remaining(at: now) else { return }
        let delay = min(remaining, Self.refreshInterval)
        pendingTick = scheduler.schedule(after: delay) { [weak self] in
            self?.refresh()
        }
    }
}
