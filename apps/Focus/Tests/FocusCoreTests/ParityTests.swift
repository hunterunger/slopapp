import Foundation
import Testing
@testable import FocusCore

// Features added in the parity pass: finish, −5, categories, notes, pauses, reflection,
// break screen, app hiding, history edits.

@Suite("Timer machine: parity")
struct MachineParityTests {
    let settings = TimerSettings()

    func started(_ settings: TimerSettings = TimerSettings(), category: String? = nil) -> TimerMachine {
        var m = TimerMachine(state: TimerState(label: "Draft", categoryID: category), calendar: utc)
        _ = m.start(.focus, settings: settings, unit: 60, now: t0)
        return m
    }

    @Test func finishCountsAndStartsTheBreakWithoutAnAlert() {
        var m = started()
        let events = m.finish(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(10)))
        guard case .recorded(let record) = events[1] else { Issue.record("no record"); return }
        #expect(record.completed && record.counted)
        #expect(record.focused == minutes(10))
        #expect(events.last == .started(.shortBreak))
        #expect(!events.contains { if case .alert = $0 { true } else { false } })
        #expect(m.state.cycleCount == 1)
    }

    @Test func finishOffersTheBreakWhenBreaksDontAutoStart() {
        var s = settings
        s.autoStartBreaks = false
        var m = started(s)
        _ = m.finish(settings: s, unit: 60, now: t0.addingTimeInterval(minutes(3)))
        #expect(m.state.run == nil)
        #expect(m.state.pendingBreak == .shortBreak)
        // Only focus sessions can be finished.
        _ = m.start(.shortBreak, settings: s, unit: 60, now: t0.addingTimeInterval(minutes(4)))
        #expect(m.finish(settings: s, unit: 60, now: t0.addingTimeInterval(minutes(5))).isEmpty)
    }

    @Test func shortenTakesTimeOffRunningAndPaused() {
        var m = started()
        _ = m.shorten(by: minutes(5), now: t0.addingTimeInterval(minutes(1)))
        #expect(m.state.run?.endsAt == t0.addingTimeInterval(minutes(20)))
        #expect(m.state.run?.planned == minutes(20))
        _ = m.pause(now: t0.addingTimeInterval(minutes(10)))
        _ = m.shorten(by: minutes(5), now: t0.addingTimeInterval(minutes(11)))
        #expect(m.state.run?.pausedRemaining == minutes(5))
        // Not when that would end it.
        #expect(m.shorten(by: minutes(5), now: t0.addingTimeInterval(minutes(12))).isEmpty)
        #expect(m.state.run?.pausedRemaining == minutes(5))
    }

    @Test func pausesAreAddedUpInTheRecord() {
        var m = started()
        _ = m.pause(now: t0.addingTimeInterval(minutes(5)))
        _ = m.resume(now: t0.addingTimeInterval(minutes(8)))
        _ = m.pause(now: t0.addingTimeInterval(minutes(10)))
        #expect(m.state.run?.paused(at: t0.addingTimeInterval(minutes(12))) == minutes(5))
        let events = m.stop(now: t0.addingTimeInterval(minutes(12)))
        guard case .recorded(let record) = events.last else { Issue.record("no record"); return }
        #expect(record.paused == minutes(5))
        #expect(record.focused == minutes(7))
    }

    @Test func categoryAndNotesFollowTheSessionIntoTheLog() {
        var m = started(category: "work")
        m.setNotes("Outline done")
        m.setCategory("study")
        let events = m.advance(settings: settings, unit: 60, now: t0.addingTimeInterval(minutes(25)), lateAfter: 60)
        guard case .recorded(let record) = events[1] else { Issue.record("no record"); return }
        #expect(record.categoryID == "study")
        #expect(record.notes == "Outline done")
        #expect(record.label == "Draft")
        // Breaks carry no category or notes; the choice stays for the next session.
        #expect(m.state.run?.categoryID == nil)
        #expect(m.state.categoryID == "study")
        m.setNotes("ignored on a break")
        #expect(m.state.run?.notes == nil)
    }

    @Test func filesWrittenBeforeThisVersionStillLoad() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldRecord = #"{"completed":true,"counted":true,"endedAt":"2026-11-03T10:25:00Z","focused":1500,"label":"Old","planned":1500,"startedAt":"2026-11-03T10:00:00Z"}"#
        let record = try decoder.decode(SessionRecord.self, from: Data(oldRecord.utf8))
        #expect(record.kind == .focus && record.mood == nil && !record.deleted && record.paused == 0)
        let again = try decoder.decode(SessionRecord.self, from: Data(oldRecord.utf8))
        #expect(record.id == again.id, "old lines get a stable id")
        let oldState = #"{"cycleCount":1,"label":"x","run":{"phase":"focus","planned":1500,"startedAt":"2026-11-03T10:00:00Z","endsAt":"2026-11-03T10:25:00Z","lastSeen":"2026-11-03T10:01:00Z"}}"#
        let state = try decoder.decode(TimerState.self, from: Data(oldState.utf8))
        #expect(state.run?.pausedTotal == 0)
        #expect(state.categoryID == nil && state.pendingReflection == nil)
        let oldSettings = #"{"focusMinutes":30}"#
        let s = try decoder.decode(TimerSettings.self, from: Data(oldSettings.utf8))
        #expect(s.categories == Category.defaults)
        #expect(s.askReflection && !s.breakScreen && !s.hideApps && s.dailyGoal == 8)
    }
}

