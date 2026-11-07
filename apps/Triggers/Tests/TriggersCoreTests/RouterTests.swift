import CoreGraphics
import Foundation
import Testing
@testable import TriggersCore

@Suite struct RouterTests {
    let tap3 = Trigger.gesture(.tap(3), modifiers: [])
    let back = Trigger.mouseButton(3, modifiers: [])

    @Test func appBeatsGroupBeatsAllApps() {
        let all = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let group = TriggerBinding(trigger: tap3, action: .click(.right), scope: .browsers)
        let own = TriggerBinding(trigger: tap3, action: .window(.maximize), scope: .app(bundleID: "com.apple.Safari"))
        let table = RoutingTable(config: Config(bindings: [all, group, own]))
        #expect(table.resolve(tap3, frontApp: "com.apple.Safari") == .perform(own))
        #expect(table.resolve(tap3, frontApp: "com.google.Chrome") == .perform(group))
        #expect(table.resolve(tap3, frontApp: "com.apple.Notes") == .perform(all))
        #expect(table.resolve(tap3, frontApp: nil) == .perform(all))
    }

    @Test func allAppsOffInAnApp() {
        let all = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let gameOwn = TriggerBinding(trigger: back, action: .window(.center), scope: .app(bundleID: "com.example.game"))
        var config = Config(bindings: [all, gameOwn])
        config.setUsesAllAppsTriggers(false, in: "com.example.game", name: "Game")
        let table = RoutingTable(config: config)
        #expect(table.resolve(tap3, frontApp: "com.example.game") == .none)
        #expect(table.resolve(back, frontApp: "com.example.game") == .perform(gameOwn), "its own bindings still work")
        #expect(table.resolve(tap3, frontApp: "com.apple.Notes") == .perform(all))
    }

    @Test func passThroughOverridesAllApps() {
        let all = TriggerBinding(trigger: back, action: .pressKeys(cmdLeftBracket), scope: .allApps)
        let pass = TriggerBinding(trigger: back, action: .passThrough, scope: .app(bundleID: "com.apple.Notes"))
        let table = RoutingTable(config: Config(bindings: [all, pass]))
        #expect(table.resolve(back, frontApp: "com.apple.Notes") == .passThrough(pass))
        #expect(table.mouseRoutes(frontApp: "com.apple.Notes").isEmpty, "not swallowed there")
        #expect(table.mouseRoutes(frontApp: "com.apple.Safari").binding(button: 3, modifiers: []) == all.id)
    }

    @Test func disabledAndIncompleteBindingsAreIgnored() {
        let off = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps, isEnabled: false)
        let empty = TriggerBinding(trigger: tap3, action: .menuItem([]), scope: .allApps)
        let table = RoutingTable(config: Config(bindings: [off, empty]))
        #expect(table.resolve(tap3, frontApp: nil) == .none)
        #expect(!table.hasGestureBindings)
    }

    @Test func firstOfDuplicatesWins() {
        let a = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let b = TriggerBinding(trigger: tap3, action: .click(.right), scope: .allApps)
        #expect(RoutingTable(config: Config(bindings: [a, b])).resolve(tap3, frontApp: nil) == .perform(a))
    }

    @Test func modifiersMustMatchExactly() {
        let plain = TriggerBinding(trigger: back, action: .click(.middle), scope: .allApps)
        let withOption = TriggerBinding(trigger: .mouseButton(3, modifiers: .option), action: .click(.right), scope: .allApps)
        let table = RoutingTable(config: Config(bindings: [plain, withOption]))
        #expect(table.resolve(.mouseButton(3, modifiers: .option), frontApp: nil) == .perform(withOption))
        #expect(table.resolve(.mouseButton(3, modifiers: .command), frontApp: nil) == .none)
    }

    @Test func hotkeysFollowTheFrontApp() {
        let global = TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.leftHalf), scope: .allApps)
        let other = KeyCombo(keyCode: 38, modifiers: [.control, .option])
        let notesOnly = TriggerBinding(trigger: .keyCombo(other), action: .window(.rightHalf), scope: .app(bundleID: "com.apple.Notes"))
        let table = RoutingTable(config: Config(bindings: [global, notesOnly]))
        #expect(table.hotkeys(frontApp: "com.apple.Notes") == [ctrlOptK, other])
        #expect(table.hotkeys(frontApp: "com.apple.Safari") == [ctrlOptK])
    }

    @Test func manyBindingsStayFast() {
        let bindings = (0..<2000).map { index in
            TriggerBinding(trigger: .keyCombo(KeyCombo(keyCode: index % 120, modifiers: Modifiers(rawValue: index % 16))),
                    action: .click(.middle), scope: index.isMultiple(of: 3) ? .allApps : .app(bundleID: "app.\(index % 50)"))
        }
        let table = RoutingTable(config: Config(bindings: bindings))
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<10_000 { _ = table.resolve(bindings[index % 2000].trigger, frontApp: "app.\(index % 50)") }
        }
        #expect(elapsed < .milliseconds(200))
    }
}

