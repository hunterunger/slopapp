import Foundation

/// The span the Stats view shows.
public enum StatsPeriod: String, CaseIterable, Sendable {
    case day, week, month

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// One day, week or month, as a half-open interval [start, end).
public struct StatsRange: Equatable, Sendable {
    public var period: StatsPeriod
    public var start: Date
    public var end: Date

    /// The period containing `date`. Weeks start on the calendar's first weekday.
    public static func containing(_ date: Date, period: StatsPeriod, calendar: Calendar) -> StatsRange {
        let interval = calendar.dateInterval(of: period.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        return StatsRange(period: period, start: interval.start, end: interval.end)
    }

    /// The previous (-1) or next (+1) period.
    public func shifted(by count: Int, calendar: Calendar) -> StatsRange {
        let moved = calendar.date(byAdding: period.component, value: count, to: start) ?? start
        return .containing(moved, period: period, calendar: calendar)
    }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// "Today", "Yesterday", "Tuesday, Nov 3"; "This Week", "Nov 1 – 7"; "This Month", "October 2026".
    public func title(now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let current = StatsRange.containing(now, period: period, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        switch period {
        case .day:
            if current == self { return "Today" }
            if current.shifted(by: -1, calendar: calendar) == self { return "Yesterday" }
            formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
            return formatter.string(from: start)
        case .week:
            if current == self { return "This Week" }
            if current.shifted(by: -1, calendar: calendar) == self { return "Last Week" }
            let last = end.addingTimeInterval(-1)
            let interval = DateIntervalFormatter()
            interval.calendar = calendar
            interval.timeZone = calendar.timeZone
            interval.locale = locale
            interval.dateTemplate = "MMMd"
            return interval.string(from: start, to: last)
        case .month:
            if current == self { return "This Month" }
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: start)
        }
    }
}

/// Seconds focused in one chart bar, split by category.
public struct StatsBucket: Equatable, Sendable, Identifiable {
    /// Start of the hour (day view) or day (week and month views).
    public var start: Date
    /// Seconds per category id ("" for no category).
    public var seconds: [String: TimeInterval]
    public var id: Date { start }
    public var total: TimeInterval { seconds.values.reduce(0, +) }
}

/// One category's share of the period.
public struct CategoryShare: Equatable, Sendable, Identifiable {
    /// Category id, "" for no category.
    public var id: String
    public var name: String
    public var color: CategoryColor?
    public var seconds: TimeInterval
    public var sessions: Int
    /// 0...1 of all focused time in the period.
    public var share: Double
}

/// Everything the Stats view shows for one period.
public struct StatsReport: Equatable, Sendable {
    public var range: StatsRange
    /// Focus sessions and breaks in the range (by end time), newest first.
    public var records: [SessionRecord]
    public var totalFocus: TimeInterval
    public var totalBreak: TimeInterval
    /// Sessions that count (completed, or most of it ran).
    public var sessions: Int
    /// Focused time per day, over the days of the range that have started.
    public var averagePerDay: TimeInterval
    /// Hour of day (0–23) with the most focused time, nil with no sessions.
    public var mostFocusedHour: Int?
    public var moods: [Mood: Int]
    /// Sessions with no reflection.
    public var unrated: Int
    public var buckets: [StatsBucket]
    public var categories: [CategoryShare]

    /// Key used in buckets and shares for sessions without a category.
    public static let noCategory = ""

