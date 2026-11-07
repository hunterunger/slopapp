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

/// How a session went, picked in the reflection after it.
public enum Mood: String, Codable, Sendable, CaseIterable {
    case focused, neutral, distracted

    public var title: String {
        switch self {
        case .focused: "Focused"
        case .neutral: "Neutral"
        case .distracted: "Distracted"
        }
    }
}

/// A category's colour. System colours only (the UI maps these to SwiftUI's named colours),
/// so they adapt to light, dark and increased contrast. `accent` follows the user's accent.
public enum CategoryColor: String, Codable, Sendable, CaseIterable {
    case accent, red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    public var title: String { rawValue == "accent" ? "Accent" : rawValue.capitalized }
}

/// What a session is for ("Work", "Study"). Sessions keep the category's id and name.
public struct Category: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: CategoryColor

    public init(id: String = UUID().uuidString, name: String, color: CategoryColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// The first-run set: three common ones, easy to rename or delete.
    public static let defaults: [Category] = [
        Category(id: "work", name: "Work", color: .blue),
        Category(id: "study", name: "Study", color: .purple),
        Category(id: "personal", name: "Personal", color: .green),
    ]
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
    public var categoryID: String?
    /// What the user wrote during the session.
    public var notes: String?
    /// Time spent paused so far (not counting the current pause).
    public var pausedTotal: TimeInterval
    /// When the current pause began.
    public var pausedAt: Date?

    public init(phase: Phase, length: TimeInterval, startedAt: Date, label: String? = nil, categoryID: String? = nil) {
        self.phase = phase
        self.planned = max(0, length)
        self.startedAt = startedAt
        self.endsAt = startedAt.addingTimeInterval(max(0, length))
        self.pausedRemaining = nil
        self.label = label
        self.lastSeen = startedAt
        self.categoryID = categoryID
        self.notes = nil
        self.pausedTotal = 0
        self.pausedAt = nil
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(Phase.self, forKey: .phase)
        planned = try c.decode(TimeInterval.self, forKey: .planned)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        pausedRemaining = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? startedAt
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        pausedTotal = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedTotal) ?? 0
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
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

    /// Paused time including the pause in progress.
    public func paused(at now: Date) -> TimeInterval {
        pausedTotal + (pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// When it will end if it keeps running from `now` (for "15:05 → 15:30").
    public func projectedEnd(at now: Date) -> Date { endsAt ?? now.addingTimeInterval(remaining(at: now)) }
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
    /// The user's intention for their sessions, kept until they change it.
    public var label: String?
    /// The category for the next sessions, kept until changed. Nil: no category.
    public var categoryID: String?
    /// The session waiting for a reflection (mood and notes), if any.
    public var pendingReflection: SessionRecord?

    public init(run: Run? = nil, pendingBreak: Phase? = nil, cycleCount: Int = 0, cycleDay: Date? = nil,
                label: String? = nil, categoryID: String? = nil, pendingReflection: SessionRecord? = nil) {
        self.run = run
        self.pendingBreak = pendingBreak
        self.cycleCount = cycleCount
        self.cycleDay = cycleDay
        self.label = label
        self.categoryID = categoryID
        self.pendingReflection = pendingReflection
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        run = try c.decodeIfPresent(Run.self, forKey: .run)
        pendingBreak = try c.decodeIfPresent(Phase.self, forKey: .pendingBreak)
        cycleCount = try c.decodeIfPresent(Int.self, forKey: .cycleCount) ?? 0
        cycleDay = try c.decodeIfPresent(Date.self, forKey: .cycleDay)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        pendingReflection = try c.decodeIfPresent(SessionRecord.self, forKey: .pendingReflection)
    }
}

/// One finished focus session or break, as written to the history log.
///
/// The log is append-only: changing a record (a reflection added, a delete) appends a new
/// line with the same `id`, and the last line for an id wins.
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    /// Stable for the session: the phase and the moment it started.
    public var id: String
    public var kind: Phase
    public var startedAt: Date
    public var endedAt: Date
    /// Planned length in seconds, including time added.
    public var planned: TimeInterval
    /// Time actually spent focusing (or resting), paused time excluded.
    public var focused: TimeInterval
    /// Ran all the way to zero, or the user finished it.
    public var completed: Bool
    /// Counts toward the day's sessions: completed, or stopped after most of it ran.
    public var counted: Bool
    /// The intention.
    public var label: String?
    public var categoryID: String?
    /// The category's name when the session ran (kept if the category is deleted later).
    public var categoryName: String?
    public var paused: TimeInterval
    public var mood: Mood?
    public var notes: String?
    /// Removed by the user. Kept as a line in the log so the removal survives a relaunch.
    public var deleted: Bool

    /// Share of the planned length that must run for a stopped session to count.
    public static let countThreshold = 0.8

    public init(startedAt: Date, endedAt: Date, planned: TimeInterval, focused: TimeInterval, completed: Bool, label: String?,
                kind: Phase = .focus, categoryID: String? = nil, categoryName: String? = nil, paused: TimeInterval = 0,
                mood: Mood? = nil, notes: String? = nil) {
        self.id = Self.makeID(kind: kind, startedAt: startedAt)
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.planned = planned
        self.focused = max(0, min(focused, planned))
        self.completed = completed
        // Half a second of slack so "stopped right at 80%" isn't lost to rounding.
        self.counted = kind == .focus && (completed || (planned > 0 && self.focused + 0.5 >= planned * Self.countThreshold))
        self.label = label
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.paused = max(0, paused)
        self.mood = mood
        self.notes = notes
        self.deleted = false
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Phase.self, forKey: .kind) ?? .focus
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        planned = try c.decode(TimeInterval.self, forKey: .planned)
        focused = try c.decode(TimeInterval.self, forKey: .focused)
        completed = try c.decode(Bool.self, forKey: .completed)
        counted = try c.decode(Bool.self, forKey: .counted)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        paused = try c.decodeIfPresent(TimeInterval.self, forKey: .paused) ?? 0
        mood = try c.decodeIfPresent(Mood.self, forKey: .mood)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        // Lines written before ids existed get the same id every time they're read.
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Self.makeID(kind: kind, startedAt: startedAt)
    }

    static func makeID(kind: Phase, startedAt: Date) -> String {
        "\(kind.rawValue)-\(Int64((startedAt.timeIntervalSince1970 * 1000).rounded()))"
    }

    public var isFocus: Bool { kind == .focus }
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
        for record in records where record.isFocus && !record.deleted && calendar.isDate(record.endedAt, inSameDayAs: day) {
            if record.counted { stats.sessions += 1 }
            stats.focused += record.focused
        }
        return stats
    }
}
