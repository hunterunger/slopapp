import Foundation
import Testing
@testable import IconsmithCore

@Suite struct PreferencesTests {
    @Test func roundTripsAndDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "iconsmith-tests-\(UUID().uuidString)"))
        let store = PreferencesStore(defaults: defaults)
        #expect(store.load() == IconsmithPreferences())
        var prefs = IconsmithPreferences()
        prefs.shape = .folder
        prefs.format = .xcode
        prefs.options.xcodePlatforms = [.watchOS]
        prefs.color = RGBA(0.1, 0.2, 0.3)
        store.save(prefs)
        #expect(store.load() == prefs)
    }

    @Test func missingOrUnknownFieldsFallBackToDefaults() throws {
        let data = Data(#"{"shape":"circle","format":"bogus"}"#.utf8)
        let prefs = try JSONDecoder().decode(IconsmithPreferences.self, from: data)
        #expect(prefs.shape == .circle)
        #expect(prefs.format == .icns)
        #expect(prefs.revealAfterExport)
    }
}
