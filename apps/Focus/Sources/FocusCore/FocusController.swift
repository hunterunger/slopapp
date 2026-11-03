import Foundation
import Observation

/// The app's state and actions. Owns the `TimerMachine`, persists it, schedules the next
/// look at the clock, and turns the machine's events into notifications, sounds, history
/// lines and shortcut runs.
///
/// Display values (`menuBarText`, `headline`, `todayText`...) are stored and only assigned
/// when they change, so a tick that changes nothing visible doesn't re-render the menu.
@MainActor
@Observable
public final class FocusController {
    /// Running/paused/idle, without the clock bookkeeping (so ticks don't re-render views).
    public private(set) var state: TimerState
    public private(set) var settings: TimerSettings
    /// The status item text ("18m"), nil when idle.
    public private(set) var menuBarText: String?
    /// The menu's first line: "Focusing · 18 min left".
    public private(set) var headline: String
    /// "Today: 3 sessions · 1 hr 15 min".
    public private(set) var todayText: String
    public private(set) var today: DayStats
    public private(set) var accessibilityLabel: String
    public private(set) var permission: NotificationPermission = .notDetermined
    /// The last shortcut run that failed, as one line for the menu.
    public private(set) var automationError: String?
    public private(set) var saveError: String?
    /// True for the "on" beats of the attention blink (when notifications can't show).
    public private(set) var isFlashing = false

    /// Length of a minute in seconds. 60, except in accelerated tests (`FOCUS_SECONDS_PER_MINUTE`).
    public let unit: TimeInterval

    @ObservationIgnored private var machine: TimerMachine
    @ObservationIgnored private let storage: any FocusStorage
    @ObservationIgnored private let notifier: any Notifier
    @ObservationIgnored private let sound: any SoundPlayer
    @ObservationIgnored private let shortcuts: any ShortcutRunner
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let activity: any ActivityToken
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let reduceMotion: @MainActor () -> Bool
    @ObservationIgnored private var now: Date
    @ObservationIgnored private var records: [SessionRecord]
    @ObservationIgnored private var savedState: TimerState
    @ObservationIgnored private var pendingTick: (any Cancellable)?
    @ObservationIgnored private var flashTick: (any Cancellable)?
    @ObservationIgnored private var flashBeats = 0
    @ObservationIgnored private var didAskPermission = false
    @ObservationIgnored private var shortcutChain: Task<Void, Never>?

    /// How many on/off beats the attention blink lasts (0.5 s each).
    static let flashBeatCount = 6

    public init(
        storage: any FocusStorage,
        notifier: any Notifier,
        sound: any SoundPlayer,
        shortcuts: any ShortcutRunner,
        scheduler: any Scheduler,
        activity: any ActivityToken,
        clock: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        unit: TimeInterval = 60,
        reduceMotion: @escaping @MainActor () -> Bool = { false }
    ) {
        self.storage = storage
        self.notifier = notifier
        self.sound = sound
        self.shortcuts = shortcuts
        self.scheduler = scheduler
        self.activity = activity
        self.clock = clock
        self.calendar = calendar
        self.unit = unit
        self.reduceMotion = reduceMotion

        let now = clock()
        let loaded = storage.loadState() ?? TimerState()
        self.now = now
        self.settings = storage.loadSettings() ?? TimerSettings()
        self.machine = TimerMachine(state: loaded, calendar: calendar)
        self.savedState = loaded
        self.state = loaded
        self.records = storage.records(since: Self.startOfYesterday(now, calendar))
        self.menuBarText = nil
        self.headline = ""
        self.todayText = ""
        self.today = DayStats()
        self.accessibilityLabel = ""

        notifier.onAction = { [weak self] action in self?.handle(action) }

        // Catch up on anything that ended while the app wasn't running: log it at the time
        // it ended, but don't announce it now.
        let events = machine.advance(settings: settings, unit: unit, now: now, lateAfter: lateAfter)
        commit(events, announce: false)
        Task { await refreshPermission() }
    }

    // MARK: - Reading

    public var isIdle: Bool { state.run == nil }
    public var runningPhase: Phase? { state.run?.phase }
    public var isPaused: Bool { state.run?.isPaused ?? false }
    public var label: String? { state.label }

    /// Overdue by more than this and the end counts as missed (the Mac was asleep).
    var lateAfter: TimeInterval { max(unit, 1) }

