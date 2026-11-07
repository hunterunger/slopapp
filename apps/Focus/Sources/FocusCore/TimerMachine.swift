import Foundation

/// Something the user should hear about when a phase ends.
public enum Alert: Equatable, Sendable {
    /// A focus session ran to zero. `breakStarted`: the break began by itself.
    case focusDone(nextBreak: Phase, breakStarted: Bool, late: Bool)
    /// A break ran to zero. `focusStarted`: the next session began by itself.
    case breakDone(focusStarted: Bool, late: Bool)

    /// It ended a while ago (the Mac was asleep, or the app wasn't running).
    public var isLate: Bool {
        switch self {
        case .focusDone(_, _, let late), .breakDone(_, let late): late
        }
    }
}

/// The pure timer: given the time, decides what happens. No clocks, timers or I/O, so every
/// edge case (sleep, relaunch, clock changes, midnight) is a plain unit test.
///
/// Each call returns the events that happened, for `FocusController` to act on.
public struct TimerMachine: Sendable {
    public enum Event: Equatable, Sendable {
        case started(Phase)
        case ended(Phase)
        case recorded(SessionRecord)
        case alert(Alert)
    }

    public var state: TimerState
    public var calendar: Calendar

    public init(state: TimerState = TimerState(), calendar: Calendar = .current) {
        self.state = state
        self.calendar = calendar
    }

    // MARK: - User actions

    /// Starts `phase` now. Whatever was running ends first (a focus session is logged).
    public mutating func start(_ phase: Phase, settings: TimerSettings, unit: TimeInterval, now: Date) -> [Event] {
        if let run = state.run, run.phase == phase, !run.isPaused { return [] }
        var events = endCurrentRun(at: now)
        state.pendingBreak = nil
        state.run = makeRun(phase, settings: settings, unit: unit, startedAt: now)
        events.append(.started(phase))
        return events
    }

    /// Starts the break that was offered when the last session ended.
    public mutating func startPendingBreak(settings: TimerSettings, unit: TimeInterval, now: Date) -> [Event] {
        guard state.run == nil, let phase = state.pendingBreak else { return [] }
        return start(phase, settings: settings, unit: unit, now: now)
    }

    /// Ends a break early and goes straight into the next focus session.
    public mutating func skipBreak(settings: TimerSettings, unit: TimeInterval, now: Date) -> [Event] {
        if let run = state.run, !run.phase.isBreak { return [] }
        return start(.focus, settings: settings, unit: unit, now: now)
    }

    public mutating func pause(now: Date) -> [Event] {
        guard var run = state.run, !run.isPaused else { return [] }
        run.pausedRemaining = run.remaining(at: now)
        run.endsAt = nil
        run.lastSeen = now
        run.pausedAt = now
        state.run = run
        return []
    }

    public mutating func resume(now: Date) -> [Event] {
        guard var run = state.run, let left = run.pausedRemaining else { return [] }
        run.endsAt = now.addingTimeInterval(left)
        run.pausedRemaining = nil
        run.lastSeen = now
        run.pausedTotal = run.paused(at: now)
        run.pausedAt = nil
        state.run = run
        return []
    }

    /// Stops without a break. A focus session is logged; it counts if most of it ran.
    public mutating func stop(now: Date) -> [Event] {
        state.pendingBreak = nil
        return endCurrentRun(at: now)
    }

    /// Ends a focus session now as done: it counts, and the break follows as if it had run
    /// to zero (started or offered, per the settings). Nothing is announced: the user did it.
    public mutating func finish(settings: TimerSettings, unit: TimeInterval, now: Date) -> [Event] {
        guard let run = state.run, run.phase == .focus else { return [] }
        state.run = nil
        var events: [Event] = [.ended(.focus), .recorded(makeRecord(for: run, endedAt: now, completed: true))]
        countSession(endedAt: now)
        let nextBreak = takeNextBreak(settings: settings)
        if settings.autoStartBreaks {
            state.run = makeRun(nextBreak, settings: settings, unit: unit, startedAt: now)
            events.append(.started(nextBreak))
        } else {
            state.pendingBreak = nextBreak
        }
        return events
    }

    /// Takes time off whatever is running or paused, if more than that is left.
    public mutating func shorten(by seconds: TimeInterval, now: Date) -> [Event] {
        guard var run = state.run, seconds > 0, run.remaining(at: now) > seconds else { return [] }
        run.planned -= seconds
        if let left = run.pausedRemaining {
            run.pausedRemaining = left - seconds
        } else if let endsAt = run.endsAt {
            run.endsAt = endsAt.addingTimeInterval(-seconds)
        }
        state.run = run
        return []
    }

    /// The category for this and the next sessions. Nil: no category.
    public mutating func setCategory(_ id: String?) {
        state.categoryID = id
        if var run = state.run, run.phase == .focus {
            run.categoryID = id
            state.run = run
        }
    }

    /// Notes for the running focus session.
    public mutating func setNotes(_ notes: String) {
        guard var run = state.run, run.phase == .focus else { return }
        run.notes = notes.isEmpty ? nil : notes
        state.run = run
    }

