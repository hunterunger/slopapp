import Foundation
import Testing
@testable import TriggersCore

/// Steps run in order with delays and waits; conditions; key sequences and the hyper key's
/// tap; inputs Triggers swallowed but didn't use go back to the app.
@MainActor
@Suite struct SequenceEngineTests {
    let tap3 = Trigger.gesture(.tap(3), modifiers: [])
    let openNotes = Action.open(.app(bundleID: "com.apple.Notes", name: "Notes"))
    let newNote = Action.pressKeys(KeyCombo(keyCode: 45, modifiers: .command))
    let notesInFront = Condition.frontApp(bundleID: "com.apple.Notes", name: "Notes", isFront: true)

    private func rig(_ bindings: [TriggerBinding]) -> EngineRig {
        let rig = EngineRig()
        rig.engine.update(config: Config(bindings: bindings))
        rig.engine.frontApp = safari
        return rig
    }

    @Test func stepsRunInOrderWithADelay() {
        let binding = TriggerBinding(trigger: tap3, steps: [.action(.click(.middle)), .delay(0.5), .action(.window(.center))], scope: .allApps)
        let rig = rig([binding])
        var fired: [ActionResult] = []
        rig.engine.onFired = { _, _, result in fired.append(result) }
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.map(\.action) == [.click(.middle)], "the first step runs at once")
        #expect(fired.isEmpty && rig.engine.isRunning(binding.id))
        rig.scheduler.advance(0.4)
        #expect(rig.performer.calls.count == 1, "not before the delay")
        rig.scheduler.advance(0.2)
        #expect(rig.performer.calls.map(\.action) == [.click(.middle), .window(.center)])
        #expect(fired == [.done] && !rig.engine.isRunning(binding.id))
    }

    @Test func waitUntilThenCarryOnInTheNewFrontApp() {
        let binding = TriggerBinding(trigger: tap3, steps: [.action(openNotes), .waitUntil(notesInFront, timeout: 5), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        rig.engine.receive(tap3)
        rig.scheduler.advance(1)
        #expect(rig.performer.calls.count == 1, "still waiting for Notes")
        rig.engine.frontApp = notes
        rig.scheduler.advance(0.2)
        #expect(rig.performer.calls.map(\.action) == [openNotes, newNote])
        #expect(rig.performer.calls.last?.app == "com.apple.Notes", "later steps act in the app in front by then")
    }

    @Test func waitUntilAlreadyTrueDoesntWait() {
        let binding = TriggerBinding(trigger: tap3, steps: [.waitUntil(.power(.charger)), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.map(\.action) == [newNote])
    }

    @Test func waitUntilGivesUpAndStops() {
        let binding = TriggerBinding(trigger: tap3, steps: [.action(openNotes), .waitUntil(notesInFront, timeout: 2), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        var fired: [ActionResult] = []
        rig.engine.onFired = { _, _, result in fired.append(result) }
        rig.engine.receive(tap3)
        rig.scheduler.advance(3)
        #expect(rig.performer.calls.map(\.action) == [openNotes], "the rest doesn't run")
        guard case .failed(let message)? = fired.first else { Issue.record("should fail"); return }
        #expect(message.contains("Notes is in front"))
        #expect(!rig.scheduler.hasPending, "no polling left behind")
    }

    @Test func aFailureStopsTheRestAndASkipDoesnt() {
        let binding = TriggerBinding(trigger: tap3, steps: [.action(.window(.center)), .action(.click(.middle)), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        rig.performer.results = [.window(.center): .skipped("No window to move.")]
        var fired: [ActionResult] = []
        rig.engine.onFired = { _, _, result in fired.append(result) }
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.count == 3, "a skipped step doesn't stop the others")
        #expect(fired == [.skipped("No window to move.")])
        rig.performer.results = [.click(.middle): .failed("Couldn't click.")]
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.count == 5, "a failed step stops the sequence")
        #expect(fired.last == .failed("Couldn't click."))
    }

    @Test func slowActionsAreWaitedFor() {
        let script = Action.script(.shell, "sleep 1")
        let binding = TriggerBinding(trigger: tap3, steps: [.action(script), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        rig.performer.slow = [script]
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.map(\.action) == [script])
        rig.performer.finishWaiting()
        #expect(rig.performer.calls.map(\.action) == [script, newNote])
    }

    @Test func aSecondFireWhileRunningIsIgnored() {
        let binding = TriggerBinding(trigger: tap3, steps: [.action(.click(.middle)), .delay(1), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        rig.engine.receive(tap3)
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.count == 1)
        rig.scheduler.advance(1.1)
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.count == 3, "runs again once the first finished")
    }

    @Test func pauseStopsARunningSequence() {
        let binding = TriggerBinding(trigger: tap3, steps: [.action(.click(.middle)), .delay(1), .action(newNote)], scope: .allApps)
        let rig = rig([binding])
        rig.engine.receive(tap3)
        rig.engine.isPaused = true
        rig.scheduler.advance(2)
        #expect(rig.performer.calls.count == 1)
        #expect(!rig.engine.isRunning(binding.id))
    }

    @Test func singleActionBindingsStayInstant() {
        let rig = rig([TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)])
        var fired = 0
        rig.engine.onFired = { _, _, _ in fired += 1 }
        rig.engine.receive(tap3)
        #expect(fired == 1 && !rig.scheduler.hasPending, "done before receive returns")
    }

    // MARK: Conditions

    @Test func conditionsPickTheTrigger() {
        let onBattery = TriggerBinding(trigger: tap3, action: .media(.playPause), conditions: ConditionSet([.power(.battery)]), scope: .allApps)
        let otherwise = TriggerBinding(trigger: tap3, action: .click(.middle), scope: .allApps)
        let rig = rig([onBattery, otherwise])
        rig.engine.receive(tap3)
        rig.state.power = .battery
        rig.engine.receive(tap3)
        #expect(rig.performer.calls.map(\.action) == [.click(.middle), .media(.playPause)])
    }

    @Test func aSwallowedButtonWhoseConditionsFailGoesToTheApp() {
        let binding = TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .pressKeys(cmdLeftBracket),
                                     conditions: ConditionSet([.network(.offline)]), scope: .allApps)
        let rig = rig([binding])
        #expect(rig.mouse.press(3).down == .swallowAndFire(binding.id), "the tap can't check conditions: it swallows")
        #expect(rig.performer.calls.isEmpty)
        #expect(rig.performer.delivered == [.mouseButton(3, modifiers: [])], "so the press is given back")
    }

    @Test func aHotkeyWhoseConditionsFailIsLetThrough() {
        let binding = TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.center),
                                     conditions: ConditionSet([.appRunning(bundleID: "com.apple.Music", name: "Music", running: true)]), scope: .allApps)
        let rig = rig([binding])
        rig.hotkeys.press(ctrlOptK)
        #expect(rig.performer.calls.isEmpty)
        #expect(rig.hotkeys.suspended == [ctrlOptK], "unregistered for a moment")
        #expect(rig.performer.delivered == [.keyCombo(ctrlOptK)])
        rig.state.running = ["com.apple.Music"]
        rig.hotkeys.press(ctrlOptK)
        #expect(rig.performer.calls.map(\.action) == [.window(.center)])
    }

    @Test func runNowIgnoresConditions() {
        let binding = TriggerBinding(trigger: tap3, action: .click(.middle), conditions: ConditionSet([.network(.offline)]), scope: .allApps)
        let rig = rig([binding])
        rig.engine.runNow(binding)
        #expect(rig.performer.calls.count == 1)
    }

    // MARK: Keyboard tap

    @Test func keyboardTapOnlyForSequencesOrTheHyperKey() {
        let rig = rig([TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.center), scope: .allApps)])
        #expect(!rig.keyboard.isInstalled, "key combinations use hotkeys, not a tap")
        rig.engine.hyperKeyEnabled = true
        #expect(rig.keyboard.isInstalled && rig.keyboard.hyperKey)
        rig.engine.hyperKeyEnabled = false
        #expect(!rig.keyboard.isInstalled && !rig.keyboard.hyperKey)
    }

    @Test func keySequencesFireTheirSteps() {
        let binding = TriggerBinding(trigger: .keySequence(.doubleTap(.command)), action: .system(.missionControl), scope: .allApps)
        let rig = rig([binding])
        #expect(rig.keyboard.isInstalled)
        #expect(rig.keyboard.sequences == [.doubleTap(.command)])
        rig.keyboard.tapModifier(.command, at: 0)
        rig.keyboard.tapModifier(.command, at: 0.3)
        #expect(rig.performer.calls.map(\.action) == [.system(.missionControl)])
    }

    @Test func perAppSequencesFollowTheFrontApp() {
        let rig = rig([TriggerBinding(trigger: .keySequence(.doubleTap(.shift)), action: .window(.center), scope: .app(bundleID: "com.apple.Notes"))])
        #expect(rig.keyboard.sequences.isEmpty, "Safari is in front")
        rig.engine.frontApp = notes
        #expect(rig.keyboard.sequences == [.doubleTap(.shift)])
    }

    @Test func pauseAndRevokedAccessibilityRemoveTheTapAndTheRemap() {
        let rig = rig([TriggerBinding(trigger: .keySequence(.doubleTap(.command)), action: .window(.center), scope: .allApps)])
        rig.engine.hyperKeyEnabled = true
        rig.engine.isPaused = true
        #expect(!rig.keyboard.isInstalled && !rig.keyboard.hyperKey, "paused: Caps Lock is Caps Lock again")
        rig.engine.isPaused = false
        #expect(rig.keyboard.isInstalled && rig.keyboard.hyperKey)
        rig.engine.accessibilityRevoked()
        #expect(!rig.keyboard.isInstalled && !rig.keyboard.hyperKey)
    }

    @Test func recordingKeepsTheHyperKeyButNotSequences() {
        let rig = rig([TriggerBinding(trigger: .keySequence(.doubleTap(.command)), action: .window(.center), scope: .allApps)])
        rig.engine.hyperKeyEnabled = true
        rig.engine.startRecording()
        #expect(rig.keyboard.hyperKey, "so a hyper combination can be recorded")
        #expect(rig.keyboard.sequences.isEmpty)
        rig.engine.stopRecording()
        #expect(rig.keyboard.sequences == [.doubleTap(.command)])
    }

    @Test func noTrustNoKeyboardTap() {
        let rig = EngineRig()
        rig.engine.isAccessibilityTrusted = false
        rig.engine.hyperKeyEnabled = true
        rig.engine.update(config: Config(bindings: [TriggerBinding(trigger: .keySequence(.doubleTap(.command)), action: .window(.center), scope: .allApps)]))
        #expect(!rig.keyboard.isInstalled)
    }

    @Test func shutDownUndoesTheRemap() {
        let rig = rig([])
        rig.engine.hyperKeyEnabled = true
        #expect(rig.keyboard.hyperKey)
        rig.engine.shutDown()
        #expect(!rig.keyboard.isInstalled && !rig.keyboard.hyperKey)
    }

    // MARK: Gesture interests

    @Test func theRecognizerLooksOnlyForBoundGesturesExceptWhileRecording() {
        let rig = rig([TriggerBinding(trigger: .gesture(.doubleTap(3), modifiers: []), action: .click(.middle), scope: .allApps)])
        #expect(rig.touch.interests == GestureInterests([.doubleTap(3)]))
        rig.engine.startRecording()
        #expect(rig.touch.interests == .all)
        rig.engine.stopRecording()
        rig.touch.feed(SyntheticTouches.frames(for: .doubleTap(3)))
        #expect(rig.performer.calls.map(\.action) == [.click(.middle)])
    }

    @Test func newGesturesRunThroughTheEngine() {
        let bindings = [Gesture.pinchOut(2), .rotate(true), .cornerTap(.topRight), .edgeSwipe(.left), .tipTap(.left), .swipe(5, .up)].map {
            TriggerBinding(trigger: .gesture($0, modifiers: []), action: .media(.volumeUp), scope: .allApps)
        }
        let rig = rig(bindings)
        for binding in bindings {
            guard case .gesture(let gesture, _) = binding.trigger else { continue }
            rig.touch.feed(SyntheticTouches.frames(for: gesture, at: rig.clock.now))
            rig.clock.now += 5
        }
        #expect(rig.performer.calls.map(\.trigger) == bindings.map(\.trigger))
    }
}
