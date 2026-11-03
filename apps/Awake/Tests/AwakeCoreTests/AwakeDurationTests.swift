import Testing
@testable import AwakeCore

@Suite struct AwakeDurationTests {
    @Test func presetTitles() {
        #expect(AwakeDuration.presets.map(\.title) == [
            "15 Minutes", "1 Hour", "2 Hours", "4 Hours", "Until Turned Off",
        ])
    }

    @Test func oddTitles() {
        #expect(AwakeDuration.minutes(1).title == "1 Minute")
        #expect(AwakeDuration.minutes(90).title == "1 hr 30 min")
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
}
