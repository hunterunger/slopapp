import Foundation
import Testing
@testable import AwakeCore

@MainActor
@Suite struct TriggerTests {
    let assertion = FakeAssertion()
    let scheduler = ManualScheduler()
    let system = FakeSystem()
    let store = TestDefaults()
    var defaults: UserDefaults { store.defaults }

    func makeController(_ configure: (AwakePreferences) -> Void = { _ in }) -> AwakeController {
        let preferences = AwakePreferences(defaults: defaults)
        configure(preferences)
        return AwakeController(
            assertion: assertion, scheduler: scheduler, preferences: preferences,
            monitors: system.monitors, clock: { [scheduler] in scheduler.now }
        )
    }

    @Test func appTriggerHoldsWhileTheAppRuns() {
        let controller = makeController { $0.addTriggerApp(FakeSystem.xcode) }
        #expect(!controller.isActive)

        system.apps.send([FakeSystem.xcode])
        #expect(controller.isActive)
        #expect(controller.isTriggerHolding)
        #expect(controller.session == nil)
        #expect(assertion.isHeld)
        #expect(controller.statusText == "On while Xcode is running")

        system.apps.send([])
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
        #expect(controller.statusText == nil)
    }

    @Test func triggerAlreadyTrueAtLaunchHolds() {
        system.apps.send([FakeSystem.xcode])
        let controller = makeController { $0.addTriggerApp(FakeSystem.xcode) }
        #expect(controller.isTriggerHolding)
        #expect(assertion.isHeld)
    }

    @Test func addingATriggerAppliesImmediately() {
        system.apps.send([FakeSystem.keynote])
        let controller = makeController()
        #expect(!controller.isActive)
        controller.preferences.addTriggerApp(FakeSystem.keynote)
        #expect(controller.isActive)
        controller.preferences.removeTriggerApp(bundleID: FakeSystem.keynote.bundleID)
        #expect(!controller.isActive)
    }

    @Test func powerAdapterTrigger() {
        let controller = makeController { $0.triggerOnPowerAdapter = true }
        #expect(controller.isTriggerHolding, "the fake starts on AC")
        #expect(controller.statusText == "On while connected to power")
        system.power.send(PowerState(isOnAC: false, batteryPercent: 80))
        #expect(!controller.isActive)
        system.power.send(PowerState(isOnAC: true, batteryPercent: 80))
        #expect(controller.isActive)
    }

    @Test func externalDisplayTrigger() {
        let controller = makeController { $0.triggerOnExternalDisplay = true }
        #expect(!controller.isActive)
        system.displays.send(2)
        #expect(controller.isActive)
        #expect(controller.statusText == "On while an external display is connected")
        system.displays.send(0)
        #expect(!controller.isActive)
    }

    @Test func masterSwitchOffIgnoresTriggers() {
        let controller = makeController {
            $0.triggerOnPowerAdapter = true
            $0.triggersEnabled = false
        }
        #expect(!controller.isActive)
        controller.preferences.triggersEnabled = true
        #expect(controller.isActive)
        controller.preferences.triggersEnabled = false
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
    }

    @Test func turningOffPausesTriggersUntilTheConditionClears() {
        let controller = makeController { $0.triggerOnExternalDisplay = true }
        system.displays.send(1)
        #expect(controller.isActive)

        controller.toggle()
        #expect(!controller.isActive, "off sticks while the display stays connected")
        #expect(controller.triggersPaused)
        #expect(!assertion.isHeld)
        system.apps.send([FakeSystem.keynote]) // unrelated change re-evaluates
        #expect(!controller.isActive)

        system.displays.send(0)
        #expect(!controller.triggersPaused)
        system.displays.send(1)
        #expect(controller.isActive, "re-armed once the condition cleared")
    }

    @Test func turningOnWhilePausedStartsASession() {
        let controller = makeController { $0.triggerOnPowerAdapter = true }
        controller.toggle()
        #expect(!controller.isActive)
        controller.toggle()
        #expect(controller.session?.duration == .indefinitely)
        #expect(assertion.isHeld)
    }

    @Test func sessionTakesPriorityInStatusAndTriggerHoldsAfterItEnds() {
        let controller = makeController { $0.triggerOnPowerAdapter = true }
        controller.start(.minutes(10))
        #expect(controller.statusText == "10 min left")
        scheduler.advance(by: 10 * 60)
        #expect(controller.session == nil)
        #expect(controller.isActive, "the trigger still holds after the timed session ends")
        #expect(assertion.isHeld)
    }

    @Test func failedAssertionDuringATriggerDoesNotRetryInALoop() {
        assertion.failNextHold = true
        let controller = makeController { $0.triggerOnPowerAdapter = true }
        #expect(controller.lastError != nil)
        #expect(controller.triggersPaused)
        #expect(!controller.isActive)
        #expect(assertion.holdCount == 0)
    }

    @Test func displayOptionAppliesToTriggers() {
        let controller = makeController {
            $0.triggerOnPowerAdapter = true
            $0.keepDisplayOn = false
        }
        #expect(assertion.keepDisplayOn == false)
        controller.preferences.keepDisplayOn = true
        #expect(assertion.keepDisplayOn == true)
    }
}

@MainActor
@Suite struct BatteryAndLockTests {
    let assertion = FakeAssertion()
    let scheduler = ManualScheduler()
    let system = FakeSystem()
    let store = TestDefaults()
    var defaults: UserDefaults { store.defaults }

