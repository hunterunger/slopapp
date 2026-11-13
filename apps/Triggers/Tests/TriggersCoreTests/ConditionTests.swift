import Foundation
import Testing
@testable import TriggersCore

@MainActor
@Suite struct ConditionTests {
    let state = FakeState()

    private func holds(_ condition: Condition, front: String? = nil) -> Bool {
        condition.holds(in: ConditionEnvironment(state: state, frontBundleID: front))
    }

    @Test func appRunningAndFront() {
        state.running = ["com.apple.Music"]
        #expect(holds(.appRunning(bundleID: "com.apple.Music", name: "Music", running: true)))
        #expect(!holds(.appRunning(bundleID: "com.apple.Music", name: "Music", running: false)))
        #expect(holds(.appRunning(bundleID: "com.apple.Notes", name: "Notes", running: false)))
        #expect(holds(.frontApp(bundleID: "com.apple.Notes", name: "Notes", isFront: true), front: "com.apple.Notes"))
        #expect(!holds(.frontApp(bundleID: "com.apple.Notes", name: "Notes", isFront: true), front: "com.apple.Safari"))
    }

    @Test func network() {
        state.network = NetworkState(isOnline: true, usesWiFi: true)
        #expect(holds(.network(.online)) && holds(.network(.wifi)) && !holds(.network(.wired)) && !holds(.network(.offline)))
        state.network = NetworkState(isOnline: false)
        #expect(holds(.network(.offline)) && !holds(.network(.wifi)))
    }

    @Test func displays() {
        #expect(holds(.display(.noExternal)) && !holds(.display(.externalConnected)))
        state.displays.append(DisplayInfo(name: "Studio Display", isBuiltIn: false))
        #expect(holds(.display(.externalConnected)) && holds(.display(.named("studio display"))) && !holds(.display(.named("LG"))))
    }

    @Test func power() {
        state.power = .battery
        #expect(holds(.power(.battery)) && !holds(.power(.charger)))
        state.power = .unknown
        #expect(!holds(.power(.battery)) && !holds(.power(.charger)), "a desktop Mac with no battery info is neither")
    }

    @Test func timeOfDayIncludingOvernight() {
        // FakeState's clock reads 08:00 UTC.
        #expect(holds(.time(from: 7 * 60, to: 9 * 60)))
        #expect(!holds(.time(from: 8 * 60 + 1, to: 9 * 60)))
        #expect(!holds(.time(from: 7 * 60, to: 8 * 60)), "the end is not included")
        #expect(holds(.time(from: 22 * 60, to: 9 * 60)), "wraps past midnight")
        #expect(!holds(.time(from: 22 * 60, to: 6 * 60)))
        #expect(Condition.minute(23 * 60, isIn: 22 * 60, 6 * 60) && Condition.minute(60, isIn: 22 * 60, 6 * 60))
    }

    @Test func daysOfTheWeek() {
        // 1_800_000_000 is a Friday (weekday 6).
        #expect(holds(.days([2, 3, 4, 5, 6])))
        #expect(!holds(.days([1, 7])))
        #expect(Condition.days([2, 3, 4, 5, 6]).title == "On weekdays")
        #expect(Condition.days([1, 7]).title == "At the weekend")
    }

    @Test func modifiersAndAppearance() {
        state.modifiers = [.option, .shift]
        #expect(holds(.modifiersHeld(.option)) && !holds(.modifiersHeld(.command)))
        state.isDarkMode = true
        #expect(holds(.appearance(dark: true)) && !holds(.appearance(dark: false)))
    }

    @Test func allAndAny() {
        state.power = .battery
        let both = [Condition.power(.battery), .network(.offline)]
        let environment = ConditionEnvironment(state: state, frontBundleID: nil)
        #expect(!ConditionSet(match: .all, both).holds(in: environment))
        #expect(ConditionSet(match: .any, both).holds(in: environment))
        #expect(ConditionSet.always.holds(in: environment), "no conditions: always")
        #expect(ConditionSet(match: .any, both).summary == "On battery or Not connected to a network")
    }

    @Test func incompleteConditions() {
        #expect(!Condition.appRunning(bundleID: "", name: "", running: true).isComplete)
        #expect(!Condition.days([]).isComplete)
        #expect(!Condition.modifiersHeld([]).isComplete)
        #expect(Condition.Kind.allCases.filter { ![.appRunning, .frontApp].contains($0) }.allSatisfy { $0.defaultCondition.isComplete })
    }
}

@Suite struct ConditionalRoutingTests {
    let tap3 = Trigger.gesture(.tap(3), modifiers: [])
    let onBattery = ConditionSet([.power(.battery)])