    public static func make(range: StatsRange, records all: [SessionRecord], categories: [Category],
                            now: Date, calendar: Calendar, categoryFilter: String? = nil) -> StatsReport {
        let inRange = all.filter { !$0.deleted && range.contains($0.endedAt) }
        let focus = inRange.filter { $0.isFocus && (categoryFilter == nil || ($0.categoryID ?? noCategory) == categoryFilter) }
        let breaks = inRange.filter { !$0.isFocus }
        let records = (categoryFilter == nil ? inRange : focus).sorted { $0.endedAt > $1.endedAt }

        let totalFocus = focus.reduce(0) { $0 + $1.focused }
        let totalBreak = breaks.reduce(0) { $0 + $1.focused }

        // Days that have started: a week in progress averages over the days so far.
        let lastDay = min(range.end, max(range.start.addingTimeInterval(1), calendar.startOfDay(for: now).addingTimeInterval(86_400)))
        let days = max(1, calendar.dateComponents([.day], from: range.start, to: lastDay).day ?? 1)

        var byHour: [Int: TimeInterval] = [:]
        for record in focus { byHour[calendar.component(.hour, from: record.startedAt), default: 0] += record.focused }
        let mostFocusedHour = byHour.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key

        var moods: [Mood: Int] = [:]
        var unrated = 0
        for record in focus {
            if let mood = record.mood { moods[mood, default: 0] += 1 } else { unrated += 1 }
        }

        // Bars: hours of the day, or days of the week/month.
        let step: Calendar.Component = range.period == .day ? .hour : .day
        var starts: [Date] = []
        var cursor = range.start
        while cursor < range.end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: step, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        var buckets = starts.map { StatsBucket(start: $0, seconds: [:]) }
        for record in focus {
            let anchor = range.period == .day ? record.startedAt : record.endedAt
            guard let index = starts.lastIndex(where: { $0 <= anchor }) else { continue }
            buckets[index].seconds[record.categoryID ?? noCategory, default: 0] += record.focused
        }

        var shares: [String: CategoryShare] = [:]
        for record in focus {
            let key = record.categoryID ?? noCategory
            let category = categories.first { $0.id == key }
            var share = shares[key] ?? CategoryShare(
                id: key,
                name: category?.name ?? record.categoryName ?? (key == noCategory ? "No Category" : "Deleted Category"),
                color: category?.color, seconds: 0, sessions: 0, share: 0
            )
            share.seconds += record.focused
            if record.counted { share.sessions += 1 }
            shares[key] = share
        }
        let categoryShares = shares.values
            .map { share -> CategoryShare in
                var s = share
                s.share = totalFocus > 0 ? share.seconds / totalFocus : 0
                return s
            }
            .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }

        return StatsReport(
            range: range, records: records, totalFocus: totalFocus, totalBreak: totalBreak,
            sessions: focus.filter(\.counted).count, averagePerDay: totalFocus / Double(days),
            mostFocusedHour: mostFocusedHour, moods: moods, unrated: unrated,
            buckets: buckets, categories: categoryShares
        )
    }
}

/// Shorter durations for stats tiles and rows: "25m", "1h 5m", "0m".
public enum CompactDuration {
    public static func text(_ seconds: TimeInterval, unit: TimeInterval = 60) -> String {
        let minutes = Int((seconds / unit + 1e-9).rounded(.down))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "9 AM", "Noon", "3 PM" (or "09:00" in 24-hour locales).
    public static func hour(_ hour: Int, calendar: Calendar, locale: Locale = .current) -> String {
        if hour == 12, locale.hourCycle == .oneToTwelve || locale.hourCycle == .zeroToEleven { return "Noon" }
        var components = DateComponents()
        components.year = 2000; components.month = 1; components.day = 1; components.hour = hour
        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}

/// Round steps for a chart's minutes axis: "0m, 30m, 1h, 1h 30m" rather than "1h 40m, 3h 20m".
public enum ChartAxis {
    /// Candidate steps in minutes.
    public static let steps: [Double] = [5, 10, 15, 30, 60, 120, 180, 240, 360, 480, 720]

    /// The smallest round step that covers `maxMinutes` in at most `maxTicks` steps, and the
    /// axis top (a whole number of steps, at least one). An empty chart gets a one-hour axis.
    public static func scale(maxMinutes: Double, maxTicks: Int = 4) -> (step: Double, top: Double) {
        let value = maxMinutes.isFinite && maxMinutes > 0 ? maxMinutes : 60
        let step = steps.first { value / $0 <= Double(maxTicks) } ?? (value / Double(maxTicks)).rounded(.up)
        return (step, max(step, (value / step).rounded(.up) * step))
    }
}
