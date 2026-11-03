import Foundation
import Testing
@testable import ZonesCore

/// Runs against the real bundled GeoNames file, loaded once.
@Suite struct SearchTests {
    static let database: CityDatabase = {
        guard let url = CityDatabase.bundledURL, let database = try? CityDatabase.load(from: url) else {
            fatalError("bundled city list missing")
        }
        return database
    }()
    let search = PlaceSearch(database: SearchTests.database, locale: T.enUS)

    func titles(_ query: String, _ count: Int = 5) -> [String] {
        Array(search.results(for: query).prefix(count).map(\.title))
    }

    @Test func databaseLoads() {
        #expect(Self.database.cities.count > 30_000)
        // Sorted by population, largest first.
        let populations = Self.database.cities.prefix(100).map(\.population)
        #expect(populations == populations.sorted(by: >))
    }

    @Test func everyBundledZoneIsKnownToTheSystem() {
        let ids = Set(Self.database.cities.map(\.timeZoneID))
        let unknown = ids.filter { TimeZone(identifier: $0) == nil }
        #expect(unknown.isEmpty, "unknown: \(unknown.sorted())")
    }

    @Test func prefixRankedByPopulation() {
        #expect(titles("par").first == "Paris")
        #expect(titles("lon").first == "London")
        #expect(titles("syd").first == "Sydney")
        #expect(titles("tok").first == "Tokyo")
    }

    @Test func exactNameBeatsLargerPrefixMatches() {
        #expect(titles("york").first == "York")
        #expect(titles("york", 10).contains("New York City"))
    }

    @Test func diacriticAndCaseInsensitive() {
        #expect(titles("zurich").first == "Zürich")
        #expect(titles("ZÜRICH").first == "Zürich")
        #expect(titles("sao paulo").first == "São Paulo")
        #expect(titles("krakow").first == "Kraków")
    }

    @Test func alternateNames() {
        #expect(titles("munchen").first == "Munich")
        #expect(titles("東京").first == "Tokyo")
        #expect(titles("nyc").first == "New York City")
    }

    @Test func resultsShowRegionAndCountry() throws {
        let paris = try #require(search.results(for: "paris").first)
        #expect(paris.subtitle == "Île-de-France, France")
        #expect(paris.place.timeZoneID == "Europe/Paris")
        #expect(paris.place.kind == .city)
    }

    @Test func duplicateNamesAreTellApart() {
        let springfields = search.results(for: "springfield").filter { $0.title == "Springfield" }
        #expect(springfields.count >= 3)
        #expect(Set(springfields.map(\.subtitle)).count == springfields.count)
    }

    @Test func commaNarrowsByCountryOrRegion() {
        let results = search.results(for: "paris, united states")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.subtitle.hasSuffix("United States") })
        let texas = search.results(for: "paris, tex")
        #expect(texas.first?.subtitle == "Texas, United States")
    }

    @Test func countryNameListsItsCities() {
        let results = search.results(for: "japan", limit: 40)
        #expect(results.contains { $0.title == "Tokyo" })
    }

    @Test func abbreviations() {
        let pst = search.results(for: "pst")
        #expect(pst.first?.place.timeZoneID == "America/Los_Angeles")
        #expect(pst.first?.title == "Pacific Time")
        // Ambiguous: every meaning is offered, before Istanbul.
        let ist = search.results(for: "IST").prefix(4).map(\.place.timeZoneID)
        #expect(ist.prefix(3) == ["Asia/Kolkata", "Europe/Dublin", "Asia/Jerusalem"])
        #expect(search.results(for: "ist", limit: 10).contains { $0.title == "Istanbul" })
        #expect(search.results(for: "cst").map(\.place.timeZoneID).prefix(3) == ["America/Chicago", "Asia/Shanghai", "America/Havana"])
    }

    @Test func utcAndOffsets() {
        #expect(search.results(for: "utc").first?.place.kind == .utc)
        #expect(search.results(for: "GMT").first?.place.kind == .utc)
        let plus = search.results(for: "utc+5:30").first
        #expect(plus?.place.kind == .fixedOffset)
        #expect(plus?.place.fixedOffset == 19_800)
        #expect(plus?.title == "UTC+5:30")
        #expect(search.results(for: "gmt-3").first?.place.fixedOffset == -10_800)
        #expect(search.results(for: "+0545").first?.place.fixedOffset == 20_700)
        #expect(PlaceSearch.parseOffset("utc+15") == nil)
        #expect(PlaceSearch.parseOffset("utc+5:20") == nil)
        #expect(PlaceSearch.parseOffset("london") == nil)
    }

    @Test func ianaIdentifiersAndZoneOnlyPlaces() {
        let europeParis = search.results(for: "Europe/Paris")
        #expect(europeParis.contains { $0.place.timeZoneID == "Europe/Paris" && $0.place.kind == .zone })
        let lordHowe = search.results(for: "lord howe")
        #expect(lordHowe.first?.place.timeZoneID == "Australia/Lord_Howe")
        // A city result already covers London's zone, so no duplicate zone row.
        let london = search.results(for: "london", limit: 40)
        #expect(!london.contains { $0.place.kind == .zone && $0.place.timeZoneID == "Europe/London" })
    }

    @Test func emptyQueryOffersPopularPlaces() {
        let results = search.results(for: "  ")
        #expect(results.first?.place.kind == .utc)
        #expect(results.contains { $0.title == "London" })
        #expect(results.contains { $0.title == "Tokyo" })
        #expect(results.count >= 15)
    }

    @Test func noMatches() {
        #expect(search.results(for: "qqqzzzxx").isEmpty)
    }

    @Test func searchIsFast() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for query in ["s", "sa", "san", "san f", "a", "e", "lon", "new"] { _ = search.results(for: query) }
        }
        #expect(elapsed < .milliseconds(240), "8 queries took \(elapsed)")
    }
}