    // MARK: - Actions

    public func startFocus() {
        perform { m, s, u, now in m.start(.focus, settings: s, unit: u, now: now) }
        askPermissionOnce()
    }

    /// Starts the offered break, or a short one if none is offered.
    public func startBreak() {
        perform { m, s, u, now in
            m.state.pendingBreak != nil
                ? m.startPendingBreak(settings: s, unit: u, now: now)
                : m.start(.shortBreak, settings: s, unit: u, now: now)
        }
        askPermissionOnce()
    }

    public func skipBreak() {
        perform { m, s, u, now in m.skipBreak(settings: s, unit: u, now: now) }
    }

    public func pause() { perform { m, _, _, now in m.pause(now: now) } }
    public func resume() { perform { m, _, _, now in m.resume(now: now) } }
    public func stop() { perform { m, _, _, now in m.stop(now: now) } }

    public func togglePause() {
        guard let run = machine.state.run else { return }
        run.isPaused ? resume() : pause()
    }

    /// Adds five minutes to whatever is running.
    public func addTime() {
        let seconds = TimeInterval(TimerSettings.minutesAdded) * unit
        perform { m, _, _, now in m.extend(by: seconds, now: now) }
    }

    /// The global shortcut: start when idle, otherwise pause or resume.
    public func primaryAction() {
        if machine.state.run == nil { startFocus() } else { togglePause() }
    }

    public func setLabel(_ label: String?) {
        perform { m, _, _, _ in
            m.setLabel(label)
            return []
        }
    }

    /// A button pressed on a notification.
    public func handle(_ action: AlertAction) {
        switch action {
        case .startBreak:
            if machine.state.run == nil { startBreak() }
        case .skipBreak, .startFocus:
            if machine.state.run?.phase != .focus { startFocus() }
        }
    }

    public func updateSettings(_ change: (inout TimerSettings) -> Void) {
        var next = settings
        change(&next)
        next = next.clamped()
        guard next != settings else { return }
        let secondsChanged = next.showSeconds != settings.showSeconds
        settings = next
        do {
            try storage.saveSettings(next)
        } catch {
            saveError = Self.saveErrorText
        }
        if secondsChanged {
            updateDisplay()
            reschedule()
        } else {
            updateDisplay()
        }
    }

    /// Looks at the clock again. Call on wake, clock or time zone changes, a new day, and
    /// when the menu opens. Ends anything that ran out meanwhile.
    public func refresh() {
        perform { _, _, _, _ in [] }
    }

    public func refreshPermission() async {
        permission = await notifier.permission()
    }

    /// The Settings "Test" button: runs a shortcut now and reports what happened. A success
    /// clears the menu's error line; a failure is only reported to Settings.
    public func testShortcut(_ name: String) async -> String? {
        do {
            try await shortcuts.run(name)
            automationError = nil
            return nil
        } catch {
            return (error as? ShortcutError)?.message ?? ShortcutError.couldntRun(name).message
        }
    }

    public func availableShortcuts() async throws -> [String] {
        try await shortcuts.list()
    }

    public var availableSounds: [String] { sound.availableSounds }

    public func previewSound(_ name: String) { sound.play(name) }

    public func dismissAutomationError() { automationError = nil }

    // MARK: - Internals

    private func perform(_ action: (inout TimerMachine, TimerSettings, TimeInterval, Date) -> [TimerMachine.Event]) {
        let now = clock()
        self.now = now
        var events = machine.advance(settings: settings, unit: unit, now: now, lateAfter: lateAfter)
        events += action(&machine, settings, unit, now)
        commit(events, announce: true)
    }

    private func commit(_ events: [TimerMachine.Event], announce: Bool) {
        for event in events {
            switch event {
            case .recorded(let record):
                records.append(record)
                do {
                    try storage.append(record)
                } catch {
                    saveError = Self.saveErrorText
                }
            case .started(.focus):
                if announce { notifier.clearDelivered() }
                runShortcut(settings.startShortcut)
            case .started:
                if announce { notifier.clearDelivered() }
            case .ended(.focus):
                runShortcut(settings.endShortcut)
            case .alert(let alert):
                if announce { deliver(alert) }
            case .ended:
                break
            }
        }

        let significant = Self.significant(machine.state)
        if significant != Self.significant(savedState) {
            do {
                try storage.saveState(machine.state)
                savedState = machine.state
            } catch {
                saveError = Self.saveErrorText
            }
        }
        if significant != Self.significant(state) {
            state = machine.state
        }
        pruneRecords()
        updateDisplay()
        reschedule()
    }

