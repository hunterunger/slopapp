import Foundation

/// Time zone arithmetic. Every function takes the instant it's about: offsets are always
/// computed for that instant (the scrubbed time, not "now"), so daylight saving is right
/// in the weeks when regions change on different dates.
public enum TimeMath {
    /// Seconds `zone` is ahead of `reference` at `instant` (negative when behind).
    public static func offset(of zone: TimeZone, from reference: TimeZone, at instant: Date) -> Int {
        zone.secondsFromGMT(for: instant) - reference.secondsFromGMT(for: instant)
    }

    /// Calendar days between the reference zone's date and `zone`'s date at `instant`:
    /// −1 yesterday, 0 same day, +1 tomorrow (can reach ±2 across the date line).
    public static func dayDifference(of zone: TimeZone, from reference: TimeZone, at instant: Date) -> Int {
        let there = dayNumber(of: instant, in: zone)
        let here = dayNumber(of: instant, in: reference)
        return there - here
    }

    /// Days since 1970-01-01 of the calendar date `instant` falls on in `zone`.
    static func dayNumber(of instant: Date, in zone: TimeZone) -> Int {
        let local = instant.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: instant))
        return Int((local / 86_400).rounded(.down))
    }

    /// Wall-clock hour and minute at `instant` in `zone`.
    public static func wallTime(of instant: Date, in zone: TimeZone) -> (hour: Int, minute: Int) {
        let local = Int((instant.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: instant))).rounded(.down))
        let secondsOfDay = ((local % 86_400) + 86_400) % 86_400
        return (secondsOfDay / 3600, (secondsOfDay % 3600) / 60)
    }

    /// The next daylight saving change in `zone` within `window` after `instant`, if any.
    public static func upcomingTransition(in zone: TimeZone, after instant: Date,
                                          within window: TimeInterval = 7 * 86_400) -> Transition? {
        guard let date = zone.nextDaylightSavingTimeTransition(after: instant),
              date.timeIntervalSince(instant) <= window else { return nil }
        let before = zone.secondsFromGMT(for: date.addingTimeInterval(-1))
        let after = zone.secondsFromGMT(for: date.addingTimeInterval(1))
        guard before != after else { return nil }
        return Transition(date: date, change: after - before)
    }

    public struct Transition: Equatable, Sendable {
        /// The instant the clocks change.
        public var date: Date
        /// Seconds the clocks move: +3600 forward, −3600 back (±1800 on Lord Howe Island).
        public var change: Int
    }
}

/// Time of day at a place, for the sun/moon cue.
public enum DayPhase: String, Sendable, CaseIterable {
    case night, morning, day, evening

    /// Hour bands: night 21:00–5:59, morning 6:00–7:59, day 8:00–17:59, evening 18:00–20:59.
    public init(hour: Int) {
        switch hour {
        case 6..<8: self = .morning
        case 8..<18: self = .day
        case 18..<21: self = .evening
        default: self = .night
        }
    }

    public var spokenName: String {
        switch self {
        case .night: "night"
        case .morning: "morning"
        case .day: "daytime"
        case .evening: "evening"
        }
    }
}

/// Text for offsets and deltas. Uses a real minus sign (U+2212).
public enum OffsetText {
    public static let minus = "\u{2212}"

    /// "+7 h", "+5 h 30 min", "−3 h 30 min", "+45 min", "+26 h", "Same time".
    public static func relative(_ seconds: Int) -> String {
        if seconds == 0 { return "Same time" }
        return sign(seconds) + duration(abs(seconds), usingDays: false)
    }

    /// "3 h 15 min", "45 min", "2 h", "1 d 3 h" (unsigned).
    public static func duration(_ seconds: Int, usingDays: Bool = true) -> String {
        let totalMinutes = abs(seconds) / 60
        let days = usingDays ? totalMinutes / 1440 : 0
        let hours = (totalMinutes - days * 1440) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) d") }
        if hours > 0 { parts.append("\(hours) h") }
        if minutes > 0 { parts.append("\(minutes) min") }
        return parts.isEmpty ? "0 min" : parts.joined(separator: " ")
    }

    /// VoiceOver: "7 hours ahead", "3 hours 30 minutes behind", "same time".
    public static func spoken(_ seconds: Int) -> String {
        if seconds == 0 { return "same time" }
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        return parts.joined(separator: " ") + (seconds > 0 ? " ahead" : " behind")
    }

    /// "UTC", "UTC+1", "UTC+5:30", "UTC−3:30", "UTC+12:45".
    public static func utcLabel(_ seconds: Int) -> String {
        if seconds == 0 { return "UTC" }
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        let body = rest == 0 ? "\(hours)" : String(format: "%d:%02d", hours, rest)
        return "UTC" + sign(seconds) + body
    }

    /// "+05:30" style for ISO 8601.
    public static func iso(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return (seconds < 0 ? "-" : "+") + String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func sign(_ seconds: Int) -> String { seconds < 0 ? minus : "+" }
}

