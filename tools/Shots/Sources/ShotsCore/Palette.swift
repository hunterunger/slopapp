import CoreGraphics
import Foundation

/// An sRGB colour, 0...1 per channel.
public struct RGB: Equatable, Sendable, CustomStringConvertible {
    public var r, g, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// "#F0407A" or "F0407A".
    public init?(hex: String) {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// Linear blend: 0 is self, 1 is `other`.
    public func mixed(with other: RGB, by amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public var description: String { hex }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)

    public func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, alpha])!
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

/// The candy palette (brand/brand.json `candy`) and the category → flavour map shared with
/// the website (web/src/lib/catalog.ts) and the launcher (Candy.swift).
public struct Candy: Equatable, Sendable {
    public static let flavourOrder = ["strawberry", "tangerine", "lime", "lagoon", "blueberry", "grape"]
    static let categoryFlavours = [
        "Hub": "strawberry", "Utilities": "blueberry", "Productivity": "tangerine",
        "Design": "grape", "Developer": "lime", "Media": "lagoon",
    ]

    public var colours: [String: RGB]

    public init(colours: [String: RGB]) {
        self.colours = colours
    }

    /// Reads `candy` from brand.json.
    public static func load(brand url: URL) throws -> Candy {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let candy = json?["candy"] as? [String: Any] ?? [:]
        var colours: [String: RGB] = [:]
        for (key, value) in candy {
            if let hex = value as? String, let rgb = RGB(hex: hex) { colours[key] = rgb }
        }
        for name in flavourOrder + ["ice", "graphite"] where colours[name] == nil {
            throw ShowcaseFile.Invalid(description: "brand.json candy has no \(name)")
        }
        return Candy(colours: colours)
    }

    /// The website's rule: the mapped flavour, else one picked by the category's character codes.
    public static func flavour(forCategory category: String) -> String {
        if let mapped = categoryFlavours[category] { return mapped }
        let sum = category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return flavourOrder[sum % flavourOrder.count]
    }

    public func colour(_ name: String) -> RGB { colours[name] ?? .white }
    public var ice: RGB { colour("ice") }
    public var graphite: RGB { colour("graphite") }
}

/// The colours of one backdrop: soft candy over frosted ice in light mode, deep jewel tones
/// over graphite in dark mode (brand/BRAND.md).
public struct BackdropPalette: Equatable, Sendable {
    public var top: RGB
    public var bottom: RGB
    /// A soft light from above.
    public var glow: RGB
    public var glowAlpha: Double
    /// A pool of the pure flavour in one corner.
    public var accent: RGB
    public var accentAlpha: Double
    public var isDark: Bool

    public init(flavour: RGB, candy: Candy, dark: Bool) {
        isDark = dark
        if dark {
            top = candy.graphite.mixed(with: flavour, by: 0.40)
            bottom = candy.graphite.mixed(with: flavour, by: 0.16).mixed(with: .black, by: 0.10)
            glow = flavour.mixed(with: .white, by: 0.25)
            glowAlpha = 0.28
            accent = flavour
            accentAlpha = 0.22
        } else {
            top = candy.ice.mixed(with: flavour, by: 0.22)
            bottom = candy.ice.mixed(with: flavour, by: 0.46)
            glow = .white
            glowAlpha = 0.7
            accent = flavour
            accentAlpha = 0.28
        }
    }

    /// The menu bar strip: a frosted band, and the colour its icon is drawn in.
    public var stripFill: (RGB, Double) { isDark ? (.black, 0.28) : (.white, 0.42) }
    public var stripHairline: (RGB, Double) { isDark ? (.white, 0.10) : (.black, 0.08) }
    public var menuBarInk: (RGB, Double) { isDark ? (.white, 0.92) : (.black, 0.84) }
    /// The pressed status item's capsule.
    public var itemHighlight: (RGB, Double) { isDark ? (.white, 0.22) : (.black, 0.10) }
}
