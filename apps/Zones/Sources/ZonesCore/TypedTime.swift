import Foundation

/// A time of day someone typed: "3pm", "3:30 pm", "15:30", "1530", "9a", "noon", "15h30".
public struct TypedTime: Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Parses a time of day. Without am/pm the hour is read as 24-hour ("3" is 3:00 in the
    /// morning, "15" is 3 pm). Returns nil for anything it can't read.
    public init?(parsing input: String) {
        var text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: ".", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        if text.isEmpty { return nil }
        switch text {
        case "noon", "midday": self.init(hour: 12, minute: 0); return
        case "midnight": self.init(hour: 0, minute: 0); return
        default: break
        }

        var meridiem: Character?
        for suffix in ["am", "pm", "a", "p"] where text.hasSuffix(suffix) {
            meridiem = suffix.first
            text.removeLast(suffix.count)
            break
        }
        if text.hasSuffix("h") { text.removeLast() }

        var hour: Int
        var minute = 0
        let separators: Set<Character> = [":", "h"]
        if let index = text.firstIndex(where: { separators.contains($0) }) {
            let hourPart = text[..<index]
            let minutePart = text[text.index(after: index)...]
            guard let h = Int(hourPart), hourPart.count <= 2,
                  let m = Int(minutePart), minutePart.count == 2 else { return nil }
            hour = h
            minute = m
        } else {
            guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text) else { return nil }
            switch text.count {
            case 1, 2: hour = value
            case 3, 4: hour = value / 100; minute = value % 100
            default: return nil
            }
        }
        guard (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "a" {
                hour = hour == 12 ? 0 : hour
            } else {
                hour = hour == 12 ? 12 : hour + 12
            }
        }
        guard (0...23).contains(hour) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// Where a typed time lands.
    public struct Resolution: Equatable, Sendable {
        public var instant: Date
        /// The wall time didn't exist that day (clocks went forward); `instant` is the first
        /// valid time after it.
        public var skippedGap: Bool
        /// The wall time happened twice that day (clocks went back); `instant` is the first.
        public var wasAmbiguous: Bool
    }

    /// This time of day in `zone`, on the calendar day `reference` falls on there.
    public func resolve(in zone: TimeZone, onDayOf reference: Date) -> Resolution {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let candidate = calendar.date(from: components) ?? reference

        // Every instant that shows this wall time in the zone (0, 1 or 2 of them). DST
        // shifts are at most 2 h (usually 1 h, 30 min on Lord Howe), so look that far around.
        let matches = stride(from: -7200, through: 7200, by: 900).compactMap { delta -> Date? in
            let date = candidate.addingTimeInterval(TimeInterval(delta))
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            guard parts.year == components.year, parts.month == components.month, parts.day == components.day,
                  parts.hour == hour, parts.minute == minute else { return nil }
            return date
        }
        if let first = matches.min() {
            return Resolution(instant: first, skippedGap: false, wasAmbiguous: Set(matches).count > 1)
        }
        // Not a real time that day: move forward to the first valid instant after the gap.
        let earlier = candidate.addingTimeInterval(-7200)
        let gapEnd = zone.nextDaylightSavingTimeTransition(after: earlier) ?? candidate
        return Resolution(instant: gapEnd, skippedGap: true, wasAmbiguous: false)
    }
}