@MainActor
@Suite("Controller: parity")
struct ControllerParityTests {
    @Test func aFinishedSessionAsksForAReflection() {
        let rig = Rig()
        rig.controller.setCategory("work")
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        let pending = rig.controller.pendingReflection
        #expect(pending?.categoryName == "Work")
        rig.controller.reflect(mood: .focused, notes: "  Shipped it \n")
        #expect(rig.controller.pendingReflection == nil)
        let saved = rig.storage.allRecords().first { $0.isFocus }
        #expect(saved?.mood == .focused)
        #expect(saved?.notes == "Shipped it")
        #expect(rig.storage.allRecords().filter(\.isFocus).count == 1, "the amended line replaces the first")
        #expect(rig.storage.state?.pendingReflection == nil, "persisted")
    }

    @Test func reflectionIsSkippedForShortSessionsAndWhenOff() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: 30)
        rig.controller.stop()
        #expect(rig.controller.pendingReflection == nil)

        let off = Rig(settings: TimerSettings(askReflection: false))
        off.controller.startFocus()
        off.scheduler.advance(by: minutes(25))
        #expect(off.controller.pendingReflection == nil)
    }

    @Test func theNextSessionClearsAnUnansweredReflection() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.controller.pendingReflection != nil)
        rig.controller.skipBreak()
        #expect(rig.controller.pendingReflection == nil)
        #expect(rig.storage.allRecords().first?.mood == nil)
    }

    @Test func reflectionSurvivesRelaunch() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        let again = rig.relaunched()
        #expect(again.controller.pendingReflection != nil)
        again.controller.skipReflection()
        #expect(again.controller.pendingReflection == nil)
    }

    @Test func typedIntentionSetsCategoryAndOneOffLength() {
        let rig = Rig()
        rig.controller.startFocus(intention: "Draft intro @stu 45m")
        #expect(rig.controller.label == "Draft intro")
        #expect(rig.controller.categoryID == "study")
        #expect(rig.controller.menuBarText == "45m")
        #expect(rig.controller.settings.focusMinutes == 25, "the default length doesn't change")
        rig.controller.stop()
        rig.controller.startFocus(intention: "")
        #expect(rig.controller.label == nil)
        #expect(rig.controller.categoryID == "study", "the category stays until changed")
    }

    @Test func finishAndRemoveTime() {
        let rig = Rig()
        rig.controller.startFocus()
        #expect(rig.controller.canRemoveTime)
        rig.controller.removeTime()
        #expect(rig.controller.menuBarText == "20m")
        rig.controller.finish()
        #expect(rig.controller.runningPhase == .shortBreak)
        #expect(rig.controller.today.sessions == 1)
        #expect(rig.notifier.posted.isEmpty, "finishing yourself isn't announced")
    }

    @Test func categoriesCanBeAddedRenamedMovedAndDeleted() {
        let rig = Rig()
        let a = rig.controller.addCategory(name: "Work", color: .red)
        #expect(a.name == "Work 2")
        var renamed = a
        renamed.name = "  "
        rig.controller.updateCategory(renamed)
        #expect(rig.controller.settings.categories.last?.name == "Work 2", "blank names are ignored")
        renamed.name = "Reading"
        renamed.color = .orange
        rig.controller.updateCategory(renamed)
        #expect(rig.controller.settings.categories.last == Category(id: a.id, name: "Reading", color: .orange))
        rig.controller.moveCategories(from: IndexSet(integer: 3), to: 0)
        #expect(rig.controller.settings.categories.map(\.name) == ["Reading", "Work", "Study", "Personal"])
        rig.controller.setCategory(a.id)
        rig.controller.deleteCategory(id: a.id)
        #expect(rig.controller.categoryID == nil)
        #expect(rig.storage.settings?.categories.count == 3)
    }

    @Test func aDeletedCategoryKeepsItsNameInTheLog() {
        let rig = Rig()
        rig.controller.setCategory("work")
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        rig.controller.deleteCategory(id: "work")
        let report = StatsReport.make(range: .containing(t0, period: .day, calendar: utc), records: rig.storage.allRecords(),
                                      categories: rig.controller.settings.categories, now: rig.scheduler.now, calendar: utc)
        #expect(report.categories.first?.name == "Work")
    }

    @Test func breakScreenShowsDuringBreaksUntilDismissed() {
        let rig = Rig(settings: TimerSettings(breakScreen: true))
        rig.controller.startFocus()
        #expect(!rig.controller.showsBreakScreen)
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.controller.showsBreakScreen)
        rig.controller.dismissBreakScreen()
        #expect(!rig.controller.showsBreakScreen)
        rig.scheduler.advance(by: minutes(5))
        rig.controller.startFocus()
        rig.controller.finish()
        #expect(rig.controller.showsBreakScreen, "the next break shows it again")

        let off = Rig()
        off.controller.startBreak()
        #expect(!off.controller.showsBreakScreen)
    }

    @Test func appsAreHiddenOnlyWhileFocusing() {
        let apps = [BlockedApp(bundleID: "com.example.chat", name: "Chat")]
        let rig = Rig(settings: TimerSettings(hideApps: true, blockedApps: apps))
        #expect(rig.blocker.calls.isEmpty)
        rig.controller.startFocus()
        #expect(rig.blocker.current == ["com.example.chat"])
        rig.controller.pause()
        #expect(rig.blocker.current == nil)
        rig.controller.resume()
        #expect(rig.blocker.current == ["com.example.chat"])
        rig.scheduler.advance(by: minutes(25))
        #expect(rig.blocker.current == nil, "not on a break")
        rig.controller.skipBreak()
        #expect(rig.blocker.current == ["com.example.chat"])
        rig.controller.updateSettings { $0.hideApps = false }
        #expect(rig.blocker.current == nil)
        let calls = rig.blocker.calls.count
        rig.controller.refresh()
        #expect(rig.blocker.calls.count == calls, "no repeat calls when nothing changed")
    }

    @Test func blockedAppsListIsSortedAndDeduplicated() {
        let rig = Rig()
        rig.controller.addBlockedApp(BlockedApp(bundleID: "b", name: "Zed"))
        rig.controller.addBlockedApp(BlockedApp(bundleID: "a", name: "alpha"))
        rig.controller.addBlockedApp(BlockedApp(bundleID: "b", name: "Zed"))
        #expect(rig.controller.settings.blockedApps.map(\.bundleID) == ["a", "b"])
        rig.controller.removeBlockedApp(bundleID: "a")
        #expect(rig.controller.settings.blockedApps.map(\.bundleID) == ["b"])
    }

    @Test func deletingAndEditingHistoryUpdatesToday() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(25))
        rig.controller.skipReflection()
        let version = rig.controller.historyVersion
        guard var record = rig.controller.todayRecords.first(where: \.isFocus) else { Issue.record("no record"); return }
        record.label = "Renamed"
        rig.controller.update(record)
        #expect(rig.controller.history().first { $0.isFocus }?.label == "Renamed")
        #expect(rig.controller.historyVersion > version)
        rig.controller.delete(record)
        #expect(rig.controller.today.sessions == 0)
        #expect(rig.controller.history().filter(\.isFocus).isEmpty)
        #expect(rig.relaunched().controller.today.sessions == 0, "the delete survives relaunch")
    }

    @Test func suggestionsComeFromPastIntentions() {
        let rig = Rig()
        for label in ["Write intro", "Email", "Rewrite outline", "Write intro"] {
            rig.controller.startFocus(intention: label)
            rig.scheduler.advance(by: minutes(1))
            rig.controller.stop()
        }
        #expect(rig.controller.suggestions(for: "wri").map(\.text) == ["Write intro", "Rewrite outline"])
        #expect(rig.controller.suggestions(for: "").map(\.text) == ["Write intro", "Rewrite outline", "Email"])
    }

    @Test func todayListsSessionsAndBreaksNewestFirst() {
        let rig = Rig()
        rig.controller.startFocus()
        rig.scheduler.advance(by: minutes(30))
        #expect(rig.controller.todayRecords.map(\.kind) == [.shortBreak, .focus])
        #expect(rig.controller.today.focused == minutes(25), "breaks don't add to focused time")
    }
}
