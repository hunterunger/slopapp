import Foundation
import Testing
@testable import SpecimenCore

@Suite struct StoreTests {
    @Test func favoritesRoundTrip() throws {
        let store = FavoritesStore(directory: temporaryDirectory())
        #expect(store.load().isEmpty)
        try store.save(["Didot", "Avenir"])
        #expect(store.load() == ["Avenir", "Didot"])
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(text.contains("\"Avenir\""))
    }

    @Test func damagedFavoritesAreSetAside() throws {
        let dir = temporaryDirectory()
        let store = FavoritesStore(directory: dir)
        try Data("{nope".utf8).write(to: store.url)
        #expect(store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("favorites.damaged.json").path))
    }

    @Test func categoryOverridesRoundTrip() throws {
        let dir = temporaryDirectory()
        let store = CategoryOverridesStore(directory: dir)
        #expect(store.load().isEmpty)
        try store.save(["Avenir": .display, "Didot": .serif])
        #expect(store.load() == ["Avenir": .display, "Didot": .serif])
        try Data(#"{"X": "nonsense", "Y": "script"}"#.utf8).write(to: store.url)
        #expect(store.load() == ["Y": .script])
    }

    @Test func environment() {
        let env = SpecimenEnvironment(environment: [
            "SPECIMEN_DATA_DIR": "/tmp/specimen-test/data", "SPECIMEN_TEST_FONTS": "/tmp/specimen-test",
            "SPECIMEN_STRESS": "500", "SPECIMEN_BENCH": "scroll",
        ], defaultDataDirectory: { URL(fileURLWithPath: "/default") })
        #expect(env.dataDirectory.path == "/tmp/specimen-test/data")
        #expect(env.isTestMode)
        #expect(env.stressCopies == 50)
        #expect(env.benchmark == "scroll")
        #expect(env.indexCacheURL.path == "/tmp/specimen-test/data/Cache/index.plist")
        #expect(env.testModeSummary?.contains("/tmp/specimen-test") == true)
        let plain = SpecimenEnvironment(environment: [:], defaultDataDirectory: { URL(fileURLWithPath: "/default") })
        #expect(plain.dataDirectory.path == "/default")
        #expect(!plain.isTestMode)
        #expect(plain.stressCopies == 1)
    }
}
