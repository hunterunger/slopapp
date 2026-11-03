import CoreGraphics
import Foundation

/// The outline an icon is drawn in.
public enum IconShape: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Apple's macOS grid: an 824 px rounded tile on a 1024 canvas, with a soft shadow.
    case macOSApp
    /// Full bleed. For iOS and Xcode, where the system applies the mask.
    case square
    case circle
    /// The picture itself on a transparent square, no outline, no background.
    case asIs
    /// The picture on the front of the current system folder icon.
    case folder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .macOSApp: "macOS App"
        case .square: "Square"
        case .circle: "Circle"
        case .asIs: "As Is"
        case .folder: "Folder"
        }
    }

    /// Whether the background setting means anything for this shape.
    public var usesBackground: Bool {
        switch self {
        case .macOSApp, .square, .circle: true
        case .asIs, .folder: false
        }
    }
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

    public init(shape: IconShape = .macOSApp, scale: Double = 1, offset: CGPoint = .zero, fill: Bool = true,
                background: BackgroundMode = .automatic, color: RGBA = .white) {
        self.shape = shape
        self.scale = scale
        self.offset = offset
        self.fill = fill
        self.background = background
        self.color = color
    }

    /// Picture placement that suits a source: pictures with transparent edges (logos)
    /// are shown whole (the shapes give them breathing room); opaque pictures fill the shape.
    public static func placementDefaults(transparentEdges: Bool) -> (scale: Double, fill: Bool) {
        transparentEdges ? (1, false) : (1, true)
    }

    public var isCentered: Bool { offset == .zero }

    /// Keeps values in range (sliders and drags can overshoot; stored values can be stale).
    public func clamped() -> IconStyle {
        var copy = self
        copy.scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        let limit = Self.offsetLimit
        copy.offset = CGPoint(x: min(max(offset.x, -limit), limit), y: min(max(offset.y, -limit), limit))
        return copy
    }
}
