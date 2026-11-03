import Foundation
import Testing
@testable import FocusCore

@Suite("Timer machine")
struct TimerMachineTests {
    let settings = TimerSettings()
    let late = 60.0

    func started(_ phase: Phase = .focus, settings: TimerSettings = TimerSettings(), at now: Date = t0) -> TimerMachine {
        var m = TimerMachine(calendar: utc)
        _ = m.start(phase, settings: settings, unit: 60, now: now)
        return m
    }

    @Test func startingFocusRunsForTheChosenLength() {
        let m = started()
        let run = try! #require(m.state.run)
        #expect(run.phase == .focus)
        #expect(run.endsAt == t0.addingTimeInterval(minutes(25)))
        #expect(run.remaining(at: t0.addingTimeInterval(minutes(7))) == minutes(18))
    }

    @Test func nothingHappensBeforeTheEnd() {
        var m = started()
        let events = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(24.9)), lateAfter: late)
        #expect(events.isEmpty)
        #expect(m.state.run?.phase == .focus)
    }

    @Test func endingFocusLogsItAndStartsTheBreak() {
        var m = started()
        let end = t0.addingTimeInterval(minutes(25))
        let events = m.advance(settings: settings, unit: 60, now: end.addingTimeInterval(0.3), lateAfter: late)
        let record = SessionRecord(startedAt: t0, endedAt: end, planned: minutes(25), focused: minutes(25), completed: true, label: nil)
        #expect(events == [
            .ended(.focus), .recorded(record), .started(.shortBreak),
            .alert(.focusDone(nextBreak: .shortBreak, breakStarted: true, late: false)),
        ])
        let run = try! #require(m.state.run)
        #expect(run.phase == .shortBreak)
        // The break is timed from when focus really ended, not from when we noticed.
        #expect(run.endsAt == end.addingTimeInterval(minutes(5)))
        #expect(m.state.cycleCount == 1)
    }

    @Test func withoutAutoStartTheBreakIsOffered() {
        var settings = self.settings
        settings.autoStartBreaks = false
        var m = started(settings: settings)
        let events = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(25)), lateAfter: late)
        #expect(m.state.run == nil)
        #expect(m.state.pendingBreak == .shortBreak)
        #expect(events.last == .alert(.focusDone(nextBreak: .shortBreak, breakStarted: false, late: false)))

        _ = m.startPendingBreak(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(26)))
        #expect(m.state.run?.phase == .shortBreak)
        #expect(m.state.pendingBreak == nil)
    }

    @Test func anOfferedBreakExpiresOvernight() {
        var settings = self.settings
        settings.autoStartBreaks = false
        var m = started(settings: settings)
        _ = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(25)), lateAfter: late)
        #expect(m.state.pendingBreak == .shortBreak)
        _ = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(300)), lateAfter: late)
        #expect(m.state.pendingBreak == .shortBreak, "still today")
        _ = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(86_400), lateAfter: late)
        #expect(m.state.pendingBreak == nil)
    }

    @Test func everyFourthSessionEarnsALongBreak() {
        var m = TimerMachine(calendar: utc)
        var now = t0
        var breaks: [Phase] = []
        for _ in 0..<5 {
            _ = m.start(.focus, settings: settings, unit: 60, now: now)
            now = now.addingTimeInterval(minutes(25))
            _ = m.advance(settings: settings, unit: 60, now: now, lateAfter: late)
            breaks.append(m.state.run!.phase)
            _ = m.stop(now: now)
        }
        #expect(breaks == [.shortBreak, .shortBreak, .shortBreak, .longBreak, .shortBreak])
        let longRun = Run(phase: .longBreak, length: settings.length(of: .longBreak), startedAt: t0)
        #expect(longRun.planned == minutes(15))
    }

    @Test func longBreaksCanBeTurnedOff() {
        var settings = self.settings
        settings.longBreakEvery = 0
        var m = TimerMachine(calendar: utc)
        var now = t0
        for _ in 0..<6 {
            _ = m.start(.focus, settings: settings, unit: 60, now: now)
            now = now.addingTimeInterval(minutes(25))
            _ = m.advance(settings: settings, unit: 60, now: now, lateAfter: late)
            #expect(m.state.run?.phase == .shortBreak)
        }
    }

    @Test func aNewDayStartsANewCycle() {
        var m = TimerMachine(state: TimerState(cycleCount: 3, cycleDay: utc.startOfDay(for: t0)), calendar: utc)
        let tomorrow = t0.addingTimeInterval(86_400)
        _ = m.start(.focus, settings: settings, unit: 60, now: tomorrow)
        _ = m.advance(settings: settings, unit: 60, now: tomorrow.addingTimeInterval(minutes(25)), lateAfter: late)
        #expect(m.state.run?.phase == .shortBreak)
        #expect(m.state.cycleCount == 1)
    }

    @Test func breakEndingGoesIdleByDefault() {
        var m = started(.shortBreak)
        let events = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(5)), lateAfter: late)
        #expect(events == [.ended(.shortBreak), .alert(.breakDone(focusStarted: false, late: false))])
        #expect(m.state.run == nil)
    }

    @Test func breakEndingCanStartTheNextSession() {
        var settings = self.settings
        settings.autoStartFocus = true
        var m = started(.shortBreak, settings: settings)
        let end = t0.addingTimeInterval(minutes(5))
        let events = m.advance(settings: settings, unit: 60, now: end, lateAfter: late)
        #expect(events.contains(.started(.focus)))
        #expect(m.state.run?.endsAt == end.addingTimeInterval(minutes(25)))
    }

    @Test func pausingFreezesTheTime() {
        var m = started()
        _ = m.pause(now: t0.addingTimeInterval(minutes(10)))
        let farLater = t0.addingTimeInterval(minutes(500))
        #expect(m.advance(settings: settings, unit: 60, now: farLater, lateAfter: late).isEmpty)
        #expect(m.state.run?.remaining(at: farLater) == minutes(15))
        _ = m.resume(now: farLater)
        #expect(m.state.run?.endsAt == farLater.addingTimeInterval(minutes(15)))
        #expect(m.state.run?.elapsed(at: farLater.addingTimeInterval(minutes(5))) == minutes(15))
    }

    @Test func stoppingEarlyLogsAnUncountedSession() {
        var m = started()
        let events = m.stop(now: t0.addingTimeInterval(minutes(10)))
        guard case .recorded(let record) = events.last else { Issue.record("no record"); return }
        #expect(record.focused == minutes(10))
        #expect(!record.counted)
        #expect(!record.completed)
        #expect(m.state.run == nil)
        #expect(m.state.cycleCount == 0)
    }

    @Test func stoppingAfterEightyPercentCounts() {
        var m = started()
        let events = m.stop(now: t0.addingTimeInterval(minutes(20)))
        guard case .recorded(let record) = events.last else { Issue.record("no record"); return }
        #expect(record.counted)
        #expect(m.state.cycleCount == 1)
    }

    @Test func stoppingABreakLogsNothing() {
        var m = started(.shortBreak)
        #expect(m.stop(now: t0.addingTimeInterval(minutes(1))) == [.ended(.shortBreak)])
    }

    @Test func addingTimeWorksRunningAndPaused() {
        var m = started()
        _ = m.extend(by: minutes(5), now: t0.addingTimeInterval(minutes(1)))
        #expect(m.state.run?.endsAt == t0.addingTimeInterval(minutes(30)))
        #expect(m.state.run?.planned == minutes(30))
        _ = m.pause(now: t0.addingTimeInterval(minutes(10)))
        _ = m.extend(by: minutes(5), now: t0.addingTimeInterval(minutes(11)))
        #expect(m.state.run?.pausedRemaining == minutes(25))
        #expect(m.state.run?.planned == minutes(35))
    }

    @Test func skipBreakStartsFocusRightAway() {
        var m = started(.shortBreak)
        let now = t0.addingTimeInterval(minutes(2))
        let events = m.skipBreak(settings: settings, unit: 60, now: now)
        #expect(events == [.ended(.shortBreak), .started(.focus)])
        #expect(m.state.run?.startedAt == now)
        // Skipping during focus does nothing.
        #expect(m.skipBreak(settings: settings, unit: 60, now: now).isEmpty)
    }

    @Test func startingWhatsAlreadyRunningDoesNothing() {
        var m = started()
        #expect(m.start(.focus, settings: settings, unit: 60, now: t0.addingTimeInterval(60)).isEmpty)
        #expect(m.state.run?.startedAt == t0)
    }

    @Test func labelsFollowTheSessionIntoTheLog() {
        var m = TimerMachine(calendar: utc)
        m.setLabel("  Write intro ")
        _ = m.start(.focus, settings: settings, unit: 60, now: t0)
        #expect(m.state.run?.label == "Write intro")
        let events = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(25)), lateAfter: late)
        #expect(events.contains { if case .recorded(let r) = $0 { r.label == "Write intro" } else { false } })
        #expect(m.state.run?.label == nil, "breaks have no label")
        m.setLabel("   ")
        #expect(m.state.label == nil)
    }

    // MARK: Sleep, relaunch and clock changes

    @Test func sleepingThroughTheEndCarriesOnWithTheBreak() {
        var m = started()
        let end = t0.addingTimeInterval(minutes(25))
        let wake = end.addingTimeInterval(minutes(3))
        let events = m.advance(settings: settings, unit: 60, now: wake, lateAfter: late)
        #expect(events.last == .alert(.focusDone(nextBreak: .shortBreak, breakStarted: true, late: true)))
        #expect(m.state.run?.phase == .shortBreak)
        #expect(m.state.run?.remaining(at: wake) == minutes(2))
        #expect(events.filter { if case .alert = $0 { true } else { false } }.count == 1)
    }

    @Test func sleepingThroughEverythingNeverInventsSessions() {
        var settings = self.settings
        settings.autoStartFocus = true
        var m = started(settings: settings)
        let wake = t0.addingTimeInterval(3600 * 8)
        let events = m.advance(settings: settings, unit: 60, now: wake, lateAfter: late)
        #expect(m.state.run == nil)
        #expect(events.filter { if case .recorded = $0 { true } else { false } }.count == 1)
        #expect(events.filter { if case .alert = $0 { true } else { false } }.count == 1)
        #expect(events.last == .alert(.focusDone(nextBreak: .shortBreak, breakStarted: false, late: true)))
        // And a second look finds nothing more.
        #expect(m.advance(settings: settings, unit: 60, now: wake.addingTimeInterval(1), lateAfter: late).isEmpty)
    }

    @Test func sleepingThroughABreakDoesntStartFocus() {
        var settings = self.settings
        settings.autoStartFocus = true
        var m = started(.shortBreak, settings: settings)
        let events = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(30)), lateAfter: late)
        #expect(m.state.run == nil)
        #expect(events.last == .alert(.breakDone(focusStarted: false, late: true)))
    }

    @Test func settingTheClockBackDoesntAddTime() {
        var m = started()
        let t = t0.addingTimeInterval(minutes(10))
        _ = m.advance(settings: settings, unit: 60, now: t, lateAfter: late)
        // The clock goes back two hours.
        let back = t.addingTimeInterval(-7200)
        _ = m.advance(settings: settings, unit: 60, now: back, lateAfter: late)
        let run = try! #require(m.state.run)
        #expect(run.remaining(at: back) == minutes(15))
        #expect(run.remaining(at: back) <= run.planned)
        _ = m.advance(settings: settings, unit: 60, now: back.addingTimeInterval(minutes(15)), lateAfter: late)
        #expect(m.state.run?.phase == .shortBreak)
    }

    @Test func remainingIsClampedEvenWithoutAdvancing() {
        let run = Run(phase: .focus, length: minutes(25), startedAt: t0)
        #expect(run.remaining(at: t0.addingTimeInterval(-3600)) == minutes(25))
        #expect(run.remaining(at: t0.addingTimeInterval(3600)) == 0)
    }

    @Test func aSessionCountsForTheDayItEnded() {
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 23, minute: 50))!
        var m = started(at: start)
        let events = m.advance(settings: settings, unit: 60, now: start.addingTimeInterval(minutes(25)), lateAfter: late)
        guard case .recorded(let record) = events[1] else { Issue.record("no record"); return }
        let nov4 = utc.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        #expect(DayStats.on(nov4, from: [record], calendar: utc).sessions == 1)
        #expect(DayStats.on(start, from: [record], calendar: utc).sessions == 0)
    }

    @Test func stateSurvivesEncoding() throws {
        var m = started()
        m.setLabel("Taxes")
        _ = m.pause(now: t0.addingTimeInterval(90))
        let data = try JSONEncoder().encode(m.state)
        #expect(try JSONDecoder().decode(TimerState.self, from: data) == m.state)
        #expect(try JSONDecoder().decode(TimerState.self, from: Data("{}".utf8)) == TimerState())
    }
}

