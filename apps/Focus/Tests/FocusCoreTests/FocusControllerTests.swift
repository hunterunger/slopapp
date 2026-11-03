import Foundation
import Testing
@testable import FocusCore

@MainActor
@Suite("Controller")
struct FocusControllerTests {
    @Test func idleHasNoTimersAtAll() {
        let rig = Rig()
        #expect(rig.controller.menuBarText == nil)
        #expect(rig.scheduler.pendingCount == 0)
        #expect(!rig.activity.isActive)
        #expect(rig.controller.headline == "Ready to focus")
        #expect(rig.controller.todayText == "Today: no sessions yet")
    }

    @Test func countdownUpdatesOncePerMinute() {
        let rig = Rig()
        rig.controller.startFocus()
        #expect(rig.controller.menuBarText == "25m")
        #expect(rig.activity.isActive)
        rig.scheduler.advance(by: 59)
        #expect(rig.controller.menuBarText == "25m")
        rig.scheduler.advance(by: 1)
        #expect(rig.controller.menuBarText == "24m")
        let before = rig.scheduler.scheduledCount
        rig.scheduler.advance(by: minutes(10))
        // One look at the clock per minute, no more.
        #expect(rig.scheduler.scheduledCount - before == 10)
        #expect(rig.controller.headline == "Focusing · 14 min left")
        #expect(rig.storage.stateSaves == 1, "ticks don't rewrite the state file")
    }

    @Test func showSecondsTicksEverySecond() {
        let rig = Rig(settings: TimerSettings(showSeconds: true))
        rig.controller.startFocus()
        #expect(rig.controller.menuBarText == "25:00")
        let before = rig.scheduler.scheduledCount
        rig.scheduler.advance(by: 10)
        #expect(rig.scheduler.scheduledCount - before == 10)
        #expect(rig.controller.menuBarText == "24:50")
        rig.controller.updateSettings { $0.showSeconds = false }
        #expect(rig.controller.menuBarText == "25m")
    }

