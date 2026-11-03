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
