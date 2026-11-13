import Foundation
import Testing
@testable import ShorthandCore

/// Records what would be posted. Nothing reaches any app.
@MainActor
final class RecordingPoster: KeyPosting {
    enum Event: Equatable {
        case backspace(Int), left(Int), type(String), paste(String, restore: Bool), pasteFormatted(String, restore: Bool)
    }
    var events: [Event] = []
    func backspace(_ count: Int) { if count > 0 { events.append(.backspace(count)) } }
    func left(_ count: Int) { if count > 0 { events.append(.left(count)) } }
    func type(_ text: String) { events.append(.type(text)) }
    func paste(_ text: String, restore: Bool) async { events.append(.paste(text, restore: restore)) }
    var lastFormatted: Resolved?
    func pasteFormatted(_ resolved: Resolved, restore: Bool) async {
        lastFormatted = resolved
        events.append(.pasteFormatted(resolved.text, restore: restore))
    }
}

@MainActor
final class FakeEnvironment: InsertionEnvironment {
    var frontApp: FrontApp? = FrontApp(pid: 42, bundleID: "app.slopapp.test.pad", name: "Pad")
    var secureInputActive = false
    var focusedFieldIsSecure = false
    var pasteboardPrivacy = PasteboardAccessState.allowed
    var clipboard = ClipboardValue.text("slopapp-test clip")
    var clipboardReads = 0
    var clock: UInt64 = 1_000
    func readClipboard() -> ClipboardValue { clipboardReads += 1; return clipboard }
    func now() -> UInt64 { clock }
    var date = Date(timeIntervalSince1970: 1_794_060_300)
}

/// The engine with no lock (tests are single-threaded).
@MainActor
final class DirectTap: TapControl {
    var engine = TapEngine()
    var clock: () -> UInt64
    init(clock: @escaping () -> UInt64) { self.clock = clock }
    func beginInsert(_ id: UInt64) -> TapEngine.InsertStart? { engine.beginInsert(id, now: clock()) }
    func finishInsert(_ id: UInt64, tail: String, undoable: Bool) { engine.finishInsert(id, tail: tail, undoable: undoable, now: clock()) }
    func cancel(_ id: UInt64) { engine.cancel(id) }
    func beginUndo() { engine.beginUndo() }
    func finishUndo(abbreviation: String) { engine.finishUndo(abbreviation: abbreviation) }
    func inserted(tail: String) { engine.inserted(tail: tail) }
}

@MainActor
struct Harness {
    let environment = FakeEnvironment()
    let poster = RecordingPoster()
    let tap: DirectTap
    let expander: Expander
    var library: Library

    init(_ snippets: [Snippet]) {
        var library = Library()
        for s in snippets { var s = s; s.groupID = library.defaultGroupID; library.addSnippet(s) }
        self.library = library
        let environment = self.environment
        tap = DirectTap { environment.clock }
        tap.engine.index = AbbreviationIndex(snippets: library.expandable)
        let lib = library
        expander = Expander(tap: tap, poster: poster, environment: environment) { id in lib.snippet(id) }
        expander.lookup = lib.lookup
    }

    /// Types into the engine; returns the first match.
    func typeMatch(_ text: String) -> Match? {
        for input in KeyInput.text(text) {
            environment.clock += 50_000_000
            if case .expand(let match) = tap.engine.handle(input, now: environment.clock) { return match }
        }
        return nil
    }
}

@Suite("Expander")
@MainActor
struct ExpanderTests {
    @Test func typesShortSingleLines() async {
        let h = Harness([snippet(";hi", "slopapp-test hello")])
        let match = h.typeMatch(";hi")!
        let report = await h.expander.expand(match)
        #expect(report.outcome == .inserted(.type, characters: 18, restoredClipboard: false))
        #expect(h.poster.events == [.backspace(3), .type("slopapp-test hello")])
        #expect(h.environment.clipboardReads == 0)
        // The next abbreviation sees the snippet's end as context.
        #expect(h.tap.engine.buffer.contents == "slopapp-test hello")
    }

    @Test func pastesMultiLineAndRestores() async {
        let h = Harness([snippet(";two", "slopapp-test\nsecond line")])
        let report = await h.expander.expand(h.typeMatch(";two")!)
        #expect(report.outcome == .inserted(.paste, characters: 24, restoredClipboard: true))
        #expect(h.poster.events == [.backspace(4), .paste("slopapp-test\nsecond line", restore: true)])
    }

    @Test func pastesWithoutRestoringUntilAllowed() async {
        let h = Harness([snippet(";two", "slopapp-test\nsecond line")])
        h.environment.pasteboardPrivacy = .asks
        let report = await h.expander.expand(h.typeMatch(";two")!)
        #expect(h.poster.events.last == .paste("slopapp-test\nsecond line", restore: false))
        #expect(report.pastedWithoutRestore)
    }

