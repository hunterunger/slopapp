import CoreGraphics
import Foundation

/// The template an icon is drawn in: an outline for app icons, or a system icon (folder,
/// document) the picture goes onto.
public enum IconShape: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Apple's macOS grid: an 824 px rounded tile on a 1024 canvas, with a soft shadow.
    case macOSApp
    /// A full-canvas rounded square, the way iOS shows app icons.
    case rounded
    /// Full bleed. For iOS and Xcode, where the system applies the mask.
    case square
    case circle
    /// The picture itself on a transparent square, no outline, no background.
    case asIs
    /// The picture on the front of the current system folder icon.
    case folder
    /// The picture covering the whole front of the folder.
    case folderCover
    /// The picture's silhouette pressed into the folder, like the symbols macOS puts on folders.
    case folderSymbol
    /// The picture on the system's blank document icon.
    case document

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .macOSApp: "macOS App"
        case .rounded: "Rounded"
        case .square: "Square"
        case .circle: "Circle"
        case .asIs: "As Is"
        case .folder: "Folder"
        case .folderCover: "Folder Cover"
        case .folderSymbol: "Folder Symbol"
        case .document: "Document"
        }
    }

    /// Gallery sections.
    public enum Group: String, CaseIterable, Sendable, Identifiable {
        case appIcons, finder
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .appIcons: "App Icons"
            case .finder: "Folders & Files"
            }
        }
    }

    public var group: Group {
        switch self {
        case .macOSApp, .rounded, .square, .circle, .asIs: .appIcons
        case .folder, .folderCover, .folderSymbol, .document: .finder
        }
    }

    public var isFolder: Bool {
        switch self {
        case .folder, .folderCover, .folderSymbol: true
        default: false
        }
    }

    /// The shape has an outline that a background fills.
    public var hasOutline: Bool {
        switch self {
        case .macOSApp, .rounded, .square, .circle: true
        default: false
        }
    }

    /// Whether the colour setting means anything: a background behind the picture, or the
    /// folder's colour.
    public var usesBackground: Bool { hasOutline || isFolder }

    /// What the colour setting is called for this shape.
    public var colorTitle: String { isFolder ? "Folder Color" : "Background" }
}

/// What goes behind the picture.
public enum BackgroundMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The colour of the picture's edges, or white when they're transparent, so every
    /// shape is visible.
    case automatic
    case none
    case color

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .none: "None"
        case .color: "Color"
        }
    }
}

/// An sRGB colour that can be stored and sent across threads.
public struct RGBA: Codable, Equatable, Hashable, Sendable {
    public var red, green, blue, alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var isOpaque: Bool { alpha >= 0.999 }

    /// "#RRGGBB" (alpha dropped), for web manifests.
    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// The same colour with full alpha (opaque outputs can't keep transparency).
    public var opaque: RGBA { RGBA(red, green, blue, 1) }

    /// The same colour to within one 8-bit step per channel (what a swatch picked, after a
    /// round trip through a colour space or the saved preferences).
    public func isClose(to other: RGBA, tolerance: Double = 1.0 / 255) -> Bool {
        abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance && abs(alpha - other.alpha) <= tolerance
    }

    /// Relative luminance (sRGB weights, no gamma), 0...1.
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// Near-black or white, whichever reads better on this colour.
    public var contrasting: RGBA { luminance > 0.62 ? RGBA(0.12, 0.12, 0.12) : .white }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxV = max(red, green, blue), minV = min(red, green, blue), delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let h = (hue - hue.rounded(.down)) * 6, s = min(max(saturation, 0), 1), v = min(max(brightness, 0), 1)
        let i = Int(h) % 6, f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(v, t, p, alpha)
        case 1: self.init(q, v, p, alpha)
        case 2: self.init(p, v, t, alpha)
        case 3: self.init(p, q, v, alpha)
        case 4: self.init(t, p, v, alpha)
        default: self.init(v, p, q, alpha)
        }
    }

    /// The colour of a symbol pressed into a folder of this colour: the same hue, darker
    /// and a little richer (lighter on dark folders).
    public var symbolTone: RGBA {
        let (h, s, b) = hsb
        if b < 0.4 { return RGBA(hue: h, saturation: s * 0.8, brightness: min(b + 0.32, 1)) }
        return RGBA(hue: h, saturation: min(s * 1.25 + 0.08, 1), brightness: b * 0.66)
    }

    public init?(_ color: CGColor) {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 4 else { return nil }
        self.init(parts[0], parts[1], parts[2], parts[3])
    }
}

