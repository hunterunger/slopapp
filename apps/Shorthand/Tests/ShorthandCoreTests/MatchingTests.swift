import CoreGraphics
import Foundation
import Testing
@testable import ShorthandCore

func snippet(_ abbreviation: String, _ content: String = "slopapp-test text", case mode: CaseMode = .exact, group: UUID = UUID()) -> Snippet {
    Snippet(groupID: group, abbreviation: abbreviation, content: content, caseMode: mode)
}

/// Types `text` into a fresh engine and returns the decisions that weren't `.none`.
func type(_ text: String, into engine: inout TapEngine, at start: UInt64 = 1_000, step: UInt64 = 50_000_000) -> [TapDecision] {
    var now = start
    var result: [TapDecision] = []
    for input in KeyInput.text(text) {
        let decision = engine.handle(input, now: now)
        if decision != .none { result.append(decision) }
        now += step
    }
    return result
}

@Suite("Rolling buffer")
struct RollingBufferTests {
    @Test func keepsTheLast32Characters() {
        var buffer = RollingBuffer()
        for scalar in String(repeating: "ab", count: 20).unicodeScalars { buffer.append(scalar.value) }
        #expect(buffer.count == 32)
        #expect(buffer.contents == String(repeating: "ab", count: 16))
        #expect(buffer.beforeIsWord) // the dropped "b" was a letter
    }

    @Test func backspaceRemovesTheNewest() {
        var buffer = RollingBuffer()
        for scalar in "abc".unicodeScalars { buffer.append(scalar.value) }
        buffer.removeLast()
        #expect(buffer.contents == "ab")
        buffer.removeLast(); buffer.removeLast(); buffer.removeLast()
        #expect(buffer.isEmpty)
        #expect(!buffer.beforeIsWord)
    }

    @Test func resetForgetsEverything() {
        var buffer = RollingBuffer()
        for scalar in "secret".unicodeScalars { buffer.append(scalar.value) }
        buffer.reset()
        #expect(buffer.contents == "")
        #expect(buffer.count == 0)
    }

    @Test func wordBefore() {
        var buffer = RollingBuffer()
        for scalar in "a;b".unicodeScalars { buffer.append(scalar.value) }
        #expect(buffer.isWordBefore(length: 2))   // "a" before ";b"
        #expect(!buffer.isWordBefore(length: 1))  // ";" before "b"
        #expect(!buffer.isWordBefore(length: 3))  // start of buffer after reset: boundary
    }
}

@Suite("Matching")
struct MatchingTests {
    func engine(_ snippets: [Snippet], wordStart: Bool = true) -> TapEngine {
        var engine = TapEngine()
        engine.index = AbbreviationIndex(snippets: snippets)
        engine.wordStartOnly = wordStart
        return engine
    }

    @Test func firesOnTheLastCharacter() {
        let addr = snippet(";addr")
        var engine = engine([addr])
        let decisions = type(";addr", into: &engine)
        #expect(decisions.count == 1)
        guard case .expand(let match) = decisions.first else { Issue.record("no match"); return }
        #expect(match.snippetID == addr.id)
        #expect(match.length == 5)
    }

    @Test func wholeWordRule() {
        var on = engine([snippet("sig")])
        #expect(type("design", into: &on).isEmpty)
        #expect(type(" sig", into: &on).count == 1)

        var off = engine([snippet("sig")], wordStart: false)
        #expect(type("design", into: &off).count == 1)
    }

    @Test func afterPunctuationAndNewLines() {
        var e = engine([snippet("sig")])
        #expect(type("(sig", into: &e).count == 1)
        var e2 = engine([snippet("sig")])
        _ = e2.handle(KeyInput(kind: .boundary), now: 1)
        #expect(type("sig", into: &e2).count == 1)
    }

    @Test func exactCaseOnly() {
        var e = engine([snippet(";addr")])
        #expect(type(";ADDR", into: &e).isEmpty)
        #expect(type(" ;Addr", into: &e).isEmpty)
    }