    @Test func longTextPastesAndModesForceEitherWay() async {
        let long = String(repeating: "x", count: 201)
        let h = Harness([snippet(";long", long), snippet(";multi", "a\nb")])
        _ = await h.expander.expand(h.typeMatch(";long")!)
        #expect(h.poster.events.last == .paste(long, restore: true))
        h.expander.settings.insertMode = .alwaysType
        _ = await h.expander.expand(h.typeMatch(" ;multi")!)
        #expect(h.poster.events.last == .type("a\nb"))
        h.expander.settings.insertMode = .alwaysPaste
        h.expander.settings.restoreClipboard = false
        _ = await h.expander.expand(h.typeMatch(" ;long")!)
        #expect(h.poster.events.last == .paste(long, restore: false))
        #expect(InsertionPlanner.method(for: "a\tb", mode: .automatic) == .paste)
        #expect(InsertionPlanner.method(for: String(repeating: "y", count: 200), mode: .automatic) == .type)
    }

    @Test func cursorMarkerPressesLeft() async {
        let h = Harness([snippet(";dear", "Dear {cursor}, thanks")])
        _ = await h.expander.expand(h.typeMatch(";dear")!)
        #expect(h.poster.events == [.backspace(5), .type("Dear , thanks"), .left(8)])
        #expect(h.tap.engine.buffer.contents == "Dear ")
    }

    @Test func keysTypedMeanwhileAreRetypedAfter() async {
        let h = Harness([snippet(";hi", "slopapp-test")])
        let match = h.typeMatch(";hi")!
        for input in KeyInput.text("ab") {
            h.environment.clock += 10_000_000
            _ = h.tap.engine.handle(input, now: h.environment.clock)
        }
        _ = await h.expander.expand(match)
        #expect(h.poster.events == [.backspace(5), .type("slopapp-test"), .type("ab")])
        #expect(h.tap.engine.buffer.contents == "slopapp-testab")
    }

    @Test func guards() async {
        let h = Harness([snippet(";hi", "slopapp-test")])
        h.environment.secureInputActive = true
        #expect(await h.expander.expand(h.typeMatch(";hi")!).outcome == .blockedSecureInput)
        h.environment.secureInputActive = false
        h.environment.focusedFieldIsSecure = true
        #expect(await h.expander.expand(h.typeMatch(" ;hi")!).outcome == .blockedPasswordField)
        h.environment.focusedFieldIsSecure = false
        let match = h.typeMatch(" ;hi")!
        h.tap.engine.frontChanged()
        #expect(await h.expander.expand(match).outcome == .dropped)
        #expect(h.poster.events.isEmpty)
    }

    @Test func clipboardPlaceholderRespectsPrivacy() async {
        let h = Harness([snippet(";c", "[{clipboard}]")])
        _ = await h.expander.expand(h.typeMatch(";c")!)
        #expect(h.poster.events.last == .type("[slopapp-test clip]"))
        h.environment.pasteboardPrivacy = .asks
        let report = await h.expander.expand(h.typeMatch(" ;c")!)
        #expect(h.poster.events.last == .type("[]"))
        #expect(report.clipboardBlocked)
        #expect(h.environment.clipboardReads == 1)
    }

    @Test func backspaceUndo() async {
        let h = Harness([snippet(";hi", "slopapp-test")])
        let match = h.typeMatch(";hi")!
        _ = await h.expander.expand(match)
        h.environment.clock += 100_000_000
        guard case .undo(let id) = h.tap.engine.handle(KeyInput(kind: .backspace), now: h.environment.clock) else {
            Issue.record("no undo"); return
        }
        #expect(h.expander.undo(id))
        #expect(h.poster.events.suffix(2) == [.backspace(11), .type(";hi")])
        #expect(h.tap.engine.buffer.contents == ";hi")
        // Undo doesn't fire again for the same expansion.
        #expect(!h.expander.undo(id))
    }

    @Test func fillInsWaitForTheForm() async {
        let h = Harness([snippet(";reply", "Hi {field:Name}, {choice:Tone|warm|brief}.")])
        let match = h.typeMatch(";reply")!
        // A key typed before the form opens stays after the snippet.
        h.environment.clock += 10_000_000
        _ = h.tap.engine.handle(KeyInput.text("x")[0], now: h.environment.clock)
        let report = await h.expander.expand(match)
        #expect(report.outcome == .needsFillIn)
        #expect(h.poster.events.isEmpty)
        let request = report.fillIn!
        #expect(request.fields.map(\.name) == ["Name", "Tone"])
        #expect(request.backspaces == 7 && request.retype == "x" && request.targetPID == 42)
        // While the form is open the tap ignores keys (they're the form's).
        #expect(h.tap.engine.isBusy)
        let done = await h.expander.complete(request, values: FillValues(["name": .text("Bo"), "Tone": .text("brief")]))
        #expect(done.outcome == .inserted(.type, characters: 13, restoredClipboard: false))
        #expect(h.poster.events == [.backspace(7), .type("Hi Bo, brief."), .type("x")])
        #expect(!h.tap.engine.isBusy)
        #expect(h.tap.engine.buffer.contents == "Hi Bo, brief.x")
    }

