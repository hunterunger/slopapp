import Foundation
import Testing
@testable import ZonesCore

@Suite struct FormattingTests {
    @Test func hourCycles() {
        let instant = T.date("2026-11-03T17:20:00Z")
        let london = T.zone("Europe/London")
        #expect(T.formatter(.twelve).time(instant, in: london) == "5:20 PM")
        #expect(T.formatter(.twentyFour).time(instant, in: london) == "17:20")
        // System follows the locale: en_US is 12-hour, en_GB/de_DE 24-hour.
        #expect(TimeFormatter(locale: T.enUS, hourCycle: .system).time(instant, in: london) == "5:20 PM")
        #expect(TimeFormatter(locale: Locale(identifier: "de_DE"), hourCycle: .system).time(instant, in: london) == "17:20")
    }

    @Test func offsetTexts() {
        #expect(OffsetText.relative(0) == "Same time")
        #expect(OffsetText.relative(7 * 3600) == "+7 h")
        #expect(OffsetText.relative(-45 * 60) == "\u{2212}45 min")
        #expect(OffsetText.spoken(19_800) == "5 hours 30 minutes ahead")
        #expect(OffsetText.spoken(-3600) == "1 hour behind")
        #expect(OffsetText.iso(-12_600) == "-03:30")
    }

    @Test func dayPhases() {
        #expect(DayPhase(hour: 0) == .night)
        #expect(DayPhase(hour: 5) == .night)
        #expect(DayPhase(hour: 6) == .morning)
        #expect(DayPhase(hour: 8) == .day)
        #expect(DayPhase(hour: 17) == .day)
        #expect(DayPhase(hour: 18) == .evening)
        #expect(DayPhase(hour: 21) == .night)
    }

    @Test func abbreviationsOnlyWhenTheyAreReal() {
        let winter = T.date("2026-01-15T12:00:00Z")
        #expect(ZoneAbbreviation.display(for: T.zone("America/New_York"), at: winter) == "EST")
        #expect(ZoneAbbreviation.display(for: T.zone("UTC"), at: winter) == "UTC")
        #expect(ZoneAbbreviation.display(for: T.zone("Asia/Kathmandu"), at: winter) == "UTC+5:45")
        let summer = T.date("2026-07-15T12:00:00Z")
        #expect(ZoneAbbreviation.display(for: T.zone("Europe/London"), at: winter) == "GMT")
        #expect(ZoneAbbreviation.display(for: T.zone("Europe/London"), at: summer) == "BST")
        #expect(ZoneAbbreviation.display(for: T.zone("Europe/Berlin"), at: summer) == "CEST")
        #expect(ZoneAbbreviation.display(for: T.zone("Australia/Sydney"), at: winter) == "AEDT")
        #expect(ZoneAbbreviation.display(for: T.zone("Asia/Tokyo"), at: winter) == "JST")
        #expect(ZoneAbbreviation.display(for: T.zone("Asia/Kolkata"), at: winter) == "IST")
        #expect(ZoneAbbreviation.display(for: T.zone("Asia/Shanghai"), at: winter) == "UTC+8")  // CST is ambiguous
        #expect(ZoneAbbreviation.display(for: T.zone("America/Los_Angeles"), at: summer) == "PDT")
        let fixed = Place.fixed(offset: -3 * 3600)
        #expect(ZoneAbbreviation.display(for: fixed.timeZone, at: winter) == "UTC\u{2212}3")
    }

    @Test func rowAccessibilitySentence() {
        let rows = ClockRows.make(places: [T.city("London", "Europe/London")], local: T.zone("America/Chicago"),
                                  showLocal: true, at: T.date("2026-11-03T23:20:00Z"), formatter: T.formatter())
        #expect(rows[0].accessibilityLabel == "Chicago, 5:20 PM, local time, daytime")
        #expect(rows[1].accessibilityLabel == "London, 11:20 PM, today, 6 hours ahead, night")
    }

    @Test func copyFormats() {
        let entries = [
            TimesText.Entry(label: "Chicago", zone: T.zone("America/Chicago")),
            TimesText.Entry(label: "London", zone: T.zone("Europe/London")),
            TimesText.Entry(label: "Tokyo", zone: T.zone("Asia/Tokyo")),
            TimesText.Entry(label: "Kathmandu", zone: T.zone("Asia/Kathmandu")),
        ]
        let instant = T.date("2026-11-03T17:00:00Z")
        let list = TimesText.make(entries, at: instant, format: .list, formatter: T.formatter())
        #expect(list == """
            Chicago: Tue, Nov 3, 11:00 AM CST
            London: Tue, Nov 3, 5:00 PM GMT
            Tokyo: Wed, Nov 4, 2:00 AM JST
            Kathmandu: Tue, Nov 3, 10:45 PM UTC+5:45
            """)
        let line = TimesText.make(Array(entries.prefix(3)), at: instant, format: .singleLine, formatter: T.formatter())
        #expect(line == "11:00 AM Chicago · 5:00 PM London · 2:00 AM Tokyo (Wed)")
        let iso = TimesText.make(Array(entries.prefix(2)), at: instant, format: .iso8601, formatter: T.formatter())
        #expect(iso == "Chicago: 2026-11-03T11:00-06:00\nLondon: 2026-11-03T17:00+00:00")
        #expect(!list.contains("Tomorrow") && !list.contains("Today"))
    }

    @Test func menuBarTags() {
        #expect(MenuBarClock.tag(for: T.city("London", "Europe/London")) == "LON")
        #expect(MenuBarClock.tag(for: T.city("New York City", "America/New_York")) == "NYC")
        #expect(MenuBarClock.tag(for: T.city("Los Angeles", "America/Los_Angeles")) == "LA")
        #expect(MenuBarClock.tag(for: .utc()) == "UTC")
        var mum = T.city("Melbourne", "Australia/Melbourne")
        mum.customName = "Mum"
        #expect(MenuBarClock.tag(for: mum) == "Mum")
        #expect(MenuBarClock.tag(for: .fixed(offset: 19_800)) == "UTC+5:30")
        #expect(MenuBarClock.title(for: T.city("London", "Europe/London"), at: T.date("2026-11-03T17:20:00Z"),
                                   formatter: T.formatter(.twentyFour)) == "LON 17:20")
    }

    @Test func folding() {
        #expect(SearchFolding.fold("Zürich") == "zurich")
        #expect(SearchFolding.fold("São Paulo") == "sao paulo")
        #expect(SearchFolding.fold("KRAKÓW ") == "krakow")
        #expect(SearchFolding.fold("ＴＯＫＹＯ") == "tokyo")
    }

    @Test func placeLabelsAndZones() {
        var place = Place.zone("America/Argentina/Buenos_Aires")
        #expect(place.label == "Buenos Aires")
        place.customName = "  "
        #expect(place.label == "Buenos Aires")
        #expect(Place.fixed(offset: 19_800).timeZone.secondsFromGMT() == 19_800)
        #expect(Place.utc().timeZone.secondsFromGMT() == 0)
    }

    @Test func preferencesDecodeOldSaves() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(#"{"showLocalTime":false,"hourCycle":"bogus"}"#.utf8))
        #expect(decoded.showLocalTime == false)
        #expect(decoded.hourCycle == .system)
        #expect(decoded.copyFormat == .list)
    }
}
