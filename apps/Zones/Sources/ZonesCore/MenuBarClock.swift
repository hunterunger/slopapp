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

    /// "LON 5:20 PM", with a one-digit hour padded by a figure space (as wide as a digit in
    /// the menu bar's monospaced-digit font), so the item doesn't grow at 10 o'clock.
    public static func title(for place: Place, at instant: Date, formatter: TimeFormatter) -> String {
        "\(tag(for: place)) \(padHour(formatter.time(instant, in: place.timeZone)))"
    }

    /// The same title at the widest time it can show: a two-digit hour, with each day period
    /// in turn (their widths differ by a fraction of a point). The menu bar item is sized to
    /// the widest of these, so it never changes width as the time ticks.
    public static func widestTitles(for place: Place, formatter: TimeFormatter) -> [String] {
        // 10:00 and 22:00 UTC: two-digit hours on either side of noon, in any hour cycle.
        [36_000, 79_200].map { seconds in
            "\(tag(for: place)) \(padHour(formatter.time(Date(timeIntervalSince1970: TimeInterval(seconds)), in: .gmt)))"
        }
    }

    /// U+2007 FIGURE SPACE: the width of one digit.
    public static let figureSpace = "\u{2007}"

    /// "9:05 PM" → "\u{2007}9:05 PM", "午後3:00" → "午後\u{2007}3:00"; two-digit hours stay.
    static func padHour(_ time: String) -> String {
        guard let first = time.firstIndex(where: \.isNumber) else { return time }
        let run = time[first...].prefix(while: \.isNumber)
        guard run.count == 1 else { return time }
        var padded = time
        padded.insert(contentsOf: figureSpace, at: first)
        return padded
    }
}