    /// Adds time to whatever is running or paused.
    public mutating func extend(by seconds: TimeInterval, now: Date) -> [Event] {
        guard var run = state.run, seconds > 0 else { return [] }
        run.planned += seconds
        if let left = run.pausedRemaining {
            run.pausedRemaining = left + seconds
        } else if let endsAt = run.endsAt {
            // Count from what's actually left, so time added after zero isn't swallowed.
            run.endsAt = max(endsAt, now).addingTimeInterval(seconds)
        }
        state.run = run
        return []
    }

    public mutating func setLabel(_ label: String?) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        state.label = value
        if var run = state.run, run.phase == .focus {
            run.label = value
            state.run = run
        }
    }

    // MARK: - Time passing

    /// Brings the state up to `now`: ends a phase whose time is up and starts what follows.
    ///
    /// - `lateAfter`: how overdue an end can be and still count as "on time". Later than that
    ///   the Mac was asleep (or the app wasn't running): the phase is logged at the time it
    ///   really ended, a break that would still be running carries on, and nothing else
    ///   starts by itself, so a night asleep can't invent a string of sessions.
    public mutating func advance(settings: TimerSettings, unit: TimeInterval, now: Date, lateAfter: TimeInterval) -> [Event] {
        // A break offered yesterday isn't on offer this morning.
        if state.pendingBreak != nil, let day = state.cycleDay, !calendar.isDate(day, inSameDayAs: now) {
            state.pendingBreak = nil
        }
        guard var run = state.run else { return [] }

        // The clock was set back: assume no time passed and shift the run with it.
        let setBack = run.lastSeen.timeIntervalSince(now)
        if setBack > 1 {
            run.startedAt = run.startedAt.addingTimeInterval(-setBack)
            run.endsAt = run.endsAt?.addingTimeInterval(-setBack)
        }
        run.lastSeen = now
        state.run = run

        guard let endsAt = run.endsAt, now >= endsAt else { return [] }
        let late = now.timeIntervalSince(endsAt) > lateAfter
        state.run = nil
        var events: [Event] = [.ended(run.phase)]

        if run.phase == .focus {
            events.append(.recorded(makeRecord(for: run, endedAt: endsAt, completed: true)))
            countSession(endedAt: endsAt)
            let nextBreak = takeNextBreak(settings: settings)
            var breakStarted = false
            if settings.autoStartBreaks {
                let breakRun = makeRun(nextBreak, settings: settings, unit: unit, startedAt: endsAt)
                if let breakEnd = breakRun.endsAt, breakEnd > now {
                    var running = breakRun
                    running.lastSeen = now
                    state.run = running
                    breakStarted = true
                    events.append(.started(nextBreak))
                }
            } else {
                state.pendingBreak = nextBreak
            }
            events.append(.alert(.focusDone(nextBreak: nextBreak, breakStarted: breakStarted, late: late)))
        } else {
            events.append(.recorded(makeRecord(for: run, endedAt: endsAt, completed: true)))
            var focusStarted = false
            if settings.autoStartFocus, !late {
                var focusRun = makeRun(.focus, settings: settings, unit: unit, startedAt: endsAt)
                focusRun.lastSeen = now
                state.run = focusRun
                focusStarted = true
                events.append(.started(.focus))
            }
            events.append(.alert(.breakDone(focusStarted: focusStarted, late: late)))
        }
        return events
    }

    // MARK: - Helpers

    private mutating func endCurrentRun(at now: Date) -> [Event] {
        guard let run = state.run else { return [] }
        state.run = nil
        let record = makeRecord(for: run, endedAt: now, completed: false)
        guard run.phase == .focus else { return [.ended(run.phase), .recorded(record)] }
        if record.counted { countSession(endedAt: now) }
        return [.ended(.focus), .recorded(record)]
    }

    private func makeRun(_ phase: Phase, settings: TimerSettings, unit: TimeInterval, startedAt: Date) -> Run {
        let isFocus = phase == .focus
        return Run(phase: phase, length: settings.length(of: phase, unit: unit), startedAt: startedAt,
                   label: isFocus ? state.label : nil, categoryID: isFocus ? state.categoryID : nil)
    }

    /// The log line for a phase that ended at `endedAt`.
    private func makeRecord(for run: Run, endedAt: Date, completed: Bool) -> SessionRecord {
        let ranToZero = completed && run.endsAt.map { endedAt >= $0 } ?? false
        return SessionRecord(startedAt: run.startedAt, endedAt: endedAt, planned: run.planned,
                             focused: ranToZero ? run.planned : run.elapsed(at: endedAt), completed: completed,
                             label: run.label, kind: run.phase, categoryID: run.categoryID,
                             paused: run.paused(at: endedAt), notes: run.notes)
    }

    private mutating func countSession(endedAt: Date) {
        let day = calendar.startOfDay(for: endedAt)
        if state.cycleDay != day {
            state.cycleDay = day
            state.cycleCount = 0
        }
        state.cycleCount += 1
    }

    /// The break that follows a finished session. Choosing a long break starts a new cycle.
    private mutating func takeNextBreak(settings: TimerSettings) -> Phase {
        guard settings.longBreakEvery > 0, state.cycleCount >= settings.longBreakEvery else { return .shortBreak }
        state.cycleCount = 0
        return .longBreak
    }
}
