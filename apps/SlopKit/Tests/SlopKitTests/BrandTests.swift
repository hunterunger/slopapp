import Foundation
import Testing
@testable import SlopKit

// Brand.Nordic mirrors brand/brand.json `nordic`; these keep the two in step.

@Suite struct NordicPaletteTests {
    private static var brandJSON: [String: Any] {
        // Tests/SlopKitTests/BrandTests.swift → repo root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("brand/brand.json")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static var nordic: [String: Any] { brandJSON["nordic"] as? [String: Any] ?? [:] }

    private static func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }

    @Test func coloursMatchBrandJSON() throws {
        let expected: [String: UInt32] = [
            "birch": Brand.Nordic.Hex.birch, "oat": Brand.Nordic.Hex.oat, "charcoal": Brand.Nordic.Hex.charcoal,
            "night": Brand.Nordic.Hex.night, "pine": Brand.Nordic.Hex.pine, "sage": Brand.Nordic.Hex.sage,
            "clay": Brand.Nordic.Hex.clay, "ochre": Brand.Nordic.Hex.ochre, "fjord": Brand.Nordic.Hex.fjord,
            "heather": Brand.Nordic.Hex.heather, "rosewood": Brand.Nordic.Hex.rosewood,
            "lingonberry": Brand.Nordic.Hex.lingonberry,
        ]
        #expect(!Self.nordic.isEmpty, "brand.json has a nordic block")
        for (name, value) in expected {
            let json = try #require(Self.nordic[name] as? String, "brand.json nordic has \(name)")
            #expect(json.uppercased() == Self.hex(value), "\(name)")
        }
    }

    @Test func categoriesMatchBrandJSON() throws {
        let categories = try #require(Self.nordic["categories"] as? [String: String])
        #expect(!categories.isEmpty)
        for (category, colourName) in categories {
            let json = try #require(Self.nordic[colourName] as? String, "\(category) → \(colourName)")
            #expect(Self.hex(Brand.Nordic.category(category)) == json.uppercased(), "\(category)")
        }
    }

    @Test func newCategoriesGetAStablePanelColour() {
        let pick = Brand.Nordic.category("Games")
        #expect(Brand.Nordic.panels.contains(pick))
        #expect(Brand.Nordic.category("Games") == pick)
    }

    @Test func taglineMatchesBrandJSON() {
        #expect(Self.brandJSON["tagline"] as? String == Brand.tagline)
    }
}
