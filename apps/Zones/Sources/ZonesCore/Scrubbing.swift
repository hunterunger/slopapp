import Foundation

/// Moving the shown time away from "now". All steps are in real (UTC) instants, so stepping
/// across a daylight saving gap never lands on a time that doesn't exist or gets stuck.
public enum Scrubbing {
    public static let quarterHour = 900
    public static let hour = 3600
    /// Minutes of time per point of horizontal drag.
    public static let secondsPerPoint: Double = 180

    /// Moves `count` marks of `size` seconds (15 min or 1 h), aligned to the local clock.
    /// From 10:07, +1 quarter is 10:15 and −1 quarter is 10:00; from 10:00 they are 10:15
    /// and 9:45. Marks follow local wall time, so a +5:30 zone steps to :00/:15/:30/:45.
    /// The move itself is real elapsed time, so the repeated hour when clocks go back is
    /// stepped through and the missing hour when they go forward is skipped, never stuck.
    public static func step(from base: Date, marks count: Int, of size: Int, local: TimeZone) -> Date {
        guard count != 0, size > 0 else { return base }
        let seconds = Int(base.timeIntervalSince1970.rounded(.down))
        let wall = seconds + local.secondsFromGMT(for: base)
        let remainder = ((wall % size) + size) % size
        let delta: Int
        if count > 0 {
            delta = (remainder == 0 ? size : size - remainder) + (count - 1) * size
        } else {
            delta = -(remainder == 0 ? size : remainder) + (count + 1) * size
        }
        return Date(timeIntervalSince1970: TimeInterval(seconds + delta))
    }

    /// Same wall-clock time `days` days later in `local` (keeps 9:00 at 9:00 across DST).
    public static func step(from base: Date, days: Int, local: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = local
        return calendar.date(byAdding: .day, value: days, to: base) ?? base.addingTimeInterval(TimeInterval(days * 86_400))
    }

    /// The instant for a horizontal drag of `points` from `start`, snapped to quarter hours
    /// of local time. Dragging right moves later.
    public static func drag(from start: Date, points: Double, local: TimeZone) -> Date {
        let raw = start.addingTimeInterval(points * secondsPerPoint)
        return snap(raw, to: quarterHour, local: local)
    }

    /// Nearest `size`-second mark of local wall time.
    public static func snap(_ date: Date, to size: Int, local: TimeZone) -> Date {
        let offset = local.secondsFromGMT(for: date)
        let wall = date.timeIntervalSince1970 + Double(offset)
        let snapped = (wall / Double(size)).rounded() * Double(size)
        return Date(timeIntervalSince1970: snapped - Double(offset))
    }

    /// "+3 h 15 min", "−45 min" under a day; "+1 day 2 h", "+10 days" beyond (minutes
    /// dropped: the date line and the rows give the exact time). Rounded to whole minutes.
    public static func deltaText(from now: Date, to instant: Date) -> String {
        let seconds = Int((instant.timeIntervalSince(now) / 60).rounded()) * 60
        if seconds == 0 { return "Now" }
        let minutes = abs(seconds) / 60
        guard minutes >= 1440 else { return OffsetText.sign(seconds) + OffsetText.duration(seconds) }
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        var text = days == 1 ? "1 day" : "\(days) days"
        if hours > 0 { text += " \(hours) h" }
        return OffsetText.sign(seconds) + text
    }

    /// VoiceOver: "3 hours 15 minutes later", "10 days later", "1 day 2 hours earlier".
    public static func spokenDelta(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let rest = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if rest > 0, days == 0 { parts.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        if parts.isEmpty { return "now" }
        return parts.joined(separator: " ") + (seconds > 0 ? " later" : " earlier")
    }
}
