import Foundation
@testable import ZonesCore

/// Fixed-clock helpers: every test pins an instant and a locale.
enum T {
    static let enUS = Locale(identifier: "en_US")

    static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { fatalError("bad date \(iso)") }
        return date
    }

    static func zone(_ id: String) -> TimeZone {
        guard let zone = TimeZone(identifier: id) else { fatalError("unknown zone \(id)") }
        return zone
    }

    static func formatter(_ cycle: HourCycle = .twelve) -> TimeFormatter {
        TimeFormatter(locale: enUS, hourCycle: cycle)
    }

    static func city(_ name: String, _ zone: String) -> Place {
        Place(kind: .city, name: name, detail: "", timeZoneID: zone)
    }

    /// "HH:mm" wall time of `date` in `zone`.
    static func wall(_ date: Date, _ zone: String) -> String {
        let (hour, minute) = TimeMath.wallTime(of: date, in: T.zone(zone))
        return String(format: "%02d:%02d", hour, minute)
    }

    @MainActor
    static func model(now: String, local: String, places: [Place]? = nil,
                      preferences: Preferences? = nil) -> (ZonesModel, MemoryStorage, FixedClock) {
        let storage = MemoryStorage(places: places, preferences: preferences)
        let clock = FixedClock(now: date(now), timeZone: zone(local))
        let model = ZonesModel(storage: storage, clock: clock, locale: enUS)
        return (model, storage, clock)
    }
}
