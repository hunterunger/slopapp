import Foundation
import Testing
@testable import FocusCore

@Suite("Text")
struct FormattingTests {
    @Test func menuBarMinutesRoundUp() {
        #expect(TimeText.menuBar(minutes(25), showSeconds: false) == "25m")
        #expect(TimeText.menuBar(minutes(24) + 1, showSeconds: false) == "25m")
        #expect(TimeText.menuBar(minutes(24), showSeconds: false) == "24m")
        #expect(TimeText.menuBar(20, showSeconds: false) == "1m")
        #expect(TimeText.menuBar(0, showSeconds: false) == "1m")
        #expect(TimeText.menuBar(minutes(90), showSeconds: false) == "90m")
    }

    @Test func menuBarSeconds() {
        #expect(TimeText.menuBar(minutes(25), showSeconds: true) == "25:00")
        #expect(TimeText.menuBar(minutes(17) + 41.2, showSeconds: true) == "17:42")
        #expect(TimeText.menuBar(9, showSeconds: true) == "0:09")
        #expect(TimeText.menuBar(minutes(65), showSeconds: true) == "1:05:00")
    }

    @Test func acceleratedUnitsReadTheSame() {
        // FOCUS_SECONDS_PER_MINUTE=1: a "minute" lasts one second.
        #expect(TimeText.menuBar(18, showSeconds: false, unit: 1) == "18m")
        #expect(TimeText.left(4.5, unit: 1) == "5 min left")
    }

    @Test func leftAndDurations() {
        #expect(TimeText.left(minutes(18)) == "18 min left")
        #expect(TimeText.left(minutes(65)) == "1 hr 5 min left")
        #expect(TimeText.left(5) == "1 min left")
        #expect(TimeText.duration(minutes: 60) == "1 hr")
        #expect(TimeText.duration(minutes: 75) == "1 hr 15 min")
        #expect(TimeText.duration(seconds: minutes(24.9)) == "24 min")
    }

    @Test func todayLine() {
        #expect(TimeText.today(DayStats()) == "Today: no sessions yet")
        #expect(TimeText.today(DayStats(sessions: 1, focused: minutes(25))) == "Today: 1 session · 25 min")
        #expect(TimeText.today(DayStats(sessions: 3, focused: minutes(75))) == "Today: 3 sessions · 1 hr 15 min")
        #expect(TimeText.today(DayStats(sessions: 0, focused: minutes(10))) == "Today: 0 sessions · 10 min")
    }

    @Test func headlines() {
        var state = TimerState()
        #expect(StatusText.headline(state: state, now: t0) == "Ready to focus")
        state.pendingBreak = .shortBreak
        #expect(StatusText.headline(state: state, now: t0) == "Session done · break next")
        state.pendingBreak = nil
        state.label = "Taxes"
        #expect(StatusText.headline(state: state, now: t0) == "Ready to focus · Taxes")
        state.label = nil
        state.run = Run(phase: .focus, length: minutes(25), startedAt: t0)
        #expect(StatusText.headline(state: state, now: t0.addingTimeInterval(minutes(7))) == "Focusing · 18 min left")
        state.run?.label = "Write intro"
        #expect(StatusText.headline(state: state, now: t0) == "Write intro · 25 min left")
        state.run?.pausedRemaining = minutes(10)
        #expect(StatusText.headline(state: state, now: t0) == "Paused · Write intro · 10 min left")
        state.run = Run(phase: .longBreak, length: minutes(15), startedAt: t0)
        #expect(StatusText.headline(state: state, now: t0) == "Long break · 15 min left")
    }

    @Test func voiceOverLabels() {
        var state = TimerState()
        #expect(StatusText.accessibilityLabel(state: state, now: t0) == "Focus timer, ready")
        state.run = Run(phase: .focus, length: minutes(25), startedAt: t0)
        #expect(StatusText.accessibilityLabel(state: state, now: t0.addingTimeInterval(minutes(7))) == "Focus timer, focusing, 18 minutes left")
        state.run = Run(phase: .shortBreak, length: 30, startedAt: t0)
        #expect(StatusText.accessibilityLabel(state: state, now: t0) == "Focus timer, on a short break, 1 minute left")
    }

    @Test func alertCopy() {
        let s = TimerSettings()
        let started = AlertContent.make(.focusDone(nextBreak: .shortBreak, breakStarted: true, late: false), settings: s)
        #expect(started == AlertContent(title: "Focus session done", body: "Your 5-minute break has started.", actions: [.skipBreak]))
        let offered = AlertContent.make(.focusDone(nextBreak: .longBreak, breakStarted: false, late: false), settings: s)
        #expect(offered.body == "Take a 15-minute long break when you're ready.")
        #expect(offered.actions == [.startBreak, .startFocus])
        #expect(offered.category == "startBreak+startFocus")
        let asleep = AlertContent.make(.focusDone(nextBreak: .shortBreak, breakStarted: false, late: true), settings: s)
        #expect(asleep.body == "It ended while your Mac was asleep.")
        let breakOver = AlertContent.make(.breakDone(focusStarted: false, late: false), settings: s)
        #expect(breakOver == AlertContent(title: "Break's over", body: "Start the next session when you're ready.", actions: [.startFocus]))
        let next = AlertContent.make(.breakDone(focusStarted: true, late: false), settings: s)
        #expect(next.actions.isEmpty && next.category == "plain")
        // House style: no exclamation marks anywhere.
        for alert in [Alert.focusDone(nextBreak: .shortBreak, breakStarted: true, late: true), .breakDone(focusStarted: false, late: true)] {
            #expect(!AlertContent.make(alert, settings: s).body.contains("!"))
        }
    }

    @Test func ticksLandWhenTheShownValueChanges() {
        // 25:00 left, minute display: next change at 24:00, 60 s away.
        #expect(TickPlanner.delay(remaining: minutes(25), granularity: 60) == 60)
        // 24:30 left: "25m" until 24:00, 30 s away.
        #expect(abs(TickPlanner.delay(remaining: minutes(24.5), granularity: 60) - 30) < 0.001)
        // Last 20 s: tick at the end.
        #expect(TickPlanner.delay(remaining: 20, granularity: 60) == 20)
        // Seconds display.
        #expect(abs(TickPlanner.delay(remaining: 10.25, granularity: 1) - 0.25) < 0.001)
        #expect(TickPlanner.delay(remaining: 0, granularity: 60) == 0)
    }
}
