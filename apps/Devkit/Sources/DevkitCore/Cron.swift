import Foundation

/// Cron expressions: 5 fields (minute hour day-of-month month day-of-week), an optional
/// 6th leading seconds field, and the @hourly-style macros. Explains them in English and
/// lists the next run times.
public enum Cron {
    public struct ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
    }

    public struct Field: Sendable, Equatable {
        public var values: Set<Int>
        /// `*` (or `?`): matters for the day-of-month / day-of-week rule.
        public var isWildcard: Bool
        public var text: String
    }

    public struct Schedule: Sendable, Equatable {
        public var seconds: Field?
        public var minutes: Field
        public var hours: Field
        public var days: Field
        public var months: Field
        public var weekdays: Field
        public var expression: String
    }

    static let macros: [String: String] = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *", "@weekly": "0 0 * * 0",
        "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *",
    ]
    static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    // Descriptions are English sentences, so the names are too (not the user's locale).
    static let weekdaySymbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let monthSymbols = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    public static func parse(_ text: String) throws -> Schedule {
        var expression = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let macro = macros[expression.lowercased()] { expression = macro }
        if expression.lowercased() == "@reboot" { throw ParseError(description: "@reboot runs once at startup; it has no schedule to show") }
        let fields = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 || fields.count == 6 else {
            throw ParseError(description: "Expected 5 fields (minute hour day month weekday), or 6 with seconds first; found \(fields.count)")
        }
        let offset = fields.count - 5
        return Schedule(
            seconds: offset == 1 ? try field(fields[0], name: "second", range: 0...59) : nil,
            minutes: try field(fields[offset], name: "minute", range: 0...59),
            hours: try field(fields[offset + 1], name: "hour", range: 0...23),
            days: try field(fields[offset + 2], name: "day of month", range: 1...31),
            months: try field(fields[offset + 3], name: "month", range: 1...12, names: monthNames, nameBase: 1),
            weekdays: try weekdayField(fields[offset + 4]),
            expression: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func weekdayField(_ text: String) throws -> Field {
        // 7 is also Sunday.
        var parsed = try field(text, name: "day of week", range: 0...7, names: dayNames, nameBase: 0)
        if parsed.values.contains(7) {
            parsed.values.remove(7)
            parsed.values.insert(0)
        }
        return parsed
    }

    static func field(_ text: String, name: String, range: ClosedRange<Int>, names: [String] = [], nameBase: Int = 0) throws -> Field {
        if text == "*" || text == "?" { return Field(values: Set(range), isWildcard: true, text: text) }
        var values = Set<Int>()
        func number(_ part: Substring) throws -> Int {
            if let value = Int(part) { return value }
            if let index = names.firstIndex(of: part.lowercased()) { return index + nameBase }
            throw ParseError(description: "“\(part)” isn't a valid \(name)")
        }
        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            guard !item.isEmpty else { throw ParseError(description: "Empty value in the \(name) field") }
            let pieces = item.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count <= 2 else { throw ParseError(description: "Too many “/” in the \(name) field") }
            var step = 1
            if pieces.count == 2 {
                guard let value = Int(pieces[1]), value > 0 else { throw ParseError(description: "“\(pieces[1])” isn't a valid step for \(name)") }
                step = value
            }
            let base = pieces[0]
            let bounds: ClosedRange<Int>
            if base == "*" || base == "?" {
                bounds = range
            } else if let dash = base.firstIndex(of: "-") {
                let low = try number(base[..<dash]), high = try number(base[base.index(after: dash)...])
                guard low <= high else { throw ParseError(description: "\(name.capitalized) range \(base) runs backwards") }
                bounds = low...high
            } else {
                let value = try number(base)
                bounds = pieces.count == 2 ? value...range.upperBound : value...value
            }
            guard range.contains(bounds.lowerBound), range.contains(bounds.upperBound) else {
                throw ParseError(description: "\(name.capitalized) must be \(range.lowerBound)–\(range.upperBound); got \(base)")
            }
            for value in stride(from: bounds.lowerBound, through: bounds.upperBound, by: step) { values.insert(value) }
        }
        return Field(values: values, isWildcard: false, text: text)
    }

    // MARK: Next runs

    /// The next `count` times the schedule fires after `date`, in `calendar`'s time zone.
    public static func nextRuns(of schedule: Schedule, after date: Date, count: Int, calendar: Calendar) -> [Date] {
        var results: [Date] = []
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        // Start at the next whole second (or minute without a seconds field).
        guard var cursor = calendar.date(from: components) else { return [] }
        cursor = cursor.addingTimeInterval(schedule.seconds == nil ? 60 - Double(components.second ?? 0) : 1)
        let limit = calendar.date(byAdding: .year, value: 8, to: date) ?? date
        while results.count < count, cursor < limit {
            components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: cursor)
            guard let month = components.month, let day = components.day, let hour = components.hour,
                  let minute = components.minute, let second = components.second, let weekday = components.weekday else { break }
            if !schedule.months.values.contains(month) {
                cursor = startOfNext(.month, from: cursor, calendar: calendar)
                continue
            }
            if !dayMatches(schedule, day: day, weekday: weekday - 1) {
                cursor = startOfNext(.day, from: cursor, calendar: calendar)
                continue
            }
            if !schedule.hours.values.contains(hour) {
                cursor = startOfNext(.hour, from: cursor, calendar: calendar)
                continue
            }
            if !schedule.minutes.values.contains(minute) {
                cursor = startOfNext(.minute, from: cursor, calendar: calendar)
                continue
            }
            if let seconds = schedule.seconds {
                if !seconds.values.contains(second) {
                    cursor = cursor.addingTimeInterval(1)
                    continue
                }
            } else if second != 0 {
                cursor = startOfNext(.minute, from: cursor, calendar: calendar)
                continue
            }
            results.append(cursor)
            cursor = cursor.addingTimeInterval(schedule.seconds == nil ? 60 : 1)
        }
        return results
    }

    /// Standard cron: when both day fields are restricted, either may match.
    static func dayMatches(_ schedule: Schedule, day: Int, weekday: Int) -> Bool {
        let dayOK = schedule.days.values.contains(day)
        let weekdayOK = schedule.weekdays.values.contains(weekday)
        if schedule.days.isWildcard || schedule.weekdays.isWildcard { return dayOK && weekdayOK }
        return dayOK || weekdayOK
    }

    static func startOfNext(_ unit: Calendar.Component, from date: Date, calendar: Calendar) -> Date {
        let interval = calendar.dateInterval(of: unit, for: date)
        return interval?.end ?? date.addingTimeInterval(60)
    }

    // MARK: Description

    public static func describe(_ schedule: Schedule) -> String {
        var parts: [String] = []
        parts.append(timeDescription(schedule))
        if let days = dayDescription(schedule) { parts.append(days) }
        if !schedule.months.isWildcard {
            parts.append("in " + list(schedule.months.values.sorted().map { monthSymbols[$0 - 1] }))
        }
        let sentence = parts.joined(separator: ", ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    static func timeDescription(_ schedule: Schedule) -> String {
        let minutes = schedule.minutes, hours = schedule.hours
        let secondsPrefix: String = {
            guard let seconds = schedule.seconds else { return "" }
            if seconds.isWildcard { return "every second, " }
            if let step = step(of: seconds, range: 0...59) { return "every \(step) seconds, " }
            return "at second \(list(seconds.values.sorted().map(String.init))), "
        }()
        // Single fixed times: "at 09:30".
        if minutes.values.count == 1, hours.values.count <= 4, !hours.isWildcard, step(of: hours, range: 0...23) == nil || hours.values.count == 1 {
            let minute = minutes.values.first!
            let times = hours.values.sorted().map { String(format: "%02d:%02d", $0, minute) }
            return secondsPrefix + "at " + list(times)
        }
        var text: String
        if minutes.isWildcard {
            text = "every minute"
        } else if let step = step(of: minutes, range: 0...59) {
            text = "every \(step) minutes"
        } else if minutes.values.count == 1 {
            text = "at minute \(minutes.values.first!)"
        } else {
            text = "at minutes \(list(minutes.values.sorted().map(String.init)))"
        }
        if hours.isWildcard {
            if !minutes.isWildcard, step(of: minutes, range: 0...59) == nil { text += " past every hour" }
        } else if let step = step(of: hours, range: 0...23) {
            text += minutes.values.count == 1 ? " past every \(step) hours" : ", every \(step) hours"
        } else if isContiguous(hours.values) && hours.values.count > 1 {
            let sorted = hours.values.sorted()
            text += String(format: ", between %02d:00 and %02d:59", sorted.first!, sorted.last!)
        } else {
            text += ", during hour " + list(hours.values.sorted().map { String(format: "%02d", $0) })
        }
        return secondsPrefix + text
    }

    static func dayDescription(_ schedule: Schedule) -> String? {
        let days = schedule.days, weekdays = schedule.weekdays
        let weekdayText: String? = {
            guard !weekdays.isWildcard else { return nil }
            let sorted = weekdays.values.sorted()
            let symbols = weekdaySymbols
            if sorted == [1, 2, 3, 4, 5] { return "Monday through Friday" }
            if sorted == [0, 6] { return "on Saturday and Sunday" }
            if isContiguous(weekdays.values), sorted.count > 2 { return "\(symbols[sorted.first!]) through \(symbols[sorted.last!])" }
            return "on " + list(sorted.map { symbols[$0] })
        }()
        let dayText: String? = {
            guard !days.isWildcard else { return nil }
            if let step = step(of: days, range: 1...31) { return "every \(step) days" }
            return "on day " + list(days.values.sorted().map(String.init)) + " of the month"
        }()
        switch (dayText, weekdayText) {
        case let (day?, weekday?): return "\(day) or \(weekday)"
        case let (day?, nil): return day
        case let (nil, weekday?): return weekday
        default: return nil
        }
    }

    /// `*/n` or `a-b/n` covering the whole range from its start.
    static func step(of field: Field, range: ClosedRange<Int>) -> Int? {
        guard !field.isWildcard, field.text.contains("/"), field.values.count > 1 else { return nil }
        let sorted = field.values.sorted()
        let gap = sorted[1] - sorted[0]
        guard sorted.first == range.lowerBound, zip(sorted, sorted.dropFirst()).allSatisfy({ $1 - $0 == gap }) else { return nil }
        return gap
    }

    static func isContiguous(_ values: Set<Int>) -> Bool {
        let sorted = values.sorted()
        return zip(sorted, sorted.dropFirst()).allSatisfy { $1 - $0 == 1 }
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }

    public static func looksLikeCron(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if macros[trimmed.lowercased()] != nil { return true }
        let fields = trimmed.split(separator: " ")
        guard fields.count == 5 || fields.count == 6,
              fields.allSatisfy({ $0.allSatisfy { "0123456789*/,-?".contains($0) || $0.isLetter } }),
              fields.contains(where: { $0.contains("*") || $0.contains("/") }) else { return false }
        return (try? parse(trimmed)) != nil
    }
}
