import Foundation
import Testing
@testable import TriggersCore

private let g = 5, h = 4, k = 40

@Suite struct KeySequenceTests {
    private func matcher(_ sequences: [KeySequence]) -> KeySequenceMatcher {
        var matcher = KeySequenceMatcher()
        matcher.set(sequences)
        return matcher
    }

    /// A lone modifier tap: down, then up 50 ms later.
    private func tap(_ modifier: Modifiers, at time: Double, _ matcher: inout KeySequenceMatcher) -> KeySequence? {
        _ = matcher.flagsChanged(modifier, time: time)
        return matcher.flagsChanged([], time: time + 0.05)
    }

    @Test func commandTwice() {
        var m = matcher([.doubleTap(.command)])
        #expect(tap(.command, at: 0, &m) == nil)
        #expect(tap(.command, at: 0.3, &m) == .doubleTap(.command))
    }

    @Test func tooSlowIsNotASequence() {
        var m = matcher([.doubleTap(.command)])
        _ = tap(.command, at: 0, &m)
        #expect(tap(.command, at: 0.8, &m) == nil, "more than the 0.5 s timeout apart")
        #expect(tap(.command, at: 1.1, &m) == .doubleTap(.command), "but the second one starts a new try")
    }

    @Test func aChordIsNotAModifierTap() {
        var m = matcher([KeySequence([.modifierTap(.command)])])
        _ = m.flagsChanged(.command, time: 0)
        _ = m.flagsChanged([.command, .shift], time: 0.05)
        _ = m.flagsChanged(.command, time: 0.08)
        #expect(m.flagsChanged([], time: 0.1) == nil)
    }

    @Test func commandWithAKeyIsNotACommandTap() {
        var m = matcher([KeySequence([.modifierTap(.command)])])
        _ = m.flagsChanged(.command, time: 0)
        _ = m.keyDown(keyCode: k, modifiers: .command, isRepeat: false, time: 0.05)
        #expect(m.flagsChanged([], time: 0.1) == nil)
    }

    @Test func commandClickIsNotACommandTap() {
        var m = matcher([KeySequence([.modifierTap(.command)])])
        _ = m.flagsChanged(.command, time: 0)
        #expect(m.flagsChanged([], time: 0.2) { _ in true } == nil, "a click happened while ⌘ was down")
    }

    @Test func heldTooLongIsNotATap() {
        var m = matcher([KeySequence([.modifierTap(.option)])])
        _ = m.flagsChanged(.option, time: 0)
        #expect(m.flagsChanged([], time: 0.9) == nil)
    }

    @Test func gThenH() {
        let sequence = KeySequence([.key(KeyCombo(keyCode: g, modifiers: [])), .key(KeyCombo(keyCode: h, modifiers: []))])
        var m = matcher([sequence])
        #expect(m.keyDown(keyCode: g, modifiers: [], isRepeat: false, time: 0) == nil)
        #expect(m.keyDown(keyCode: h, modifiers: [], isRepeat: false, time: 0.2) == sequence)
        // Shift-G then H is something else.
        #expect(m.keyDown(keyCode: g, modifiers: .shift, isRepeat: false, time: 1) == nil)
        #expect(m.keyDown(keyCode: h, modifiers: [], isRepeat: false, time: 1.1) == nil)
    }

    @Test func autorepeatIsNotAPress() {
        let sequence = KeySequence([.key(KeyCombo(keyCode: g, modifiers: [])), .key(KeyCombo(keyCode: g, modifiers: []))])
        var m = matcher([sequence])
        _ = m.keyDown(keyCode: g, modifiers: [], isRepeat: false, time: 0)
        #expect(m.keyDown(keyCode: g, modifiers: [], isRepeat: true, time: 0.1) == nil, "holding G isn't G twice")
    }

    @Test func historyStartsOverAfterAMatch() {
        var m = matcher([.doubleTap(.command)])
        _ = tap(.command, at: 0, &m)
        #expect(tap(.command, at: 0.2, &m) != nil)
        #expect(tap(.command, at: 0.4, &m) == nil, "the third tap doesn't fire again")
    }