    @Test func cancellingAFormLeavesTheAbbreviation() async {
        let h = Harness([snippet(";reply", "Hi {field:Name}")])
        let report = await h.expander.expand(h.typeMatch(";reply")!)
        h.expander.cancel(report.fillIn!)
        #expect(h.poster.events.isEmpty)
        #expect(!h.tap.engine.isBusy)
    }

    @Test func nothingIsTypedIfAnotherAppCameForward() async {
        let h = Harness([snippet(";reply", "Hi {field:Name}")])
        let report = await h.expander.expand(h.typeMatch(";reply")!)
        h.environment.frontApp = FrontApp(pid: 7, bundleID: "app.slopapp.test.other", name: "Other")
        let done = await h.expander.complete(report.fillIn!, values: FillValues(["Name": .text("Bo")]))
        #expect(done.outcome == .targetChanged)
        #expect(done.resolved?.text == "Hi Bo")
        #expect(h.poster.events.isEmpty)
        #expect(!h.tap.engine.isBusy)
    }

    @Test func insertingFromSearchDeletesNothing() async {
        let h = Harness([snippet(";hi", "slopapp-test hello"), snippet(";f", "Dear {field:Name}")])
        let report = await h.expander.insert(h.library.snippets[0].id)
        #expect(report.outcome == .inserted(.type, characters: 18, restoredClipboard: false))
        #expect(h.poster.events == [.type("slopapp-test hello")])
        #expect(h.tap.engine.buffer.contents == "slopapp-test hello")
        let form = await h.expander.insert(h.library.snippets[1].id)
        #expect(form.outcome == .needsFillIn)
        #expect(form.fillIn?.matchID == nil && form.fillIn?.backspaces == 0)
        _ = await h.expander.complete(form.fillIn!, values: FillValues(["Name": .text("Bo")]))
        #expect(h.poster.events.last == .type("Dear Bo"))
    }

    @Test func searchInsertRespectsGuards() async {
        let h = Harness([snippet(";hi", "slopapp-test")])
        h.environment.focusedFieldIsSecure = true
        #expect(await h.expander.insert(h.library.snippets[0].id).outcome == .blockedPasswordField)
        #expect(await h.expander.insert(UUID()).outcome == .snippetMissing)
        #expect(h.poster.events.isEmpty)
    }

    @Test func formattedSnippetsPasteFormatted() async {
        var s = snippet(";sig", "slopapp-test Best")
        s.richText = Data([0])
        let h = Harness([s, snippet(";outer", "Thanks\n{snippet:;sig}")])
        h.expander.settings.insertMode = .alwaysType
        let report = await h.expander.expand(h.typeMatch(";sig")!)
        #expect(report.formatted)
        #expect(h.poster.events == [.backspace(4), .pasteFormatted("slopapp-test Best", restore: true)])
        // A plain snippet including a formatted one goes formatted too.
        _ = await h.expander.expand(h.typeMatch(" ;outer")!)
        #expect(h.poster.events.last == .pasteFormatted("Thanks\nslopapp-test Best", restore: true))
        #expect(h.poster.lastFormatted?.includedSnippets == [h.library.snippets[0].id])
    }

    @Test func missingSnippet() async {
        let h = Harness([])
        let match = Match(id: 1, snippetID: UUID(), length: 2, typedCase: .asWritten, frontGeneration: 0, at: 0)
        #expect(await h.expander.expand(match).outcome == .snippetMissing)
    }
}

@Suite("Benchmark")
struct BenchmarkTests {
    @Test func matcherWithFiveThousandAbbreviations() {
        let index = AbbreviationIndex(snippets: Benchmark.library(count: 5_000))
        let stats = Benchmark.run(index: index, keys: 200_000)
        // Budget p99 ≤ 2 µs in release; the debug test build gets ×10.
        #expect(stats.percentile(0.99) <= 20)
        print("matcher benchmark (debug):", stats.summary)
    }

    @Test func latencyStats() {
        var stats = LatencyStats()
        for v in [0.5, 1.5, 3, 15, 900] { stats.record(microseconds: v) }
        #expect(stats.count == 5)
        #expect(stats.percentile(0.5) == 5)
        #expect(stats.maxMicroseconds == 900)
    }

    @Test func replayTimelines() throws {
        let timeline = ReplayTimeline.typing(";hi", interval: 15)
        #expect(timeline.steps.count == 3)
        let data = try JSONEncoder().encode(timeline)
        #expect(try JSONDecoder().decode(ReplayTimeline.self, from: data) == timeline)
        #expect(ReplayTimeline.inputs(for: .init(after: 0, key: "backspace")) == [KeyInput(kind: .backspace)])
    }
}
