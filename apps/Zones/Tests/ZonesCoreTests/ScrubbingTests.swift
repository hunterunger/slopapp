import Foundation
import Testing
@testable import ZonesCore

@Suite struct ScrubbingTests {
    let newYork = T.zone("America/New_York")

    @Test func quarterStepsAlignToMarks() {
        let base = T.date("2026-11-03T15:07:23Z")  // 10:07:23 EST
        #expect(T.wall(Scrubbing.step(from: base, marks: 1, of: 900, local: newYork), "America/New_York") == "10:15")
        #expect(T.wall(Scrubbing.step(from: base, marks: -1, of: 900, local: newYork), "America/New_York") == "10:00")
        let aligned = T.date("2026-11-03T15:00:00Z")
        #expect(T.wall(Scrubbing.step(from: aligned, marks: 1, of: 900, local: newYork), "America/New_York") == "10:15")
        #expect(T.wall(Scrubbing.step(from: aligned, marks: -1, of: 900, local: newYork), "America/New_York") == "09:45")
    }

    @Test func hourStepsAlignToLocalHours() {
        let base = T.date("2026-11-03T15:07:00Z")
        #expect(T.wall(Scrubbing.step(from: base, marks: 1, of: 3600, local: newYork), "America/New_York") == "11:00")
        #expect(T.wall(Scrubbing.step(from: base, marks: -1, of: 3600, local: newYork), "America/New_York") == "10:00")
        #expect(T.wall(Scrubbing.step(from: base, marks: 3, of: 3600, local: newYork), "America/New_York") == "13:00")
    }

    @Test func hourMarksInAHalfHourZone() {
        let kolkata = T.zone("Asia/Kolkata")
        let base = T.date("2026-11-03T04:40:00Z")  // 10:10 IST
        let next = Scrubbing.step(from: base, marks: 1, of: 3600, local: kolkata)
        #expect(T.wall(next, "Asia/Kolkata") == "11:00")
        #expect(T.wall(next, "UTC") == "05:30")
    }

    @Test func springForwardGapIsSkippedNotStuck() {
        var instant = T.date("2026-03-08T06:30:00Z")  // 01:30 EST
        var walls: [String] = []
        for _ in 0..<4 {
            let next = Scrubbing.step(from: instant, marks: 1, of: 900, local: newYork)
            #expect(next > instant)
            instant = next
            walls.append(T.wall(instant, "America/New_York"))
        }
        #expect(walls == ["01:45", "03:00", "03:15", "03:30"])
        // And back again.
        var back: [String] = []
        for _ in 0..<4 {
            let previous = Scrubbing.step(from: instant, marks: -1, of: 900, local: newYork)
            #expect(previous < instant)
            instant = previous
            back.append(T.wall(instant, "America/New_York"))
        }
        #expect(back == ["03:15", "03:00", "01:45", "01:30"])
    }

    @Test func fallBackRepeatedHourIsSteppedThrough() {
        var instant = T.date("2026-11-01T05:30:00Z")  // 01:30 EDT
        var seen: [String] = []
        for _ in 0..<6 {
            instant = Scrubbing.step(from: instant, marks: 1, of: 900, local: newYork)
            seen.append(T.wall(instant, "America/New_York") + " " + ZoneAbbreviation.display(for: newYork, at: instant))
        }
        #expect(seen == ["01:45 EDT", "01:00 EST", "01:15 EST", "01:30 EST", "01:45 EST", "02:00 EST"])
    }

    @Test func dayStepsKeepWallTimeAcrossDST() {
        let before = T.date("2026-03-07T14:00:00Z")  // Sat 09:00 EST
        let after = Scrubbing.step(from: before, days: 1, local: newYork)
        #expect(T.wall(after, "America/New_York") == "09:00")
        #expect(after.timeIntervalSince(before) == 23 * 3600)
    }

    @Test func dragSnapsToQuarterHoursAndRightIsLater() {
        let start = T.date("2026-11-03T15:07:00Z")
        let later = Scrubbing.drag(from: start, points: 20, local: newYork)  // +60 min raw → 11:07 → 11:00
        #expect(T.wall(later, "America/New_York") == "11:00")
        let earlier = Scrubbing.drag(from: start, points: -10, local: newYork)  // −30 → 9:37 → 9:30
        #expect(T.wall(earlier, "America/New_York") == "09:30")
    }