    @Test func adaptCaseMatchesAnyCaseAndReportsIt() {
        var e = engine([snippet(";addr", case: .adapt)])
        guard case .expand(let upper) = type(";ADDR", into: &e).first else { Issue.record("no match"); return }
        #expect(upper.typedCase == .upper)
        e.cancel(upper.id)
        guard case .expand(let capital) = type(" ;Addr", into: &e).first else { Issue.record("no match"); return }
        #expect(capital.typedCase == .capitalized)
        e.cancel(capital.id)
        guard case .expand(let lower) = type(" ;addr", into: &e).first else { Issue.record("no match"); return }
        #expect(lower.typedCase == .asWritten)
    }

    @Test func longestMatchWins() {
        let short = snippet("dr")
        let long = snippet(";addr")
        var e = engine([short, long], wordStart: false)
        guard case .expand(let match) = type(";addr", into: &e).last else { Issue.record("no match"); return }
        #expect(match.snippetID == long.id)
    }

    @Test func duplicatesNeverExpand() {
        var e = engine([snippet(";x"), snippet(";x")])
        #expect(type(";x", into: &e).isEmpty)
        // An adapt-case one clashes with an exact one of the same letters.
        var e2 = engine([snippet(";Ab"), snippet(";ab", case: .adapt)])
        #expect(type(";ab", into: &e2).isEmpty)
    }

    @Test func backspaceEditsTheBuffer() {
        var e = engine([snippet(";addr")])
        #expect(type(";adx", into: &e).isEmpty)
        _ = e.handle(KeyInput(kind: .backspace), now: 10)
        #expect(type("dr", into: &e).count == 1)
    }

    @Test func resetsOnNavigationAndShortcuts() {
        var e = engine([snippet(";addr")])
        _ = type(";ad", into: &e)
        _ = e.handle(KeyInput(kind: .reset), now: 10)
        #expect(type("dr", into: &e).isEmpty)
    }

    @Test func deadKeysResetAndSkipTheComposedLetter() {
        var e = engine([snippet("ex")])
        _ = e.handle(KeyInput(kind: .deadKey), now: 1)
        // The composed letter: ignored, and what follows is mid-word.
        #expect(type("ex", into: &e).isEmpty)
        var e2 = engine([snippet("x")])
        _ = e2.handle(KeyInput(kind: .deadKey), now: 1)
        #expect(type("ex", into: &e2).isEmpty)  // "e" composed, then "x" mid-word
    }

    @Test func syntheticEventsNeverMatch() {
        var e = engine([snippet(";addr")])
        var now: UInt64 = 1
        for input in KeyInput.text(";addr", origin: .synthetic) {
            #expect(e.handle(input, now: now) == .none)
            now += 1
        }
        for input in KeyInput.text(";addr", origin: .ours) {
            #expect(e.handle(input, now: now) == .none)
            now += 1
        }
        #expect(e.syntheticSkipped == 5)
    }

    @Test func closedGateBuffersNothing() {
        var e = engine([snippet(";addr")])
        _ = type(";ad", into: &e)
        var gate = TapGate()
        gate.excludedApp = true
        e.setGate(gate)
        #expect(e.buffer.isEmpty)
        #expect(type("dr;addr", into: &e).isEmpty)
        #expect(e.buffer.isEmpty)
        for flag in [\TapGate.paused, \TapGate.inputMethod, \TapGate.secureInput] {
            var g = TapGate()
            g[keyPath: flag] = true
            e.setGate(g)
            #expect(type(";addr", into: &e).isEmpty)
            #expect(e.buffer.isEmpty)
        }
        e.setGate(TapGate())
        #expect(type(";addr", into: &e).count == 1)
    }

    @Test func nonLatinAbbreviations() {
        var e = engine([snippet(";ñu"), snippet("→x")])
        #expect(type(";ñu", into: &e).count == 1)
    }
}

@Suite("Keys typed during an expansion")
struct PendingKeysTests {
    func engine() -> (TapEngine, Snippet) {
        let s = snippet(";addr")
        var engine = TapEngine()
        engine.index = AbbreviationIndex(snippets: [s])
        return (engine, s)
    }

