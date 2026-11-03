import Foundation

/// All user-facing text, deterministic (no locale lookups) so it's easy to test.
/// `unit` is the length of a minute in seconds: 60, except in accelerated tests.
public enum TimeText {
    /// Whole minutes left, rounded up so a fresh 25-minute session reads "25".
    public static func minutesLeft(_ seconds: TimeInterval, unit: TimeInterval = 60) -> Int {
        guard seconds > 0 else { return 0 }
        return Int((seconds / unit - 1e-9).rounded(.up))
    }

    /// The menu bar text: "18m", or "17:42" / "1:05:00" with seconds shown.
    public static func menuBar(_ seconds: TimeInterval, showSeconds: Bool, unit: TimeInterval = 60) -> String {
        if !showSeconds {
            return "\(max(1, minutesLeft(seconds, unit: unit)))m"
        }
        let total = Int((seconds * 60 / unit - 1e-9).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "18 min left", "1 hr 5 min left", "1 min left".
    public static func left(_ seconds: TimeInterval, unit: TimeInterval = 60) -> String {
        "\(duration(minutes: max(1, minutesLeft(seconds, unit: unit)))) left"
    }

    /// "25 min", "1 hr", "1 hr 15 min". Spelled-out units read better in a status line.
    public static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    /// Focused time rounded down to whole minutes.
    public static func duration(seconds: TimeInterval, unit: TimeInterval = 60) -> String {
        duration(minutes: Int((seconds / unit + 1e-9).rounded(.down)))
    }

    /// "Today: 3 sessions · 1 hr 15 min", "Today: no sessions yet".
    public static func today(_ stats: DayStats, unit: TimeInterval = 60) -> String {
        let minutes = Int((stats.focused / unit + 1e-9).rounded(.down))
        if stats.sessions == 0 && minutes == 0 { return "Today: no sessions yet" }
        let count = stats.sessions == 1 ? "1 session" : "\(stats.sessions) sessions"
        return "Today: \(count) · \(duration(minutes: minutes))"
    }

    /// Menu titles for the length presets: "25 Minutes".
    public static func minutesTitle(_ minutes: Int) -> String {
        minutes == 1 ? "1 Minute" : "\(minutes) Minutes"
    }

    /// "5-minute" for alert bodies.
    public static func adjective(minutes: Int) -> String { "\(minutes)-minute" }

    /// Spoken minutes for VoiceOver: "18 minutes", "1 minute".
    public static func spoken(minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

/// The menu's first line and the status item's VoiceOver label.
public enum StatusText {
    public static func headline(state: TimerState, now: Date, unit: TimeInterval = 60) -> String {
        guard let run = state.run else {
            if let pending = state.pendingBreak {
                return pending == .longBreak ? "Session done · long break next" : "Session done · break next"
            }
            return state.label.map { "Ready to focus · \($0)" } ?? "Ready to focus"
        }
        let left = TimeText.left(run.remaining(at: now), unit: unit)
        let name: String
        switch run.phase {
        case .focus: name = run.label ?? "Focusing"
        case .shortBreak: name = "Short break"
        case .longBreak: name = "Long break"
        }
        return run.isPaused ? "Paused · \(name) · \(left)" : "\(name) · \(left)"
    }

    public static func accessibilityLabel(state: TimerState, now: Date, unit: TimeInterval = 60) -> String {
        guard let run = state.run else { return "Focus timer, ready" }
        let minutes = TimeText.spoken(minutes: max(1, TimeText.minutesLeft(run.remaining(at: now), unit: unit)))
        let what: String
        switch run.phase {
        case .focus: what = "focusing"
        case .shortBreak: what = "on a short break"
        case .longBreak: what = "on a long break"
        }
        return run.isPaused ? "Focus timer, paused, \(minutes) left" : "Focus timer, \(what), \(minutes) left"
    }
}

/// Buttons on a notification.
public enum AlertAction: String, Sendable, CaseIterable {
    case startBreak, skipBreak, startFocus

    public var title: String {
        switch self {
        case .startBreak: "Start Break"
        case .skipBreak: "Skip Break"
        case .startFocus: "Start Focus"
        }
    }
}

/// What a notification says.
public struct AlertContent: Equatable, Sendable {
    public var title: String
    public var body: String
    public var actions: [AlertAction]

    public init(title: String, body: String, actions: [AlertAction]) {
        self.title = title
        self.body = body
        self.actions = actions
    }

    /// Notification category: one per distinct set of buttons.
    public var category: String {
        actions.isEmpty ? "plain" : actions.map(\.rawValue).joined(separator: "+")
    }

    public static func make(_ alert: Alert, settings: TimerSettings) -> AlertContent {
        switch alert {
        case let .focusDone(nextBreak, breakStarted, late):
            let minutes = TimeText.adjective(minutes: settings.minutes(for: nextBreak))
            let kind = nextBreak == .longBreak ? "long break" : "break"
            if late {
                return AlertContent(
                    title: "Focus session done",
                    body: breakStarted
                        ? "It ended while your Mac was asleep. Your \(kind) is still running."
                        : "It ended while your Mac was asleep.",
                    actions: breakStarted ? [.skipBreak] : [.startFocus]
                )
            }
            if breakStarted {
                return AlertContent(title: "Focus session done",
                                    body: "Your \(minutes) \(kind) has started.",
                                    actions: [.skipBreak])
            }
            return AlertContent(title: "Focus session done",
                                body: "Take a \(minutes) \(kind) when you're ready.",
                                actions: [.startBreak, .startFocus])
        case let .breakDone(focusStarted, late):
            if late {
                return AlertContent(title: "Break's over",
                                    body: "It ended while your Mac was asleep.",
                                    actions: [.startFocus])
            }
            if focusStarted {
                return AlertContent(title: "Break's over",
                                    body: "Your next \(TimeText.adjective(minutes: settings.focusMinutes)) session has started.",
                                    actions: [])
            }
            return AlertContent(title: "Break's over",
                                body: "Start the next session when you're ready.",
                                actions: [.startFocus])
        }
    }
}

/// When to look at the clock next while a phase runs: when the shown value changes, or at
/// the end, whichever comes first. Nothing ticks faster than what's on screen.
public enum TickPlanner {
    /// - Parameters:
    ///   - remaining: seconds left.
    ///   - granularity: seconds per displayed step (60 for "18m", 1 for "17:42").
    public static func delay(remaining: TimeInterval, granularity: TimeInterval) -> TimeInterval {
        guard remaining > 0 else { return 0 }
        guard granularity > 0 else { return remaining }
        let steps = (remaining / granularity - 1e-9).rounded(.up)
        let untilChange = remaining - (steps - 1) * granularity
        return min(max(untilChange, 0.001), remaining)
    }
}
