import Foundation

/// What the timer is counting down.
public enum Phase: String, Codable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }

    /// "Focus", "Short break", "Long break": sentence case for status lines.
    public var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

/// One running or paused phase.
///
/// Time is modelled from dates, never by counting ticks: a running phase stores when it
/// ends, so sleep, App Nap or a late timer can't make it drift. A paused phase stores the
/// time that was left. `lastSeen` is the last time the app looked at the clock; if the clock
/// is ever earlier than that, it was set back and `TimerMachine` shifts the run to match.
public struct Run: Codable, Equatable, Sendable {
    public var phase: Phase
    /// Planned length in seconds, including any time added.
    public var planned: TimeInterval
    public var startedAt: Date
    /// When it ends. Nil while paused.
    public var endsAt: Date?
    /// Time left when it was paused. Nil while running.
    public var pausedRemaining: TimeInterval?
    public var label: String?
    public var lastSeen: Date

    public init(phase: Phase, length: TimeInterval, startedAt: Date, label: String? = nil) {
        self.phase = phase
        self.planned = max(0, length)
        self.startedAt = startedAt
        self.endsAt = startedAt.addingTimeInterval(max(0, length))
        self.pausedRemaining = nil
        self.label = label
        self.lastSeen = startedAt
    }

    public var isPaused: Bool { pausedRemaining != nil }

    /// Time left, never negative and never more than planned (clock changes can't make it so).
    public func remaining(at now: Date) -> TimeInterval {
        let raw: TimeInterval
        if let pausedRemaining {
            raw = pausedRemaining
        } else if let endsAt {
            raw = endsAt.timeIntervalSince(now)
        } else {
            raw = 0
        }
        return min(max(0, raw), planned)
    }

    /// Time spent in this phase so far (paused time excluded).
    public func elapsed(at now: Date) -> TimeInterval { planned - remaining(at: now) }
}

/// Everything the timer needs to survive a relaunch. Saved after every change.
public struct TimerState: Codable, Equatable, Sendable {
    public var run: Run?
    /// A break that's offered (Start Break) because breaks don't start by themselves.
    public var pendingBreak: Phase?
    /// Counted focus sessions since the last long break, today.
    public var cycleCount: Int
    /// Start of the day `cycleCount` belongs to. A new day starts a new cycle.
    public var cycleDay: Date?
    /// The user's label for their sessions, kept until they change it.
    public var label: String?

    public init(run: Run? = nil, pendingBreak: Phase? = nil, cycleCount: Int = 0, cycleDay: Date? = nil, label: String? = nil) {
        self.run = run
        self.pendingBreak = pendingBreak
        self.cycleCount = cycleCount
        self.cycleDay = cycleDay
        self.label = label
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decodeIfPresent(Run.self, forKey: .run)
        pendingBreak = try c.decodeIfPresent(Phase.self, forKey: .pendingBreak)
        cycleCount = try c.decodeIfPresent(Int.self, forKey: .cycleCount) ?? 0
        cycleDay = try c.decodeIfPresent(Date.self, forKey: .cycleDay)
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

/// One finished focus session, as written to the history log.
public struct SessionRecord: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    /// Planned length in seconds, including time added.
    public var planned: TimeInterval
    /// Time actually spent focusing (paused time excluded).
    public var focused: TimeInterval
    /// Ran all the way to zero.
    public var completed: Bool
    /// Counts toward the day's sessions: completed, or stopped after most of it ran.
    public var counted: Bool
    public var label: String?

    /// Share of the planned length that must run for a stopped session to count.
    public static let countThreshold = 0.8

    public init(startedAt: Date, endedAt: Date, planned: TimeInterval, focused: TimeInterval, completed: Bool, label: String?) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.planned = planned
        self.focused = max(0, min(focused, planned))
        self.completed = completed
        // Half a second of slack so "stopped right at 80%" isn't lost to rounding.
        self.counted = completed || (planned > 0 && self.focused + 0.5 >= planned * Self.countThreshold)
        self.label = label
    }
}

/// The status line's numbers: sessions counted today and time focused today.
public struct DayStats: Equatable, Sendable {
    public var sessions: Int
    public var focused: TimeInterval

    public init(sessions: Int = 0, focused: TimeInterval = 0) {
        self.sessions = sessions
        self.focused = focused
    }

    /// A session belongs to the day it ended on (local time). Every minute focused counts
    /// toward the total, including sessions stopped early; only counted ones add to the tally.
    public static func on(_ day: Date, from records: [SessionRecord], calendar: Calendar) -> DayStats {
        var stats = DayStats()
        for record in records where calendar.isDate(record.endedAt, inSameDayAs: day) {
            if record.counted { stats.sessions += 1 }
            stats.focused += record.focused
        }
        return stats
    }
}
