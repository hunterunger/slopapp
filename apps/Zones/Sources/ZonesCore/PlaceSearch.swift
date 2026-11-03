import Foundation

/// One search result: a ready-to-add place plus how to show it.
public struct SearchResult: Identifiable, Hashable, Sendable {
    public var id: String
    public var place: Place
    /// "Paris"
    public var title: String
    /// "Île-de-France, France", "PST · Los Angeles", "Fixed offset, no daylight saving"
    public var subtitle: String

    public var timeZone: TimeZone { place.timeZone }
}

/// Offline search over cities, countries, IANA zone identifiers, abbreviations and UTC
/// offsets. Diacritic- and case-insensitive. Pure and synchronous: about a millisecond
/// or two over the 34k bundled cities.
public struct PlaceSearch: Sendable {
    public let database: CityDatabase
    public let locale: Locale
    public let zoneIdentifiers: [String]
    private let countries: [(code: String, folded: String)]

    public init(database: CityDatabase, locale: Locale = .autoupdatingCurrent,
                zoneIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers) {
        self.database = database
        self.locale = locale
        self.zoneIdentifiers = zoneIdentifiers
        var codes = Set(database.cities.map(\.countryCode))
        codes.remove("")
        self.countries = codes.sorted().map { code in
            (code, SearchFolding.fold(locale.localizedString(forRegionCode: code) ?? code))
        }
    }

    /// Big, commonly-added cities shown before anything is typed, as (name, country code).
    public static let popular: [(String, String)] = [
        ("London", "GB"), ("New York City", "US"), ("Los Angeles", "US"), ("San Francisco", "US"),
        ("Chicago", "US"), ("Toronto", "CA"), ("São Paulo", "BR"), ("Paris", "FR"), ("Berlin", "DE"),
        ("Dubai", "AE"), ("Mumbai", "IN"), ("Singapore", "SG"), ("Hong Kong", "HK"),
        ("Shanghai", "CN"), ("Tokyo", "JP"), ("Sydney", "AU"), ("Auckland", "NZ"),
    ]