    @Test func longestSequenceWins() {
        let twice = KeySequence.doubleTap(.shift)
        let thrice = KeySequence([.modifierTap(.shift), .modifierTap(.shift), .modifierTap(.shift)])
        var m = matcher([twice, thrice])
        _ = tap(.shift, at: 0, &m)
        #expect(tap(.shift, at: 0.2, &m) == twice)
        // Three in a row after a pause: the history was cleared, so two more give "twice" again,
        // but three straight after a fresh start reach "three times" only if nothing fired.
        var only3 = matcher([thrice])
        _ = tap(.shift, at: 0, &only3)
        _ = tap(.shift, at: 0.2, &only3)
        #expect(tap(.shift, at: 0.4, &only3) == thrice)
    }

    @Test func usableSequences() {
        #expect(KeySequence.doubleTap(.command).isUsable)
        #expect(KeySequence([.modifierTap(.option)]).isUsable, "a lone modifier tap")
        #expect(!KeySequence([.key(KeyCombo(keyCode: g, modifiers: []))]).isUsable, "one plain key is typing")
        #expect(!KeySequence([.modifierTap([.command, .option])]).isUsable, "a tap is one modifier")
        #expect(!KeySequence(Array(repeating: .modifierTap(.command), count: 5)).isUsable, "at most four presses")
        #expect(KeySequence([.key(KeyCombo(keyCode: g, modifiers: [])), .key(KeyCombo(keyCode: h, modifiers: []))]).typesText)
        #expect(!KeySequence.doubleTap(.command).typesText)
    }

    // MARK: Recording

    @Test func recordingAComboStaysACombo() {
        var recorder = KeySequenceRecorder(timeout: 1)
        _ = recorder.keyDown(keyCode: k, modifiers: [.control, .option], isRepeat: false, time: 0)
        #expect(recorder.trigger == .keyCombo(KeyCombo(keyCode: k, modifiers: [.control, .option])))
    }

    @Test func aSecondPressMakesASequence() {
        var recorder = KeySequenceRecorder(timeout: 1)
        _ = recorder.keyDown(keyCode: k, modifiers: .control, isRepeat: false, time: 0)
        _ = recorder.keyDown(keyCode: 8, modifiers: .control, isRepeat: false, time: 0.4)
        guard case .keySequence(let sequence)? = recorder.trigger else { Issue.record("not a sequence"); return }
        #expect(sequence.steps == [.key(KeyCombo(keyCode: k, modifiers: .control)), .key(KeyCombo(keyCode: 8, modifiers: .control))])
        #expect(sequence.timeout >= 0.5, "fast enough for the pause it was recorded with")
    }

    @Test func aSlowRecordingGetsAMoreForgivingTimeout() {
        var recorder = KeySequenceRecorder(timeout: 1)
        _ = recorder.keyDown(keyCode: g, modifiers: [], isRepeat: false, time: 0)
        _ = recorder.keyDown(keyCode: h, modifiers: [], isRepeat: false, time: 0.8)
        guard case .keySequence(let sequence)? = recorder.trigger else { Issue.record("not a sequence"); return }
        #expect(sequence.timeout >= 1, "0.8 s between presses needs at least a second")
    }

    @Test func onePlainKeyIsNothingYet() {
        var recorder = KeySequenceRecorder(timeout: 1)
        #expect(recorder.keyDown(keyCode: g, modifiers: [], isRepeat: false, time: 0) == .recording([.key(KeyCombo(keyCode: g, modifiers: []))]))
        #expect(recorder.trigger == nil)
    }

    @Test func modifierTapsRecord() {
        var recorder = KeySequenceRecorder(timeout: 1)
        _ = recorder.flagsChanged(.command, time: 0)
        _ = recorder.flagsChanged([], time: 0.05)
        #expect(recorder.trigger == .keySequence(KeySequence([.modifierTap(.command)])))
        _ = recorder.flagsChanged(.command, time: 0.3)
        _ = recorder.flagsChanged([], time: 0.35)
        #expect(recorder.trigger == .keySequence(.doubleTap(.command)))
    }