    private func deliver(_ alert: Alert) {
        notifier.post(AlertContent.make(alert, settings: settings))
        // No sound for something that ended while the Mac slept: waking it shouldn't chime.
        if settings.playSound, !alert.isLate { sound.play(settings.soundName) }
        if permission != .authorized, !reduceMotion() { flash() }
    }

    /// On the first Start of each launch, unless already allowed. macOS never shows the
    /// prompt again after the user has answered it, so this only brings back a prompt that
    /// was never answered (macOS withdraws it when the app quits, and reports "denied" meanwhile).
    private func askPermissionOnce() {
        guard !didAskPermission else { return }
        didAskPermission = true
        Task {
            let current = await notifier.permission()
            permission = current == .authorized ? current : await notifier.requestPermission()
        }
    }

    private func runShortcut(_ name: String?) {
        guard settings.runShortcuts, let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // One at a time, in order: an "end" shortcut must not overtake the "start" one.
        let previous = shortcutChain
        let runner = shortcuts
        shortcutChain = Task { [weak self] in
            await previous?.value
            do {
                try await runner.run(name)
                self?.automationError = nil
            } catch {
                self?.automationError = (error as? ShortcutError)?.message ?? ShortcutError.couldntRun(name).message
            }
        }
    }

    /// Waits for queued shortcut runs (tests).
    public func waitForShortcuts() async {
        await shortcutChain?.value
    }

    private func reschedule() {
        pendingTick?.cancel()
        pendingTick = nil
        guard let run = machine.state.run, !run.isPaused, run.endsAt != nil else {
            activity.end()
            return
        }
        activity.begin()
        let remaining = run.remaining(at: now)
        let granularity = settings.showSeconds ? max(unit / 60, min(1, unit)) : unit
        let delay = TickPlanner.delay(remaining: remaining, granularity: granularity)
        let isEnd = delay >= remaining - 0.001
        let tolerance = isEnd ? 0.05 : (settings.showSeconds ? 0.1 : min(2, granularity / 10))
        pendingTick = scheduler.schedule(after: delay, tolerance: tolerance) { [weak self] in
            self?.refresh()
        }
    }

    private func updateDisplay() {
        let run = machine.state.run
        let newBarText = run.map { TimeText.menuBar($0.remaining(at: now), showSeconds: settings.showSeconds, unit: unit) }
        if newBarText != menuBarText { menuBarText = newBarText }
        let newHeadline = StatusText.headline(state: machine.state, now: now, unit: unit)
        if newHeadline != headline { headline = newHeadline }
        let newToday = DayStats.on(now, from: records, calendar: calendar)
        if newToday != today { today = newToday }
        let newTodayText = TimeText.today(newToday, unit: unit)
        if newTodayText != todayText { todayText = newTodayText }
        let newLabel = StatusText.accessibilityLabel(state: machine.state, now: now, unit: unit)
        if newLabel != accessibilityLabel { accessibilityLabel = newLabel }
    }

    private func flash() {
        flashTick?.cancel()
        flashBeats = Self.flashBeatCount
        beat()
    }

    private func beat() {
        guard flashBeats > 0 else {
            isFlashing = false
            flashTick = nil
            return
        }
        flashBeats -= 1
        isFlashing.toggle()
        flashTick = scheduler.schedule(after: 0.5, tolerance: 0.05) { [weak self] in self?.beat() }
    }

    private func pruneRecords() {
        let cutoff = Self.startOfYesterday(now, calendar)
        if let first = records.first, first.endedAt < cutoff {
            records.removeAll { $0.endedAt < cutoff }
        }
    }

    private static func startOfYesterday(_ now: Date, _ calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
    }

    /// The state minus clock bookkeeping, for "did anything really change?".
    private static func significant(_ state: TimerState) -> TimerState {
        var copy = state
        copy.run?.lastSeen = .distantPast
        return copy
    }

    static let saveErrorText = "Couldn't save your sessions. Check that your disk isn't full."

    /// Records kept in memory (yesterday and today), for tests.
    var recentRecords: [SessionRecord] { records }
}