    @Test func aFullSessionNotifiesPlaysAndStartsTheBreak() async {
        let rig = Rig()
        await rig.controller.refreshPermission()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.notifier.posted == [AlertContent(title: "Focus session done", body: "Your 5-minute break has started.", actions: [.skipBreak])])
        #expect(rig.sound.played == ["Glass"])
        #expect(rig.controller.runningPhase == .shortBreak)
        #expect(rig.controller.menuBarText == "5m")
        #expect(rig.controller.todayText == "Today: 1 session · 25 min")
        #expect(rig.storage.history.count == 1)
        rig.scheduler.advance(by: minutes(5))
        #expect(rig.notifier.posted.last?.title == "Break's over")
        #expect(rig.controller.isIdle)
        #expect(rig.controller.menuBarText == nil)
        #expect(rig.scheduler.pendingCount == 0)
        #expect(!rig.activity.isActive)
    }

    @Test func pauseStopsTheClockAndTheTimer() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(5))
        rig.controller.pause()
        #expect(rig.scheduler.pendingCount == 0)
        #expect(rig.controller.headline == "Paused · Focusing · 20 min left")
        rig.scheduler.advance(by: minutes(60))
        rig.controller.togglePause()
        #expect(rig.controller.menuBarText == "20m")
        rig.scheduler.advance(by: minutes(20))
        #expect(rig.controller.runningPhase == .shortBreak)
    }

    @Test func stopLogsWithoutAnnouncing() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(21))
        rig.controller.stop()
        #expect(rig.controller.isIdle)
        #expect(rig.notifier.posted.isEmpty)
        #expect(rig.sound.played.isEmpty)
        #expect(rig.controller.todayText == "Today: 1 session · 21 min")
    }

    @Test func addTimeExtendsTheCountdown() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.controller.addTime()
        #expect(rig.controller.menuBarText == "30m")
        rig.scheduler.advance(by: minutes(29))
        #expect(rig.controller.runningPhase == .focus)
        rig.scheduler.advance(by: minutes(1))
        #expect(rig.controller.runningPhase == .shortBreak)
    }

    // MARK: Sleep and relaunch

    @Test func wakingAfterTheEndAnnouncesOnceWithoutSound() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(10))
        // The Mac sleeps for an hour: no timers fire.
        rig.scheduler.jump(by: minutes(60))
        rig.controller.refresh()
        #expect(rig.notifier.posted.count == 1)
        #expect(rig.notifier.posted.first?.body == "It ended while your Mac was asleep.")
        #expect(rig.sound.played.isEmpty)
        #expect(rig.controller.isIdle)
        #expect(rig.storage.history.count == 1)
        // A late timer firing afterwards changes nothing.
        rig.scheduler.advance(by: minutes(30))
        rig.controller.refresh()
        #expect(rig.notifier.posted.count == 1)
    }

    @Test func wakingMidSessionJustCatchesUp() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.jump(by: minutes(12))
        rig.controller.refresh()
        #expect(rig.controller.menuBarText == "13m")
        #expect(rig.notifier.posted.isEmpty)
        rig.scheduler.advance(by: minutes(13))
        #expect(rig.notifier.posted.count == 1)
        #expect(rig.sound.played.count == 1)
    }

    @Test func relaunchingMidSessionResumes() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(7))
        let again = rig.relaunched()
        #expect(again.controller.runningPhase == .focus)
        #expect(again.controller.menuBarText == "18m")
        again.scheduler.advance(by: minutes(18))
        #expect(again.controller.runningPhase == .shortBreak)
        #expect(again.notifier.posted.count == 1)
    }

    @Test func relaunchingPausedStaysPaused() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(3))
        rig.controller.pause()
        rig.scheduler.jump(by: 3600)
        let again = rig.relaunched()
        #expect(again.controller.isPaused)
        #expect(again.controller.headline == "Paused · Focusing · 22 min left")
    }

    @Test func relaunchingAfterTheEndLogsQuietly() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.jump(by: minutes(90))
        let again = rig.relaunched()
        #expect(again.controller.isIdle)
        #expect(again.notifier.posted.isEmpty)
        #expect(again.sound.played.isEmpty)
        #expect(again.storage.history.count == 1)
        #expect(again.controller.todayText == "Today: 1 session · 25 min")
    }

    @Test func historyFromEarlierTodayIsLoaded() {
        let storage = MemoryStorage(history: [
            SessionRecord(startedAt: t0.addingTimeInterval(-7200), endedAt: t0.addingTimeInterval(-5700), planned: 1500, focused: 1500, completed: true, label: nil),
            SessionRecord(startedAt: t0.addingTimeInterval(-90_000), endedAt: t0.addingTimeInterval(-88_500), planned: 1500, focused: 1500, completed: true, label: nil),
        ])
        let rig = Rig(storage: storage)
        #expect(rig.controller.todayText == "Today: 1 session · 25 min")
    }

    @Test func theCountResetsAtMidnight() {
        let late = utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 23, minute: 0))!
        let rig = Rig(scheduler: ManualScheduler(now: late))
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        rig.controller.stop()
        #expect(rig.controller.todayText == "Today: 1 session · 25 min")
        rig.scheduler.jump(by: minutes(60))
        rig.controller.refresh()
        #expect(rig.controller.todayText == "Today: no sessions yet")
    }

    // MARK: Notifications

    @Test func permissionIsAskedOnFirstStartOnly() async {
        let rig = Rig(permission: .notDetermined)
        #expect(rig.notifier.requests == 0)
        rig.controller.startFocus()
        await Task.yield(); await Task.yield(); await Task.yield()
        #expect(rig.notifier.requests == 1)
        #expect(rig.controller.permission == .denied)
        rig.controller.stop()
        rig.controller.startFocus()
        await Task.yield(); await Task.yield()
        #expect(rig.notifier.requests == 1)
    }

    @Test func deniedIsAskedAgainOncePerLaunch() async {
        // macOS reports "denied" while its prompt is unanswered; asking again re-shows an
        // unanswered prompt and does nothing after a real "Don't Allow".
        let rig = Rig(permission: .denied)
        rig.controller.startFocus()
        await Task.yield(); await Task.yield(); await Task.yield()
        #expect(rig.notifier.requests == 1)
        rig.controller.stop()
        rig.controller.startFocus()
        await Task.yield(); await Task.yield()
        #expect(rig.notifier.requests == 1)
    }

    @Test func allowedIsNeverAskedAgain() async {
        let rig = Rig(permission: .authorized)
        rig.controller.startFocus()
        await Task.yield(); await Task.yield(); await Task.yield()
        #expect(rig.notifier.requests == 0)
    }

    @Test func startingANewPhaseClearsOldNotifications() async {
        let rig = Rig()
        rig.controller.startFocus()
        #expect(rig.notifier.clears == 1)
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.notifier.clears == 2, "the break started")
        rig.scheduler.advance(by: minutes(5))
        #expect(rig.notifier.posted.last?.title == "Break's over")
        #expect(rig.notifier.clears == 2, "ending doesn't clear the notification it just posted")
    }

    @Test func deniedNotificationsBlinkTheIcon() async {
        let rig = Rig(permission: .denied)
        await rig.controller.refreshPermission()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.controller.isFlashing)
        #expect(rig.sound.played == ["Glass"], "the sound still plays")
        rig.scheduler.advance(by: 0.5)
        #expect(!rig.controller.isFlashing)
        rig.scheduler.advance(by: 3)
        #expect(!rig.controller.isFlashing)
        #expect(rig.scheduler.pendingCount == 1, "only the break's tick is left")
    }

    @Test func reduceMotionMeansNoBlink() async {
        let rig = Rig(permission: .denied, reduceMotion: true)
        await rig.controller.refreshPermission()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(!rig.controller.isFlashing)
        #expect(rig.controller.menuBarText == "5m", "the text change is the cue")
    }

    @Test func allowedNotificationsDontBlink() async {
        let rig = Rig(permission: .authorized)
        await rig.controller.refreshPermission()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(!rig.controller.isFlashing)
    }

    @Test func soundCanBeTurnedOff() {
        let rig = Rig(settings: TimerSettings(playSound: false))
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.sound.played.isEmpty)
        #expect(rig.notifier.posted.count == 1)
    }

    @Test func notificationButtonsWork() {
        let rig = Rig(settings: TimerSettings(autoStartBreaks: false))
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.controller.headline == "Session done · break next")
        rig.notifier.press(.startBreak)
        #expect(rig.controller.runningPhase == .shortBreak)
        rig.notifier.press(.skipBreak)
        #expect(rig.controller.runningPhase == .focus)
        // Pressing a stale button again changes nothing.
        rig.notifier.press(.startFocus)
        #expect(rig.controller.runningPhase == .focus)
        rig.notifier.press(.startBreak)
        #expect(rig.controller.runningPhase == .focus)
    }

    @Test func globalShortcutStartsPausesResumes() {
        let rig = Rig()
        rig.controller.primaryAction()
        #expect(rig.controller.runningPhase == .focus)
        rig.controller.primaryAction()
        #expect(rig.controller.isPaused)
        rig.controller.primaryAction()
        #expect(!rig.controller.isPaused)
    }

    // MARK: Shortcuts app

    @Test func shortcutsRunInOrderAtStartAndEnd() async {
        let rig = Rig(settings: TimerSettings(runShortcuts: true, startShortcut: "Focus On", endShortcut: "Focus Off"))
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        await rig.controller.waitForShortcuts()
        #expect(await rig.shortcuts.runs == ["Focus On", "Focus Off"])
        // A break ending runs nothing.
        rig.scheduler.advance(by: minutes(5))
        await rig.controller.waitForShortcuts()
        #expect(await rig.shortcuts.runs.count == 2)
    }

    @Test func shortcutsAreOffByDefault() async {
        let rig = Rig(settings: TimerSettings(startShortcut: "Focus On", endShortcut: "Focus Off"))
        rig.controller.startFocus()
        rig.controller.stop()
        await rig.controller.waitForShortcuts()
        #expect(await rig.shortcuts.runs.isEmpty)
    }

    @Test func aFailingShortcutShowsOneLineAndTheTimerCarriesOn() async {
        let shortcuts = FakeShortcuts()
        await shortcuts.setFailing(["Focus On"])
        let rig = Rig(settings: TimerSettings(runShortcuts: true, startShortcut: "Focus On"), shortcuts: shortcuts)
        rig.controller.startFocus()
        await rig.controller.waitForShortcuts()
        #expect(rig.controller.automationError == "Couldn't run “Focus On”. Check it in the Shortcuts app.")
        #expect(rig.controller.runningPhase == .focus)
        #expect(await rig.controller.testShortcut("Focus Off") == nil)
        #expect(rig.controller.automationError == nil)
    }

    @Test func wakingAfterTheEndStillRunsTheEndShortcut() async {
        let rig = Rig(settings: TimerSettings(runShortcuts: true, endShortcut: "Focus Off"))
        rig.controller.startFocus()
        rig.scheduler.jump(by: minutes(120))
        rig.controller.refresh()
        await rig.controller.waitForShortcuts()
        #expect(await rig.shortcuts.runs == ["Focus Off"])
    }

    // MARK: Settings and storage

    @Test func settingsAreClampedAndSaved() {
        let rig = Rig()
        rig.controller.updateSettings { $0.focusMinutes = 500 }
        #expect(rig.controller.settings.focusMinutes == 180)
        #expect(rig.storage.settings?.focusMinutes == 180)
        rig.controller.updateSettings { $0.focusMinutes = 45 }
        rig.controller.startFocus()
        #expect(rig.controller.menuBarText == "45m")
    }

    @Test func aFailedSaveIsReported() {
        let storage = MemoryStorage()
        storage.failWrites = true
        let rig = Rig(storage: storage)
        rig.controller.startFocus()
        #expect(rig.controller.saveError != nil)
        #expect(rig.controller.runningPhase == .focus, "the timer still works")
    }

    @Test func labelShowsInTheHeadline() {
        let rig = Rig()
        rig.controller.setLabel("Write intro")
        rig.controller.startFocus()
        #expect(rig.controller.headline == "Write intro · 25 min left")
        rig.controller.setLabel(nil)
        #expect(rig.controller.headline == "Focusing · 25 min left")
    }

    @Test func acceleratedUnitForScriptedTests() {
        let s = ManualScheduler()
        let storage = MemoryStorage()
        let controller = FocusController(
            storage: storage, notifier: FakeNotifier(), sound: FakeSound(), shortcuts: FakeShortcuts(),
            scheduler: s, activity: FakeActivity(), clock: { s.now }, calendar: utc, unit: 1
        )
        controller.startFocus()
        #expect(controller.menuBarText == "25m")
        s.advance(by: 25)
        #expect(controller.runningPhase == .shortBreak)
        #expect(controller.todayText == "Today: 1 session · 25 min")
    }
}
