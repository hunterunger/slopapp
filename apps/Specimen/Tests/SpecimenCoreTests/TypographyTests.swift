import CoreText
import Foundation
import Testing
@testable import SpecimenCore

@Suite struct VariationTests {
    let weight = VariationAxis(tag: "wght", name: "Weight", minimum: 100, maximum: 900, defaultValue: 400)
    let width = VariationAxis(tag: "wdth", name: "Width", minimum: 75, maximum: 125, defaultValue: 100)

    @Test func clampsAndReportsChangedAxes() {
        var settings = VariationSettings(axes: [weight, width])
        #expect(settings.isDefault)
        #expect(settings.coreTextVariation.isEmpty)
        settings.set("wght", to: 1200)
        settings.set("nope", to: 3)
        #expect(settings.value("wght") == 900)
        #expect(settings.value("wdth") == 100)
        #expect(!settings.isDefault)
        #expect(settings.coreTextVariation == [0x7767_6874: 900])
        settings.set("wdth", to: 87.5)
        #expect(settings.css == #"font-variation-settings: "wght" 900, "wdth" 87.5;"#)
        #expect(settings.coreTextValues == [0x7767_6874: 900, 0x7764_7468: 87.5])
        settings.reset()
        #expect(settings.isDefault)
        #expect(settings.coreTextValues == [0x7767_6874: 400, 0x7764_7468: 100])
    }

    @Test func tagsAndIdentifiersRoundTrip() {
        #expect(VariationAxis.identifier(fromTag: "wght") == 0x7767_6874)
        #expect(VariationAxis.tag(from: 0x7767_6874) == "wght")
        let settings = VariationSettings.from(axes: [weight, width], coreText: [0x7767_6874: 628])
        #expect(settings.value("wght") == 628)
    }

    @Test func stopsSpanTheAxis() {
        #expect(VariationSettings.stops(for: weight) == [100, 300, 500, 700, 900])
        #expect(VariationSettings.stops(for: VariationAxis(tag: "x", name: "x", minimum: 1, maximum: 1, defaultValue: 1)) == [1])
    }
}

@Suite struct CharacterTests {
    let latin: [UInt32] = Array(0x20...0x7E) + [0xA0, 0xE9, 0x20AC, 0x0301, 0xE000]

    @Test func listsVisibleCharactersOnly() {
        let set = Set(latin)
        let chars = CharacterCatalog.characters(planes: [0]) { set.contains($0) }
        #expect(!chars.contains(0x20))    // space
        #expect(!chars.contains(0xA0))    // no-break space
        #expect(!chars.contains(0xE000))  // private use
        #expect(chars.contains(0x41) && chars.contains(0x20AC) && chars.contains(0x0301))
        #expect(CharacterCatalog.characters(planes: [0], limit: 3) { set.contains($0) }.count == 3)
    }

    @Test func groupsAndSearch() {
        let chars = CharacterCatalog.characters(planes: [0]) { Set(latin).contains($0) }
        #expect(CharacterCatalog.filter(chars, group: .currency, search: "") .contains(0x20AC))
        #expect(CharacterCatalog.filter(chars, group: .numbers, search: "").count == 10)
        #expect(CharacterCatalog.filter(chars, group: .marks, search: "") == [0x0301])
        #expect(CharacterCatalog.filter(chars, group: .all, search: "euro") == [0x20AC])
        #expect(CharacterCatalog.filter(chars, group: .all, search: "U+0041") == [0x41])
        #expect(CharacterCatalog.filter(chars, group: .all, search: "a") == [0x41, 0x61])
        #expect(CharacterCatalog.filter(chars, group: .all, search: "latin small letter e") .contains(0xE9))
        #expect(CharacterCatalog.filter(chars, group: .letters, search: "euro").isEmpty)
    }

    @Test func formats() {
        #expect(CharacterCatalog.codePoint(0x41) == "U+0041")
        #expect(CharacterCatalog.codePoint(0x1F600) == "U+1F600")
        #expect(CharacterCatalog.htmlEntity(0x20AC) == "&#x20AC;")
        #expect(CharacterCatalog.name(0x20AC) == "Euro Sign")
        #expect(CharacterCatalog.string(0xE9) == "é")
        #expect(CharacterCatalog.parseCodePoint("20ac") == 0x20AC)
        #expect(CharacterCatalog.parseCodePoint("ab") == nil)
        #expect(CharacterCatalog.parseCodePoint("u+zz") == nil)
    }
}

@Suite struct CoverageTests {
    @Test func coversEveryVisibleCharacter() {
        let latin = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".utf16)
        let covers: ([UInt16]) -> Bool = { $0.allSatisfy(latin.contains) }
        #expect(PreviewText.covers("Hello World", covers: covers))
        #expect(!PreviewText.covers("Año", covers: covers))
        #expect(PreviewText.covers("", covers: covers))
        #expect(PreviewText.coverageText("  \nsecond") == nil)
        #expect(PreviewText.coverageText("Hi\nthere") == "Hi")
    }

    @Test func realFontCoverage() throws {
        // Helvetica ships with every Mac and has no Thai.
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let covers: ([UInt16]) -> Bool = { units in
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
        }
        #expect(PreviewText.covers("Café €5", covers: covers))
        #expect(!PreviewText.covers("สวัสดี", covers: covers))
    }
}

@Suite struct InstallPlanTests {
    let folder = URL(fileURLWithPath: "/tmp/specimen-test/Installed")

    @Test func plansCopiesAndProblems() {
        let files = ["/x/New.otf", "/x/Same.otf", "/x/Clash.ttf", "/x/Broken.ttf", "/x/Taken.otf", "/x/Twice.otf"].map(URL.init(fileURLWithPath:))
        let names: [String: [String]] = [
            "New.otf": ["New-Regular"], "Same.otf": ["Same-Regular"], "Clash.ttf": ["Helvetica"],
            "Taken.otf": ["Taken-Regular"], "Twice.otf": ["New-Regular"],
        ]
        let existing: Set<String> = ["/tmp/specimen-test/Installed/Same.otf", "/tmp/specimen-test/Installed/Taken.otf"]
        let plan = InstallPlan.make(
            files: files, into: folder, installed: ["Helvetica", "Same-Regular"],
            names: { names[$0.lastPathComponent] }, exists: { existing.contains($0.path) },
            sameFile: { a, _ in a.lastPathComponent == "Same.otf" }
        )
        #expect(plan.items.map(\.outcome) == [
            .copy(destination: folder.appendingPathComponent("New.otf")),
            .alreadyInstalled,
            .nameInUse(postScriptName: "Helvetica"),
            .unreadable,
            .copy(destination: folder.appendingPathComponent("Taken 2.otf")),
            .nameInUse(postScriptName: "New-Regular"),
        ])
        #expect(plan.copies.count == 2)
        #expect(plan.problems.count == 4)
    }

    @Test func findsFontFilesInDrops() {
        let urls = ["/d/Folder", "/d/a.OTF", "/d/readme.txt"].map(URL.init(fileURLWithPath:))
        let found = InstallPlan.fontFiles(in: urls, isDirectory: { $0.lastPathComponent == "Folder" }, contents: { _ in
            ["/d/Folder/z.ttf", "/d/Folder/b.ttc", "/d/Folder/x.pdf"].map(URL.init(fileURLWithPath:))
        })
        #expect(found.map(\.lastPathComponent) == ["b.ttc", "z.ttf", "a.OTF"])
    }
}
