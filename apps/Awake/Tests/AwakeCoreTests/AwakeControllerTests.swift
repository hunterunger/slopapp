import Foundation
import Testing
@testable import AwakeCore

@MainActor
@Suite struct AwakeControllerTests {
    let assertion = FakeAssertion()
    let scheduler = ManualScheduler()
    let system = FakeSystem()
    let store = TestDefaults()
    var defaults: UserDefaults { store.defaults }

    func makeController() -> AwakeController {
        AwakeController(
            assertion: assertion, scheduler: scheduler,
            preferences: AwakePreferences(defaults: defaults), monitors: system.monitors,
            clock: { [scheduler] in scheduler.now },
            timeText: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                return String(format: "%02d:%02d", parts.hour!, parts.minute!)
            }
        )
    }

    // MARK: Sessions

    @Test func startsIdle() {
        let controller = makeController()
        #expect(!controller.isActive)
        #expect(controller.statusText == nil)
        #expect(!assertion.isHeld)
    }

    @Test func timedSessionHoldsThenExpires() {
        let controller = makeController()
        controller.start(.minutes(15))
        #expect(controller.isActive)
        #expect(assertion.isHeld)
        #expect(controller.statusText == "15 min left")

        scheduler.advance(by: 10 * 60)
        #expect(controller.isActive)
        #expect(controller.statusText == "5 min left")

        scheduler.advance(by: 5 * 60)
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
        #expect(scheduler.pendingCount == 0)
        #expect(controller.statusText == nil, "a session that simply ran out needs no explanation")
    }

    @Test func statusTextRefreshesWhileRunning() {
        let controller = makeController()
        controller.start(.hours(1))
        scheduler.advance(by: AwakeController.refreshInterval)
        #expect(controller.statusText == "1 hr left")
        scheduler.advance(by: AwakeController.refreshInterval)
        #expect(controller.statusText == "59 min left")
        #expect(controller.menuBarText == "59m")
    }

    @Test func indefiniteSessionNeverExpires() {
        let controller = makeController()
        controller.start(.indefinitely)
        #expect(controller.statusText == "On until turned off")
        #expect(controller.menuBarText == nil)
        #expect(scheduler.pendingCount == 0)
        scheduler.advance(by: 30 * 24 * 3600)
        #expect(controller.isActive)
        #expect(assertion.isHeld)
    }

    @Test func stopReleasesAndCancels() {
        let controller = makeController()
        controller.start(.hours(2))
        controller.stop()
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func restartingReplacesTheSession() {
        let controller = makeController()
        controller.start(.minutes(15))
        scheduler.advance(by: 10 * 60)
        controller.start(.hours(1))
        scheduler.advance(by: 10 * 60)
        #expect(controller.isActive, "the old 15-minute timer must not end the new session")
        #expect(controller.session?.duration == .hours(1))
        #expect(scheduler.pendingCount == 1)
    }

    @Test func refreshAfterSleepEndsExpiredSession() {
        let controller = makeController()
        controller.start(.minutes(15))
        scheduler.jump(by: 2 * 3600) // Mac slept; no timers fired
        controller.refresh()
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
    }

    @Test func toggleUsesTheDefaultDuration() {
        let controller = makeController()
        controller.preferences.defaultDuration = .hours(2)
        controller.toggle()
        #expect(controller.session?.duration == .hours(2))
        controller.toggle()
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
    }

    @Test func toggleDefaultsToIndefinitely() {
        let controller = makeController()
        controller.toggle()
        #expect(controller.session?.duration == .indefinitely)
    }

    @Test func untilSessionEndsAtTheTime() {
        let controller = makeController()
        let end = scheduler.now.addingTimeInterval(90 * 60)
        controller.start(.until(end))
        #expect(controller.isActive)
        #expect(controller.statusText?.hasPrefix("On until ") == true)
        #expect(controller.statusText?.hasSuffix(", 1 hr 30 min left") == true)
        scheduler.advance(by: 90 * 60)
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
    }

    @Test func confirmationTextSaysWhatTheShortcutDid() {
        let controller = makeController()
        #expect(controller.confirmationText == "Awake is off")
        controller.start(.indefinitely)
        #expect(controller.confirmationText == "Awake is on")
        // 1_000_000 s after the epoch is 13:46:40 UTC; plus 2 hours.
        controller.start(.hours(2))
        #expect(controller.confirmationText == "Awake is on until 15:46")
        controller.start(.until(scheduler.now.addingTimeInterval(30 * 60)))
        #expect(controller.confirmationText == "Awake is on until 14:16")
        system.apps.send([FakeSystem.xcode])
        controller.start(.whileRunning(FakeSystem.xcode))
        #expect(controller.confirmationText == "Awake is on while Xcode is running")
        controller.stop()
        #expect(controller.confirmationText == "Awake is off")
    }

    @Test func untilAPastTimeIsIgnored() {
        let controller = makeController()
        controller.start(.until(scheduler.now.addingTimeInterval(-60)))
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
    }

    @Test func extendAddsThirtyMinutes() {
        let controller = makeController()
        controller.start(.minutes(10))
        controller.extend()
        #expect(controller.statusText == "40 min left")
        scheduler.advance(by: 15 * 60)
        #expect(controller.isActive)
    }

    @Test func extendDoesNothingForOpenEndedSessions() {
        let controller = makeController()
        controller.start(.indefinitely)
        controller.extend()
        #expect(controller.session?.endsAt == nil)
    }

    // MARK: While an app is running

    @Test func whileRunningEndsWhenTheAppQuits() {
        system.apps.send([FakeSystem.xcode, FakeSystem.keynote])
        let controller = makeController()
        controller.start(.whileRunning(FakeSystem.xcode))
        #expect(controller.statusText == "On while Xcode is running")
        #expect(assertion.isHeld)
        #expect(scheduler.pendingCount == 0)

        system.apps.send([FakeSystem.keynote])
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
        #expect(controller.lastEnd == .appQuit("Xcode"))
        #expect(controller.statusText == "Turned off: Xcode quit")

        controller.start(.minutes(10))
        #expect(controller.lastEnd == nil, "a new session clears the old reason")
    }

    @Test func whileRunningAnAppThatIsGoneEndsImmediately() {
        let controller = makeController()
        controller.start(.whileRunning(FakeSystem.xcode))
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
    }

    // MARK: Display option

    @Test func togglingDisplayWhileActiveRetakesAssertion() {
        let controller = makeController()
        controller.start(.hours(1))
        #expect(assertion.keepDisplayOn == true)
        controller.preferences.keepDisplayOn = false
        #expect(assertion.keepDisplayOn == false)
        #expect(assertion.holdCount == 2)
    }

    @Test func togglingDisplayWhileIdleDoesNotTakeAssertion() {
        let controller = makeController()
        controller.preferences.keepDisplayOn = false
        #expect(!assertion.isHeld)
        #expect(assertion.holdCount == 0)
    }

    @Test func monitorChangesDoNotRetakeAHeldAssertion() {
        let controller = makeController()
        controller.start(.hours(1))
        system.displays.send(1)
        system.apps.send([FakeSystem.keynote])
        #expect(assertion.holdCount == 1)
        #expect(controller.isActive)
    }

    @Test func failedAssertionReportsErrorAndStaysIdle() {
        let controller = makeController()
        assertion.failNextHold = true
        controller.start(.hours(1))
        #expect(!controller.isActive)
        #expect(controller.lastError != nil)
        #expect(scheduler.pendingCount == 0)

        controller.start(.hours(1))
        #expect(controller.isActive)
        #expect(controller.lastError == nil)
    }
}
