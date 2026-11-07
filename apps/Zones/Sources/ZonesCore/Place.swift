import Foundation

/// One clock in the list: a city, a whole time zone, UTC, or a fixed UTC offset.
///
/// Places store the IANA identifier, never an offset, so daylight saving and rule changes
/// always come from the operating system's time zone database.
public struct Place: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case city, zone, utc, fixedOffset
    }

    public var id: UUID
    public var kind: Kind
    /// The name it was added with ("London", "Pacific Time", "UTC+5:30").
    public var name: String
    /// What the user renamed it to ("Mum", "Berlin office"), if anything.
    public var customName: String?
    /// "England, United Kingdom", "Time zone", "Fixed offset"...
    public var detail: String
    /// IANA identifier ("Europe/London"), "UTC", or empty for fixed offsets.
    public var timeZoneID: String
    /// Seconds east of UTC, only for `.fixedOffset`.
    public var fixedOffset: Int?
    /// This place's working hours, when they differ from the default in Settings.
    public var workingHours: WorkingHours?

    public init(id: UUID = UUID(), kind: Kind, name: String, customName: String? = nil,
                detail: String, timeZoneID: String, fixedOffset: Int? = nil, workingHours: WorkingHours? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.customName = customName
        self.detail = detail
        self.timeZoneID = timeZoneID
        self.fixedOffset = fixedOffset
        self.workingHours = workingHours
    }

    /// What the list shows: the user's name for it, or the name it was added with.
    public var label: String {
        if let customName, !customName.trimmingCharacters(in: .whitespaces).isEmpty { return customName }
        return name
    }

    public var timeZone: TimeZone {
        if kind == .fixedOffset, let fixedOffset, let zone = TimeZone(secondsFromGMT: fixedOffset) {
            return zone
        }
        return TimeZone(identifier: timeZoneID) ?? .gmt
    }

    /// Same clock under the same name (used to avoid offering a place that's already listed).
    public func isSameClock(as other: Place) -> Bool {
        kind == other.kind && name == other.name && timeZoneID == other.timeZoneID && fixedOffset == other.fixedOffset
    }

    // MARK: Factories

    public static func utc(id: UUID = UUID()) -> Place {
        Place(id: id, kind: .utc, name: "UTC", detail: "Coordinated Universal Time", timeZoneID: "UTC")
    }

    /// A fixed offset from UTC that never changes for daylight saving. `seconds` must be
    /// between −12 h and +14 h.
    public static func fixed(offset seconds: Int, id: UUID = UUID()) -> Place {
        Place(id: id, kind: .fixedOffset, name: OffsetText.utcLabel(seconds),
              detail: "Fixed offset, no daylight saving", timeZoneID: "", fixedOffset: seconds)
    }

    /// A whole time zone by identifier, named after its city ("America/New_York" → "New York").
    public static func zone(_ identifier: String, id: UUID = UUID()) -> Place {
        Place(id: id, kind: .zone, name: ZoneNames.cityName(forIdentifier: identifier),
              detail: "Time zone \(identifier)", timeZoneID: identifier)
    }
}

/// Names derived from time zone identifiers.
public enum ZoneNames {
    /// "America/Argentina/Buenos_Aires" → "Buenos Aires". "UTC" → "UTC".
    public static func cityName(forIdentifier identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }
}
