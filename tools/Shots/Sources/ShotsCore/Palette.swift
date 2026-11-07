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

/// The Nordic palette (brand/brand.json `nordic`) and each app's own tile colour, read from its
/// herbarium icon spec (`apps/<Name>/Icon.py`, brand/ICONS.md), so a shot's backdrop is the
/// colour of the app's icon.
public struct Nordic: Equatable, Sendable {
    public var colours: [String: RGB]
    /// Category → colour name (brand.json `nordic.categories`), for apps without an icon spec.
    public var categories: [String: String]

    public init(colours: [String: RGB], categories: [String: String] = [:]) {
        self.colours = colours
        self.categories = categories
    }

    /// Reads `nordic` from brand.json.
    public static func load(brand url: URL) throws -> Nordic {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let nordic = json?["nordic"] as? [String: Any] ?? [:]
        var colours: [String: RGB] = [:]
        for (key, value) in nordic {
            if let hex = value as? String, let rgb = RGB(hex: hex) { colours[key] = rgb }
        }
        for name in ["birch", "night", "charcoal", "pine"] where colours[name] == nil {
            throw ShowcaseFile.Invalid(description: "brand.json nordic has no \(name)")
        }
        return Nordic(colours: colours, categories: nordic["categories"] as? [String: String] ?? [:])
    }

    public func colour(_ name: String) -> RGB? { colours[name] }
    public var birch: RGB { colours["birch"] ?? .white }
    public var night: RGB { colours["night"] ?? .black }
    public var charcoal: RGB { colours["charcoal"] ?? .black }

    /// A category's colour, for apps that don't have an icon spec yet (pine if it has none).
    public func colour(forCategory category: String) -> RGB {
        categories[category].flatMap { colours[$0] } ?? colours["pine"] ?? .black
    }

    // MARK: The app's tile

    /// The tile colour in an icon spec: `tile=TILES["clay"]` (looked up in the generator's
    /// `TILES` table) or `tile="#C4704F"`.
    public static func tile(inSpec spec: String, tiles: [String: RGB]) -> RGB? {
        if let name = firstMatch(#"tile\s*=\s*TILES\[\s*["']([A-Za-z0-9_]+)["']\s*\]"#, in: spec) {
            return tiles[name]
        }
        return firstMatch(#"tile\s*=\s*["'](#?[0-9A-Fa-f]{6})["']"#, in: spec).flatMap(RGB.init(hex:))
    }

    /// The `TILES = { "name": "#RRGGBB", ... }` table of scripts/icons/herbarium.py.
    public static func tiles(inGenerator source: String) -> [String: RGB] {
        guard let start = source.range(of: "TILES = {"),
              let end = source.range(of: "}", range: start.upperBound..<source.endIndex) else { return [:] }
        let table = String(source[start.upperBound..<end.lowerBound])
        var tiles: [String: RGB] = [:]
        let pattern = try! NSRegularExpression(pattern: #"["']([A-Za-z0-9_]+)["']\s*:\s*["'](#[0-9A-Fa-f]{6})["']"#)
        for match in pattern.matches(in: table, range: NSRange(table.startIndex..., in: table)) {
            guard let name = Range(match.range(at: 1), in: table), let hex = Range(match.range(at: 2), in: table),
                  let rgb = RGB(hex: String(table[hex])) else { continue }
            tiles[String(table[name])] = rgb
        }
        return tiles
    }

    /// The tile colour of the app whose folder is `appDirectory` (`apps/<Name>`): its
    /// `Icon.py`, or the older `brand/icon-lab/icons/<Name>.py`. nil when there's no spec.
    public static func appTile(appDirectory: URL, repoRoot: URL) -> RGB? {
        let name = appDirectory.lastPathComponent
        let specs = [appDirectory.appendingPathComponent("Icon.py"),
                     repoRoot.appendingPathComponent("brand/icon-lab/icons/\(name).py")]
        guard let spec = specs.lazy.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first else { return nil }
        let generator = (try? String(contentsOf: repoRoot.appendingPathComponent("scripts/icons/herbarium.py"), encoding: .utf8)) ?? ""
        return tile(inSpec: spec, tiles: tiles(inGenerator: generator))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// The colours of one backdrop: the app's tile colour as a soft, matte wash over birch in light
/// mode and over night in dark mode (brand/BRAND.md, Nordic). No gloss, no texture: prints only
/// belong inside panels.
public struct BackdropPalette: Equatable, Sendable {
    public var top: RGB
    public var bottom: RGB
    /// A soft light from above.
    public var glow: RGB
    public var glowAlpha: Double
    /// A pool of the tile colour in one corner.
    public var accent: RGB
    public var accentAlpha: Double
    public var isDark: Bool

    public init(tile: RGB, nordic: Nordic, dark: Bool) {
        isDark = dark
        if dark {
            // The icons' dark rule: the tile sinks toward night.
            top = nordic.night.mixed(with: tile, by: 0.30)
            bottom = nordic.night.mixed(with: tile, by: 0.12)
            glow = tile.mixed(with: nordic.birch, by: 0.3)
            glowAlpha = 0.14
            accent = tile
            accentAlpha = 0.18
        } else {
            top = nordic.birch.mixed(with: tile, by: 0.14)
            bottom = nordic.birch.mixed(with: tile, by: 0.40)
            glow = nordic.birch
            glowAlpha = 0.6
            accent = tile
            accentAlpha = 0.24
        }
    }

    /// The menu bar strip: a frosted band, and the colour its icon is drawn in.
    public var stripFill: (RGB, Double) { isDark ? (.black, 0.28) : (.white, 0.42) }
    public var stripHairline: (RGB, Double) { isDark ? (.white, 0.10) : (.black, 0.08) }
    public var menuBarInk: (RGB, Double) { isDark ? (.white, 0.92) : (.black, 0.84) }
    /// The pressed status item's capsule.
    public var itemHighlight: (RGB, Double) { isDark ? (.white, 0.22) : (.black, 0.10) }
}