    func makeController(_ configure: (AwakePreferences) -> Void = { _ in }) -> AwakeController {
        let preferences = AwakePreferences(defaults: defaults)
        configure(preferences)
        return AwakeController(
            assertion: assertion, scheduler: scheduler, preferences: preferences,
            monitors: system.monitors, clock: { [scheduler] in scheduler.now }
        )
    }

    @Test func unpluggingEndsTheSessionWhenAsked() {
        let controller = makeController { $0.stopOnSwitchToBattery = true }
        controller.start(.hours(1))
        system.power.send(PowerState(isOnAC: false, batteryPercent: 80))
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
        #expect(controller.lastEnd == .switchedToBattery)
        #expect(controller.statusText == "Turned off: switched to battery")
    }

    @Test func unpluggingKeepsTheSessionByDefault() {
        let controller = makeController()
        controller.start(.hours(1))
        system.power.send(PowerState(isOnAC: false, batteryPercent: 80))
        #expect(controller.isActive)
    }

    @Test func manualStartOnBatteryIsAllowed() {
        system.power.send(PowerState(isOnAC: false, batteryPercent: 80))
        let controller = makeController { $0.stopOnSwitchToBattery = true }
        controller.start(.hours(1))
        #expect(controller.isActive)
    }

    @Test func triggersWaitOnBatteryAndResumeWhenPluggedIn() {
        system.apps.send([FakeSystem.xcode])
        let controller = makeController {
            $0.stopOnSwitchToBattery = true
            $0.addTriggerApp(FakeSystem.xcode)
        }
        #expect(controller.isActive)
        system.power.send(PowerState(isOnAC: false, batteryPercent: 80))
        #expect(!controller.isActive)
        #expect(controller.lastEnd == .switchedToBattery)
        system.power.send(PowerState(isOnAC: true, batteryPercent: 80))
        #expect(controller.isActive)
    }

    @Test func lowBatteryEndsTheSessionAtTheThreshold() {
        system.power.send(PowerState(isOnAC: false, batteryPercent: 30))
        let controller = makeController {
            $0.stopOnLowBattery = true
            $0.lowBatteryThreshold = 20
        }
        controller.start(.indefinitely)
        system.power.send(PowerState(isOnAC: false, batteryPercent: 21))
        #expect(controller.isActive)
        system.power.send(PowerState(isOnAC: false, batteryPercent: 20))
        #expect(!controller.isActive)
        #expect(!assertion.isHeld)
        #expect(controller.lastEnd == .lowBattery(20))
        #expect(controller.statusText == "Turned off: battery at 20%")
    }

    @Test func startingAgainWhileLowIsAnOverride() {
        system.power.send(PowerState(isOnAC: false, batteryPercent: 30))
        let controller = makeController { $0.stopOnLowBattery = true }
        controller.start(.indefinitely)
        system.power.send(PowerState(isOnAC: false, batteryPercent: 15))
        #expect(!controller.isActive)
        controller.start(.hours(1))
        system.power.send(PowerState(isOnAC: false, batteryPercent: 14))
        #expect(controller.isActive, "only crossing the threshold turns it off")
    }

    @Test func lowBatteryBlocksTriggersUntilCharging() {
        system.power.send(PowerState(isOnAC: false, batteryPercent: 50))
        system.displays.send(1)
        let controller = makeController {
            $0.stopOnLowBattery = true
            $0.triggerOnExternalDisplay = true
        }
        #expect(controller.isActive)
        system.power.send(PowerState(isOnAC: false, batteryPercent: 10))
        #expect(!controller.isActive)
        #expect(controller.lastEnd == .lowBattery(10))
        system.power.send(PowerState(isOnAC: true, batteryPercent: 11))
        #expect(controller.isActive, "plugging in lifts the low-battery block")
    }

    @Test func alreadyLowAtLaunchIsNotReported() {
        system.power.send(PowerState(isOnAC: false, batteryPercent: 5))
        let controller = makeController { $0.stopOnLowBattery = true }
        #expect(controller.lastEnd == nil)
        #expect(controller.isLowBattery)
    }

    @Test func lowBatteryRuleIgnoresDesktops() {
        system.power.send(.desktop)
        let controller = makeController { $0.stopOnLowBattery = true }
        controller.start(.indefinitely)
        #expect(!controller.isLowBattery)
        #expect(controller.isActive)
    }

    @Test func lowBatteryRuleOffByDefault() {
        system.power.send(PowerState(isOnAC: false, batteryPercent: 30))
        let controller = makeController()
        controller.start(.indefinitely)
        system.power.send(PowerState(isOnAC: false, batteryPercent: 3))
        #expect(controller.isActive)
    }

    @Test func lockedScreenLetsTheMacSleepWhenAsked() {
        let controller = makeController { $0.allowSleepWhenLocked = true }
        controller.start(.hours(1))
        #expect(assertion.isHeld)
        system.locked.send(true)
        #expect(controller.isActive, "the session carries on")
        #expect(controller.isPausedForLock)
        #expect(!assertion.isHeld)
        system.locked.send(false)
        #expect(assertion.isHeld)
    }

    @Test func lockedScreenKeepsHoldingByDefault() {
        let controller = makeController()
        controller.start(.hours(1))
        system.locked.send(true)
        #expect(assertion.isHeld)
        #expect(!controller.isPausedForLock)
    }
}