    @Test func firstBindingWhoseConditionsHoldWins() {
        let battery = TriggerBinding(trigger: tap3, action: .media(.playPause), conditions: onBattery, scope: .allApps)
        let otherwise = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let table = RoutingTable(config: Config(bindings: [battery, otherwise]))
        #expect(table.resolve(tap3, frontApp: nil) { _ in true } == .perform(battery))
        #expect(table.resolve(tap3, frontApp: nil) { _ in false } == .perform(otherwise))
    }

    @Test func anAppsConditionalTriggerFallsBackToAllApps() {
        let own = TriggerBinding(trigger: tap3, action: .window(.maximize), conditions: onBattery, scope: .app(bundleID: "com.apple.Safari"))
        let all = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let table = RoutingTable(config: Config(bindings: [own, all]))
        #expect(table.resolve(tap3, frontApp: "com.apple.Safari") { _ in false } == .perform(all))
        #expect(table.resolve(tap3, frontApp: "com.apple.Safari") { _ in true } == .perform(own))
    }

    @Test func blockedWhenNothingHolds() {
        let only = TriggerBinding(trigger: tap3, action: .click(.middle), conditions: onBattery, scope: .allApps)
        let table = RoutingTable(config: Config(bindings: [only]))
        #expect(table.resolve(tap3, frontApp: nil) { _ in false } == .blocked)
        #expect(table.resolve(.gesture(.tap(4), modifiers: []), frontApp: nil) == .none)
    }

    @Test func conditionalDoNothingDoesntHideWhatsBelowIt() {
        let back = Trigger.mouseButton(3, modifiers: [])
        let all = TriggerBinding(trigger: back, action: .pressKeys(cmdLeftBracket), scope: .allApps)
        let sometimes = TriggerBinding(trigger: back, action: .passThrough, conditions: onBattery, scope: .app(bundleID: "com.apple.Notes"))
        let always = TriggerBinding(trigger: back, action: .passThrough, scope: .app(bundleID: "com.apple.Safari"))
        let table = RoutingTable(config: Config(bindings: [all, sometimes, always]))
        #expect(table.mouseRoutes(frontApp: "com.apple.Notes").binding(button: 3, modifiers: []) == all.id, "the tap must still catch it")
        #expect(table.mouseRoutes(frontApp: "com.apple.Safari").isEmpty, "an unconditional Do Nothing lets the app have it")
        #expect(table.resolve(back, frontApp: "com.apple.Notes") { _ in true } == .passThrough(sometimes))
    }

    @Test func keySequencesPerFrontApp() {
        let notesOnly = TriggerBinding(trigger: .keySequence(.doubleTap(.command)), action: .window(.center), scope: .app(bundleID: "com.apple.Notes"))
        let table = RoutingTable(config: Config(bindings: [notesOnly]))
        #expect(table.hasKeySequenceBindings && !table.hasKeyBindings)
        #expect(table.keySequences(frontApp: "com.apple.Notes") == [.doubleTap(.command)])
        #expect(table.keySequences(frontApp: "com.apple.Safari").isEmpty)
    }

    @Test func boundGesturesBecomeTheRecognizersInterests() {
        let table = RoutingTable(config: Config(bindings: [
            TriggerBinding(trigger: .gesture(.pinchIn(2), modifiers: []), action: .media(.volumeDown), scope: .allApps),
            TriggerBinding(trigger: .gesture(.tap(5), modifiers: []), action: .passThrough, scope: .app(bundleID: "x")),
        ]))
        #expect(table.gestures == [.pinchIn(2)], "Do Nothing bindings don't need recognizing")
    }

    @Test func conditionsTurnDuplicatesIntoChoices() {
        let plain = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let battery = TriggerBinding(trigger: tap3, action: .media(.playPause), conditions: onBattery, scope: .allApps)
        let twin = TriggerBinding(trigger: tap3, action: .click(.right), scope: .allApps)
        let config = Config(bindings: [plain, battery, twin])
        let checker = ConflictChecker()
        #expect(!checker.conflicts(for: battery, in: config).contains { if case .duplicate = $0 { return true }; return false })
        #expect(checker.conflicts(for: twin, in: config).contains(.duplicate(plain)))
    }
}

@Suite struct NewActionModelTests {
    @Test func accessibilityAndCompleteness() {
        #expect(Action.media(.volumeUp).needsAccessibility, "posting the key needs it")
        #expect(Action.system(.lockScreen).needsAccessibility)
        #expect(!Action.system(.missionControl).needsAccessibility)
        #expect(!Action.script(.shell, "true").needsAccessibility)
        #expect(Action.typeText("hi").needsAccessibility)
        #expect(!Action.typeText("").isComplete)
        #expect(!Action.script(.appleScript, "  \n").isComplete)
        #expect(!Action.windowArea(UnitRect(x: 0.6, y: 0, width: 0.6, height: 1)).isComplete, "off the screen")
        #expect(Action.windowArea(UnitRect(x: 0.5, y: 0, width: 0.5, height: 1)).isComplete)
    }

