import Foundation

/// Unix timestamps ⇄ dates. Guesses seconds, milliseconds, microseconds or nanoseconds by
/// magnitude, and parses common date formats (ISO 8601, RFC 2822, "2024-11-03 10:00").
public enum Timestamps {
    public enum Unit: String, CaseIterable, Sendable, Identifiable {
        case automatic, seconds, milliseconds, microseconds, nanoseconds

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .automatic: "Automatic"
            case .seconds: "Seconds"
            case .milliseconds: "Milliseconds"
            case .microseconds: "Microseconds"
            case .nanoseconds: "Nanoseconds"
            }
        }

        var perSecond: Double {
            switch self {
            case .automatic, .seconds: 1
            case .milliseconds: 1e3
            case .microseconds: 1e6
            case .nanoseconds: 1e9
            }
        }
    }

    public enum Input: Sendable, Equatable {
        case number(Unit)
        case text(format: String)
    }

    public struct Parsed: Sendable, Equatable {
        public var date: Date
        public var input: Input
    }

    public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case unrecognized

        public var description: String {
            switch self {
            case .empty: "Type a Unix timestamp like 1730592000, or a date like 2024-11-03 10:00."
            case .unrecognized: "This isn't a timestamp or a date I recognize. Try 1730592000, 2024-11-03T10:00:00Z or Sun, 03 Nov 2024 10:00:00 +0000."
            }
        }
    }

    /// Picks the unit by size: seconds until year 5138, then ms, µs, ns.
    public static func guessUnit(_ magnitude: Double) -> Unit {
        switch abs(magnitude) {
        case ..<1e11: .seconds
        case ..<1e14: .milliseconds
        case ..<1e17: .microseconds
        default: .nanoseconds
        }
    }

    public static func parse(_ text: String, unit: Unit = .automatic, timeZone: TimeZone = .current, now: Date = Date()) throws -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }
        if trimmed.lowercased() == "now" { return Parsed(date: now, input: .text(format: "Now")) }
        if isNumeric(trimmed), let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) {
            let value = NSDecimalNumber(decimal: decimal).doubleValue
            let used = unit == .automatic ? guessUnit(value) : unit
            // Divide in Decimal so 19-digit nanosecond values keep their precision.
            let seconds = NSDecimalNumber(decimal: decimal / Decimal(used.perSecond)).doubleValue
            return Parsed(date: Date(timeIntervalSince1970: seconds), input: .number(used))
        }
        if let (date, format) = parseDate(trimmed, timeZone: timeZone) {
            return Parsed(date: date, input: .text(format: format))
        }
        throw ParseError.unrecognized
    }

    static func isNumeric(_ text: String) -> Bool {
        var body = Substring(text)
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isASCIIDigit) } && (parts.count == 1 || !parts[1].isEmpty)
    }

    static func parseDate(_ text: String, timeZone: TimeZone) -> (Date, String)? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return (date, "ISO 8601") }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return (date, "ISO 8601") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        // RFC 2822 (email, HTTP headers) and friends.
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return (date, "RFC 2822") }
        }
        // Local times without a zone, the way people type them.
        let local = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd",
        ]
        for format in local {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return (date, "Local time") }
        }
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return (date, "Date with offset") }
        }
        return nil
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// Every useful representation of `date`.
    public static func rows(for date: Date, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> [Row] {
        let utc = TimeZone(identifier: "UTC")!
        let fractional = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) != 0
        let local = DateFormatter()
        local.locale = locale
        local.timeZone = timeZone
        local.dateStyle = .full
        local.timeStyle = .long

        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.timeZone = utc
        utcFormatter.dateFormat = fractional ? "yyyy-MM-dd HH:mm:ss.SSS 'UTC'" : "yyyy-MM-dd HH:mm:ss 'UTC'"

        let rfc2822 = DateFormatter()
        rfc2822.locale = Locale(identifier: "en_US_POSIX")
        rfc2822.timeZone = utc
        rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let week = calendar.component(.weekOfYear, from: date)

        let seconds = date.timeIntervalSince1970
        return [
            Row("Local", local.string(from: date)),
            Row("UTC", utcFormatter.string(from: date)),
            Row("ISO 8601", isoString(date, timeZone: utc, fractional: fractional)),
            Row("ISO 8601 (local)", isoString(date, timeZone: timeZone, fractional: fractional)),
            Row("RFC 2822", rfc2822.string(from: date)),
            Row("Relative", relative(date, now: now, locale: locale)),
            Row("Unix seconds", formatNumber(seconds, fractionDigits: fractional ? 3 : 0)),
            Row("Unix milliseconds", formatNumber((seconds * 1000).rounded(), fractionDigits: 0)),
            Row("Day and week", "Day \(dayOfYear), ISO week \(week)"),
        ]
    }

    public static func isoString(_ date: Date, timeZone: TimeZone, fractional: Bool) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func relative(_ date: Date, now: Date, locale: Locale = .current) -> String {
        if abs(date.timeIntervalSince(now)) < 1 { return "Now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func formatNumber(_ value: Double, fractionDigits: Int) -> String {
        if fractionDigits == 0, abs(value) < 9e15 { return String(Int64(value)) }
        return String(format: "%.\(fractionDigits)f", value)
    }

    /// True for integers (or decimals) that are plausibly a Unix time between 1990 and
    /// 2100, in seconds (9–10 digits) or milliseconds (13 digits).
    public static func isPlausibleTimestamp(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
              let whole = Int64(parts[0]) else { return false }
        let lower: Int64 = 631_152_000 // 1990-01-01
        let upper: Int64 = 4_102_444_800 // 2100-01-01
        switch parts[0].count {
        case 9, 10: return (lower...upper).contains(whole)
        case 13: return (lower * 1000...upper * 1000).contains(whole)
        default: return false
        }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