    @Test func keysAfterTheMatchAreHandedBackInOrder() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        _ = type("abc", into: &e, at: match.at + 1_000_000, step: 1_000_000)
        let start = e.beginInsert(match.id, now: match.at + 10_000_000)
        #expect(start?.pending == "abc")
        #expect(start?.typed == ";addr")
    }

    @Test func aKeyThatCantBeReplayedDropsTheExpansion() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        _ = e.handle(KeyInput(kind: .boundary), now: match.at + 1_000_000)
        #expect(e.beginInsert(match.id, now: match.at + 2_000_000) == nil)
        #expect(!e.isBusy)
    }

    @Test func timesOutAfterHalfASecond() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        #expect(e.beginInsert(match.id, now: match.at + 600_000_000) == nil)
        // And a key after the timeout starts afresh.
        var (e2, _) = engine()
        guard case .expand(let m2) = type(";addr", into: &e2).first else { Issue.record("no match"); return }
        _ = e2.handle(KeyInput.text("x")[0], now: m2.at + 600_000_000)
        #expect(!e2.isBusy)
    }

    @Test func frontAppChangeDropsTheMatch() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        e.frontChanged()
        #expect(e.beginInsert(match.id, now: match.at + 1) == nil)
    }

    @Test func keysDuringPostingAreCountedNotBuffered() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        _ = e.beginInsert(match.id, now: match.at + 1)
        _ = type("zz", into: &e, at: match.at + 2)
        #expect(e.interleavedKeys == 2)
        e.finishInsert(match.id, tail: "1 Main Street", undoable: false, now: match.at + 3)
        #expect(e.buffer.contents == "1 Main Street")
    }

    @Test func tooManyPendingKeysDropIt() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        _ = type(String(repeating: "x", count: 17), into: &e, at: match.at + 1, step: 1)
        #expect(e.beginInsert(match.id, now: match.at + 100) == nil)
    }

    @Test func backspaceRightAfterUndoes() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        _ = e.beginInsert(match.id, now: match.at + 1)
        e.finishInsert(match.id, tail: "1 Main Street", undoable: true, now: match.at + 2)
        #expect(e.handle(KeyInput(kind: .backspace), now: match.at + 500_000_000) == .undo(match.id))
        // Only once, and only straight away.
        #expect(e.handle(KeyInput(kind: .backspace), now: match.at + 600_000_000) == .none)
    }

    @Test func undoWindowCloses() {
        var (e, _) = engine()
        guard case .expand(let match) = type(";addr", into: &e).first else { Issue.record("no match"); return }
        _ = e.beginInsert(match.id, now: match.at + 1)
        e.finishInsert(match.id, tail: "x", undoable: true, now: match.at + 2)
        #expect(e.handle(KeyInput(kind: .backspace), now: match.at + 3_000_000_000) == .none)
        // Typing in between also closes it.
        var (e2, _) = engine()
        guard case .expand(let m2) = type(";addr", into: &e2).first else { Issue.record("no match"); return }
        _ = e2.beginInsert(m2.id, now: m2.at + 1)
        e2.finishInsert(m2.id, tail: "x", undoable: true, now: m2.at + 2)
        _ = e2.handle(KeyInput.text("a")[0], now: m2.at + 3)
        #expect(e2.handle(KeyInput(kind: .backspace), now: m2.at + 4) == .none)
    }
}