    @Test func aPauseStartsOver() {
        var recorder = KeySequenceRecorder(timeout: 1)
        _ = recorder.keyDown(keyCode: g, modifiers: [], isRepeat: false, time: 0)
        #expect(recorder.isFinished(at: 1.5))
        _ = recorder.keyDown(keyCode: k, modifiers: .command, isRepeat: false, time: 2)
        #expect(recorder.trigger == .keyCombo(KeyCombo(keyCode: k, modifiers: .command)))
    }
}

@Suite struct HyperKeyTests {
    private let hyperFlags = Modifiers.all.cgFlags

    @Test func capsLockDownPressesAllFourModifiers() {
        var decider = HyperKeyDecider()
        guard case .replace(let events) = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 0, isOwnEvent: false) else {
            Issue.record("F18 down should be replaced"); return
        }
        #expect(events.map(\.kind) == [.flagsChanged, .flagsChanged, .flagsChanged, .flagsChanged])
        #expect(KeyPostPlan.finalModifiers(events) == .all)
        #expect(decider.isHeld)
    }

    @Test func keysWhileHeldCarryHyper() {
        var decider = HyperKeyDecider()
        _ = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 0, isOwnEvent: false)
        #expect(decider.decide(.keyDown, keyCode: k, flags: 0, isRepeat: false, time: 0.1, isOwnEvent: false) == .passWithFlags(hyperFlags))
        #expect(decider.decide(.keyUp, keyCode: k, flags: 0, isRepeat: false, time: 0.15, isOwnEvent: false) == .passWithFlags(hyperFlags))
    }

    @Test func releasingAfterUseLetsGoWithoutEscape() {
        var decider = HyperKeyDecider()
        _ = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 0, isOwnEvent: false)
        _ = decider.decide(.keyDown, keyCode: k, flags: hyperFlags, isRepeat: false, time: 0.1, isOwnEvent: false)
        guard case .replace(let events) = decider.decide(.keyUp, keyCode: KeyNames.f18, flags: hyperFlags, isRepeat: false, time: 0.2, isOwnEvent: false) else {
            Issue.record("F18 up should be replaced"); return
        }
        #expect(KeyPostPlan.finalModifiers(events) == [], "every modifier let go")
        #expect(!events.contains { $0.keyCode == KeyNames.escape })
        #expect(!decider.isHeld)
    }

    @Test func aTapAloneIsEscape() {
        var decider = HyperKeyDecider()
        _ = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 0, isOwnEvent: false)
        guard case .replace(let events) = decider.decide(.keyUp, keyCode: KeyNames.f18, flags: hyperFlags, isRepeat: false, time: 0.15, isOwnEvent: false) else {
            Issue.record("F18 up should be replaced"); return
        }
        let escape = events.filter { $0.keyCode == KeyNames.escape }
        #expect(escape.map(\.kind) == [.keyDown, .keyUp])
        #expect(escape.allSatisfy { Modifiers(cgFlags: $0.flags).isEmpty }, "a plain Escape, not hyper-Escape")
        #expect(KeyPostPlan.finalModifiers(events) == [])
    }

    @Test func aLongHoldOrAClickIsNotEscape() {
        var decider = HyperKeyDecider()
        _ = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 0, isOwnEvent: false)
        guard case .replace(let long) = decider.decide(.keyUp, keyCode: KeyNames.f18, flags: hyperFlags, isRepeat: false, time: 2, isOwnEvent: false) else { return }
        #expect(!long.contains { $0.keyCode == KeyNames.escape })
        _ = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 5, isOwnEvent: false)
        guard case .replace(let clicked) = decider.decide(.keyUp, keyCode: KeyNames.f18, flags: hyperFlags, isRepeat: false, time: 5.2,
                                                           isOwnEvent: false, clickedSince: { _ in true }) else { return }
        #expect(!clicked.contains { $0.keyCode == KeyNames.escape }, "hyper-click used it")
    }

    @Test func repeatsAreSwallowedAndOwnEventsPass() {
        var decider = HyperKeyDecider()
        _ = decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: false, time: 0, isOwnEvent: false)
        #expect(decider.decide(.keyDown, keyCode: KeyNames.f18, flags: 0, isRepeat: true, time: 0.5, isOwnEvent: false) == .replace(with: []))
        #expect(decider.decide(.keyDown, keyCode: k, flags: 0, isRepeat: false, time: 0.6, isOwnEvent: true) == .pass, "our own posted keys")
    }

    @Test func otherKeysPassWhenNotHeld() {
        var decider = HyperKeyDecider()
        #expect(decider.decide(.keyDown, keyCode: k, flags: 0, isRepeat: false, time: 0, isOwnEvent: false) == .pass)
        #expect(decider.decide(.flagsChanged, keyCode: 55, flags: Modifiers.command.cgFlags, isRepeat: false, time: 0, isOwnEvent: false) == .pass)
    }

    // MARK: The remap

    @MainActor
    final class FakeRemapper: KeyRemapper {
        var state = KeyRemapState.none
        var accepts = true
        private(set) var applies = 0
        private(set) var removes = 0
        func currentMapping() -> KeyRemapState { state }
        func applyHyper() -> Bool {
            applies += 1
            if accepts { state = .ours }
            return accepts
        }
        func removeHyper() {
            removes += 1
            state = .none
        }
    }

    @MainActor @Test func turnsOnAndOffCleanly() {
        let remapper = FakeRemapper()
        let controller = HyperKeyController(remapper: remapper)
        controller.setActive(true)
        #expect(controller.isActive && remapper.state == .ours && controller.problem == nil)
        controller.setActive(true)
        #expect(remapper.applies == 1, "idempotent")
        controller.setActive(false)
        #expect(!controller.isActive && remapper.state == .none)
    }

    @MainActor @Test func neverOverwritesSomeoneElsesRemap() {
        let remapper = FakeRemapper()
        remapper.state = .other
        let controller = HyperKeyController(remapper: remapper)
        controller.setActive(true)
        #expect(!controller.isActive)
        #expect(remapper.applies == 0)
        #expect(controller.problem != nil)
    }

    @MainActor @Test func aRefusedRemapLeavesCapsLockAlone() {
        let remapper = FakeRemapper()
        remapper.accepts = false
        let controller = HyperKeyController(remapper: remapper)
        controller.setActive(true)
        #expect(!controller.isActive && controller.problem != nil)
    }

    @MainActor @Test func leftoversFromACrashAreCleanedUp() {
        let remapper = FakeRemapper()
        remapper.state = .ours
        let controller = HyperKeyController(remapper: remapper)
        controller.cleanUpLeftovers()
        #expect(remapper.state == .none && remapper.removes == 1)
        remapper.state = .other
        controller.cleanUpLeftovers()
        #expect(remapper.state == .other, "someone else's mapping is never touched")
    }

    @MainActor @Test func reappliesForNewKeyboardsOnlyWhileOn() {
        let remapper = FakeRemapper()
        let controller = HyperKeyController(remapper: remapper)
        controller.reapply()
        #expect(remapper.applies == 0)
        controller.setActive(true)
        controller.reapply()
        #expect(remapper.applies == 2)
    }

    @Test func readsHidutilOutput() {
        let none = """
        RegistryID  Key                   Value
        100000b30   UserKeyMapping   (null)
        100000a0a   UserKeyMapping   (null)
        """
        #expect(UserKeyMappingText.state(of: none) == .none)
        let ours = """
        RegistryID  Key                   Value
        100000b30   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000a0a   UserKeyMapping   (null)
        """
        #expect(UserKeyMappingText.state(of: ours) == .ours)
        let other = """
        RegistryID  Key                   Value
        100000b30   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771300;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        #expect(UserKeyMappingText.state(of: other) == .other)
        #expect(UserKeyMappingText.hyperJSON.contains("30064771129") && UserKeyMappingText.hyperJSON.contains("30064771181"))
    }
}
