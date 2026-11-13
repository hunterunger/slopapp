import Foundation
import Testing
@testable import TriggersCore

@MainActor
@Suite struct EngineTests {
    @Test func startsNothingWithNoBindings() {
        let rig = EngineRig()
        rig.engine.update(config: Config())
        #expect(!rig.touch.isRunning)
        #expect(!rig.mouse.isInstalled)
        #expect(rig.hotkeys.registered.isEmpty)
    }

    @Test func gestureRunsItsAction() {
        let rig = EngineRig()
        rig.engine.update(config: Config(bindings: [TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps)]))
        rig.engine.frontApp = safari
        #expect(rig.touch.isRunning)
        #expect(!rig.mouse.isInstalled, "no tap without mouse bindings")
        rig.touch.feed(SyntheticTouches.tap(fingers: 3))
        #expect(rig.performer.calls == [.init(action: .click(.middle), app: "com.apple.Safari", trigger: .gesture(.tap(3), modifiers: []))])
    }

    @Test func gestureCarriesHeldModifiers() {
        let rig = EngineRig(modifiers: .option)
        let binding = TriggerBinding(trigger: .gesture(.swipe(4, .left), modifiers: .option), action: .window(.leftHalf), scope: .allApps)
        rig.engine.update(config: Config(bindings: [binding]))
        rig.touch.feed(SyntheticTouches.swipe(fingers: 4, direction: .left))
        #expect(rig.performer.calls.map(\.action) == [.window(.leftHalf)])
    }

    @Test func mouseTapOnlyWithMouseBindingsAndAccessibility() {
        let rig = EngineRig()
        let binding = TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .pressKeys(cmdLeftBracket), scope: .browsers)
        rig.engine.isAccessibilityTrusted = false
        rig.engine.update(config: Config(bindings: [binding]))
        #expect(!rig.mouse.isInstalled)
        rig.engine.isAccessibilityTrusted = true
        #expect(rig.mouse.isInstalled)
        rig.engine.frontApp = safari
        #expect(rig.mouse.press(3).down == .swallowAndFire(binding.id))
        rig.engine.frontApp = notes
        #expect(rig.mouse.press(3).down == .pass, "passed through outside browsers")
        #expect(rig.performer.calls.count == 1)
    }

    @Test func accessibilityRevokedRemovesTheTapImmediately() {
        let rig = EngineRig()
        rig.engine.update(config: Config(bindings: [TriggerBinding(trigger: .mouseButton(2, modifiers: []), action: .window(.center), scope: .allApps)]))
        #expect(rig.mouse.isInstalled)
        rig.engine.accessibilityRevoked()
        #expect(!rig.mouse.isInstalled)
        rig.engine.isAccessibilityTrusted = true
        #expect(rig.mouse.isInstalled, "comes back without a restart")
    }

    @Test func removingTheLastMouseBindingRemovesTheTap() {
        let rig = EngineRig()
        let binding = TriggerBinding(trigger: .mouseButton(2, modifiers: []), action: .window(.center), scope: .allApps)
        rig.engine.update(config: Config(bindings: [binding]))
        #expect(rig.mouse.isInstalled)
        var off = binding
        off.isEnabled = false
        rig.engine.update(config: Config(bindings: [off]))
        #expect(!rig.mouse.isInstalled)
    }

    @Test func hotkeysRegisteredPerFrontApp() {
        let rig = EngineRig()
        let notesOnly = TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .menuItem(["Format", "Bold"]), scope: .app(bundleID: "com.apple.Notes"))
        rig.engine.update(config: Config(bindings: [notesOnly]))
        rig.engine.frontApp = safari
        #expect(rig.hotkeys.registered.isEmpty, "the combo stays Safari's own")
        rig.engine.frontApp = notes
        #expect(rig.hotkeys.registered == [ctrlOptK])
        rig.hotkeys.press(ctrlOptK)
        #expect(rig.performer.calls.map(\.action) == [.menuItem(["Format", "Bold"])])
    }

    @Test func takenHotkeysAreReported() {
        let rig = EngineRig()
        rig.hotkeys.takenByOthers = [ctrlOptK]
        rig.engine.update(config: Config(bindings: [TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.maximize), scope: .allApps)]))
        #expect(rig.engine.unavailableShortcuts == [ctrlOptK])
    }

    @Test func pauseStopsEverythingAndResumeRestores() {
        let rig = EngineRig()
        rig.engine.update(config: Config(bindings: [
            TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps),
            TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .click(.right), scope: .allApps),
            TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.center), scope: .allApps),
        ]))
        rig.engine.isPaused = true
        #expect(!rig.touch.isRunning && !rig.mouse.isInstalled && rig.hotkeys.registered.isEmpty)
        rig.engine.receive(.keyCombo(ctrlOptK))
        #expect(rig.performer.calls.isEmpty)
        rig.engine.isPaused = false
        #expect(rig.touch.isRunning && rig.mouse.isInstalled && rig.hotkeys.registered == [ctrlOptK])
    }

    @Test func recordingNamesInputsAndPerformsNothing() {
        let rig = EngineRig()
        rig.engine.update(config: Config(bindings: [
            TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .click(.right), scope: .allApps),
            TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.center), scope: .allApps),
        ]))
        var recorded: [Trigger] = []
        rig.engine.onRecord = { recorded.append($0) }
        rig.engine.startRecording()
        #expect(rig.touch.isRunning, "touches are read while recording, even with no gesture bindings")
        #expect(rig.hotkeys.registered.isEmpty, "existing combos can be pressed and recorded")
        #expect(rig.mouse.press(3).down == .pass, "buttons reach the recording window")
        rig.touch.feed(SyntheticTouches.tap(fingers: 4))
        rig.touch.idle(until: 10) // recording also listens for double taps, so a single one waits
        rig.engine.receive(.keyCombo(ctrlOptK))
        #expect(recorded == [.gesture(.tap(4), modifiers: []), .keyCombo(ctrlOptK)])
        #expect(rig.performer.calls.isEmpty)
        rig.engine.stopRecording()
        #expect(!rig.touch.isRunning)
        #expect(rig.hotkeys.registered == [ctrlOptK])
    }

    @Test func gesturesUnavailableLeavesMouseAndKeysWorking() {
        let rig = EngineRig()
        rig.touch.unavailableReason = "Trackpad gestures aren't available on this Mac."
        rig.engine.update(config: Config(bindings: [
            TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps),
            TriggerBinding(trigger: .mouseButton(3, modifiers: []), action: .click(.right), scope: .allApps),
            TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.center), scope: .allApps),
        ]))
        #expect(!rig.touch.isRunning)
        #expect(rig.mouse.isInstalled)
        rig.hotkeys.press(ctrlOptK)
        #expect(rig.performer.calls.count == 1)
    }

    @Test func postedKeysDontLoopThroughTheirOwnHotkey() {
        let rig = EngineRig()
        // A binding that presses its own trigger (the editor warns about it).
        rig.engine.update(config: Config(bindings: [TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .pressKeys(ctrlOptK), scope: .allApps)]))
        rig.hotkeys.press(ctrlOptK)
        rig.clock.now += 0.01
        rig.hotkeys.press(ctrlOptK) // the posted copy comes back
        #expect(rig.performer.calls.count == 1)
        rig.clock.now += 1
        rig.hotkeys.press(ctrlOptK) // a real press later works again
        #expect(rig.performer.calls.count == 2)
    }

    @Test func runNowAndFiredCallback() {
        let rig = EngineRig()
        let binding = TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .open(.url("https://example.com")), scope: .allApps)
        rig.engine.update(config: Config(bindings: [binding]))
        var fired: [(UUID, ActionResult)] = []
        rig.engine.onFired = { binding, _, result in fired.append((binding.id, result)) }
        rig.performer.result = .failed("Couldn't open it.")
        rig.engine.runNow(binding)
        #expect(fired.count == 1 && fired[0].0 == binding.id && fired[0].1 == .failed("Couldn't open it."))
    }

    @Test func turnOffInFrontAppUpdatesLiveRouting() {
        let rig = EngineRig()
        var config = Config(bindings: [TriggerBinding(trigger: .mouseButton(2, modifiers: []), action: .window(.center), scope: .allApps)])
        rig.engine.update(config: config)
        rig.engine.frontApp = game
        #expect(!rig.mouse.routes.isEmpty)
        config.setUsesAllAppsTriggers(false, in: "com.example.game", name: "Game")
        rig.engine.update(config: config)
        #expect(rig.mouse.routes.isEmpty)
        #expect(rig.mouse.isInstalled, "still needed for other apps")
    }

    @Test func dispatchLatencyIsRecorded() {
        let rig = EngineRig()
        rig.engine.update(config: Config(bindings: [TriggerBinding(trigger: .keyCombo(ctrlOptK), action: .window(.center), scope: .allApps)]))
        rig.engine.receive(.keyCombo(ctrlOptK))
        #expect(rig.engine.dispatchLatency.count == 1)
    }
}
