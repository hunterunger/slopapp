import Foundation
import Testing
@testable import DropperCore

@Suite struct HistoryTests {
    func color(_ i: Int) -> ColorValue { ColorValue(red: Double(i % 256) / 255, green: Double(i / 256) / 255, blue: 0) }
    let t = Date(timeIntervalSince1970: 0)

    @Test func newestFirst() {
        var h = ColorHistory()
        h.add(color(1), at: t)
        h.add(color(2), at: t)
        #expect(h.items.map(\.color) == [color(2), color(1)])
        #expect(h.latest?.color == color(2))
    }

    @Test func duplicatesMoveToTop() {
        var h = ColorHistory()
        h.add(color(1), at: t)
        h.add(color(2), at: t)
        h.add(ColorValue(red: 1.0 / 255 + 0.0001, green: 0, blue: 0), at: t) // same 8-bit color as 1
        #expect(h.items.count == 2)
        #expect(h.items.first?.color.identityKey == color(1).identityKey)
    }

    @Test func capDropsOldest() {
        var h = ColorHistory()
        for i in 0..<150 { h.add(color(i), at: t) }
        #expect(h.items.count == 100)
        #expect(h.items.first?.color == color(149))
        #expect(h.items.last?.color == color(50))
    }

    @Test func loadingNormalizes() {
        let items = (0..<120).map { PickedColor(color: color($0 % 110), date: t) }
        let h = ColorHistory(items: items)
        #expect(h.items.count == 100)
        #expect(Set(h.items.map(\.color.identityKey)).count == 100)
    }

    @Test func touchAndRemove() {
        var h = ColorHistory()
        let a = h.add(color(1), at: t)
        h.add(color(2), at: t)
        h.touch(a.id, at: Date(timeIntervalSince1970: 5))
        #expect(h.latest?.id == a.id)
        #expect(h.latest?.date == Date(timeIntervalSince1970: 5))
        h.remove(a.id)
        #expect(h.items.map(\.color) == [color(2)])
        h.clear()
        #expect(h.items.isEmpty)
    }

    @Test func fileStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dropper-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileLibraryStore(directory: dir)
        #expect(try store.load().history.isEmpty)
        let items = [PickedColor(color: ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0)), date: Date(timeIntervalSince1970: 100))]
        try store.save(LibraryContents(history: items))
        let loaded = try store.load().history
        #expect(loaded.count == 1)
        #expect(loaded[0].id == items[0].id)
        #expect(close(loaded[0].color.sRGB, items[0].color.sRGB, 1e-9))
    }

    @Test func corruptFileIsMovedAsideNotDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dropper-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = FileLibraryStore(directory: dir)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("colors.json.unreadable-") })
        #expect(try store.load().history.isEmpty)
    }
}
