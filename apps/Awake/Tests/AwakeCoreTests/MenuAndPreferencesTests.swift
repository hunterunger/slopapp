import Foundation
import Testing
@testable import AwakeCore

@MainActor
@Suite struct MenuContentTests {
    let scheduler = ManualScheduler()
    let system = FakeSystem()
    let store = TestDefaults()
    let assertion = FakeAssertion()
    var defaults: UserDefaults { store.defaults }

    func makeController() -> AwakeController {
        AwakeController(
            assertion: assertion, scheduler: scheduler,
            preferences: AwakePreferences(defaults: defaults), monitors: system.monitors,
            clock: { [scheduler] in scheduler.now }
        )
    }

    func dump(_ controller: AwakeController) -> String {
        MenuContent.dump(MenuContent.entries(for: controller, appName: "Awake"))
    }

    @Test func idleMenu() {
        system.apps.send([FakeSystem.xcode, FakeSystem.keynote])
        let text = dump(makeController())
        #expect(text == """
              Turn On  (global shortcut)
            ----
            == Keep Awake ==
              Indefinitely
              10 Minutes
              30 Minutes
              1 Hour
              2 Hours
              4 Hours
              8 Hours
              12 Hours
              Custom Duration…
              Until…
              While App Is Running ▸
                  Keynote
                  Xcode
            ----
              Allow Display Sleep
              Set Up Triggers…
            ----
              Settings…  ⌘,
              About Awake
              Report a Problem…
            ----
              Quit Awake  ⌘Q
            """)
    }

    @Test func aFailedAssertionShowsItsErrorFirst() {
        let controller = makeController()
        assertion.failNextHold = true
        controller.start(.hours(1))
        let entries = MenuContent.entries(for: controller, appName: "Awake")
        #expect(entries.first == .error("Couldn't keep the Mac awake (IOKit error -1)."))
        #expect(entries[1] == .item("Turn On", .turnOn, showsToggleShortcut: true))
    }

    @Test func activeTimedMenuChecksThePresetAndOffersMoreTime() {
        let controller = makeController()
        controller.start(.hours(2))
        let entries = MenuContent.entries(for: controller, appName: "Awake")
        #expect(entries.first == .status("2 hr left"))
        #expect(entries[1] == .item("Turn Off", .turnOff, showsToggleShortcut: true))
        #expect(entries[2] == .item("Add 30 Minutes", .extend))
        #expect(entries.contains(.item("2 Hours", .start(.hours(2)), checked: true)))
        #expect(entries.contains(.item("1 Hour", .start(.hours(1)), checked: false)))
    }

    @Test func indefiniteSessionHasNoAddTime() {
        let controller = makeController()
        controller.start(.indefinitely)
        let entries = MenuContent.entries(for: controller, appName: "Awake")
        #expect(!entries.contains(.item("Add 30 Minutes", .extend)))
        #expect(entries.contains(.item("Indefinitely", .start(.indefinitely), checked: true)))
    }

    @Test func customAndUntilSessionsCheckTheirItems() {
        let controller = makeController()
        controller.start(.minutes(45))
        #expect(MenuContent.entries(for: controller, appName: "Awake")
            .contains(.item("Custom Duration…", .customDuration, checked: true)))
        controller.start(.until(scheduler.now.addingTimeInterval(3600)))
        #expect(MenuContent.entries(for: controller, appName: "Awake")
            .contains(.item("Until…", .until, checked: true)))
    }

    @Test func whileRunningChecksTheApp() {
        system.apps.send([FakeSystem.xcode])
        let controller = makeController()
        controller.start(.whileRunning(FakeSystem.xcode))
        let entries = MenuContent.entries(for: controller, appName: "Awake")
        #expect(entries.contains(.submenu("While App Is Running", [.item("Xcode", .whileRunning(FakeSystem.xcode), checked: true)])))
    }

    @Test func noRunningApps() {
        let entries = MenuContent.entries(for: makeController(), appName: "Awake")
        #expect(entries.contains(.submenu("While App Is Running", [.text("No Apps Running")])))
    }

    @Test func turnOnNamesANonDefaultDuration() {
        let controller = makeController()
        controller.preferences.defaultDuration = .hours(1)
        #expect(MenuContent.entries(for: controller, appName: "Awake").first
            == .item("Turn On for 1 Hour", .turnOn, showsToggleShortcut: true))
    }

    @Test func triggersCheckboxOnceConfigured() {
        let controller = makeController()
        controller.preferences.triggerOnExternalDisplay = true
        let entries = MenuContent.entries(for: controller, appName: "Awake")
        #expect(entries.contains(.item("Use Triggers", .toggleTriggers, checked: true)))
        #expect(!entries.contains(.item("Set Up Triggers…", .setUpTriggers)))
    }

    @Test func allowDisplaySleepReflectsThePreference() {
        let controller = makeController()
        controller.preferences.keepDisplayOn = false
        #expect(MenuContent.entries(for: controller, appName: "Awake")
            .contains(.item("Allow Display Sleep", .toggleDisplaySleep, checked: true)))
    }

    @Test func triggerStatusShowsFirst() {
        let controller = makeController()
        controller.preferences.triggerOnPowerAdapter = true
        let entries = MenuContent.entries(for: controller, appName: "Awake")
        #expect(entries.first == .status("On while connected to power"))
        #expect(entries[1] == .item("Turn Off", .turnOff, showsToggleShortcut: true))
    }
}

@MainActor
@Suite struct PreferencesTests {
    let store = TestDefaults()
    var defaults: UserDefaults { store.defaults }

    @Test func defaultValues() {
        let preferences = AwakePreferences(defaults: defaults)
        #expect(preferences.keepDisplayOn)
        #expect(preferences.defaultDuration == .indefinitely)
        #expect(!preferences.activateAtLaunch)
        #expect(preferences.leftClick == .toggle)
        #expect(!preferences.allowSleepWhenLocked)
        #expect(!preferences.stopOnSwitchToBattery)
        #expect(!preferences.stopOnLowBattery)
        #expect(preferences.lowBatteryThreshold == 20)
        #expect(!preferences.dimIconWhenOff)
        #expect(!preferences.showTimeInMenuBar)
        #expect(preferences.triggersEnabled)
        #expect(!preferences.hasTriggers)
    }

    @Test func everythingPersists() {
        let preferences = AwakePreferences(defaults: defaults)
        preferences.keepDisplayOn = false
        preferences.defaultDuration = .hours(4)
        preferences.activateAtLaunch = true
        preferences.leftClick = .openMenu
        preferences.allowSleepWhenLocked = true
        preferences.stopOnSwitchToBattery = true
        preferences.stopOnLowBattery = true
        preferences.lowBatteryThreshold = 35
        preferences.dimIconWhenOff = true
        preferences.showTimeInMenuBar = true
        preferences.triggersEnabled = false
        preferences.addTriggerApp(FakeSystem.xcode)
        preferences.addTriggerApp(FakeSystem.keynote)
        preferences.addTriggerApp(FakeSystem.xcode)
        preferences.triggerOnPowerAdapter = true
        preferences.triggerOnExternalDisplay = true

        let reloaded = AwakePreferences(defaults: defaults)
        #expect(!reloaded.keepDisplayOn)
        #expect(reloaded.defaultDuration == .hours(4))
        #expect(reloaded.activateAtLaunch)
        #expect(reloaded.leftClick == .openMenu)
        #expect(reloaded.allowSleepWhenLocked)
        #expect(reloaded.stopOnSwitchToBattery)
        #expect(reloaded.stopOnLowBattery)
        #expect(reloaded.lowBatteryThreshold == 35)
        #expect(reloaded.dimIconWhenOff)
        #expect(reloaded.showTimeInMenuBar)
        #expect(!reloaded.triggersEnabled)
        #expect(reloaded.triggerApps == [FakeSystem.keynote, FakeSystem.xcode], "deduped and sorted by name")
        #expect(reloaded.triggerOnPowerAdapter)
        #expect(reloaded.triggerOnExternalDisplay)
    }

    @Test func keepsTheOldDisplayKey() {
        defaults.set(false, forKey: "keepDisplayOn")
        #expect(!AwakePreferences(defaults: defaults).keepDisplayOn)
    }

    @Test func badThresholdFallsBack() {
        defaults.set(0, forKey: "lowBatteryThreshold")
        #expect(AwakePreferences(defaults: defaults).lowBatteryThreshold == 20)
    }
}
