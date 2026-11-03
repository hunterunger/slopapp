import Foundation

/// How "Copy Times" writes the list. Always absolute dates: the reader isn't here, so
/// "Tomorrow" would be wrong by the time they read it.
public enum CopyFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    /// One line per place: "London: Tue, Nov 3, 5:00 PM UTC", "Chicago: Tue, Nov 3, 11:00 AM CST"
    case list
    /// "11:00 AM Chicago · 5:00 PM London · 2:00 AM Tokyo (Wed)"
    case singleLine
    /// One line per place: "London: 2026-11-03T17:00+00:00"
    case iso8601

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .list: "List"
        case .singleLine: "Single line"
        case .iso8601: "ISO 8601"
        }
    }
}

public enum TimesText {
    public struct Entry: Sendable {
        public var label: String
        public var zone: TimeZone

        public init(label: String, zone: TimeZone) {
            self.label = label
            self.zone = zone
        }
    }

    /// Plain text for `entries` at `instant`.
    public static func make(_ entries: [Entry], at instant: Date, format: CopyFormat,
                            formatter: TimeFormatter) -> String {
        switch format {
        case .list:
            return entries.map { entry in
                let date = formatter.shortDate(instant, in: entry.zone)
                let time = formatter.time(instant, in: entry.zone)
                let zoneName = ZoneAbbreviation.display(for: entry.zone, at: instant)
                return "\(entry.label): \(date), \(time) \(zoneName)"
            }.joined(separator: "\n")
        case .singleLine:
            guard let first = entries.first else { return "" }
            let firstDay = TimeMath.dayNumber(of: instant, in: first.zone)
            return entries.map { entry in
                var text = "\(formatter.time(instant, in: entry.zone)) \(entry.label)"
                if TimeMath.dayNumber(of: instant, in: entry.zone) != firstDay {
                    text += " (\(formatter.weekday(instant, in: entry.zone)))"
                }
                return text
            }.joined(separator: " · ")
        case .iso8601:
            return entries.map { "\($0.label): \(formatter.iso8601(instant, in: $0.zone))" }
                .joined(separator: "\n")
        }
    }
}
