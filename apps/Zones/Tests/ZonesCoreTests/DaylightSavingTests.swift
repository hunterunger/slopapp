import Foundation
import Testing
@testable import ZonesCore

/// DST correctness is a headline feature. Every case pins the instant.
@Suite struct DaylightSavingTests {
    let newYork = T.zone("America/New_York")
    let london = T.zone("Europe/London")

    // MARK: US/EU mismatch weeks (2026: US changes Mar 8 and Nov 1, EU Mar 29 and Oct 25)

    static let mismatchCases: [(String, Int)] = [
        ("2026-03-01T15:00:00Z", 5 * 3600),   // both on standard time
        ("2026-03-08T12:00:00Z", 4 * 3600),   // US sprang forward that morning
        ("2026-03-15T15:00:00Z", 4 * 3600),   // mismatch week
        ("2026-03-28T23:00:00Z", 4 * 3600),   // last evening of the mismatch
        ("2026-03-29T02:00:00Z", 5 * 3600),   // EU sprang forward at 01:00 UTC
        ("2026-07-01T12:00:00Z", 5 * 3600),   // both on summer time
        ("2026-10-24T23:30:00Z", 5 * 3600),   // just before EU falls back
        ("2026-10-25T01:00:00Z", 4 * 3600),   // EU fell back at 01:00 UTC
        ("2026-10-28T12:00:00Z", 4 * 3600),   // autumn mismatch week
        ("2026-11-01T05:59:00Z", 4 * 3600),   // US not yet back
        ("2026-11-01T06:00:00Z", 5 * 3600),   // US fell back at 06:00 UTC
    ]

    @Test(arguments: mismatchCases)
    func londonAheadOfNewYork(_ iso: String, _ expected: Int) {
        #expect(TimeMath.offset(of: london, from: newYork, at: T.date(iso)) == expected)
    }

    @Test func mismatchWeekShowsInRows() {
        let rows = ClockRows.make(places: [T.city("London", "Europe/London")], local: newYork, showLocal: true,
                                  at: T.date("2026-03-15T15:00:00Z"), formatter: T.formatter())
        #expect(rows[0].time == "11:00 AM")
        #expect(rows[1].time == "3:00 PM")
        #expect(rows[1].subtitle == "+4 h")
        let normal = ClockRows.make(places: [T.city("London", "Europe/London")], local: newYork, showLocal: true,
                                    at: T.date("2026-04-15T15:00:00Z"), formatter: T.formatter())
        #expect(normal[1].subtitle == "+5 h")
    }

    @Test func scrubbingIntoTheMismatchChangesTheOffset() {
        // Offsets are computed at the scrubbed instant, not cached from "now".
        var instant = T.date("2026-03-07T15:00:00Z")
        #expect(TimeMath.offset(of: london, from: newYork, at: instant) == 5 * 3600)
        instant = Scrubbing.step(from: instant, days: 2, local: newYork)
        #expect(TimeMath.offset(of: london, from: newYork, at: instant) == 4 * 3600)
        #expect(T.wall(instant, "America/New_York") == "10:00")  // wall time kept across the change
    }

    // MARK: Southern hemisphere

    @Test func sydneyMovesOppositeToLondon() {
        let sydney = T.zone("Australia/Sydney")
        // January: Sydney on summer time (+11), London on GMT.
        #expect(TimeMath.offset(of: sydney, from: london, at: T.date("2026-01-15T00:00:00Z")) == 11 * 3600)
        // July: Sydney standard (+10), London BST (+1).
        #expect(TimeMath.offset(of: sydney, from: london, at: T.date("2026-07-15T00:00:00Z")) == 9 * 3600)
        // Between Sydney's April 5 change and London's March 29 change: +10 vs +1 = 9... and
        // between March 29 and April 5 both are on summer time: 11 − 1 = 10.
        #expect(TimeMath.offset(of: sydney, from: london, at: T.date("2026-04-01T00:00:00Z")) == 10 * 3600)
    }

