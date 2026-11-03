import Foundation
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("clips-tests-\(UUID().uuidString)")
}

@Suite struct DatabaseTests {
    @Test func roundTrip() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        let snapshot = PasteboardSnapshot(items: [[Representation(type: PasteboardType.string, data: Data("slopapp-test rich".utf8)),
                                                   Representation(type: PasteboardType.rtf, data: Data("{\\rtf1}".utf8))]])
        var (clip, payload) = try ClipBuilder.build(snapshot, sourceBundleID: "com.apple.TextEdit", sourceName: "TextEdit", now: now).get()
        try await db.save(clip, payload: payload)

        let loaded = try await db.loadAll()
        #expect(loaded == [clip])
        #expect(try await db.payload(for: clip.id) == payload)

        clip.isPinned = true
        clip.useCount = 3
        clip.lastUsed = now + 60
        try await db.update(clip)
        #expect(try await db.loadAll() == [clip])

        try await db.delete(ids: [clip.id])
        #expect(try await db.loadAll().isEmpty)
        #expect(try await db.payload(for: clip.id) == nil)
    }

    @Test func filesAndThumbnails() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        let png = makePNG(width: 10, height: 10)
        let (clip, payload) = try ClipBuilder.build(PasteboardSnapshot(items: [[Representation(type: PasteboardType.png, data: png)]]),
                                                    sourceBundleID: nil, sourceName: nil, now: now).get()
        try await db.save(clip, payload: payload, thumbnail: Data([1, 2, 3]))
        #expect(try await db.thumbnail(for: clip.id) == Data([1, 2, 3]))
        // Metadata-only saves keep the thumbnail.
        try await db.save(clip, payload: nil)
        #expect(try await db.thumbnail(for: clip.id) == Data([1, 2, 3]))
        #expect(try await db.payload(for: clip.id)?.items[0][0].data == png)

        let attributes = try FileManager.default.attributesOfItem(atPath: db.fileURL.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func survivesReopen() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = textClip("slopapp-test persisted", at: now)
        do {
            let db = try ClipDatabase(directory: dir)
            try await db.save(clip, payload: ClipPayload(items: [[Representation(type: PasteboardType.string, data: Data(clip.text.utf8))]]))
        }
        let reopened = try ClipDatabase(directory: dir)
        #expect(try await reopened.loadAll().map(\.text) == ["slopapp-test persisted"])
    }

    @Test func longTextSurvivesReload() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clips-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let long = String(repeating: "slopapp-test ", count: 2_000) + "ENDMARK"
        let (clip, payload) = try ClipBuilder.build(PasteboardSnapshot(text: long), sourceBundleID: nil, sourceName: nil, now: now).get()
        let db = try ClipDatabase(directory: dir)
        try await db.save(clip, payload: payload)
        let loaded = try await ClipDatabase(directory: dir).loadAll()
        #expect(loaded.first?.longText == long)
        #expect(ClipSearch.run(loaded, query: "endmark").count == 1)
    }

    @Test func fiveThousandLoadQuickly() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try ClipDatabase(directory: dir)
        let synthetic = SyntheticHistory.make(count: 5_000, now: now)
        try await db.saveAll(synthetic.map { ($0.0, $0.1) })
        let clock = ContinuousClock()
        var loaded: [Clip] = []
        let elapsed = try await clock.measure { loaded = try await db.loadAll() }
        #expect(loaded.count == 5_000)
        #expect(loaded.first?.lastUsed == synthetic.map(\.0.lastUsed).max())
        #expect(elapsed < .milliseconds(500), "loading 5,000 clips took \(elapsed)")
    }
}
