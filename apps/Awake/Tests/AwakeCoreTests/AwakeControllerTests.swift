import Foundation
import Testing
@testable import AwakeCore

@MainActor
@Suite struct AwakeControllerTests {
    let assertion = FakeAssertion()
    let scheduler = ManualScheduler()
    let defaults = UserDefaults(suiteName: "AwakeTests-\(UUID().uuidString)")!

    func makeController() -> AwakeController {
        AwakeController(assertion: assertion, scheduler: scheduler, defaults: defaults) { [scheduler] in
            scheduler.now
        }
    }

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
    }

    @Test func statusTextRefreshesWhileRunning() {
        let controller = makeController()
        controller.start(.hours(1))
        scheduler.advance(by: AwakeController.refreshInterval)
        #expect(controller.statusText == "1 hr left")
        scheduler.advance(by: AwakeController.refreshInterval)
        #expect(controller.statusText == "59 min left")
    }

    @Test func indefiniteSessionNeverExpires() {
        let controller = makeController()
        controller.start(.indefinitely)
        #expect(controller.statusText == "On until turned off")
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

    @Test func keepDisplayOnDefaultsToTrueAndPersists() {
        let controller = makeController()
        #expect(controller.keepDisplayOn)
        controller.keepDisplayOn = false
        #expect(makeController().keepDisplayOn == false)
    }

    @Test func togglingDisplayWhileActiveRetakesAssertion() {
        let controller = makeController()
        controller.start(.hours(1))
        #expect(assertion.keepDisplayOn == true)
        controller.keepDisplayOn = false
        #expect(assertion.keepDisplayOn == false)
        #expect(assertion.holdCount == 2)
    }

    @Test func togglingDisplayWhileIdleDoesNotTakeAssertion() {
        let controller = makeController()
        controller.keepDisplayOn = false
        #expect(!assertion.isHeld)
        #expect(assertion.holdCount == 0)
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
