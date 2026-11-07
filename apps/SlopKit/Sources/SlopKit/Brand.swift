import SwiftUI

/// Slopapp brand values. Keep in sync with brand/brand.json.
/// Apps use these only in the About view and icons, never in regular UI
/// (see docs/design-system.md: the user's accent color wins). The launcher's frame is the
/// one exception: it's drawn in `Nordic`.
public enum Brand {
    public static let name = "Slopapp"
    public static let tagline = "Native Mac apps, made with care."
    public static let repoURL = URL(string: "https://github.com/hunterunger/slopapp")!
    public static let license = "MIT"

    /// The Nordic herbarium palette (brand.json `nordic`, brand/BRAND.md): matte, muted natural
    /// colour on warm birch. App icons, the website and the Slopapp launcher's frame use it; the
    /// apps themselves keep the system look and the user's accent colour.
    public enum Nordic {
        public enum Hex {
            public static let birch: UInt32 = 0xF5F0E8
            public static let oat: UInt32 = 0xE4D9C6
            public static let charcoal: UInt32 = 0x2F2D2A
            public static let night: UInt32 = 0x24231F
            public static let pine: UInt32 = 0x3F5E4E
            public static let sage: UInt32 = 0x8EA58B
            public static let clay: UInt32 = 0xC4704F
            public static let ochre: UInt32 = 0xD2A04C
            public static let fjord: UInt32 = 0x5D7E9A
            public static let heather: UInt32 = 0x8C7EA0
            public static let rosewood: UInt32 = 0xA9665C
            public static let lingonberry: UInt32 = 0xB9473B
        }

        /// Page background and light surfaces.
        public static let birch = Color(hex: Hex.birch) // lint:allow brand palette
        /// Quiet fills, empty specimen slots.
        public static let oat = Color(hex: Hex.oat) // lint:allow brand palette
        /// Text and the logo.
        public static let charcoal = Color(hex: Hex.charcoal) // lint:allow brand palette
        /// The dark-mode base.
        public static let night = Color(hex: Hex.night) // lint:allow brand palette
        /// Primary buttons and links.
        public static let pine = Color(hex: Hex.pine) // lint:allow brand palette
        public static let sage = Color(hex: Hex.sage) // lint:allow brand palette
        public static let clay = Color(hex: Hex.clay) // lint:allow brand palette
        public static let ochre = Color(hex: Hex.ochre) // lint:allow brand palette
        public static let fjord = Color(hex: Hex.fjord) // lint:allow brand palette
        public static let heather = Color(hex: Hex.heather) // lint:allow brand palette
        public static let rosewood = Color(hex: Hex.rosewood) // lint:allow brand palette
        public static let lingonberry = Color(hex: Hex.lingonberry) // lint:allow brand palette

        /// The print-panel colours (each is also an app's icon tile), in the order they cycle.
        public static let panels: [UInt32] = [Hex.sage, Hex.clay, Hex.ochre, Hex.fjord, Hex.heather, Hex.rosewood]

        /// Each category's colour (brand.json `nordic.categories`): one per category, so a
        /// category is the same colour wherever it's shown. Categories added later get a
        /// stable pick from `panels`.
        public static func category(_ name: String) -> UInt32 {
            switch name {
            case "Hub": Hex.pine
            case "Utilities": Hex.fjord
            case "Productivity": Hex.ochre
            case "Media": Hex.clay
            case "Design": Hex.heather
            case "Developer": Hex.sage
            default: panels[Int(name.unicodeScalars.reduce(UInt32(0)) { $0 &+ $1.value } % UInt32(panels.count))]
            }
        }
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
