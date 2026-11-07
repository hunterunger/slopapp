import Foundation
import Testing
@testable import AwakeCore

@Suite struct AwakeDurationTests {
    @Test func presetTitles() {
        #expect(AwakeDuration.presets.map(\.title) == [
            "Indefinitely", "10 Minutes", "30 Minutes", "1 Hour", "2 Hours", "4 Hours", "8 Hours", "12 Hours",
        ])
    }

    @Test func oddTitles() {
        #expect(AwakeDuration.minutes(1).title == "1 Minute")
        #expect(AwakeDuration.minutes(90).title == "1 hr 30 min")
        #expect(AwakeDuration.minutes(45).title == "45 Minutes")
    }

    @Test(arguments: [
        ("15m", 900.0), ("2h", 7200.0), ("90s", 90.0), ("30", 1800.0), (" 1.5h ", 5400.0), ("15M", 900.0),
    ])
    func parsesTimedValues(text: String, seconds: Double) {
        #expect(AwakeDuration(parsing: text)?.seconds == seconds)
    }

    @Test(arguments: ["forever", "ON", "indefinitely"])
    func parsesIndefinite(text: String) {
        #expect(AwakeDuration(parsing: text) == .indefinitely)
    }

    @Test(arguments: ["", "m", "-5m", "0", "abc", "5x", "inf"])
    func rejectsGarbage(text: String) {
        #expect(AwakeDuration(parsing: text) == nil)
    }

    @Test func presetIDsAreUnique() {
        #expect(Set(AwakeDuration.presets.map(\.id)).count == AwakeDuration.presets.count)
    }
}

@Suite struct NextOccurrenceTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func laterToday() {
        #expect(NextOccurrence.of(hour: 17, minute: 30, after: date(3, 9, 15), calendar: calendar) == date(3, 17, 30))
    }

    @Test func earlierMeansTomorrow() {
        #expect(NextOccurrence.of(hour: 8, minute: 0, after: date(3, 9, 15), calendar: calendar) == date(4, 8, 0))
    }

    @Test func theCurrentMinuteMeansTomorrow() {
        #expect(NextOccurrence.of(hour: 9, minute: 15, after: date(3, 9, 15), calendar: calendar) == date(4, 9, 15))
    }
}

@Suite struct RemainingTimeTests {
    @Test(arguments: [
        (0.0, "Less than a minute left"),
        (59.0, "Less than a minute left"),
        (60.0, "1 min left"),
        (61.0, "2 min left"),
        (900.0, "15 min left"),
        (850.0, "15 min left"),
        (3600.0, "1 hr left"),
        (3660.0, "1 hr 1 min left"),
        (14_400.0, "4 hr left"),
    ])
    func formats(seconds: Double, text: String) {
        #expect(RemainingTime.string(seconds) == text)
    }

    @Test(arguments: [
        (30.0, "<1m"), (60.0, "1m"), (2700.0, "45m"), (3600.0, "1h 00m"), (3900.0, "1h 05m"), (43_200.0, "12h 00m"),
    ])
    func compact(seconds: Double, text: String) {
        #expect(RemainingTime.compact(seconds) == text)
    }
}
