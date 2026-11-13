import CoreText
import Foundation
import Testing
@testable import SpecimenCore

@Suite struct FeatureTests {
    /// What CoreText reports for a typical OpenType font (shape from Avenir Next on macOS 27).
    static var raw: [[String: Any]] { [
        ["CTFeatureTypeIdentifier": 0, "CTFeatureTypeName": "All Typographic Features",
         "CTFeatureTypeSelectors": [["CTFeatureSelectorIdentifier": 0, "CTFeatureSelectorName": "On", "CTFeatureSelectorDefault": 1]]],
        ["CTFeatureTypeIdentifier": 1, "CTFeatureTypeName": "Ligatures", "CTFeatureTypeSelectors": [
            ["CTFeatureSelectorIdentifier": 2, "CTFeatureSelectorName": "Common Ligatures", "CTFeatureSelectorDefault": 1,
             "CTFeatureOpenTypeTag": "liga", "CTFeatureOpenTypeValue": 1],
            ["CTFeatureSelectorIdentifier": 4, "CTFeatureSelectorName": "Rare Ligatures", "CTFeatureOpenTypeTag": "dlig", "CTFeatureOpenTypeValue": 1],
        ]],
        ["CTFeatureTypeIdentifier": 21, "CTFeatureTypeName": "Number Case", "CTFeatureTypeExclusive": 1, "CTFeatureTypeSelectors": [
            ["CTFeatureSelectorIdentifier": 0, "CTFeatureSelectorName": "Old-Style Figures", "CTFeatureOpenTypeTag": "onum", "CTFeatureOpenTypeValue": 1],
            ["CTFeatureSelectorIdentifier": 2, "CTFeatureSelectorName": "Default", "CTFeatureSelectorDefault": 1],
        ]],
        ["CTFeatureTypeIdentifier": 6, "CTFeatureTypeName": "Number Spacing", "CTFeatureTypeExclusive": 1, "CTFeatureTypeSelectors": [
            ["CTFeatureSelectorIdentifier": 0, "CTFeatureSelectorName": "Monospaced Numbers"],
            ["CTFeatureSelectorIdentifier": 1, "CTFeatureSelectorName": "Proportional Numbers"],
        ]],
        ["CTFeatureTypeIdentifier": 35, "CTFeatureTypeName": "Stylistic Alternatives", "CTFeatureTypeSelectors": [
            ["CTFeatureSelectorIdentifier": 2, "CTFeatureSelectorName": "Single-storey a", "CTFeatureOpenTypeTag": "ss01", "CTFeatureOpenTypeValue": 1],
        ]],
        ["CTFeatureTypeName": "'cv01'", "CTFeatureTypeExclusive": 1, "CTFeatureTypeSelectors": [
            ["CTFeatureSelectorIdentifier": 0, "CTFeatureSelectorName": "Off", "CTFeatureSelectorDefault": 1, "CTFeatureOpenTypeTag": "cv01", "CTFeatureOpenTypeValue": 0],
            ["CTFeatureSelectorIdentifier": 1, "CTFeatureSelectorName": "On", "CTFeatureOpenTypeTag": "cv01", "CTFeatureOpenTypeValue": 1],
        ]],
        ["CTFeatureTypeName": "'REQD'", "CTFeatureTypeExclusive": 1, "CTFeatureTypeSelectors": [
            ["CTFeatureSelectorIdentifier": 0, "CTFeatureSelectorName": "Off", "CTFeatureOpenTypeTag": "REQD", "CTFeatureOpenTypeValue": 0],
            ["CTFeatureSelectorIdentifier": 1, "CTFeatureSelectorName": "On", "CTFeatureOpenTypeTag": "REQD", "CTFeatureOpenTypeValue": 1],
        ]],
    ] }

    var types: [FontFeatureType] { FeatureCatalog.types(fromCoreText: Self.raw) }

    @Test func discoversUserFacingTypes() {
        #expect(types.map(\.title) == ["Ligatures", "Number Case", "Number Spacing", "Stylistic Alternatives", "Character Variant 1"])
        #expect(types.map(\.group) == [.ligatures, .figures, .figures, .stylisticSets, .characterVariants])
        #expect(types[4].tag == "cv01")
        #expect(types[4].id == "ot:cv01")
        #expect(types[1].defaultSelector?.name == "Default")
        // No default flagged: the first selector is the default of an exclusive type.
        #expect(types[2].defaultSelector?.name == "Monospaced Numbers")
    }

