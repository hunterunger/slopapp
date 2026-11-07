import Foundation

/// A time zone as written in a sheet: its identifier and the name to show.
struct ZoneRef: Hashable, Sendable {
    var id: String
    var label: String
}

/// Places and abbreviations Tally understands as time zones: every city in the system's
/// time zone database ("Tokyo", "New York"), common extra cities and countries, and
/// upper-case abbreviations ("PST", "CET"). Matching is offline and instant.
enum Zones {
    /// Upper case only, so "est" or "art" in a note never reads as a zone. Abbreviations
    /// follow their region's daylight saving time: "PST" in July means Pacific time, which is
    /// what people mean when they write it.
    static let abbreviations: [String: String] = [
        "UTC": "UTC", "GMT": "GMT", "Z": "UTC",
        "PST": "America/Los_Angeles", "PDT": "America/Los_Angeles", "PT": "America/Los_Angeles",
        "MST": "America/Denver", "MDT": "America/Denver", "MT": "America/Denver",
        "CST": "America/Chicago", "CDT": "America/Chicago", "CT": "America/Chicago",
        "EST": "America/New_York", "EDT": "America/New_York", "ET": "America/New_York",
        "AKST": "America/Anchorage", "AKDT": "America/Anchorage", "HST": "Pacific/Honolulu",
        "AST": "America/Halifax", "ADT": "America/Halifax", "NST": "America/St_Johns",
        "BST": "Europe/London", "WET": "Europe/Lisbon", "WEST": "Europe/Lisbon",
        "CET": "Europe/Paris", "CEST": "Europe/Paris", "EET": "Europe/Athens", "EEST": "Europe/Athens",
        "MSK": "Europe/Moscow", "IST": "Asia/Kolkata", "PKT": "Asia/Karachi", "ICT": "Asia/Bangkok",
        "WIB": "Asia/Jakarta", "SGT": "Asia/Singapore", "HKT": "Asia/Hong_Kong", "PHT": "Asia/Manila",
        "JST": "Asia/Tokyo", "KST": "Asia/Seoul", "AEST": "Australia/Sydney", "AEDT": "Australia/Sydney",
        "ACST": "Australia/Adelaide", "ACDT": "Australia/Adelaide", "AWST": "Australia/Perth",
        "NZST": "Pacific/Auckland", "NZDT": "Pacific/Auckland", "BRT": "America/Sao_Paulo",
        "ART": "America/Argentina/Buenos_Aires", "SAST": "Africa/Johannesburg", "EAT": "Africa/Nairobi",
        "WAT": "Africa/Lagos", "GST": "Asia/Dubai",
    ]

    /// Cities and countries the zone database doesn't name directly, lower case.
    static let extraPlaces: [String: String] = [
        "san francisco": "America/Los_Angeles", "seattle": "America/Los_Angeles", "portland": "America/Los_Angeles",
        "san diego": "America/Los_Angeles", "las vegas": "America/Los_Angeles", "california": "America/Los_Angeles",
        "silicon valley": "America/Los_Angeles", "boston": "America/New_York", "washington": "America/New_York",
        "philadelphia": "America/New_York", "miami": "America/New_York", "atlanta": "America/New_York",
        "dallas": "America/Chicago", "houston": "America/Chicago", "austin": "America/Chicago", "texas": "America/Chicago",
        "minneapolis": "America/Chicago", "salt lake city": "America/Denver", "montreal": "America/Toronto",
        "ottawa": "America/Toronto", "calgary": "America/Edmonton", "hawaii": "Pacific/Honolulu",
        "rio": "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo", "brasilia": "America/Sao_Paulo",
        "barcelona": "Europe/Madrid", "munich": "Europe/Berlin", "hamburg": "Europe/Berlin", "frankfurt": "Europe/Berlin",
        "milan": "Europe/Rome", "venice": "Europe/Rome", "florence": "Europe/Rome", "geneva": "Europe/Zurich",
        "edinburgh": "Europe/London", "manchester": "Europe/London", "kyiv": "Europe/Kyiv", "kiev": "Europe/Kyiv",
        "st petersburg": "Europe/Moscow", "saint petersburg": "Europe/Moscow", "beijing": "Asia/Shanghai",
        "shenzhen": "Asia/Shanghai", "guangzhou": "Asia/Shanghai", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "new delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata", "chennai": "Asia/Kolkata",
        "hyderabad": "Asia/Kolkata", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "busan": "Asia/Seoul",
        "hanoi": "Asia/Bangkok", "ho chi minh city": "Asia/Ho_Chi_Minh", "saigon": "Asia/Ho_Chi_Minh",
        "tel aviv": "Asia/Jerusalem", "abu dhabi": "Asia/Dubai", "canberra": "Australia/Sydney",
        "wellington": "Pacific/Auckland",
        // Countries: their capital's or largest city's zone.
        "japan": "Asia/Tokyo", "china": "Asia/Shanghai", "india": "Asia/Kolkata", "germany": "Europe/Berlin",
        "france": "Europe/Paris", "spain": "Europe/Madrid", "italy": "Europe/Rome", "uk": "Europe/London",
        "england": "Europe/London", "britain": "Europe/London", "scotland": "Europe/London", "ireland": "Europe/Dublin",
        "netherlands": "Europe/Amsterdam", "holland": "Europe/Amsterdam", "belgium": "Europe/Brussels",
        "switzerland": "Europe/Zurich", "austria": "Europe/Vienna", "sweden": "Europe/Stockholm",
        "norway": "Europe/Oslo", "denmark": "Europe/Copenhagen", "finland": "Europe/Helsinki", "poland": "Europe/Warsaw",
        "portugal": "Europe/Lisbon", "greece": "Europe/Athens", "turkey": "Europe/Istanbul", "russia": "Europe/Moscow",
        "ukraine": "Europe/Kyiv", "czechia": "Europe/Prague", "hungary": "Europe/Budapest", "romania": "Europe/Bucharest",
        "israel": "Asia/Jerusalem", "egypt": "Africa/Cairo", "kenya": "Africa/Nairobi", "nigeria": "Africa/Lagos",
        "south africa": "Africa/Johannesburg", "morocco": "Africa/Casablanca", "brazil": "America/Sao_Paulo",
        "argentina": "America/Argentina/Buenos_Aires", "chile": "America/Santiago", "colombia": "America/Bogota",
        "peru": "America/Lima", "mexico": "America/Mexico_City", "canada": "America/Toronto",
        "australia": "Australia/Sydney", "new zealand": "Pacific/Auckland", "korea": "Asia/Seoul",
        "south korea": "Asia/Seoul", "taiwan": "Asia/Taipei", "thailand": "Asia/Bangkok", "vietnam": "Asia/Ho_Chi_Minh",
        "indonesia": "Asia/Jakarta", "philippines": "Asia/Manila", "malaysia": "Asia/Kuala_Lumpur",
        "uae": "Asia/Dubai", "saudi arabia": "Asia/Riyadh", "qatar": "Asia/Qatar", "pakistan": "Asia/Karachi",
        "bangladesh": "Asia/Dhaka", "nepal": "Asia/Kathmandu", "iceland": "Atlantic/Reykjavik", "iran": "Asia/Tehran",
    ]

