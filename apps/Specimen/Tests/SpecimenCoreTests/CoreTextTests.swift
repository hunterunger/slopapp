import CoreText
import Foundation
import Testing
@testable import SpecimenCore

/// Read-only checks against the real system font list, plus the OFL fixture registered at
/// process scope (visible to this test process only; nothing installed is touched).
@Suite(.serialized) struct CoreTextTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    @Test func indexesTheRealLibrary() {
        let clock = ContinuousClock()
        var result: FontIndexer.Result?
        let cold = clock.measure { result = FontIndexer(system: CoreTextFontSystem()).build(cache: IndexCache()) }
        guard let result else { return }
        #expect(result.faces.count > 50)
        #expect(!result.faces.contains { $0.postScriptName.hasPrefix(".") })
        let warm = clock.measure { _ = FontIndexer(system: CoreTextFontSystem()).build(cache: result.cache) }
        let families = FontFamily.group(result.faces)
        let perThousand = cold / max(1, result.faces.count) * 1000
        print("real library: \(result.faces.count) faces, \(families.count) families; cold index \(cold) (\(perThousand) per 1k faces), warm \(warm)")
        let counts = Dictionary(grouping: families, by: \.category).mapValues(\.count)
        print("categories: " + FontCategory.allCases.map { "\($0.title) \(counts[$0] ?? 0)" }.joined(separator: ", "))
        #expect(warm < cold)
        // Well-known macOS families land in sensible categories.
        let byName = Dictionary(families.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        if let menlo = byName["Menlo"] { #expect(menlo.category == .monospaced) }
        if let times = byName["Times New Roman"] { #expect(times.category == .serif) }
        if let helvetica = byName["Helvetica"] { #expect(helvetica.category == .sansSerif) }
        if let helvetica = byName["Helvetica"] { #expect(helvetica.isSystem) }
    }

    @Test func fixtureLoadsFromItsFileAndClassifies() throws {
        let regular = Self.fixtures.appendingPathComponent("Silkscreen-Regular.ttf")
        #expect(FileManager.default.fileExists(atPath: regular.path))
        let font = try #require(FontLoader.makeFont(postScriptName: "Silkscreen-Regular", path: regular.path, isEnabled: false, size: 20))
        #expect(CTFontCopyPostScriptName(font) as String == "Silkscreen-Regular")
        let system = CoreTextFontSystem()
        let details = system.details(for: SystemFace(postScriptName: "Silkscreen-Regular", familyName: "Silkscreen",
                                                     styleName: "Regular", path: regular.path, isEnabled: false))
        #expect(details.coversBasicLatin)
        #expect(details.axes.isEmpty)
    }

    @Test func processScopeRegistrationShowsUpAndGoesAway() throws {
        let urls = ["Silkscreen-Regular.ttf", "Silkscreen-Bold.ttf"].map { Self.fixtures.appendingPathComponent($0) }
        // Process scope only: no other app sees it, and it ends with this process.
        let errors = TestFonts.wait { CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, $0) }
        #expect(errors.isEmpty)
        defer { _ = TestFonts.wait { CTFontManagerUnregisterFontURLs(urls as CFArray, .process, $0) } }
        let faces = CoreTextFontSystem().listFaces().filter { $0.familyName == "Silkscreen" }
        #expect(faces.count == 2)
        #expect(faces.allSatisfy { $0.isEnabled })
        let indexed = faces.map { FontIndexer.makeFace($0, details: FaceDetails(), modified: nil) }
        #expect(FontFamily.group(indexed).first?.representative?.styleName == "Regular")
        #expect(indexed.allSatisfy { $0.location == .other } == true)
    }
}
