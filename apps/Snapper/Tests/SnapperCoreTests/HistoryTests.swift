import CoreGraphics
import Foundation
import Testing
@testable import SnapperCore

/// A solid test image (never a real capture).
private func testImage(width: Int = 40, height: Int = 30, red: CGFloat = 0.2) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("snapper-history-tests-\(UUID().uuidString)", isDirectory: true)
}

private let day: TimeInterval = 86_400
private let reference = Date(timeIntervalSince1970: 1_800_000_000)

private func entry(_ age: TimeInterval, kind: HistoryKind = .screenshot, app: String? = nil, bytes: Int64 = 100) -> HistoryEntry {
    HistoryEntry(createdAt: reference.addingTimeInterval(-age), kind: kind, pixelWidth: 10, pixelHeight: 10, scale: 2,
                 fileName: "a.png", byteSize: bytes, source: app.map { SourceApp(bundleID: "com.example.\($0.lowercased())", name: $0) })
}

@Suite("History index")
struct HistoryIndexTests {
    @Test func roundTripsAndKeepsNewestFirst() throws {
        let old = entry(3 * day, kind: .window, app: "Safari")
        let new = entry(60, kind: .gif, app: "Notes")
        let index = HistoryIndex(entries: [old, new])
        #expect(index.entries.map(\.id) == [new.id, old.id])
        let decoded = HistoryIndex.decode(try index.encoded())
        #expect(decoded == index)
        #expect(decoded.totalBytes == 200)
    }

    @Test func decodingIsMigrationSafe() throws {
        let id = UUID()
        // An older entry (few fields), a newer one (an unknown kind and extra fields), and a
        // broken one (no id): the first two load with defaults, the broken one is skipped.
        let json = """
        {"version": 7, "entries": [
          {"id": "\(id.uuidString)", "createdAt": "2026-11-07T10:00:00Z", "fileName": "x.png"},
          {"id": "\(UUID().uuidString)", "kind": "hologram", "fileName": "y.png", "futureField": [1, 2, 3], "source": {"name": "Notes"}},
          {"kind": "window", "fileName": "z.png"}
        ]}
        """
        let index = HistoryIndex.decode(Data(json.utf8))
        #expect(index.entries.count == 2)
        let first = try #require(index.entry(id))
        #expect(first.kind == .screenshot)
        #expect(first.scale == 2)
        #expect(first.byteSize == 0)
        #expect(index.entries.contains { $0.kind == .screenshot && $0.source?.name == "Notes" && $0.source?.bundleID == nil })
    }

    @Test func acceptsABareArrayAndSurvivesGarbage() throws {
        let one = entry(10)
        let array = try JSONEncoder.iso.encode([one])
        #expect(HistoryIndex.decode(array).entries.map(\.id) == [one.id])
        #expect(HistoryIndex.decode(Data("not json".utf8)).entries.isEmpty)
    }

    @Test func retentionUsesTheClock() {
        let index = HistoryIndex(entries: [entry(60), entry(2 * day), entry(10 * day), entry(40 * day)])
        #expect(index.expired(retention: .forever, now: reference).isEmpty)
        #expect(index.expired(retention: .month, now: reference).count == 1)
        #expect(index.expired(retention: .week, now: reference).count == 2)
        #expect(index.expired(retention: .day, now: reference).count == 3)
        #expect(index.expired(retention: .off, now: reference).count == 4)
        // A day later the 2-day-old one is 3 days old: still within a week.
        #expect(index.expired(retention: .week, now: reference.addingTimeInterval(day)).count == 2)
    }

    @Test func openItemsAreNeverPruned() {
        let open = entry(40 * day)
        let index = HistoryIndex(entries: [open, entry(41 * day)])
        let expired = index.expired(retention: .month, now: reference, protected: [open.id])
        #expect(expired.count == 1)
        #expect(!expired.contains { $0.id == open.id })
    }

    @Test func filtersByKindAndSearchesBySourceApp() {
        let index = HistoryIndex(entries: [entry(1, kind: .window, app: "Safari"), entry(2, kind: .screenshot, app: "Notes"),
                                           entry(3, kind: .recording, app: "Safari")])
        #expect(index.filtered(kind: nil, search: "").count == 3)
        #expect(index.filtered(kind: .window, search: "").count == 1)
        #expect(index.filtered(kind: nil, search: "safari").count == 2)
        #expect(index.filtered(kind: .recording, search: "notes").isEmpty)
        #expect(index.filtered(kind: nil, search: "com.example.notes").count == 1)
    }

