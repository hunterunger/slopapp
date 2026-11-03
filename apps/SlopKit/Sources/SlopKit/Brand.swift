import SwiftUI

/// Slopapp brand values. Keep in sync with brand/brand.json.
/// Apps use these only in the About view and icons, never in regular UI
/// (see docs/design-system.md: the user's accent color wins).
public enum Brand {
    public static let name = "Slopapp"
    public static let tagline = "The name is a joke. The apps aren't."
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

    public static let forest = Color(hex: Hex.forest)
    public static let leaf = Color(hex: Hex.leaf)
    public static let mint = Color(hex: Hex.mint)
    public static let cream = Color(hex: Hex.cream)
    public static let ember = Color(hex: Hex.ember)
    public static let ink = Color(hex: Hex.ink)
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
