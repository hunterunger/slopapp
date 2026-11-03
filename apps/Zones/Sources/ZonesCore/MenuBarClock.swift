import Foundation

/// What the menu bar item shows.
public enum MenuBarDisplay: String, Codable, Sendable, CaseIterable, Identifiable {
    case iconOnly, iconAndTime, timeOnly
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .iconAndTime: "Icon and time"
        case .timeOnly: "Time only"
        }
    }

    public var showsTime: Bool { self != .iconOnly }
}

public enum MenuBarClock {
    /// A short tag for the menu bar: a renamed label up to 8 characters as typed ("Mum");
    /// otherwise initials of a multi-word name ("New York City" → "NYC", "Los Angeles" →
    /// "LA") or the first three letters ("London" → "LON"). Names of 3 or fewer characters
    /// stay as they are ("UTC").
    public static func tag(for place: Place) -> String {
        if let custom = place.customName?.trimmingCharacters(in: .whitespaces), !custom.isEmpty, custom.count <= 8 {
            return custom
        }
        let name = place.label
        if name.count <= 3 { return name.uppercased() }
        if place.kind == .fixedOffset { return name }
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { $0.first?.isLetter == true }
        if words.count >= 2 {
            return String(words.prefix(3).compactMap(\.first)).uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }

    /// "LON 5:20 PM"
    public static func title(for place: Place, at instant: Date, formatter: TimeFormatter) -> String {
        "\(tag(for: place)) \(formatter.time(instant, in: place.timeZone))"
    }
}