@Suite("Key decoding")
struct KeyDecodingTests {
    func keyDown(_ code: CGKeyCode, text: String? = nil, flags: CGEventFlags = [], source: CGEventSource? = CGEventSource(stateID: .hidSystemState)) -> CGEvent {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)!
        event.flags = flags
        if let text {
            var units = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        } else {
            var none: [UInt16] = []
            event.keyboardSetUnicodeString(stringLength: 0, unicodeString: &none)
        }
        return event
    }

    @Test func charactersFromTheLayout() {
        // Dvorak's "a" key position doesn't matter: the produced character does.
        let input = KeyDecoder.decode(keyDown(0, text: "é"), type: .keyDown)
        #expect(input.kind == .characters)
        #expect(input.count == 1)
        #expect(input[0] == 0xE9)
        #expect(input.origin == .hardware)
    }

    @Test func astralCharacters() {
        let input = KeyDecoder.decode(keyDown(0, text: "𝒜"), type: .keyDown)
        #expect(input.count == 1)
        #expect(input[0] == 0x1D49C)
    }

    @Test func specialKeys() {
        #expect(KeyDecoder.decode(keyDown(51), type: .keyDown).kind == .backspace)
        #expect(KeyDecoder.decode(keyDown(51, flags: .maskAlternate), type: .keyDown).kind == .reset)
        #expect(KeyDecoder.decode(keyDown(36, text: "\r"), type: .keyDown).kind == .boundary)
        #expect(KeyDecoder.decode(keyDown(48, text: "\t"), type: .keyDown).kind == .boundary)
        #expect(KeyDecoder.decode(keyDown(123), type: .keyDown).kind == .reset)
        #expect(KeyDecoder.decode(keyDown(53), type: .keyDown).kind == .reset)
        #expect(KeyDecoder.decode(keyDown(9, text: "v", flags: .maskCommand), type: .keyDown).kind == .reset)
        #expect(KeyDecoder.decode(keyDown(0, text: "a", flags: .maskControl), type: .keyDown).kind == .reset)
    }

    @Test func deadKeyProducesNothing() {
        #expect(KeyDecoder.decode(keyDown(14, flags: .maskAlternate), type: .keyDown).kind == .deadKey)
    }

    @Test func modifierChangesAreIgnored() {
        let event = CGEvent(source: CGEventSource(stateID: .hidSystemState))!
        #expect(KeyDecoder.decode(event, type: .flagsChanged).kind == .ignored)
    }

    @Test func originFromSourceAndMarker() {
        #expect(KeyDecoder.decode(keyDown(0, text: "a", source: CGEventSource(stateID: .combinedSessionState)), type: .keyDown).origin == .synthetic)
        #expect(KeyDecoder.decode(keyDown(0, text: "a", source: CGEventSource(stateID: .privateState)), type: .keyDown).origin == .synthetic)
        let ours = keyDown(0, text: "a", source: CGEventSource(stateID: .combinedSessionState))
        ours.setIntegerValueField(.eventSourceUserData, value: KeyDecoder.marker)
        #expect(KeyDecoder.decode(ours, type: .keyDown).origin == .ours)
    }

    @Test func controlCharacters() {
        #expect(KeyDecoder.decode(keyDown(0, text: "\u{1B}"), type: .keyDown).kind == .reset)
    }
}

@Suite("Abbreviation rules and conflicts")
struct ConflictTests {
    @Test func validation() {
        #expect(AbbreviationRules.validate(";addr") == nil)
        #expect(AbbreviationRules.validate("->") == nil)
        #expect(AbbreviationRules.validate("ñ1") == nil)
        #expect(AbbreviationRules.validate("") == .empty)
        #expect(AbbreviationRules.validate("a b") == .whitespace)
        #expect(AbbreviationRules.validate(String(repeating: "x", count: 33)) == .tooLong)
        #expect(AbbreviationRules.validate(String(repeating: "x", count: 32)) == nil)
        #expect(AbbreviationRules.validate("😀") == .unsupportedCharacter("😀"))
        #expect(AbbreviationRules.validate("e\u{301}") == .unsupportedCharacter("e\u{301}"))
    }

    @Test func warnings() {
        let group = UUID()
        let library = Library(groups: [SnippetGroup(id: group, name: "Snippets")],
                              snippets: [snippet(";ad", group: group), snippet(";addr", group: group), snippet(";x", group: group)])
        let long = library.snippets[1]
        #expect(ConflictChecker.warnings(for: long, in: library) == [.shadowedBy(shorter: ";ad")])
        let short = library.snippets[0]
        #expect(ConflictChecker.warnings(for: short, in: library) == [.shadows(longer: ";addr")])
        var dup = snippet(";x", group: group)
        dup.name = "Other"
        #expect(ConflictChecker.warnings(for: dup, in: library).first?.blocksExpansion == true)
        #expect(ConflictChecker.warnings(for: snippet("sig", group: group), in: library) == [.plainWord])
    }

    @Test func disabledGroupsDontClash() {
        let off = SnippetGroup(name: "Off", isEnabled: false)
        let on = SnippetGroup(name: "On")
        let library = Library(groups: [on, off], snippets: [snippet(";x", group: off.id)])
        #expect(ConflictChecker.warnings(for: snippet(";x", group: on.id), in: library).isEmpty)
        #expect(library.expandable.isEmpty)
    }
}