    @Test func groupsByDayNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_762_509_600) // 2025-11-07 10:00 UTC
        let entries = [now.addingTimeInterval(-60), now.addingTimeInterval(-day), now.addingTimeInterval(-day - 60), now.addingTimeInterval(-9 * day)]
            .map { HistoryEntry(createdAt: $0, kind: .screenshot, pixelWidth: 1, pixelHeight: 1, scale: 1, fileName: "a.png") }
        let days = HistoryDays.group(entries, calendar: calendar)
        #expect(days.map(\.entries.count) == [1, 2, 1])
        let locale = Locale(identifier: "en_US")
        #expect(HistoryDays.title(for: days[0].start, now: now, calendar: calendar, locale: locale) == "Today")
        #expect(HistoryDays.title(for: days[1].start, now: now, calendar: calendar, locale: locale) == "Yesterday")
        #expect(HistoryDays.title(for: days[2].start, now: now, calendar: calendar, locale: locale) == "Wednesday, October 29")
    }

    @Test func kindsFromCapturePaths() {
        #expect(HistoryKind(captureKind: "area") == .screenshot)
        #expect(HistoryKind(captureKind: "selfTimer") == .screenshot)
        #expect(HistoryKind(captureKind: "selfTimerWindow") == .window)
        #expect(HistoryKind(captureKind: "scrolling") == .scrolling)
        #expect(HistoryKind(captureKind: "video") == .recording)
        #expect(HistoryKind(captureKind: "gif") == .gif)
    }
}

@Suite("Annotation document coding")
struct DocumentCodingTests {
    @Test func roundTripsEveryKindOfMark() throws {
        let document = AnnotationDocument(
            imageSize: CGSize(width: 400, height: 300),
            annotations: [
                Annotation(kind: .arrow, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40), color: RGBA(1, 0, 0), width: 4),
                Annotation(kind: .text, start: CGPoint(x: 5, y: 5), text: "Hello"),
                Annotation(kind: .pencil, start: .zero, points: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 3)]),
                Annotation(kind: .counter, start: CGPoint(x: 9, y: 9), number: 3),
            ],
            crop: CGRect(x: 10, y: 10, width: 100, height: 80),
            background: CaptureBackground(fill: .gradient(.dusk), padding: 32, cornerRadius: 8, shadow: 0.4))
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: try JSONEncoder().encode(document))
        #expect(decoded == document)
    }

    @Test func dropsMarksItDoesNotKnow() throws {
        let json = """
        {"imageSize": [100, 50], "annotations": [{"kind": "laser", "start": [1, 1]}, {"kind": "rectangle", "start": [1, 1], "end": [9, 9]}]}
        """
        let document = try JSONDecoder().decode(AnnotationDocument.self, from: Data(json.utf8))
        #expect(document.annotations.map(\.kind) == [.rectangle])
        #expect(document.imageSize == CGSize(width: 100, height: 50))
    }
}

@Suite("History store")
struct HistoryStoreTests {
    private func capture(_ store: HistoryStore, age: TimeInterval = 0, document: AnnotationDocument? = nil) async throws -> HistoryEntry {
        try await store.add(HistoryCapture(id: UUID(), createdAt: reference.addingTimeInterval(-age), kind: .screenshot, scale: 2,
                                           image: testImage(), original: testImage(red: 0.9), document: document, format: .png,
                                           baseName: "Screenshot 2026-11-07 at 10.42.03", source: SourceApp(bundleID: "a.b", name: "Notes")))
    }