    @Test func deltaText() {
        let now = T.date("2026-11-03T15:07:00Z")
        #expect(Scrubbing.deltaText(from: now, to: now) == "Now")
        #expect(Scrubbing.deltaText(from: now, to: now.addingTimeInterval(3 * 3600 + 900)) == "+3 h 15 min")
        #expect(Scrubbing.deltaText(from: now, to: now.addingTimeInterval(-2700)) == "\u{2212}45 min")
        #expect(Scrubbing.deltaText(from: now, to: now.addingTimeInterval(26 * 3600)) == "+1 day 2 h")
        #expect(Scrubbing.deltaText(from: now, to: now.addingTimeInterval(24 * 3600 + 27 * 60)) == "+1 day")
        #expect(Scrubbing.deltaText(from: now, to: now.addingTimeInterval(-10 * 86_400)) == "\u{2212}10 days")
        #expect(Scrubbing.spokenDelta(10 * 86_400) == "10 days later")
        #expect(Scrubbing.spokenDelta(3 * 3600 + 900) == "3 hours 15 minutes later")
        #expect(Scrubbing.spokenDelta(-(86_400 + 7200)) == "1 day 2 hours earlier")
    }
}

@Suite struct TypedTimeTests {
    static let parseCases: [(String, Int, Int)] = [
        ("3pm", 15, 0), ("3 PM", 15, 0), ("3p", 15, 0), ("3 p.m.", 15, 0), ("3:30pm", 15, 30),
        ("3.30pm", 15, 30), ("15:30", 15, 30), ("1530", 15, 30), ("930", 9, 30), ("0930", 9, 30),
        ("9a", 9, 0), ("12am", 0, 0), ("12pm", 12, 0), ("12:15 am", 0, 15), ("noon", 12, 0),
        ("midnight", 0, 0), ("15h30", 15, 30), ("15h", 15, 0), ("7", 7, 0), ("19", 19, 0), ("0:05", 0, 5),
    ]

    @Test(arguments: parseCases)
    func parses(_ text: String, _ hour: Int, _ minute: Int) {
        #expect(TypedTime(parsing: text) == TypedTime(hour: hour, minute: minute))
    }

    @Test(arguments: ["", "pm", "25", "13pm", "0am", "3:7", "3:60", "abc", "12345", "3:30:00", "-3"])
    func rejects(_ text: String) {
        #expect(TypedTime(parsing: text) == nil)
    }

    @Test func resolvesOnTheShownDayInThatZone() {
        // It's Tue 10:00 in New York; "3pm" typed on London means Tue 3 pm London.
        let reference = T.date("2026-11-03T15:00:00Z")
        let result = TypedTime(hour: 15, minute: 0).resolve(in: T.zone("Europe/London"), onDayOf: reference)
        #expect(result.instant == T.date("2026-11-03T15:00:00Z"))
        #expect(!result.skippedGap && !result.wasAmbiguous)
        // Tokyo is already Wed 00:00 at that instant, so "9am" there is Wed 9 am Tokyo.
        let tokyo = TypedTime(hour: 9, minute: 0).resolve(in: T.zone("Asia/Tokyo"), onDayOf: reference)
        #expect(tokyo.instant == T.date("2026-11-04T00:00:00Z"))
    }

    @Test func springForwardGapMovesToTheNextValidTime() {
        let reference = T.date("2026-03-08T12:00:00Z")  // Mar 8, US change day
        let result = TypedTime(hour: 2, minute: 30).resolve(in: T.zone("America/New_York"), onDayOf: reference)
        #expect(result.skippedGap)
        #expect(result.instant == T.date("2026-03-08T07:00:00Z"))  // 03:00 EDT
    }

    @Test func fallBackAmbiguityPicksTheFirst() {
        let reference = T.date("2026-11-01T12:00:00Z")
        let result = TypedTime(hour: 1, minute: 30).resolve(in: T.zone("America/New_York"), onDayOf: reference)
        #expect(result.wasAmbiguous)
        #expect(result.instant == T.date("2026-11-01T05:30:00Z"))  // 01:30 EDT, not EST
    }

    @Test func halfHourZone() {
        let result = TypedTime(hour: 9, minute: 0).resolve(in: T.zone("Asia/Kathmandu"), onDayOf: T.date("2026-11-03T12:00:00Z"))
        #expect(result.instant == T.date("2026-11-03T03:15:00Z"))
    }
}
