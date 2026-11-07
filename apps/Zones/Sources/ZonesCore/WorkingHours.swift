import Foundation

/// When someone at a place is at work: a daily span of wall-clock time on some weekdays.
/// An end at or before the start is an overnight shift (22:00–06:00), which belongs to the
/// day it starts on.
public struct WorkingHours: Codable, Hashable, Sendable {
    /// Minutes after midnight, 0..<1440.
    public var start: Int
    /// Minutes after midnight, 1...1440 (1440 = midnight at the end of the day).
    public var end: Int
    /// Workdays as `Calendar` weekdays: 1 Sunday … 7 Saturday.
    public var days: Set<Int>

    public init(start: Int, end: Int, days: Set<Int>) {
        self.start = max(0, min(1439, start))
        self.end = max(1, min(1440, end))
        self.days = days.filter { (1...7).contains($0) }
    }

    /// 9:00–17:00, Monday to Friday.
    public static let standard = WorkingHours(start: 9 * 60, end: 17 * 60, days: [2, 3, 4, 5, 6])

    public var isOvernight: Bool { end <= start }

    /// Is `minute` (after midnight) on `weekday` inside these hours?
    public func contains(minute: Int, weekday: Int) -> Bool {
        if isOvernight {
            if minute >= start { return days.contains(weekday) }
            if minute < end { return days.contains(Self.weekday(before: weekday)) }
            return false
        }
        return minute >= start && minute < end && days.contains(weekday)
    }

    /// Is `instant` inside these hours, read on `zone`'s wall clock?
    public func contains(_ instant: Date, in zone: TimeZone) -> Bool {
        let clock = WallClock(instant, zone)
        return contains(minute: clock.minuteOfDay, weekday: clock.weekday)
    }

    static func weekday(before weekday: Int) -> Int { weekday == 1 ? 7 : weekday - 1 }

    /// "9:00 AM – 5:00 PM" in the formatter's style.
    public func spanText(formatter: TimeFormatter) -> String {
        let utc = TimeZone(secondsFromGMT: 0)!
        let from = formatter.time(Date(timeIntervalSince1970: TimeInterval(start * 60)), in: utc)
        let to = formatter.time(Date(timeIntervalSince1970: TimeInterval((end % 1440) * 60)), in: utc)
        return "\(from) – \(to)"
    }

    /// "Mon–Fri", "Sun–Thu", "Mon, Wed, Fri", "Every day", "No workdays".
    public func daysText(locale: Locale = .autoupdatingCurrent) -> String {
        if days.isEmpty { return "No workdays" }
        if days.count == 7 { return "Every day" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let names = calendar.shortWeekdaySymbols // index 0 = Sunday
        // Find a single run in week order, allowing it to wrap past Saturday.
        let sorted = days.sorted()
        for first in sorted {
            let run = (0..<days.count).map { ((first - 1 + $0) % 7) + 1 }
            if Set(run) == days, days.count > 2 {
                return "\(names[run.first! - 1])–\(names[run.last! - 1])"
            }
        }
        // Not one run: list them from Monday.
        let order = [2, 3, 4, 5, 6, 7, 1].filter(days.contains)
        return order.map { names[$0 - 1] }.joined(separator: ", ")
    }

    /// "9:00 AM – 5:00 PM, Mon–Fri"
    public func summary(formatter: TimeFormatter) -> String {
        "\(spanText(formatter: formatter)), \(daysText(locale: formatter.locale))"
    }
}

/// What people at a place are probably doing at an instant. Drives the time's colour,
/// the day strips and the planner.
public enum Activity: String, Sendable, CaseIterable {
    /// Inside their working hours.
    case working
    /// Awake, outside working hours on a workday.
    case afterHours
    /// Awake on a day off.
    case dayOff
    /// Probably asleep (22:00–07:00), unless that's their working time.
    case night

    /// Sleeping hours used for `.night`: 22:00 to 07:00.
    public static let nightStart = 22 * 60
    public static let nightEnd = 7 * 60

    public static func at(_ instant: Date, in zone: TimeZone, hours: WorkingHours) -> Activity {
        let clock = WallClock(instant, zone)
        return at(minute: clock.minuteOfDay, weekday: clock.weekday, hours: hours)
    }

    public static func at(minute: Int, weekday: Int, hours: WorkingHours) -> Activity {
        if hours.contains(minute: minute, weekday: weekday) { return .working }
        if minute >= nightStart || minute < nightEnd { return .night }
        return hours.days.contains(weekday) ? .afterHours : .dayOff
    }

    /// "Working hours", "After hours", "Day off", "Night".
    public var title: String {
        switch self {
        case .working: "Working hours"
        case .afterHours: "After hours"
        case .dayOff: "Day off"
        case .night: "Night"
        }
    }

    public var spokenName: String { title.lowercased() }
}

/// Wall-clock reading of an instant in a zone, without Calendar (fast enough for strips).
public struct WallClock: Equatable, Sendable {
    /// Days since 1970-01-01 on the zone's calendar.
    public var day: Int
    public var minuteOfDay: Int
    /// `Calendar` weekday: 1 Sunday … 7 Saturday.
    public var weekday: Int

    public init(_ instant: Date, _ zone: TimeZone) {
        let local = Int((instant.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: instant))).rounded(.down))
        let day = Int((Double(local) / 86_400).rounded(.down))
        self.day = day
        minuteOfDay = (local - day * 86_400) / 60
        // 1970-01-01 was a Thursday (weekday 5).
        weekday = ((day + 4) % 7 + 7) % 7 + 1
    }
}