    @Test func everyKindRoundTripsThroughItsDefault() {
        for group in ActionKind.groups {
            for kind in group.kinds {
                #expect(kind.defaultAction(from: nil).kind == kind, "\(kind.title)")
            }
        }
        // Switching between the script languages keeps the script.
        #expect(ActionKind.appleScript.defaultAction(from: .script(.shell, "say hi")) == .script(.appleScript, "say hi"))
    }

    @Test func mediaKeyEventData() {
        #expect(MediaKey.playPause.data1(down: true) == (16 << 16) | (0xA << 8))
        #expect(MediaKey.volumeUp.data1(down: false) == (0 << 16) | (0xB << 8))
    }

    @Test func summaries() {
        let binding = TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), steps: [
            .action(.open(.app(bundleID: "com.apple.Notes", name: "Notes"))),
            .waitUntil(.frontApp(bundleID: "com.apple.Notes", name: "Notes", isFront: true)),
            .delay(0.5),
            .action(.pressKeys(KeyCombo(keyCode: 45, modifiers: .command))),
        ], scope: .allApps)
        #expect(binding.fallbackSummary == "Open Notes → Wait until Notes is in front → Wait 0.5 s → Press ⌘N")
        #expect(ActionStep.waitUntil(.power(.battery)).title(keys: { $0.fallbackDisplay }) == "Wait until on battery")
        #expect(Action.typeText("A very long piece of text that goes on and on").fallbackTitle.hasSuffix("…”"))
    }

    @Test func doNothingStandsAlone() {
        let alone = TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .passThrough, scope: .browsers)
        #expect(alone.isPassThrough && alone.isComplete)
        let mixed = TriggerBinding(trigger: .mouseButton(3, modifiers: []), steps: [.action(.passThrough), .action(.click(.middle))], scope: .browsers)
        #expect(!mixed.isPassThrough && !mixed.isComplete)
    }
}

@Suite struct MoreWindowLayoutTests {
    let screen = CGRect(x: 0, y: 25, width: 1511, height: 920)

    @Test func thirdsMeetExactly() {
        let left = WindowLayout.target(for: .leftThird, window: .zero, visible: screen)!
        let middle = WindowLayout.target(for: .centerThird, window: .zero, visible: screen)!
        let right = WindowLayout.target(for: .rightThird, window: .zero, visible: screen)!
        #expect(left.minX == screen.minX && left.maxX == middle.minX && middle.maxX == right.minX && right.maxX == screen.maxX)
        #expect(left.height == screen.height)
        let twoThirds = WindowLayout.target(for: .leftTwoThirds, window: .zero, visible: screen)!
        #expect(twoThirds.maxX == middle.maxX)
    }

    @Test func quartersTileTheScreen() {
        let tl = WindowLayout.target(for: .topLeftQuarter, window: .zero, visible: screen)!
        let br = WindowLayout.target(for: .bottomRightQuarter, window: .zero, visible: screen)!
        #expect(tl.origin == screen.origin && br.maxX == screen.maxX && br.maxY == screen.maxY)
        #expect(tl.maxX == br.minX && tl.maxY == br.minY)
    }

    @Test func halvesAreUnchanged() {
        let left = WindowLayout.target(for: .leftHalf, window: .zero, visible: screen)!
        let right = WindowLayout.target(for: .rightHalf, window: .zero, visible: screen)!
        #expect(left == CGRect(x: 0, y: 25, width: 755, height: 920))
        #expect(right == CGRect(x: 755, y: 25, width: 756, height: 920))
    }

    @Test func customArea() {
        let area = WindowLayout.rect(UnitRect(x: 0.25, y: 0, width: 0.5, height: 1), in: screen)
        #expect(area == CGRect(x: 377, y: 25, width: 756, height: 920))
    }

    @Test func aWideMinimumSizeKeepsTheRightEdgeForRightThird() {
        let target = WindowLayout.target(for: .rightThird, window: .zero, visible: screen)!
        let settled = WindowLayout.settle(actual: CGSize(width: 700, height: target.height), target: target, move: .rightThird, visible: screen)
        #expect(settled.maxX == screen.maxX)
    }

    @Test func fullScreenAndMinimizeAreNotFrames() {
        #expect(WindowLayout.target(for: .fullScreen, window: screen, visible: screen) == nil)
        #expect(WindowLayout.target(for: .minimize, window: screen, visible: screen) == nil)
    }
}