/// Everything the user adjusts about how the picture becomes an icon.
public struct IconStyle: Codable, Equatable, Sendable {
    public static let scaleRange: ClosedRange<Double> = 0.25...2
    public static let offsetLimit: Double = 0.75

    public var shape: IconShape = .macOSApp
    /// Picture size relative to the shape's content area (1 = fits it exactly).
    public var scale: Double = 1
    /// Picture offset as a fraction of the canvas; y points up.
    public var offset: CGPoint = .zero
    /// Fill crops a non-square picture to cover the area; fit shows all of it.
    public var fill: Bool = true
    public var background: BackgroundMode = .automatic
    public var color: RGBA = .white
    /// Picture rotation in degrees, counter-clockwise.
    public var rotation: Double = 0
    /// Text or emoji drawn over the picture (empty: none).
    public var text = IconText()

    public init(shape: IconShape = .macOSApp, scale: Double = 1, offset: CGPoint = .zero, fill: Bool = true,
                background: BackgroundMode = .automatic, color: RGBA = .white, rotation: Double = 0, text: IconText = IconText()) {
        self.shape = shape
        self.scale = scale
        self.offset = offset
        self.fill = fill
        self.background = background
        self.color = color
        self.rotation = rotation
        self.text = text
    }

    public static let rotationRange: ClosedRange<Double> = -180...180

    /// Picture placement that suits a source: pictures with transparent edges (logos)
    /// are shown whole (the shapes give them breathing room); opaque pictures fill the shape.
    public static func placementDefaults(transparentEdges: Bool) -> (scale: Double, fill: Bool) {
        transparentEdges ? (1, false) : (1, true)
    }

    public var isCentered: Bool { offset == .zero }

    /// The folder's own colour replaces the standard one.
    public var tintsFolder: Bool { shape.isFolder && background == .color }

    /// Keeps values in range (sliders and drags can overshoot; stored values can be stale).
    public func clamped() -> IconStyle {
        var copy = self
        copy.scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        let limit = Self.offsetLimit
        copy.offset = CGPoint(x: min(max(offset.x, -limit), limit), y: min(max(offset.y, -limit), limit))
        copy.rotation = min(max(rotation, Self.rotationRange.lowerBound), Self.rotationRange.upperBound)
        copy.text.size = min(max(text.size, IconText.sizeRange.lowerBound), IconText.sizeRange.upperBound)
        return copy
    }
}

/// Text or emoji on an icon: a label on a folder, a word on a blank icon, or a corner badge.
public struct IconText: Codable, Equatable, Sendable {
    public enum Design: String, CaseIterable, Codable, Sendable, Identifiable {
        case standard, rounded, serif, monospaced
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .standard: "System"
            case .rounded: "Rounded"
            case .serif: "Serif"
            case .monospaced: "Monospaced"
            }
        }
    }

    public enum Weight: String, CaseIterable, Codable, Sendable, Identifiable {
        case regular, medium, semibold, bold, heavy, black
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public enum Position: String, CaseIterable, Codable, Sendable, Identifiable {
        case center, top, bottom, badge
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .center: "Middle"
            case .top: "Top"
            case .bottom: "Bottom"
            case .badge: "Badge"
            }
        }
    }

    /// Text size as a fraction of the area it sits in (height).
    public static let sizeRange: ClosedRange<Double> = 0.05...1

    public var string: String = ""
    public var design: Design = .rounded
    public var weight: Weight = .bold
    /// Shrinks or grows the text to fill its area.
    public var autoSize = true
    public var size: Double = 0.3
    /// Nil: picked to contrast with what's behind (or pressed into a folder).
    public var color: RGBA?
    public var position: Position = .center
    /// The badge's circle colour (nil: red).
    public var badgeColor: RGBA?

    public init(string: String = "", design: Design = .rounded, weight: Weight = .bold, autoSize: Bool = true, size: Double = 0.3,
                color: RGBA? = nil, position: Position = .center, badgeColor: RGBA? = nil) {
        self.string = string
        self.design = design
        self.weight = weight
        self.autoSize = autoSize
        self.size = size
        self.color = color
        self.position = position
        self.badgeColor = badgeColor
    }

    /// The text to draw (trimmed), or nil when there's none.
    public var visible: String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static let defaultBadge = RGBA(0.95, 0.23, 0.19)
}