    @Test func sydneyFallsBackInApril() throws {
        let sydney = T.zone("Australia/Sydney")
        let transition = try #require(TimeMath.upcomingTransition(in: sydney, after: T.date("2026-04-01T00:00:00Z")))
        #expect(transition.change == -3600)
        #expect(T.wall(transition.date, "Australia/Sydney") == "02:00")  // 3:00 → 2:00
    }

    @Test func santiagoDiffersFromNewYorkBySeason() {
        let santiago = T.zone("America/Santiago")
        let january = TimeMath.offset(of: santiago, from: newYork, at: T.date("2026-01-15T12:00:00Z"))
        let july = TimeMath.offset(of: santiago, from: newYork, at: T.date("2026-07-15T12:00:00Z"))
        #expect(january == 2 * 3600)   // Chile summer −3, NY winter −5
        #expect(july == 0)             // Chile winter −4, NY summer −4
    }

    @Test func lordHoweShiftsByHalfAnHour() throws {
        let lordHowe = T.zone("Australia/Lord_Howe")
        #expect(lordHowe.secondsFromGMT(for: T.date("2026-01-15T00:00:00Z")) == 11 * 3600)
        #expect(lordHowe.secondsFromGMT(for: T.date("2026-07-15T00:00:00Z")) == 10 * 3600 + 1800)
        let transition = try #require(TimeMath.upcomingTransition(in: lordHowe, after: T.date("2026-04-01T00:00:00Z")))
        #expect(transition.change == -1800)
        #expect(ClockRows.transitionText(transition, zone: lordHowe, formatter: T.formatter()) == "Clocks go back 30 min on Sun")
    }

    // MARK: Half-hour and 45-minute offsets

    static let nonHourCases: [(String, String, String, String)] = [
        ("Asia/Kolkata", "2026-11-03T12:00:00Z", "+5 h 30 min", "UTC+5:30"),
        ("Asia/Kathmandu", "2026-11-03T12:00:00Z", "+5 h 45 min", "UTC+5:45"),
        ("Pacific/Chatham", "2026-07-15T12:00:00Z", "+12 h 45 min", "UTC+12:45"),
        ("Pacific/Chatham", "2026-01-15T12:00:00Z", "+13 h 45 min", "UTC+13:45"),
        ("America/St_Johns", "2026-01-15T12:00:00Z", "\u{2212}3 h 30 min", "UTC\u{2212}3:30"),
        ("America/St_Johns", "2026-07-15T12:00:00Z", "\u{2212}2 h 30 min", "UTC\u{2212}2:30"),
        ("Australia/Adelaide", "2026-07-15T12:00:00Z", "+9 h 30 min", "UTC+9:30"),
        ("Australia/Eucla", "2026-07-15T12:00:00Z", "+8 h 45 min", "UTC+8:45"),
    ]

    @Test(arguments: nonHourCases)
    func nonHourOffsets(_ id: String, _ iso: String, _ relative: String, _ label: String) {
        let seconds = TimeMath.offset(of: T.zone(id), from: T.zone("UTC"), at: T.date(iso))
        #expect(OffsetText.relative(seconds) == relative)
        #expect(OffsetText.utcLabel(seconds) == label)
    }

    @Test func kathmanduTimeShows45Minutes() {
        let rows = ClockRows.make(places: [T.city("Kathmandu", "Asia/Kathmandu")], local: T.zone("UTC"),
                                  showLocal: false, at: T.date("2026-11-03T12:00:00Z"), formatter: T.formatter(.twentyFour))
        #expect(rows[0].time == "17:45")
    }

    // MARK: Date line

