import Foundation
import Testing
@testable import DropperCore

@MainActor
final class FakeSampler: ColorSampling {
    var queue: [ColorValue?]
    var calls = 0
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false

    init(_ queue: [ColorValue?]) { self.queue = queue }

    func sample(prompt: String?) async -> ColorValue? {
        calls += 1
        if holdNext {
            await withCheckedContinuation { gate = $0 }
        }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    func release() {
        holdNext = false
        gate?.resume()
        gate = nil
    }
}

@MainActor
final class FakeClipboard: Clipboard {
    var writes: [String] = []
    func write(_ text: String) { writes.append(text) }
}

final class FakePreferences: PreferencesStore, @unchecked Sendable {
    var stored: Preferences
    var saves = 0
    init(_ p: Preferences = Preferences()) { stored = p }
    func load() -> Preferences { stored }
    func save(_ preferences: Preferences) { stored = preferences; saves += 1 }
}

struct BrokenStore: LibraryStore {
    func load() throws -> LibraryContents { throw CocoaError(.fileReadCorruptFile) }
    func save(_ contents: LibraryContents) throws {}
}

@MainActor
@Suite struct ModelTests {
    let blue = ColorValue(red: 0.2, green: 0.4, blue: 0.8)
    let red = ColorValue(red: 1, green: 0, blue: 0)

    func makeModel(_ picks: [ColorValue?], prefs: Preferences = Preferences(), store: LibraryStore = MemoryLibraryStore())
        -> (DropperModel, FakeSampler, FakeClipboard) {
        let sampler = FakeSampler(picks)
        let clipboard = FakeClipboard()
        let model = DropperModel(sampler: sampler, clipboard: clipboard, historyStore: store,
                                 preferencesStore: FakePreferences(prefs), now: { Date(timeIntervalSince1970: 1000) })
        return (model, sampler, clipboard)
    }

    @Test func pickCopiesInDefaultFormatAndRemembers() async throws {
        let store = MemoryLibraryStore()
        let (model, _, clipboard) = makeModel([blue], store: store)
        let result = await model.pickAndCopy()
        #expect(result?.text == "#3366CC")
        #expect(result?.wasClamped == false)
        #expect(clipboard.writes == ["#3366CC"])
        #expect(model.history.latest?.color == blue)
        #expect(try store.load().history.count == 1)
    }

    @Test func cancelLeavesEverythingAlone() async {
        let store = MemoryLibraryStore()
        let (model, _, clipboard) = makeModel([nil], store: store)
        let result = await model.pickAndCopy()
        #expect(result == nil)
        #expect(clipboard.writes.isEmpty)
        #expect(model.history.items.isEmpty)
        #expect(store.saveCount == 0)
        #expect(!model.isPicking)
    }

    @Test func secondPickWhileSamplingIsIgnored() async {
        let (model, sampler, clipboard) = makeModel([blue, red])
        sampler.holdNext = true
        async let first = model.pickAndCopy()
        await Task.yield()
        #expect(model.isPicking)
        let second = await model.pickAndCopy()
        #expect(second == nil)
        sampler.release()
        let result = await first
        #expect(result?.text == "#3366CC")
        #expect(sampler.calls == 1)
        #expect(clipboard.writes == ["#3366CC"])
    }

    @Test func formatAndSpaceFollowPreferences() async {
        let prefs = Preferences(format: .swiftUI, options: FormatOptions(space: .displayP3))
        let p3Red = ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0))
        let (model, _, clipboard) = makeModel([p3Red], prefs: prefs)
        let result = await model.pickAndCopy()
        #expect(clipboard.writes == ["Color(.displayP3, red: 1, green: 0, blue: 0)"])
        #expect(result?.wasClamped == false)
    }

    @Test func outOfGamutPickIsFlaggedInSRGB() async {
        let p3Red = ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0))
        let (model, _, _) = makeModel([p3Red])
        let result = await model.pickAndCopy()
        #expect(result?.text == "#FF0000")
        #expect(result?.wasClamped == true)
        #expect(model.isClamped(p3Red, as: .cssDisplayP3) == false)
    }

    @Test func copyingFromHistoryMovesToTop() async {
        let (model, _, clipboard) = makeModel([blue, red])
        _ = await model.pickAndCopy()
        _ = await model.pickAndCopy()
        let older = model.history.items[1]
        #expect(older.color == blue)
        let text = model.copy(older, as: .cssRGB)
        #expect(text == "rgb(51, 102, 204)")
        #expect(clipboard.writes.last == "rgb(51, 102, 204)")
        #expect(model.history.latest?.color == blue)
        #expect(model.history.items.count == 2)
    }

    @Test func preferencesAreSaved() {
        let prefsStore = FakePreferences()
        let model = DropperModel(sampler: FakeSampler([]), clipboard: FakeClipboard(), historyStore: MemoryLibraryStore(),
                                 preferencesStore: prefsStore)
        model.preferences.format = .uiColor
        model.preferences.options.hexUppercase = false
        #expect(prefsStore.stored.format == .uiColor)
        #expect(prefsStore.stored.options.hexUppercase == false)
        #expect(prefsStore.saves == 2)
    }

    @Test func unreadableHistoryStartsEmptyWithAMessage() {
        let model = DropperModel(sampler: FakeSampler([]), clipboard: FakeClipboard(), historyStore: BrokenStore(),
                                 preferencesStore: FakePreferences())
        #expect(model.history.items.isEmpty)
        #expect(model.historyLoadError != nil)
    }

    @Test func clearHistory() async throws {
        let store = MemoryLibraryStore()
        let (model, _, _) = makeModel([blue], store: store)
        _ = await model.pickAndCopy()
        model.clearHistory()
        #expect(model.history.items.isEmpty)
        #expect(try store.load().history.isEmpty)
    }

    @Test func pickColorWithoutCopyingStillRemembers() async {
        let (model, _, clipboard) = makeModel([red])
        let color = await model.pickColor()
        #expect(color == red)
        #expect(clipboard.writes.isEmpty)
        #expect(model.history.latest?.color == red)
    }
}