    @Test func addWritesAFolderAndTheIndex() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let entry = try await capture(store)
        #expect(entry.fileName == "Screenshot 2026-11-07 at 10.42.03.png")
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: entry).path))
        #expect(FileManager.default.fileExists(atPath: try #require(store.originalURL(for: entry)).path))
        #expect(entry.byteSize > 0)
        #expect(entry.pixelWidth == 40)
        // A fresh store (a relaunch) reads it back.
        let reloaded = await HistoryStore(root: root).load()
        #expect(reloaded.entries == [entry])
    }

    @Test func editsUpdateTheEntryAndStayEditable() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let entry = try await capture(store)
        #expect(!entry.isEdited)
        let document = AnnotationDocument(imageSize: CGSize(width: 20, height: 15),
                                          annotations: [Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 5, y: 5))])
        let updated = try #require(try await store.update(entry.id, image: testImage(width: 60, height: 50), document: document,
                                                          format: .jpeg, baseName: "Screenshot 2026-11-07 at 10.42.03"))
        #expect(updated.isEdited)
        #expect(updated.fileName.hasSuffix(".jpg") || updated.fileName.hasSuffix(".jpeg"))
        #expect(updated.pixelWidth == 60)
        #expect(!FileManager.default.fileExists(atPath: store.folder(for: entry.id).appendingPathComponent(entry.fileName).path))
        #expect(await store.document(for: updated) == document)
        // Undoing every edit removes the document again.
        let plain = try #require(try await store.update(entry.id, image: testImage(), document: nil, format: .png, baseName: "Screenshot"))
        #expect(!plain.isEdited)
    }

    @Test func restoreBringsBackTheEditsAsObjects() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = AnnotationDocument(imageSize: CGSize(width: 20, height: 15),
                                          annotations: [Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 9, y: 9))])
        let entry = try await capture(HistoryStore(root: root), document: document)
        // After a relaunch: a new store on the same folder.
        let restored = try #require(await HistoryStore(root: root).restorable(entry))
        #expect(restored.current.width == 40)
        #expect(restored.original != nil)
        #expect(restored.document == document)
        // Files gone (deleted by hand): nothing to restore, no crash.
        try FileManager.default.removeItem(at: HistoryStore(root: root).folder(for: entry.id))
        #expect(await HistoryStore(root: root).restorable(entry) == nil)
    }

    @Test func deleteIsUndoableUntilPurged() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let a = try await capture(store), b = try await capture(store, age: 60)
        let removed = await store.delete([a.id])
        #expect(removed.map(\.id) == [a.id])
        #expect(await store.load().entries.map(\.id) == [b.id])
        #expect(!FileManager.default.fileExists(atPath: store.folder(for: a.id).path))
        await store.restoreDeleted(removed)
        #expect(Set(await store.load().entries.map(\.id)) == [a.id, b.id])
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: a).path))
        // Delete again and purge: the files are gone for good.
        let again = await store.delete([a.id])
        await store.purgeDeleted()
        await store.restoreDeleted(again)
        #expect(await store.load().entries.map(\.id) == [b.id])
    }

    @Test func pruneErasesExpiredFoldersButNotOpenOnes() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let fresh = try await capture(store, age: 60)
        let old = try await capture(store, age: 40 * day)
        let openOld = try await capture(store, age: 45 * day)
        let pruned = await store.prune(retention: .month, now: reference, protected: [openOld.id])
        #expect(pruned == [old.id])
        #expect(!FileManager.default.fileExists(atPath: store.folder(for: old.id).path))
        #expect(Set(await store.load().entries.map(\.id)) == [fresh.id, openOld.id])
    }

    @Test func clearErasesEverythingButOpenItems() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let open = try await capture(store)
        _ = try await capture(store, age: 10)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(UUID().uuidString), withIntermediateDirectories: true)
        await store.clear(protected: [open.id])
        #expect(await store.load().entries.map(\.id) == [open.id])
        let folders = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") && $0 != "index.json" }
        #expect(folders == [open.id.uuidString])
    }

    @Test func entriesWithoutFilesAreDroppedOnLoad() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try await capture(HistoryStore(root: root))
        try FileManager.default.removeItem(at: HistoryStore(root: root).folder(for: entry.id))
        #expect(await HistoryStore(root: root).load().entries.isEmpty)
    }

    @Test func recordingsCopyTheFileAndAPoster() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.deletingLastPathComponent().appendingPathComponent("rec-\(UUID().uuidString).mp4")
        try Data("not really a movie".utf8).write(to: media)
        defer { try? FileManager.default.removeItem(at: media) }
        let store = HistoryStore(root: root)
        let entry = try await store.add(HistoryCapture(id: UUID(), createdAt: reference, kind: .recording, scale: 2, image: testImage(),
                                                       original: nil, media: media, duration: 4.5, format: .png,
                                                       baseName: "Recording 2026-11-07 at 10.42.03", source: nil))
        #expect(entry.fileName == "Recording 2026-11-07 at 10.42.03.mp4")
        #expect(entry.posterFileName == "poster.png")
        #expect(entry.duration == 4.5)
        #expect(store.thumbnailSourceURL(for: entry).lastPathComponent == "poster.png")
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: entry).path))
    }

    @Test func thumbnailsAreSmall() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(root: root)
        let entry = try await store.add(HistoryCapture(id: UUID(), createdAt: reference, kind: .screenshot, scale: 2,
                                                       image: testImage(width: 2000, height: 1000), original: nil, format: .png,
                                                       baseName: "Big", source: nil))
        let thumbnail = try #require(HistoryThumbnail.make(from: store.fileURL(for: entry), maxPixelSize: 200))
        #expect(max(thumbnail.width, thumbnail.height) == 200)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

@Suite("History grid keyboard navigation")
struct GridNavigationTests {
    // Two days: 7 captures (rows of 3: 3, 3, 1) then 4 (3, 1).
    let grid = GridNavigation(sections: [7, 4], columns: 3)

    @Test func leftAndRightStepThroughTheFlatOrder() {
        #expect(grid.target(from: 0, .left) == 0)
        #expect(grid.target(from: 6, .right) == 7)
        #expect(grid.target(from: 10, .right) == 10)
        #expect(grid.target(from: nil, .right) == 0)
        #expect(grid.target(from: 4, .end) == 10)
    }

    @Test func downKeepsTheColumnAndCrossesDays() {
        #expect(grid.target(from: 1, .down) == 4)
        #expect(grid.target(from: 5, .down) == 6)   // short last row: its only item
        #expect(grid.target(from: 6, .down) == 7)   // into the next day, column 0
        #expect(grid.target(from: 8, .down) == 10)
        #expect(grid.target(from: 10, .down) == 10) // the end
    }

    @Test func upKeepsTheColumnAndCrossesDays() {
        #expect(grid.target(from: 4, .up) == 1)
        #expect(grid.target(from: 8, .up) == 6)     // column 1 of the short row above → its last item
        #expect(grid.target(from: 7, .up) == 6)
        #expect(grid.target(from: 1, .up) == 1)
    }

    @Test func columnsFitTheWidth() {
        #expect(GridNavigation.columns(width: 560, tile: 176, spacing: 8) == 3)
        #expect(GridNavigation.columns(width: 100, tile: 176, spacing: 8) == 1)
        #expect(GridNavigation(sections: [], columns: 3).target(from: nil, .down) == nil)
    }
}
