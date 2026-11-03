import Testing
@testable import SpecimenCore

@Suite struct PreviewTextTests {
    @Test func emptyTextShowsFamilyName() {
        #expect(PreviewText.line(for: "", familyName: "Didot") == "Didot")
        #expect(PreviewText.line(for: "   ", familyName: "Didot") == "Didot")
        #expect(PreviewText.line(for: "Hello\nWorld", familyName: "Didot") == "Hello")
        #expect(PreviewText.line(for: "\nWorld", familyName: "Didot") == "Didot")
    }

    @Test func runsMarkMissingCharacters() {
        // A "font" that only has ASCII.
        let ascii: ([UInt16]) -> Bool = { $0.allSatisfy { $0 < 0x80 } }
        let runs = PreviewText.runs("Año €5", covers: ascii)
        #expect(runs.map(\.text) == ["A", "ñ", "o ", "€", "5"])
        #expect(runs.map(\.covered) == [true, false, true, false, true])
        #expect(PreviewText.missingCount(runs) == 2)
        #expect(abs(PreviewText.coverage(runs) - 3.0 / 5.0) < 0.001)
    }

    @Test func joinersAndSelectorsDontCountAsMissing() {
        var asked: [[UInt16]] = []
        _ = PreviewText.runs("❤️ 👍🏽", covers: { asked.append($0); return true })
        #expect(asked == [Array("❤".utf16), Array("👍".utf16)])
        #expect(PreviewText.coverage(PreviewText.runs("   ", covers: { _ in false })) == 1)
    }

    @Test func sampleUsesTheFontsOwnLetters() {
        let tamil = PreviewText.sample(hasColorGlyphs: false, contains: { (0x0B80...0x0BFF).contains($0) })
        #expect(!tamil.isEmpty)
        #expect(tamil.unicodeScalars.allSatisfy { (0x0B80...0x0BFF).contains($0.value) })
        let emoji = PreviewText.sample(hasColorGlyphs: true, contains: { $0 > 0x1F000 })
        #expect(emoji.contains("😀"))
        let symbols = PreviewText.sample(hasColorGlyphs: false, contains: { (0x2600...0x2610).contains($0) })
        #expect(symbols.unicodeScalars.first?.value == 0x2600)
        #expect(PreviewText.sample(hasColorGlyphs: false, contains: { $0 == 0x41 }) == "A")
    }

    @Test func sizeSteps() {
        #expect(PreviewSize.bigger(36) == 42)
        #expect(PreviewSize.smaller(36) == 32)
        #expect(PreviewSize.bigger(200) == 200)
        #expect(PreviewSize.smaller(8) == 8)
        #expect(PreviewSize.bigger(37) == 42)
        #expect(PreviewSize.clamp(1000) == 200)
        #expect(PreviewPreset.all.first?.text == "")
    }
}