@Suite("Settings and stats")
struct SettingsTests {
    @Test func missingKeysUseDefaults() throws {
        let s = try JSONDecoder().decode(TimerSettings.self, from: Data(#"{"focusMinutes": 50}"#.utf8))
        #expect(s.focusMinutes == 50)
        #expect(s.shortBreakMinutes == 5)
        #expect(s.autoStartBreaks)
        #expect(!s.showSeconds)
    }

    @Test func lengthsAreClamped() throws {
        let s = try JSONDecoder().decode(TimerSettings.self, from: Data(#"{"focusMinutes": 900, "shortBreakMinutes": 0, "longBreakEvery": 1}"#.utf8))
        #expect(s.focusMinutes == 180)
        #expect(s.shortBreakMinutes == 1)
        #expect(s.longBreakEvery == 2)
        #expect(TimerSettings(longBreakEvery: -3).clamped().longBreakEvery == 0)
    }

    @Test func defaultsMatchTheResearch() {
        let s = TimerSettings()
        #expect(s.focusMinutes == 25 && s.shortBreakMinutes == 5 && s.longBreakMinutes == 15)
        #expect(s.longBreakEvery == 4 && s.autoStartBreaks && !s.autoStartFocus && s.playSound && !s.runShortcuts)
    }

    @Test func todayCountsOnlyCountedSessionsButAllTime() {
        let r1 = SessionRecord(startedAt: t0, endedAt: t0.addingTimeInterval(minutes(25)), planned: minutes(25), focused: minutes(25), completed: true, label: nil)
        let r2 = SessionRecord(startedAt: t0, endedAt: t0.addingTimeInterval(minutes(40)), planned: minutes(25), focused: minutes(10), completed: false, label: nil)
        let yesterday = SessionRecord(startedAt: t0.addingTimeInterval(-86_400), endedAt: t0.addingTimeInterval(-86_000), planned: 60, focused: 60, completed: true, label: nil)
        let stats = DayStats.on(t0, from: [r1, r2, yesterday], calendar: utc)
        #expect(stats == DayStats(sessions: 1, focused: minutes(35)))
    }

    @Test func recordClampsFocusedTime() {
        let r = SessionRecord(startedAt: t0, endedAt: t0, planned: 100, focused: 500, completed: false, label: nil)
        #expect(r.focused == 100)
        let zero = SessionRecord(startedAt: t0, endedAt: t0, planned: 0, focused: 0, completed: false, label: nil)
        #expect(!zero.counted)
    }
}