    /// Lower-case place name → (zone id, display name).
    static let places: [String: ZoneRef] = {
        var map: [String: ZoneRef] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            guard let last = id.split(separator: "/").last, id.contains("/") else { continue }
            let name = last.replacingOccurrences(of: "_", with: " ")
            map[name.lowercased()] = ZoneRef(id: id, label: name)
        }
        for (place, id) in extraPlaces where TimeZone(identifier: id) != nil {
            map[place] = ZoneRef(id: id, label: place.split(separator: " ").map { word in
                word.count <= 3 && ["uk", "uae"].contains(String(word)) ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
            }.joined(separator: " "))
        }
        // Common spellings with accents dropped.
        if let sp = map["sao paulo"] { map["são paulo"] = ZoneRef(id: sp.id, label: "São Paulo") }
        return map
    }()

    /// The longest place name allowed, in words ("ho chi minh city").
    static let maxWords = 4

    /// A zone named by `words` starting at index 0: up to four words for places, one for
    /// abbreviations. Returns the zone and how many words it used.
    static func lookup(_ words: [String]) -> (ZoneRef, Int)? {
        guard let first = words.first else { return nil }
        if let id = abbreviations[first] { return (ZoneRef(id: id, label: first), 1) }
        var n = min(maxWords, words.count)
        while n >= 1 {
            let key = words[0..<n].joined(separator: " ").lowercased()
            if let place = places[key] { return (place, n) }
            n -= 1
        }
        return nil
    }
}

/// Calendar helpers for date arithmetic. Everything is Gregorian, in the given zone.
enum DateMath {
    /// Calendars and zones are slow to make; sheets ask for the same few over and over.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var calendars: [String: Calendar] = [:]
        private var zones: [String: TimeZone] = [:]

        func calendar(_ zone: TimeZone) -> Calendar {
            lock.lock()
            defer { lock.unlock() }
            if let c = calendars[zone.identifier] { return c }
            var c = Calendar(identifier: .gregorian)
            c.timeZone = zone
            calendars[zone.identifier] = c
            return c
        }

        func zone(_ id: String) -> TimeZone? {
            lock.lock()
            defer { lock.unlock() }
            if let z = zones[id] { return z }
            let z = TimeZone(identifier: id)
            zones[id] = z
            return z
        }
    }

    private static let cache = Cache()

    static func calendar(_ zone: TimeZone) -> Calendar {
        cache.calendar(zone)
    }

    static func zone(_ id: String) -> TimeZone? {
        cache.zone(id)
    }

    static func seconds(_ date: Date) -> Decimal {
        Decimal(string: String(format: "%.3f", date.timeIntervalSince1970), locale: DecimalMath.posix) ?? 0
    }

    static func date(_ seconds: Decimal) -> Date {
        Date(timeIntervalSince1970: DecimalMath.toDouble(seconds))
    }

    /// `hour:minute` on today's date as it is in `zone` right now.
    static func timeToday(hour: Int, minute: Int, second: Int, zone: TimeZone, now: Date) -> Date? {
        let cal = calendar(zone)
        var parts = cal.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = second
        return cal.date(from: parts)
    }

    /// A calendar day at midnight in `zone`; nil when the day doesn't exist (Feb 30).
    static func day(year: Int, month: Int, day: Int, zone: TimeZone) -> Date? {
        let cal = calendar(zone)
        let parts = DateComponents(year: year, month: month, day: day)
        guard parts.isValidDate(in: cal) else { return nil }
        return cal.date(from: parts)
    }

    static func startOfDay(_ date: Date, zone: TimeZone, addingDays days: Int = 0) -> Date {
        let cal = calendar(zone)
        let start = cal.startOfDay(for: date)
        return days == 0 ? start : cal.date(byAdding: .day, value: days, to: start) ?? start
    }

    static func year(of date: Date, zone: TimeZone) -> Int {
        calendar(zone).component(.year, from: date)
    }

    /// Whole days from `a` to `b` by the calendar (so a DST change doesn't give 0.96 days).
    static func dayDifference(from a: Date, to b: Date, zone: TimeZone) -> Int? {
        let cal = calendar(zone)
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day
    }

    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4,
        "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9,
        "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]
}
