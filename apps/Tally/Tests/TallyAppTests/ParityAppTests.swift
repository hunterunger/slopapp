import AppKit
import Testing
@testable import Tally
@testable import TallyCore

@MainActor @Suite(.serialized) struct Sheets {
    func makeModel(_ text: String? = "a = 2") -> (SheetModel, MemorySheetStorage, FakeClipboard) {
        let storage = MemorySheetStorage(text)
        let clipboard = FakeClipboard()
        let model = SheetModel(libraryStorage: storage, ratesStorage: EmptyRatesStorage(), fetcher: NoNetwork(), clipboard: clipboard)
        return (model, storage, clipboard)
    }

    func editor(for model: SheetModel) -> SheetTextView {
        let view = SheetTextView.make()
        view.setFrameSize(NSSize(width: 500, height: 400))
        view.variableNames = { [weak model] in model?.current.variableNames ?? [] }
        model.register(view)
        return view
    }

    @Test func newSheetsSwitchAndKeepTheirOwnText() {
        let (model, storage, _) = makeModel("rent = 1450")
        let first = model.currentID
        let view = editor(for: model)
        #expect(view.string == "rent = 1450")
        model.newSheet()
        #expect(model.rows.count == 2)
        #expect(view.string.isEmpty)
        model.textDidChange("# Trip\n5 km in miles")
        #expect(model.currentTitle == "Trip")
        #expect(model.displays.last??.text == "3.106855961 mi")
        model.select(first)
        #expect(view.string == "rent = 1450")
        #expect(model.rows.first { $0.id != first }?.title == "Trip")
        model.saveNow()
        #expect(storage.texts.values.contains("# Trip\n5 km in miles"))
    }

    @Test func eachSheetHasItsOwnUndo() {
        let (model, _, _) = makeModel("1 + 1")
        let first = model.current.undoManager
        model.newSheet()
        #expect(model.current.undoManager !== first)
    }

    @Test func twoEditorsShareTheSheet() {
        let (model, _, _) = makeModel("2 + 2")
        let window = editor(for: model)
        let panel = editor(for: model)
        #expect(window.textStorage === panel.textStorage)
        panel.insertText("0", replacementRange: NSRange(location: 5, length: 0))
        model.storageDidChange()
        #expect(window.string == "2 + 20")
        #expect(window.displays.first??.text == "22")
        model.newSheet(text: "3 * 3")
        #expect(window.string == "3 * 3" && panel.string == "3 * 3")
        #expect(panel.displays.first??.text == "9")
    }

    @Test func deletingTheCurrentSheetShowsTheNextOne() {
        let (model, _, _) = makeModel("first")
        let first = model.currentID
        model.newSheet(text: "second")
        let view = editor(for: model)
        model.deleteSheet(model.currentID, confirm: false)
        #expect(model.currentID == first)
        #expect(view.string == "first")
        #expect(model.rows.count == 1)
        model.deleteSheet(first, confirm: false)
        #expect(model.rows.count == 1)
        #expect(view.string.isEmpty)
    }

    @Test func footerShowsTheTotalAndTheSelection() {
        let (model, _, clipboard) = makeModel("$10\n$5\n2 kg")
        #expect(model.footer.total == "$15.00")
        model.textDidChange("$10\n$5\n$2.50")
        #expect(model.footer.total == "$17.50")
        model.selectionChanged(NSRange(location: 0, length: 7), lineStarts: [0, 4, 7])
        #expect(model.footer == Footer(total: "$15.00", isSelection: true))
        model.copyTotal()
        #expect(clipboard.last == "$15.00")
        model.selectionChanged(NSRange(location: 2, length: 0), lineStarts: [0, 4, 7])
        #expect(model.footer.isSelection == false)
    }

    @Test func themesRestyleTheSheet() {
        let (model, _, _) = makeModel("price = 4 // note")
        let view = editor(for: model)
        model.setTheme(Theme.midnight.id)
        #expect(view.backgroundColor == Theme.midnight.background)
        let color = view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == Theme.midnight.variable)
        #expect(view.typingAttributes[.foregroundColor] as? NSColor == Theme.midnight.text)
        model.setTheme(Theme.system.id)
    }

    @Test func tabAcceptsTheGreySuggestion() {
        let (model, _, _) = makeModel("price = 4\n")
        let view = editor(for: model)
        let host = UndoHost()
        view.delegate = host
        view.setSelectedRange(NSRange(location: 10, length: 0))
        view.insertText("pr", replacementRange: view.selectedRange())
        model.storageDidChange()
        #expect(view.suggestion == "ice")
        view.insertTab(nil)
        #expect(view.string == "price = 4\nprice")
        #expect(view.suggestion == nil)
        view.insertText(" * pr", replacementRange: view.selectedRange())
        #expect(view.suggestion == "ice")
        view.cancelOperation(nil)
        #expect(view.suggestion == nil)
    }

    @Test func clockLinesAreMarked() {
        let (model, _, _) = makeModel("now in Tokyo")
        #expect(model.current.usesClock)
        #expect(model.displays.first??.text.hasSuffix("Tokyo") == true)
    }
}
