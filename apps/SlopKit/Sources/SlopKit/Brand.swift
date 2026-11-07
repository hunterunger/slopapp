import SwiftUI

/// Slopapp brand values. Keep in sync with brand/brand.json.
/// Apps use these only in the About view and icons, never in regular UI
/// (see docs/design-system.md: the user's accent color wins).
public enum Brand {
    public static let name = "Slopapp"
    public static let tagline = "Native Mac apps, made with care."
    public static let repoURL = URL(string: "https://github.com/hunterunger/slopapp")!
    public static let license = "MIT"

    public enum Hex {
        public static let forest: UInt32 = 0x0F3D2E
        public static let leaf: UInt32 = 0x3DBE74
        public static let mint: UInt32 = 0xD4F2DF
        public static let cream: UInt32 = 0xFAF6EC
        public static let ember: UInt32 = 0xE5603D
        public static let ink: UInt32 = 0x13201A
    }

    public static let forest = Color(hex: Hex.forest) // lint:allow brand palette
    public static let leaf = Color(hex: Hex.leaf) // lint:allow brand palette
    public static let mint = Color(hex: Hex.mint) // lint:allow brand palette
    public static let cream = Color(hex: Hex.cream) // lint:allow brand palette
    public static let ember = Color(hex: Hex.ember) // lint:allow brand palette
    public static let ink = Color(hex: Hex.ink) // lint:allow brand palette

    /// The launcher's and website's palette (brand.json `candy`): translucent sugar-candy
    /// plastic over frosted ice. Only the Slopapp launcher uses it; the apps keep the
    /// system look and the user's accent colour.
    public enum Candy {
        public static let strawberry = Color(hex: 0xF0407A) // lint:allow brand palette
        public static let tangerine = Color(hex: 0xF28A0C) // lint:allow brand palette
        public static let lime = Color(hex: 0x6CCB2F) // lint:allow brand palette
        public static let lagoon = Color(hex: 0x0A9DBF) // lint:allow brand palette
        public static let blueberry = Color(hex: 0x2F6FE4) // lint:allow brand palette
        public static let grape = Color(hex: 0x8A4BD1) // lint:allow brand palette
        public static let ice = Color(hex: 0xF3F6F9) // lint:allow brand palette
        public static let graphite = Color(hex: 0x1C1F24) // lint:allow brand palette
        /// Every flavour, in the order they cycle (category tints, decorative accents).
        public static let flavours: [Color] = [strawberry, tangerine, lime, lagoon, blueberry, grape]
    }
}

/// sRGB components (0...1) of a 0xRRGGBB value.
public func rgbComponents(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
    (
        Double((hex >> 16) & 0xFF) / 255,
        Double((hex >> 8) & 0xFF) / 255,
        Double(hex & 0xFF) / 255
    )
}

extension Color {
    public init(hex: UInt32) {
        let c = rgbComponents(hex)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }
}