    @Test func switchesAndChoices() {
        let types = types
        let ligatures = types[0], numberCase = types[1], variant = types[4]
        var settings = FeatureSettings()
        #expect(settings.isOn(ligatures.selectors[0], in: ligatures))
        #expect(!settings.isOn(ligatures.selectors[1], in: ligatures))
        settings.set(ligatures.selectors[0], in: ligatures, on: false)
        settings.set(ligatures.selectors[1], in: ligatures, on: true)
        settings.choose(numberCase.selectors[0], in: numberCase)
        settings.set(variant.selectors[1], in: variant, on: true)
        #expect(settings.changeCount == 4)
        let values = settings.values(for: types)
        #expect(Set(values) == [
            FeatureValue(typeID: 1, selectorID: 3, tag: "liga", value: 0),
            FeatureValue(typeID: 1, selectorID: 4, tag: "dlig", value: 1),
            FeatureValue(typeID: 21, selectorID: 0, tag: "onum", value: 1),
            FeatureValue(typeID: nil, selectorID: 1, tag: "cv01", value: 1),
        ])
        #expect(settings.css(for: types) == "font-feature-settings: \"liga\" 0, \"dlig\", \"onum\", \"cv01\";")
        // Back to the default removes the change.
        settings.choose(numberCase.defaultSelector, in: numberCase)
        settings.set(ligatures.selectors[0], in: ligatures, on: true)
        #expect(settings.changeCount == 2)
        settings.reset()
        #expect(settings.isDefault)
        #expect(settings.css(for: types) == nil)
    }

    @Test func appleFeaturesMapToOpenTypeForCSS() {
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 6, selectorID: 0, tag: nil, value: 1))! == ("tnum", 1))
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 37, selectorID: 1, tag: nil, value: 1))! == ("smcp", 1))
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 11, selectorID: 2, tag: nil, value: 1))! == ("frac", 1))
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 35, selectorID: 6, tag: nil, value: 1))! == ("ss03", 1))
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 35, selectorID: 7, tag: nil, value: 0))! == ("ss03", 0))
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 1, selectorID: 3, tag: nil, value: 0))! == ("liga", 0))
        #expect(FeatureCatalog.openType(for: FeatureValue(typeID: 99, selectorID: 1, tag: nil, value: 1)) == nil)
        // AAT-only settings without a mapping drop out of the CSS.
        let style = FontFeatureType(typeID: 19, name: "Style Options", isExclusive: true, selectors: [
            FeatureSelector(id: 0, name: "No Change", isDefault: true), FeatureSelector(id: 3, name: "Engraved Text"),
        ])
        var settings = FeatureSettings()
        settings.choose(style.selectors[1], in: style)
        #expect(settings.values(for: [style]) == [FeatureValue(typeID: 19, selectorID: 3, tag: nil, value: 1)])
        #expect(settings.css(for: [style]) == nil)
    }

    @Test func labelsTellSmallCapsApart() {
        let lower = FontFeatureType(typeID: 37, name: "Lower Case", isExclusive: true, selectors: [FeatureSelector(id: 0, name: "Default", isDefault: true), FeatureSelector(id: 1, name: "Small Capitals")])
        let upper = FontFeatureType(typeID: 38, name: "Upper Case", isExclusive: true, selectors: [FeatureSelector(id: 0, name: "Default", isDefault: true), FeatureSelector(id: 1, name: "Small Capitals")])
        #expect(FeatureCatalog.label(for: lower.selectors[1], in: lower) != FeatureCatalog.label(for: upper.selectors[1], in: upper))
        #expect(FeatureCatalog.label(for: types[4].selectors[1], in: types[4]) == "Character Variant 1")
    }

    @Test func samplesSuitTheFeature() {
        let types = types
        #expect(FeatureCatalog.sample(for: types[0], previewText: "Hello").contains("ffi"))
        #expect(FeatureCatalog.sample(for: types[1], previewText: "").contains("0123456789"))
        #expect(FeatureCatalog.sample(for: types[3], previewText: "Hello") == "Hello")
    }

    @Test func realFontsReportFeaturesThatChangeGlyphs() throws {
        // STIX Two Text and Avenir Next ship with macOS (read only, nothing registered).
        let avenir = CTFontCreateWithName("AvenirNext-Regular" as CFString, 24, nil)
        guard CTFontCopyPostScriptName(avenir) as String == "AvenirNext-Regular" else { return }
        let types = FeatureCatalog.types(of: avenir)
        let numberCase = try #require(types.first { $0.typeID == 21 })
        var settings = FeatureSettings()
        let oldStyle = try #require(numberCase.selectors.first { $0.openTypeTag == "onum" })
        settings.choose(oldStyle, in: numberCase)
        let values = settings.values(for: types)
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: values.map(\.coreTextSetting)] as CFDictionary)
        let styled = CTFontCreateCopyWithAttributes(avenir, 24, nil, descriptor)
        #expect(glyphs("0123456789", avenir) != glyphs("0123456789", styled))

        let stix = CTFontCreateWithName("STIXTwoText" as CFString, 24, nil)
        if CTFontCopyPostScriptName(stix) as String == "STIXTwoText" {
            #expect(FeatureCatalog.types(of: stix).contains { $0.group == .characterVariants })
        }
    }

    private func glyphs(_ text: String, _ font: CTFont) -> [CGGlyph] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
        return (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).flatMap { run -> [CGGlyph] in
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            return glyphs
        }
    }
}
