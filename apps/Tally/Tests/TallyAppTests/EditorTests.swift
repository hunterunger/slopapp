import AppKit
import Testing
@testable import Tally
@testable import TallyCore

/// Gives a window-less text view an undo manager, like its window would.
@MainActor
final class UndoHost: NSObject, NSTextViewDelegate {
    let manager = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { manager }
}

/// A library in memory. `text` is the first sheet's text (what the old single-sheet tests
/// checked).
final class MemorySheetStorage: LibraryStorage {
    var index: LibraryIndex?
    var texts: [UUID: String] = [:]
    var legacy: String?
    var saves = 0

    init(_ text: String?) { legacy = text }

    var text: String? {
        guard let id = index?.current else { return nil }
        return texts[id]
    }

    func loadIndex() -> LibraryIndex? { index }
    func saveIndex(_ index: LibraryIndex) throws { self.index = index }
    func loadText(_ id: UUID) -> String? { texts[id] }
    func saveText(_ text: String, id: UUID) throws {
        saves += 1
        texts[id] = text
    }
    func deleteText(_ id: UUID) throws { texts[id] = nil }
    func loadLegacySheet() -> String? { legacy }
}

final class EmptyRatesStorage: RatesStorage {
    func load() -> StoredRates { .none }
    func save(_ table: RateTable) throws {}
    func delete() throws {}
}

struct NoNetwork: RatesFetching {
    func fetch() async throws -> Data { throw URLError(.notConnectedToInternet) }
}

@MainActor
final class FakeClipboard: Clipboard {
    var last: String?
    func setString(_ string: String) { last = string }
}

@MainActor @Suite struct Editor {
    @Test func clearAllIsOneUndoableStep() {
        let view = SheetTextView.make()
        let host = UndoHost()
        view.delegate = host
        view.string = "rent = 1450\nrent / 3"
        view.replaceAll(with: "", actionName: "Clear All")
        #expect(view.string.isEmpty)
        #expect(host.manager.undoActionName == "Clear All")
        host.manager.undo()
        #expect(view.string == "rent = 1450\nrent / 3")
        host.manager.redo()
        #expect(view.string.isEmpty)
    }

    @Test func onlyLinesWithResultsWrapBeforeTheirAnswer() {
        let view = SheetTextView.make()
        view.setFrameSize(NSSize(width: 400, height: 300))
        let long = String(repeating: "word ", count: 14)
        view.string = "\(long)\n// \(long)"
        view.apply(displays: [ResultDisplay(text: "123,456,789", kind: .value), nil])
        let container = view.textContainer as! ResultAwareTextContainer
        let proposed = NSRect(x: 0, y: 0, width: container.size.width, height: 20)
        let withResult = container.lineFragmentRect(forProposedRect: proposed, at: 0, writingDirection: .leftToRight, remaining: nil)
        let secondLine = view.lineStarts[1]
        let without = container.lineFragmentRect(forProposedRect: proposed, at: secondLine, writingDirection: .leftToRight, remaining: nil)
        #expect(withResult.width < without.width)
        #expect(without.width == container.size.width)
        #expect(withResult.width <= container.size.width - view.resultWidth(ResultDisplay(text: "123,456,789", kind: .value)))
    }

    @Test func currentLineFollowsTheInsertionPoint() {
        let view = SheetTextView.make()
        view.string = "1\n2 + 2\n3"
        view.apply(displays: [nil, nil, nil])
        view.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(view.currentLine == 1)
        #expect(view.characterRange(ofLine: 1) == NSRange(location: 2, length: 5))
    }
}

@MainActor @Suite struct Model {
    func makeModel(_ text: String?) -> (SheetModel, MemorySheetStorage, FakeClipboard) {
        let storage = MemorySheetStorage(text)
        let clipboard = FakeClipboard()
        let model = SheetModel(libraryStorage: storage, ratesStorage: EmptyRatesStorage(), fetcher: NoNetwork(), clipboard: clipboard)
        return (model, storage, clipboard)
    }

    @Test func firstRunShowsTheWelcomeSheetWithAnswers() {
        let (model, storage, _) = makeModel(nil)
        #expect(model.text == SheetText.welcome)
        #expect(model.displays.compactMap { $0 }.map(\.text).contains("$219.95"))
        #expect(storage.saves == 0) // nothing written until the user edits
    }

    @Test func editsReEvaluateImmediatelyAndAutosave() async throws {
        let (model, storage, _) = makeModel("a = 2")
        model.textDidChange("a = 2\na * 21")
        #expect(model.displays.last??.text == "42")
        try await Task.sleep(for: .milliseconds(900))
        #expect(storage.text == "a = 2\na * 21")
        model.textDidChange("b = 2\na * 21")
        #expect(model.displays.last??.text == "unknown name “a”")
        #expect(model.displays.last??.kind == .error)
        model.saveNow()
        #expect(storage.text == "b = 2\na * 21")
    }

    @Test func ratesOffIsClickableToSettings() {
        let (model, _, _) = makeModel("100 USD in EUR")
        let display = model.displays[0]
        #expect(display?.text == "rates off")
        #expect(display?.opensCurrencySettings == true)
        var opened = false
        model.openSettingsAction = { opened = true }
        model.resultClicked(line: 0)
        #expect(opened)
    }
}
