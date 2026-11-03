import Foundation

/// Everything one row in the panel shows, computed for one instant.
public struct ClockRow: Identifiable, Equatable, Sendable {
    /// The place's id, or `ClockRow.localID` for the local time row.
    public var id: UUID
    public var label: String
    public var isLocal: Bool
    public var timeZone: TimeZone
    /// "5:20 PM"
    public var time: String
    /// −1 yesterday, 0 today, +1 tomorrow (relative to the local date at the same instant).
    public var dayDifference: Int
    /// "Tomorrow · +7 h", "Today · Same time", "Local time".
    public var subtitle: String
    /// "Clocks go back 1 h on Sun", within a week of a daylight saving change.
    public var transitionNote: String?
    public var phase: DayPhase
    /// Seconds ahead of local time.
    public var offset: Int
    /// One VoiceOver sentence: "London, 5:20 PM, tomorrow, 7 hours ahead, evening".
    public var accessibilityLabel: String

    /// Stable id of the local time row.
    public static let localID = UUID(uuidString: "00000000-0000-0000-0000-00000000001C")!
}

public enum ClockRows {
    /// Rows for every place at `instant`, the local row first when `showLocal`.
    public static func make(places: [Place], local: TimeZone, showLocal: Bool, at instant: Date,
                            formatter: TimeFormatter) -> [ClockRow] {
        var rows: [ClockRow] = []
        if showLocal {
            rows.append(row(id: ClockRow.localID, label: localName(for: local), zone: local, isLocal: true,
                            local: local, instant: instant, formatter: formatter))
        }
        for place in places {
            rows.append(row(id: place.id, label: place.label, zone: place.timeZone, isLocal: false,
                            local: local, instant: instant, formatter: formatter))
        }
        return rows
    }

    /// The local row's name: the city part of the system zone ("America/Chicago" → "Chicago").
    public static func localName(for zone: TimeZone) -> String {
        if zone.identifier == "UTC" || zone.identifier == "GMT" { return "UTC" }
        return ZoneNames.cityName(forIdentifier: zone.identifier)
    }

    static func row(id: UUID, label: String, zone: TimeZone, isLocal: Bool, local: TimeZone,
                    instant: Date, formatter: TimeFormatter) -> ClockRow {
        let offset = TimeMath.offset(of: zone, from: local, at: instant)
        let days = TimeMath.dayDifference(of: zone, from: local, at: instant)
        let time = formatter.time(instant, in: zone)
        let phase = DayPhase(hour: TimeMath.wallTime(of: instant, in: zone).hour)
        let dayText = dayLabel(days, instant: instant, zone: zone, formatter: formatter)
        let subtitle = isLocal ? "Local time" : "\(dayText) · \(OffsetText.relative(offset))"
        let note = TimeMath.upcomingTransition(in: zone, after: instant).map {
            transitionText($0, zone: zone, formatter: formatter)
        }
        var spoken = [label, time]
        if !isLocal {
            spoken.append(dayText.lowercased())
            spoken.append(OffsetText.spoken(offset))
        } else {
            spoken.append("local time")
        }
        spoken.append(phase.spokenName)
        if let note { spoken.append(note) }
        return ClockRow(id: id, label: label, isLocal: isLocal, timeZone: zone, time: time,
                        dayDifference: days, subtitle: subtitle, transitionNote: note, phase: phase,
                        offset: offset, accessibilityLabel: spoken.joined(separator: ", "))
    }

    /// "Yesterday", "Today", "Tomorrow", or the weekday two days away.
    public static func dayLabel(_ days: Int, instant: Date, zone: TimeZone, formatter: TimeFormatter) -> String {
        switch days {
        case -1: "Yesterday"
        case 0: "Today"
        case 1: "Tomorrow"
        default: formatter.weekday(instant, in: zone)
        }
    }

    /// "Clocks go forward 1 h on Sun", "Clocks go back 30 min on Sun".
    public static func transitionText(_ transition: TimeMath.Transition, zone: TimeZone,
                                      formatter: TimeFormatter) -> String {
        let direction = transition.change > 0 ? "forward" : "back"
        let day = formatter.weekday(transition.date, in: zone)
        return "Clocks go \(direction) \(OffsetText.duration(transition.change)) on \(day)"
    }
}
