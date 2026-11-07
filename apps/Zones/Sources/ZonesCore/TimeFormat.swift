import Foundation

/// 12/24-hour choice. `.system` follows the Mac's Language & Region settings.
public enum HourCycle: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, twelve, twentyFour
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .twelve: "12-hour"
        case .twentyFour: "24-hour"
        }
    }

    var timeTemplate: String {
        switch self {
        case .system: "jmm"
        case .twelve: "hmma"
        case .twentyFour: "HHmm"
        }
    }
}

/// Formats times and dates for a zone. DateFormatter is expensive to create, so formatters
/// are cached per (pattern, locale, zone).
public final class TimeFormatter: @unchecked Sendable {
    public let locale: Locale
    public let hourCycle: HourCycle
    private var cache: [String: DateFormatter] = [:]
    private let lock = NSLock()

    public init(locale: Locale = .autoupdatingCurrent, hourCycle: HourCycle = .system) {
        self.locale = locale
        self.hourCycle = hourCycle
    }

    /// "5:20 PM" or "17:20". Plain spaces (ICU uses a narrow no-break space before
    /// AM/PM, which some apps paste as a box).
    public func time(_ date: Date, in zone: TimeZone) -> String {
        formatter(template: hourCycle.timeTemplate, zone: zone).string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// "5:20" and "PM" apart, so the panel can set the day period small and raised. The
    /// period can come first in some languages ("午後3:00"); 24-hour times have none.
    public func timeParts(_ date: Date, in zone: TimeZone) -> TimeParts {
        let text = time(date, in: zone)
        let formatter = formatter(template: hourCycle.timeTemplate, zone: zone)
        for symbol in [formatter.amSymbol, formatter.pmSymbol] {
            guard let symbol, !symbol.isEmpty, let range = text.range(of: symbol) else { continue }
            var main = text
            main.removeSubrange(range)
            main = main.trimmingCharacters(in: .whitespaces)
            return TimeParts(main: main, period: symbol, periodFirst: range.lowerBound == text.startIndex)
        }
        return TimeParts(main: text, period: nil, periodFirst: false)
    }

    /// Whether times show AM/PM (the override, or the locale's own habit).
    public var usesDayPeriod: Bool {
        switch hourCycle {
        case .twelve: return true
        case .twentyFour: return false
        case .system:
            let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
            return pattern.contains("a") || pattern.contains("b") || pattern.contains("B")
        }
    }

    /// A planner cell: "9" + "AM", "09", "9:30" + "PM"; at midnight the weekday ("Wed"),
    /// or "12:30" + "Wed" in a half-hour zone, so day changes stand out.
    public func hourLabel(_ date: Date, in zone: TimeZone) -> TimeParts {
        let (hour, minute) = TimeMath.wallTime(of: date, in: zone)
        if hour == 0 {
            let day = weekday(date, in: zone)
            if minute == 0 { return TimeParts(main: day, period: nil, periodFirst: false) }
            let midnight = (usesDayPeriod ? "12" : "00") + String(format: ":%02d", minute)
            return TimeParts(main: midnight, period: day, periodFirst: false)
        }
        let minutes = minute == 0 ? "" : String(format: ":%02d", minute)
        guard usesDayPeriod else {
            return TimeParts(main: String(format: "%02d", hour) + minutes, period: nil, periodFirst: false)
        }
        let formatter = formatter(template: "h a", zone: zone)
        let symbol = hour < 12 ? formatter.amSymbol : formatter.pmSymbol
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return TimeParts(main: "\(twelve)" + minutes, period: symbol, periodFirst: false)
    }

    /// "Tue, Nov 3" (localized order).
    public func shortDate(_ date: Date, in zone: TimeZone) -> String {
        formatter(template: "EEEMMMd", zone: zone).string(from: date)
    }

    /// "Tue" (abbreviated weekday).
    public func weekday(_ date: Date, in zone: TimeZone) -> String {
        formatter(template: "EEE", zone: zone).string(from: date)
    }

    /// "Tuesday, November 3" for VoiceOver.
    public func longDate(_ date: Date, in zone: TimeZone) -> String {
        formatter(template: "EEEEMMMMd", zone: zone).string(from: date)
    }

    /// ISO 8601 with the zone's offset: "2026-11-03T11:00-06:00".
    public func iso8601(_ date: Date, in zone: TimeZone) -> String {
        let formatter = cached(key: "iso|\(zone.identifier)|\(zone.secondsFromGMT())") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            return formatter
        }
        return formatter.string(from: date) + OffsetText.iso(zone.secondsFromGMT(for: date))
    }

    private func formatter(template: String, zone: TimeZone) -> DateFormatter {
        cached(key: "\(template)|\(zone.identifier)|\(zone.secondsFromGMT())") {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = zone
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
            return formatter
        }
    }

    private func cached(key: String, make: () -> DateFormatter) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let formatter = cache[key] { return formatter }
        let formatter = make()
        cache[key] = formatter
        return formatter
    }
}

/// A time split for display: "5:20" + "PM".
public struct TimeParts: Equatable, Sendable {
    public var main: String
    public var period: String?
    public var periodFirst: Bool

    public init(main: String, period: String?, periodFirst: Bool) {
        self.main = main
        self.period = period
        self.periodFirst = periodFirst
    }
}