@Suite struct MouseTapDeciderTests {
    let id = UUID()
    var routes: MouseRoutes { MouseRoutes([MouseRoutes.key(button: 3, modifiers: []): id]) }

    private func event(_ type: CGEventType, button: Int, flags: CGEventFlags = [], own: Bool = false) -> CGEvent {
        let cgButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: cgButton)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.flags = flags
        if own { event.setIntegerValueField(.eventSourceUserData, value: MouseTapDecider.ownEventMarker) }
        return event
    }

    @Test func boundButtonIsSwallowedWithItsDragAndUp() {
        var decider = MouseTapDecider()
        #expect(decider.decide(event(.otherMouseDown, button: 3), routes: routes) == .swallowAndFire(id))
        #expect(decider.decide(event(.otherMouseDragged, button: 3), routes: routes) == .swallow)
        #expect(decider.decide(event(.otherMouseUp, button: 3), routes: routes) == .swallow)
        // The next unrelated up passes.
        #expect(decider.decide(event(.otherMouseUp, button: 3), routes: routes) == .pass)
    }

    @Test func unboundButtonPasses() {
        var decider = MouseTapDecider()
        #expect(decider.decide(event(.otherMouseDown, button: 4), routes: routes) == .pass)
        #expect(decider.decide(event(.otherMouseUp, button: 4), routes: routes) == .pass)
        #expect(decider.decide(event(.otherMouseDown, button: 2), routes: routes) == .pass)
    }

    @Test func modifiersFromEventFlags() {
        var decider = MouseTapDecider()
        #expect(decider.decide(event(.otherMouseDown, button: 3, flags: .maskAlternate), routes: routes) == .pass)
        let optionRoutes = MouseRoutes([MouseRoutes.key(button: 3, modifiers: .option): id])
        // Caps Lock and the like don't count.
        #expect(decider.decide(event(.otherMouseDown, button: 3, flags: [.maskAlternate, .maskAlphaShift]), routes: optionRoutes) == .swallowAndFire(id))
    }

    @Test func upIsSwallowedEvenIfRoutesChangedInBetween() {
        // Front app changed between down and up: the down's decision governs the up.
        var decider = MouseTapDecider()
        #expect(decider.decide(event(.otherMouseDown, button: 3), routes: routes) == .swallowAndFire(id))
        #expect(decider.decide(event(.otherMouseUp, button: 3), routes: .empty) == .swallow)
        // And a press that started unbound stays passed even if a binding appears before the up.
        #expect(decider.decide(event(.otherMouseDown, button: 3), routes: .empty) == .pass)
        #expect(decider.decide(event(.otherMouseUp, button: 3), routes: routes) == .pass)
    }

    @Test func ownEventsAlwaysPass() {
        // Our own posted middle click must never trigger a middle-button binding (no loops).
        var decider = MouseTapDecider()
        let middle = MouseRoutes([MouseRoutes.key(button: 2, modifiers: []): id])
        #expect(decider.decide(event(.otherMouseDown, button: 2, own: true), routes: middle) == .pass)
        #expect(decider.decide(event(.otherMouseDown, button: 2), routes: middle) == .swallowAndFire(id))
    }

    @Test func otherEventTypesPass() {
        var decider = MouseTapDecider()
        let left = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        #expect(decider.decide(left, routes: routes) == .pass)
    }

    @Test func maskIsOtherMouseOnly() {
        let mask = MouseTapDecider.eventMask
        #expect(MouseTapDecider.maskIsMinimal(mask))
        #expect(mask & (1 << CGEventType.keyDown.rawValue) == 0)
        #expect(mask & (1 << CGEventType.scrollWheel.rawValue) == 0)
        #expect(mask & (1 << CGEventType.leftMouseDown.rawValue) == 0)
        #expect(mask & (1 << CGEventType.mouseMoved.rawValue) == 0)
        #expect(!MouseTapDecider.maskIsMinimal(mask | (1 << CGEventType.keyDown.rawValue)))
    }

    @Test func outOfRangeButtonsPass() {
        var decider = MouseTapDecider()
        #expect(decider.decide(phase: .down, button: 99, modifiers: [], routes: routes, isOwnEvent: false) == .pass)
    }
}
