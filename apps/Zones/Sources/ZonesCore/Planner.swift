import Foundation

/// Bands of activity along a span of time for one place: the day strip under a row in the
/// timeline style, centred on the shown instant.
public struct DayStrip: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        /// 0...1 along the strip.
        public var start: Double
        public var end: Double
        public var activity: Activity
    }

    public var segments: [Segment]
    /// Where the place's clock passes midnight, 0...1 along the strip.
    public var midnights: [Double]

    /// Activity of `zone` from `from` to `to`, sampled every `resolution` seconds (15 min:
    /// fine enough for :30 and :45 zones and working hours on quarter hours).
    public static func make(zone: TimeZone, hours: WorkingHours, from: Date, to: Date,
                            resolution: TimeInterval = 900) -> DayStrip {
        let span = to.timeIntervalSince(from)
        guard span > 0 else { return DayStrip(segments: [], midnights: []) }
        var segments: [Segment] = []
        var midnights: [Double] = []
        // Sample at quarter-hour marks of UTC (every zone's quarter hours line up with them).
        let first = (from.timeIntervalSince1970 / resolution).rounded(.down) * resolution
        var t = first
        var previousDay: Int?
        while t < to.timeIntervalSince1970 {
            let instant = Date(timeIntervalSince1970: t)
            let clock = WallClock(instant, zone)
            let activity = Activity.at(minute: clock.minuteOfDay, weekday: clock.weekday, hours: hours)
            let start = max(0, (t - from.timeIntervalSince1970) / span)
            let end = min(1, (t + resolution - from.timeIntervalSince1970) / span)
            if let last = segments.last, last.activity == activity {
                segments[segments.count - 1].end = end
            } else {
                segments.append(Segment(start: start, end: end, activity: activity))
            }
            if let previousDay, previousDay != clock.day, start > 0 { midnights.append(start) }
            previousDay = clock.day
            t += resolution
        }
        return DayStrip(segments: segments, midnights: midnights)
    }
}

/// The meeting planner: one column per hour of a local day, one row per place.
public enum DayPlan {
    /// Starts of every hour of the local calendar day containing `date` (23, 24 or 25 of
    /// them on daylight saving days). Hours are real elapsed hours from local midnight.
    public static func hours(ofDayContaining date: Date, in local: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = local
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var result: [Date] = []
        var t = start
        while t < next {
            result.append(t)
            t = t.addingTimeInterval(3600)
        }
        return result
    }

    /// For each hour, whether every place is inside its working hours for the whole hour
    /// (checked at the start and each quarter, so :30 zones count only fully covered hours).
    public static func overlap(hours: [Date], places: [(zone: TimeZone, hours: WorkingHours)]) -> [Bool] {
        guard !places.isEmpty else { return hours.map { _ in false } }
        return hours.map { hour in
            places.allSatisfy { place in
                stride(from: 0.0, to: 3600, by: 900).allSatisfy { offset in
                    place.hours.contains(hour.addingTimeInterval(offset), in: place.zone)
                }
            }
        }
    }

    /// Runs of consecutive true values: [false, true, true, false, true] → [1..<3, 4..<5].
    public static func runs(_ flags: [Bool]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?
        for (index, flag) in flags.enumerated() {
            if flag, start == nil { start = index }
            if !flag, let begin = start { result.append(begin..<index); start = nil }
        }
        if let start { result.append(start..<flags.count) }
        return result
    }

    /// "Everyone is working 9:00 AM – 11:00 AM" / "… and 2:00 PM – 3:00 PM" / nil.
    public static func overlapText(hours: [Date], flags: [Bool], local: TimeZone, formatter: TimeFormatter) -> String? {
        let spans = runs(flags).map { run -> String in
            let from = formatter.time(hours[run.lowerBound], in: local)
            let to = formatter.time(hours[run.upperBound - 1].addingTimeInterval(3600), in: local)
            return "\(from) – \(to)"
        }
        guard !spans.isEmpty else { return nil }
        return spans.joined(separator: ", ")
    }

    /// The hour (index into `hours`) containing `instant`, if it's on that day.
    public static func index(of instant: Date, in hours: [Date]) -> Int? {
        guard let first = hours.first, instant >= first,
              instant < first.addingTimeInterval(TimeInterval(hours.count * 3600)) else { return nil }
        return Int(instant.timeIntervalSince(first) / 3600)
    }
}

/// A calendar event as an .ics file, for handing a chosen time to Calendar (or any calendar
/// app) without asking for calendar access.
public enum CalendarFile {
    public static func ics(start: Date, duration: TimeInterval, title: String, notes: String,
                           uid: String = UUID().uuidString, stamp: Date = Date()) -> String {
        let lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Slopapp//Zones//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(uid)@zones.slopapp.app",
            "DTSTAMP:\(utc(stamp))",
            "DTSTART:\(utc(start))",
            "DTEND:\(utc(start.addingTimeInterval(duration)))",
            "SUMMARY:\(escape(title))",
            "DESCRIPTION:\(escape(notes))",
            "END:VEVENT",
            "END:VCALENDAR",
        ]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// "20261103T170000Z"
    static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// RFC 5545 text escaping.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next line after a space, never splitting
    /// a UTF-8 character.
    static func fold(_ line: String) -> String {
        var result = ""
        var current = 0
        var limit = 75
        for character in line {
            let size = String(character).utf8.count
            if current + size > limit {
                result += "\r\n "
                current = 0
                limit = 74
            }
            result.append(character)
            current += size
        }
        return result
    }
}
