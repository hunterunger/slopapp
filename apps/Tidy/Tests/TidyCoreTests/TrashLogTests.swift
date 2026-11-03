import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

@Suite("Trash log")
struct TrashLogTests {
    @Test func survivesARelaunchWhileItemsAreInTheTrash() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let service = TrashService(environment: fixture.environment)
        let prefs = fixture.library.appendingPathComponent("Preferences/com.fixture.Notely.plist")
        let cache = fixture.library.appendingPathComponent("Caches/com.fixture.Notely")
        let first = service.moveToTrash([(prefs, 4_000)])
        let second = service.moveToTrash([(cache, 2_000_000)])
        let file = fixture.root.appendingPathComponent("log/history.json")
        try TrashLog.save([
            TrashLogEntry(section: "junk", moved: first.moved),
            TrashLogEntry(section: "junk", moved: second.moved, wasPutBack: true),
        ], to: file)

        let loaded = TrashLog.load(from: file)
        #expect(loaded.count == 1)   // the undone one is dropped
        #expect(loaded.first?.moved.first?.original == prefs)

        // After relaunch, Put Back still works from the log.
        let back = service.putBack(loaded[0].moved)
        #expect(back.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: prefs.path))

        // Once nothing of an entry is left in the Trash, it's gone from the log.
        #expect(TrashLog.load(from: file).isEmpty)
    }

    @Test func missingOrBrokenLogIsEmpty() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let file = fixture.root.appendingPathComponent("history.json")
        #expect(TrashLog.load(from: file).isEmpty)
        try Data("nonsense".utf8).write(to: file)
        #expect(TrashLog.load(from: file).isEmpty)
    }
}