    public func results(for query: String, limit: Int = 40) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return popularResults() }

        var results: [SearchResult] = []
        var seen = Set<String>()
        func add(_ result: SearchResult) {
            guard seen.insert(result.id).inserted else { return }
            results.append(result)
        }

        // "UTC", "GMT", "UTC+5:30", "GMT-3", "+0530"
        if let offset = Self.parseOffset(trimmed) {
            add(offset == nil ? Self.utcResult() : fixedResult(offset!))
        }

        // "City, country or region" narrows by the part after the comma.
        let parts = trimmed.split(separator: ",", maxSplits: 1).map { SearchFolding.fold(String($0)) }
        let folded = parts.first ?? ""
        let filter = parts.count > 1 ? parts[1] : ""
        guard !folded.isEmpty else { return results }

        let cityMatches = matchCities(folded, filter: filter)
        // An exact city name wins over an abbreviation ("York", "Paris"); otherwise
        // abbreviations come first ("PST", "IST" before Istanbul).
        let exactCount = cityMatches.prefix { $0.tier == 0 }.count
        for match in cityMatches.prefix(exactCount) { add(cityResult(match.city)) }
        if filter.isEmpty {
            for result in abbreviationResults(trimmed) { add(result) }
        }
        for match in cityMatches.dropFirst(exactCount) { add(cityResult(match.city)) }
        if filter.isEmpty {
            for result in zoneResults(folded, excluding: results) { add(result) }
        }
        return Array(results.prefix(limit))
    }

    // MARK: Cities

    struct Match {
        var city: City
        var tier: Int
    }

    func matchCities(_ query: String, filter: String) -> [Match] {
        let countryCodes = Set(countries.filter { $0.folded.hasPrefix(query) }.map(\.code))
        let filterCodes: Set<String>? = filter.isEmpty ? nil : Set(countries.filter {
            $0.folded.hasPrefix(filter) || $0.code.lowercased() == filter
        }.map(\.code))
        let q = Array(query.utf8)
        let separatorQuery = [UInt8(ascii: "|")] + q
        let wordQuery = [UInt8(ascii: " ")] + q
        let allowExact = query.count >= 3
        var buckets: [[Match]] = Array(repeating: [], count: 6)
        var countryHits = 0
        var regionMatches: [String: Bool] = [:]
        database.keyBytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for city in database.cities {
                if let filterCodes {
                    let regionMatch = regionMatches[city.region] ?? {
                        let match = SearchFolding.fold(city.region).hasPrefix(filter)
                        regionMatches[city.region] = match
                        return match
                    }()
                    guard filterCodes.contains(city.countryCode) || regionMatch else { continue }
                }
                let start = base + Int(city.keyStart)
                let keyLength = Int(city.keyEnd - city.keyStart)
                let nameLength = Int(city.nameEnd - city.keyStart)
                let tier: Int
                if nameLength >= q.count, memcmp(start, q, q.count) == 0 {
                    tier = (nameLength == q.count && allowExact) ? 0 : 1
                } else if let hit = Self.find(separatorQuery, in: start, length: keyLength),
                          hit + separatorQuery.count == keyLength || start[hit + separatorQuery.count] == UInt8(ascii: "|") {
                    tier = 2
                } else if Self.find(separatorQuery, in: start, length: keyLength) != nil {
                    tier = 3
                } else if Self.find(wordQuery, in: start, length: nameLength) != nil {
                    tier = 4
                } else if countryCodes.contains(city.countryCode), countryHits < 12 {
                    countryHits += 1
                    tier = 5
                } else {
                    continue
                }
                if buckets[tier].count < 60 { buckets[tier].append(Match(city: city, tier: tier)) }
            }
        }
        // The data is sorted by population, so each bucket already is too.
        return buckets.flatMap { $0 }
    }

    /// Offset of the first occurrence of `needle` in the `length` bytes at `haystack`.
    static func find(_ needle: [UInt8], in haystack: UnsafePointer<UInt8>, length: Int) -> Int? {
        guard length >= needle.count else { return nil }
        return needle.withUnsafeBufferPointer { pattern -> Int? in
            guard let found = memmem(haystack, length, pattern.baseAddress, pattern.count) else { return nil }
            return UnsafeRawPointer(haystack).distance(to: UnsafeRawPointer(found))
        }
    }

    public func cityResult(_ city: City) -> SearchResult {
        let country = locale.localizedString(forRegionCode: city.countryCode) ?? city.countryCode
        let detail = [city.region, country].filter { !$0.isEmpty }.joined(separator: ", ")
        let place = Place(kind: .city, name: city.name, detail: detail, timeZoneID: city.timeZoneID)
        return SearchResult(id: "city|\(city.name)|\(city.countryCode)|\(city.region)|\(city.timeZoneID)",
                            place: place, title: city.name, subtitle: detail)
    }

    func popularResults() -> [SearchResult] {
        var results = [Self.utcResult()]
        for (name, country) in Self.popular {
            if let city = database.cities.first(where: { $0.name == name && $0.countryCode == country }) {
                results.append(cityResult(city))
            }
        }
        return results
    }

    // MARK: Zones, abbreviations, offsets

    static func utcResult() -> SearchResult {
        SearchResult(id: "utc", place: .utc(), title: "UTC", subtitle: "Coordinated Universal Time")
    }

    func fixedResult(_ seconds: Int) -> SearchResult {
        let place = Place.fixed(offset: seconds)
        return SearchResult(id: "fixed|\(seconds)", place: place, title: place.name, subtitle: place.detail)
    }

    /// Whole time zones whose identifier or city part starts with the query
    /// ("lord howe", "europe/par"), skipping ones a city result already covers.
    func zoneResults(_ folded: String, excluding existing: [SearchResult]) -> [SearchResult] {
        let covered = Set(existing.map { "\(SearchFolding.fold($0.title))|\($0.place.timeZoneID)" })
        var results: [SearchResult] = []
        for identifier in zoneIdentifiers where identifier.contains("/") {
            let full = SearchFolding.fold(identifier.replacingOccurrences(of: "_", with: " "))
            let city = SearchFolding.fold(ZoneNames.cityName(forIdentifier: identifier))
            guard full.hasPrefix(folded) || city.hasPrefix(folded)
                    || full.hasPrefix(folded.replacingOccurrences(of: "_", with: " ")) else { continue }
            guard !covered.contains("\(city)|\(identifier)") else { continue }
            let place = Place.zone(identifier)
            results.append(SearchResult(id: "zone|\(identifier)", place: place, title: place.name,
                                        subtitle: "Time zone \(identifier)"))
            if results.count >= 10 { break }
        }
        return results
    }

    func abbreviationResults(_ query: String) -> [SearchResult] {
        let key = query.uppercased()
        guard let identifiers = Self.abbreviations[key] else { return [] }
        return identifiers.compactMap { identifier in
            guard let zone = TimeZone(identifier: identifier) else { return nil }
            let generic = zone.localizedName(for: .generic, locale: locale) ?? ZoneNames.cityName(forIdentifier: identifier)
            let city = ZoneNames.cityName(forIdentifier: identifier)
            let place = Place(kind: .zone, name: generic, detail: "Time zone \(identifier)", timeZoneID: identifier)
            return SearchResult(id: "abbr|\(key)|\(identifier)", place: place, title: generic,
                                subtitle: "\(key) · \(city)")
        }
    }

    /// Common abbreviations. Ambiguous ones list every zone they're used for.
    public static let abbreviations: [String: [String]] = [
        "PT": ["America/Los_Angeles"], "PST": ["America/Los_Angeles"], "PDT": ["America/Los_Angeles"],
        "MT": ["America/Denver"], "MST": ["America/Denver", "America/Phoenix"], "MDT": ["America/Denver"],
        "CT": ["America/Chicago"], "CST": ["America/Chicago", "Asia/Shanghai", "America/Havana"],
        "CDT": ["America/Chicago"], "ET": ["America/New_York"], "EST": ["America/New_York"],
        "EDT": ["America/New_York"], "AKST": ["America/Anchorage"], "AKDT": ["America/Anchorage"],
        "HST": ["Pacific/Honolulu"], "AST": ["America/Halifax", "Asia/Riyadh"], "ADT": ["America/Halifax"],
        "NST": ["America/St_Johns"], "NDT": ["America/St_Johns"],
        "BST": ["Europe/London", "Asia/Dhaka"], "IST": ["Asia/Kolkata", "Europe/Dublin", "Asia/Jerusalem"],
        "WET": ["Europe/Lisbon"], "WEST": ["Europe/Lisbon"], "CET": ["Europe/Paris"], "CEST": ["Europe/Paris"],
        "EET": ["Europe/Athens"], "EEST": ["Europe/Athens"], "MSK": ["Europe/Moscow"],
        "GST": ["Asia/Dubai"], "PKT": ["Asia/Karachi"], "NPT": ["Asia/Kathmandu"], "ICT": ["Asia/Bangkok"],
        "WIB": ["Asia/Jakarta"], "HKT": ["Asia/Hong_Kong"], "SGT": ["Asia/Singapore"], "PHT": ["Asia/Manila"],
        "JST": ["Asia/Tokyo"], "KST": ["Asia/Seoul"], "AWST": ["Australia/Perth"],
        "ACST": ["Australia/Adelaide"], "ACDT": ["Australia/Adelaide"], "AEST": ["Australia/Sydney"],
        "AEDT": ["Australia/Sydney"], "NZST": ["Pacific/Auckland"], "NZDT": ["Pacific/Auckland"],
        "SAST": ["Africa/Johannesburg"], "CAT": ["Africa/Maputo"], "EAT": ["Africa/Nairobi"],
        "WAT": ["Africa/Lagos"], "BRT": ["America/Sao_Paulo"], "ART": ["America/Argentina/Buenos_Aires"],
    ]

    /// Parses "UTC", "GMT", "Z" (→ `.some(nil)`, plain UTC) and "UTC+5:30", "GMT-3",
    /// "+0530", "utc+12:45" (→ seconds east of UTC, −12 h … +14 h). Nil if it isn't one.
    public static func parseOffset(_ query: String) -> Int?? {
        var text = query.lowercased().replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "\u{2212}", with: "-")
        var hadPrefix = false
        for prefix in ["utc", "gmt"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            hadPrefix = true
        }
        if text.isEmpty { return hadPrefix ? .some(nil) : nil }
        if text == "z" && !hadPrefix { return .some(nil) }
        guard let signChar = text.first, signChar == "+" || signChar == "-" else { return nil }
        text.removeFirst()
        var hours = 0
        var minutes = 0
        if let colon = text.firstIndex(of: ":") {
            guard let h = Int(text[..<colon]), let m = Int(text[text.index(after: colon)...]) else { return nil }
            hours = h; minutes = m
        } else {
            guard !text.isEmpty, text.allSatisfy(\.isNumber), let value = Int(text) else { return nil }
            if text.count <= 2 { hours = value } else if text.count <= 4 { hours = value / 100; minutes = value % 100 } else { return nil }
        }
        guard minutes < 60, minutes % 15 == 0 else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (signChar == "-" ? -1 : 1)
        guard (-12 * 3600)...(14 * 3600) ~= seconds else { return nil }
        return seconds == 0 ? .some(nil) : .some(seconds)
    }
}
