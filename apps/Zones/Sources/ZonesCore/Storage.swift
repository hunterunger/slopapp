import Foundation

/// Saved settings. Stored as one JSON value next to the place list.
public struct Preferences: Codable, Equatable, Sendable {
    public var showLocalTime = true
    public var hourCycle: HourCycle = .system
    public var copyFormat: CopyFormat = .list
    public var menuBarDisplay: MenuBarDisplay = .iconOnly
    /// The places whose times the menu bar shows, in order; `ClockRow.localID` for local
    /// time. Empty means local time.
    public var menuBarPlaceIDs: [UUID] = []
    /// Working hours for local time and every place without its own.
    public var defaultWorkingHours: WorkingHours = .standard
    /// How rows look in the panel.
    public var rowStyle: RowStyle = .standard

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case showLocalTime, hourCycle, copyFormat, menuBarDisplay, menuBarPlaceIDs, defaultWorkingHours, rowStyle
        /// Before several menu bar clocks (0.2): one place.
        case menuBarPlaceID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showLocalTime, forKey: .showLocalTime)
        try container.encode(hourCycle, forKey: .hourCycle)
        try container.encode(copyFormat, forKey: .copyFormat)
        try container.encode(menuBarDisplay, forKey: .menuBarDisplay)
        try container.encode(menuBarPlaceIDs, forKey: .menuBarPlaceIDs)
        try container.encode(defaultWorkingHours, forKey: .defaultWorkingHours)
        try container.encode(rowStyle, forKey: .rowStyle)
    }

    public init(from decoder: Decoder) throws {
        // Tolerate missing keys so older saves keep working as settings are added.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        showLocalTime = try container.decodeIfPresent(Bool.self, forKey: .showLocalTime) ?? defaults.showLocalTime
        hourCycle = (try? container.decodeIfPresent(HourCycle.self, forKey: .hourCycle)) ?? defaults.hourCycle
        copyFormat = (try? container.decodeIfPresent(CopyFormat.self, forKey: .copyFormat)) ?? defaults.copyFormat
        menuBarDisplay = (try? container.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay)) ?? defaults.menuBarDisplay
        if let ids = try? container.decodeIfPresent([UUID].self, forKey: .menuBarPlaceIDs) {
            menuBarPlaceIDs = ids
        } else if let id = try? container.decodeIfPresent(UUID.self, forKey: .menuBarPlaceID) {
            menuBarPlaceIDs = [id]
        }
        defaultWorkingHours = (try? container.decodeIfPresent(WorkingHours.self, forKey: .defaultWorkingHours)) ?? defaults.defaultWorkingHours
        rowStyle = (try? container.decodeIfPresent(RowStyle.self, forKey: .rowStyle)) ?? defaults.rowStyle
    }
}

/// How the panel draws each place.
public enum RowStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Name and offset on the left, a large time on the right.
    case standard
    /// One line per place, for long lists.
    case compact
    /// Standard plus a strip of each place's day (working hours, night) under the row.
    case timeline

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .compact: "Compact"
        case .timeline: "Timeline"
        }
    }
}

/// Where places and preferences are saved. `UserDefaults` in the app, in-memory in tests.
public protocol ZonesStorage: AnyObject {
    func loadPlaces() -> [Place]?
    func savePlaces(_ places: [Place])
    func loadPreferences() -> Preferences?
    func savePreferences(_ preferences: Preferences)
}

public final class UserDefaultsStorage: ZonesStorage {
    private let defaults: UserDefaults
    static let placesKey = "places"
    static let preferencesKey = "preferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadPlaces() -> [Place]? {
        guard let data = defaults.data(forKey: Self.placesKey) else { return nil }
        return try? JSONDecoder().decode([Place].self, from: data)
    }

    public func savePlaces(_ places: [Place]) {
        if let data = try? JSONEncoder().encode(places) { defaults.set(data, forKey: Self.placesKey) }
    }

    public func loadPreferences() -> Preferences? {
        guard let data = defaults.data(forKey: Self.preferencesKey) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: data)
    }

    public func savePreferences(_ preferences: Preferences) {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferencesKey) }
    }
}

public final class MemoryStorage: ZonesStorage {
    public var places: [Place]?
    public var preferences: Preferences?
    public private(set) var saveCount = 0

    public init(places: [Place]? = nil, preferences: Preferences? = nil) {
        self.places = places
        self.preferences = preferences
    }

    public func loadPlaces() -> [Place]? { places }
    public func savePlaces(_ places: [Place]) { self.places = places; saveCount += 1 }
    public func loadPreferences() -> Preferences? { preferences }
    public func savePreferences(_ preferences: Preferences) { self.preferences = preferences; saveCount += 1 }
}

/// The current time and the Mac's time zone. Fixed in tests.
public protocol SystemClock: AnyObject {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

public final class LiveClock: SystemClock {
    /// `ZONES_NOW=2026-03-15T15:00:00Z` pins "now" (for screenshots and tests); time doesn't move.
    private let pinned: Date?
    /// `ZONES_TIMEZONE=Europe/Berlin` overrides the local time zone.
    private let zoneOverride: TimeZone?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        pinned = environment["ZONES_NOW"].flatMap { ISO8601DateFormatter().date(from: $0) }
        zoneOverride = environment["ZONES_TIMEZONE"].flatMap(TimeZone.init(identifier:))
    }

    public var now: Date { pinned ?? Date() }

    public var timeZone: TimeZone {
        if let zoneOverride { return zoneOverride }
        NSTimeZone.resetSystemTimeZone()
        return TimeZone.current
    }
}

public final class FixedClock: SystemClock {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}
