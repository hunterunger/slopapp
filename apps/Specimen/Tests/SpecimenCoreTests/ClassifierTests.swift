import Testing
@testable import SpecimenCore

@Suite struct ClassifierTests {
    @Test(arguments: [
        (FontFacts(familyName: "Plain", isMonospaceTrait: true, stylisticClass: 1), FontCategory.monospaced),
        (FontFacts(familyName: "Plain", panose: [2, 11, 6, 9, 0, 0, 0, 0, 0, 0]), .monospaced),
        (FontFacts(familyName: "Plain", stylisticClass: 8, equalAdvances: true), .monospaced),
        (FontFacts(familyName: "Roboto Mono", stylisticClass: 8), .monospaced),
        (FontFacts(familyName: "Plain", stylisticClass: 1), .serif),
        (FontFacts(familyName: "Plain", stylisticClass: 5), .serif),
        (FontFacts(familyName: "Plain", stylisticClass: 7), .serif),
        (FontFacts(familyName: "Plain", stylisticClass: 8), .sansSerif),
        (FontFacts(familyName: "Plain", stylisticClass: 9), .display),
        (FontFacts(familyName: "Plain", stylisticClass: 10), .script),
        (FontFacts(familyName: "Plain", stylisticClass: 12), .symbol),
        (FontFacts(familyName: "Plain", panose: [2, 11, 5, 2, 0, 0, 0, 0, 0, 0]), .sansSerif),
        (FontFacts(familyName: "Plain", panose: [2, 2, 5, 3, 0, 0, 0, 0, 0, 0]), .serif),
        (FontFacts(familyName: "Plain", panose: [3, 0, 0, 0, 0, 0, 0, 0, 0, 0]), .script),
        (FontFacts(familyName: "Plain", panose: [4, 0, 0, 0, 0, 0, 0, 0, 0, 0]), .display),
        (FontFacts(familyName: "Plain", panose: [5, 0, 0, 0, 0, 0, 0, 0, 0, 0]), .symbol),
        (FontFacts(familyName: "Noto Sans Serif Display"), .sansSerif),
        (FontFacts(familyName: "PT Serif"), .serif),
        (FontFacts(familyName: "Brush Up"), .script),
        (FontFacts(familyName: "Big Stencil"), .display),
        (FontFacts(familyName: "Zapf Dingbats"), .symbol),
        (FontFacts(familyName: "Colorful", hasColorGlyphs: true), .symbol),
        (FontFacts(familyName: "Plain"), .other),
        (FontFacts(familyName: "Plain", coversBasicLatin: false), .otherScripts),
        (FontFacts(familyName: "Monotype Corsiva"), .other),   // "Monotype" isn't the word "Mono"
    ])
    func chain(facts: FontFacts, expected: FontCategory) {
        #expect(Classifier.classify(facts) == expected)
    }

    @Test func classBeatsNames() {
        // A slab named "Sans" by its class: the class wins over the name hint.
        #expect(Classifier.classify(FontFacts(familyName: "Sans Slab", stylisticClass: 5)) == .serif)
    }

    @Test func panoseAnyIsIgnored() {
        #expect(Classifier.classify(FontFacts(familyName: "Plain", panose: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == .other)
    }

    @Test func axisTags() {
        #expect(VariationAxis.tag(from: 0x7767_6874) == "wght")
        #expect(VariationAxis.tag(from: 3) == "3")
    }
}