public enum ZoneAbbreviation {
    /// The zone's letter abbreviation at `instant` ("PST", "CEST") when it has a real one;
    /// otherwise the UTC offset ("UTC+5:30"), because "GMT+5:30" style names aren't
    /// abbreviations anyone uses.
    public static func display(for zone: TimeZone, at instant: Date) -> String {
        let offset = zone.secondsFromGMT(for: instant)
        if zone.identifier == "UTC" || zone.identifier == "GMT" { return "UTC" }
        if let pair = known[zone.identifier] {
            return zone.isDaylightSavingTime(for: instant) ? pair.daylight : pair.standard
        }
        if let abbreviation = zone.abbreviation(for: instant), isLetters(abbreviation) {
            return abbreviation
        }
        return OffsetText.utcLabel(offset)
    }

    /// Widely recognised abbreviations macOS doesn't provide in English (it only has US
    /// ones and says "GMT+9" elsewhere). Deliberately small: zones whose letters are
    /// ambiguous (China's CST, Israel's IST) keep the UTC offset.
    static let known: [String: (standard: String, daylight: String)] = {
        var table: [String: (String, String)] = [
            "Europe/London": ("GMT", "BST"), "Europe/Dublin": ("GMT", "IST"),
            "Europe/Lisbon": ("WET", "WEST"), "Atlantic/Canary": ("WET", "WEST"),
            "Europe/Moscow": ("MSK", "MSK"), "Asia/Tokyo": ("JST", "JST"), "Asia/Seoul": ("KST", "KST"),
            "Asia/Kolkata": ("IST", "IST"), "Asia/Calcutta": ("IST", "IST"),
            "Asia/Hong_Kong": ("HKT", "HKT"), "Asia/Singapore": ("SGT", "SGT"),
            "Asia/Jakarta": ("WIB", "WIB"), "Asia/Manila": ("PHT", "PHT"), "Asia/Karachi": ("PKT", "PKT"),
            "Africa/Johannesburg": ("SAST", "SAST"), "Africa/Nairobi": ("EAT", "EAT"),
            "Africa/Lagos": ("WAT", "WAT"),
            "Australia/Sydney": ("AEST", "AEDT"), "Australia/Melbourne": ("AEST", "AEDT"),
            "Australia/Hobart": ("AEST", "AEDT"), "Australia/Canberra": ("AEST", "AEDT"),
            "Australia/Brisbane": ("AEST", "AEST"), "Australia/Adelaide": ("ACST", "ACDT"),
            "Australia/Darwin": ("ACST", "ACST"), "Australia/Perth": ("AWST", "AWST"),
            "Pacific/Auckland": ("NZST", "NZDT"), "Pacific/Honolulu": ("HST", "HST"),
        ]
        let central = ["Paris", "Berlin", "Madrid", "Rome", "Amsterdam", "Brussels", "Vienna", "Zurich",
                       "Stockholm", "Oslo", "Copenhagen", "Prague", "Warsaw", "Budapest", "Belgrade",
                       "Bratislava", "Ljubljana", "Zagreb", "Luxembourg", "Monaco", "Malta", "Andorra",
                       "Sarajevo", "Skopje", "Tirane", "Podgorica", "Vaduz", "San_Marino", "Vatican",
                       "Gibraltar", "Busingen"]
        let eastern = ["Athens", "Helsinki", "Kyiv", "Kiev", "Bucharest", "Sofia", "Riga", "Tallinn",
                       "Vilnius", "Chisinau", "Mariehamn", "Uzhgorod", "Zaporozhye"]
        for city in central { table["Europe/\(city)"] = ("CET", "CEST") }
        for city in eastern { table["Europe/\(city)"] = ("EET", "EEST") }
        return table.mapValues { (standard: $0.0, daylight: $0.1) }
    }()

    static func isLetters(_ text: String) -> Bool {
        (2...5).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isUppercase }
            && text != "GMT" && text != "UTC"
    }
}