    @Test func dateLineDays() {
        let instant = T.date("2026-11-03T11:00:00Z")
        let kiritimati = T.zone("Pacific/Kiritimati")  // +14
        let baker = T.zone("Etc/GMT+12")               // −12 (Baker/Howland)
        let utc = T.zone("UTC")
        #expect(TimeMath.dayDifference(of: kiritimati, from: utc, at: instant) == 1)
        #expect(TimeMath.dayDifference(of: baker, from: utc, at: instant) == -1)
        #expect(TimeMath.dayDifference(of: kiritimati, from: baker, at: instant) == 2)
        #expect(TimeMath.offset(of: kiritimati, from: baker, at: instant) == 26 * 3600)
    }

    @Test func samoaAndAmericanSamoaShowTheSameClockADayApart() {
        let instant = T.date("2026-11-03T23:00:00Z")
        let apia = T.zone("Pacific/Apia")          // +13
        let pagoPago = T.zone("Pacific/Pago_Pago") // −11
        #expect(TimeMath.wallTime(of: instant, in: apia) == TimeMath.wallTime(of: instant, in: pagoPago))
        #expect(TimeMath.dayDifference(of: apia, from: pagoPago, at: instant) == 1)
    }

    @Test func dateLineRowsSayYesterdayTomorrowAndAWeekday() {
        let places = [T.city("Kiritimati", "Pacific/Kiritimati"), T.city("Baker Island", "Etc/GMT+12")]
        let rows = ClockRows.make(places: places, local: T.zone("Etc/GMT+12"), showLocal: false,
                                  at: T.date("2026-11-03T11:00:00Z"), formatter: T.formatter())
        // Local (−12) is Mon Nov 2 23:00; Kiritimati is Wed Nov 4 01:00.
        #expect(rows[0].subtitle == "Wed · +26 h")
        #expect(rows[1].subtitle == "Same time")
        let fromUTC = ClockRows.make(places: places, local: T.zone("UTC"), showLocal: false,
                                     at: T.date("2026-11-03T11:00:00Z"), formatter: T.formatter())
        #expect(fromUTC[0].subtitle == "Tomorrow · +14 h")
        #expect(fromUTC[1].subtitle == "Yesterday · \u{2212}12 h")
    }

    @Test func scrubbingAcrossLocalMidnightFlipsTheDayLabel() {
        let tokyo = T.city("Tokyo", "Asia/Tokyo")
        let local = T.zone("America/Los_Angeles")
        var instant = T.date("2026-11-03T06:30:00Z")  // LA Nov 2 22:30, Tokyo Nov 3 15:30
        var rows = ClockRows.make(places: [tokyo], local: local, showLocal: false, at: instant, formatter: T.formatter())
        #expect(rows[0].dayDifference == 1)
        instant = Scrubbing.step(from: instant, marks: 2, of: Scrubbing.hour, local: local)  // LA 00:00 Nov 3
        rows = ClockRows.make(places: [tokyo], local: local, showLocal: false, at: instant, formatter: T.formatter())
        #expect(T.wall(instant, "America/Los_Angeles") == "00:00")
        #expect(rows[0].dayDifference == 0)
    }

    // MARK: Transition hints

    @Test func upcomingChangeIsNoted() {
        let rows = ClockRows.make(places: [T.city("London", "Europe/London")], local: newYork, showLocal: true,
                                  at: T.date("2026-10-20T12:00:00Z"), formatter: T.formatter())
        #expect(rows[1].transitionNote == "Clocks go back 1 h on Sun")
        #expect(rows[0].transitionNote == nil)  // New York changes Nov 1, more than a week away
        let spring = ClockRows.make(places: [], local: newYork, showLocal: true,
                                    at: T.date("2026-03-05T12:00:00Z"), formatter: T.formatter())
        #expect(spring[0].transitionNote == "Clocks go forward 1 h on Sun")
    }

    @Test func zonesWithoutDaylightSavingNeverNote() {
        for id in ["Asia/Tokyo", "Asia/Kolkata", "America/Phoenix", "UTC"] {
            #expect(TimeMath.upcomingTransition(in: T.zone(id), after: T.date("2026-03-05T12:00:00Z"),
                                                within: 400 * 86_400) == nil, "\(id)")
        }
    }
}
