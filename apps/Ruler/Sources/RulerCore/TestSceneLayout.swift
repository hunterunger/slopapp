import CoreGraphics

/// The generated test scene (`RULER_TEST_SCENE=1`): shapes at known sizes so measurements
/// can be checked to the point, by scripts, blind testers and the self-check hook.
///
/// Frames are in points in the scene view, top-left origin (the view is flipped).
public enum TestSceneLayout {
    public enum Kind: String, Sendable, CaseIterable {
        /// A solid filled rectangle.
        case solid
        /// A 1 pt outline, white inside.
        case outline
        /// A rounded rectangle (anti-aliased corners).
        case rounded
        /// A left-to-right gradient strip.
        case gradient
        /// A card with a soft drop shadow.
        case shadowed
        /// A 0.5 pt tall line (one pixel on Retina).
        case hairline
        /// A rect on half points (100.5 × 50.5).
        case halfPoint
        /// Two squares with a known gap between them.
        case pair
        /// A light box on a dark panel.
        case onDark
        /// Tiny squares.
        case tiny
        /// The dark panel behind `onDark`.
        case darkPanel
        /// A line of text (measured loosely: glyph bounds depend on the font).
        case text
    }

    public struct Shape: Sendable, Identifiable {
        public let id: String
        public let kind: Kind
        public let frame: CGRect
        /// The caption drawn under it ("200 × 120"). Nil: no caption.
        public let caption: String?
        /// Whether the self-check expects the measurement to equal `frame` exactly.
        public let isExact: Bool
    }

    public static let size = CGSize(width: 900, height: 560)

    public static let shapes: [Shape] = [
        Shape(id: "solid", kind: .solid, frame: CGRect(x: 40, y: 40, width: 200, height: 120), caption: "200 × 120", isExact: true),
        Shape(id: "outline", kind: .outline, frame: CGRect(x: 290, y: 40, width: 160, height: 100), caption: "160 × 100, 1 pt border", isExact: true),
        Shape(id: "rounded", kind: .rounded, frame: CGRect(x: 500, y: 40, width: 180, height: 100), caption: "180 × 100, rounded", isExact: true),
        Shape(id: "halfPoint", kind: .halfPoint, frame: CGRect(x: 730, y: 40, width: 100.5, height: 50.5), caption: "100.5 × 50.5", isExact: true),
        Shape(id: "gradient", kind: .gradient, frame: CGRect(x: 40, y: 210, width: 400, height: 40), caption: "400 × 40, gradient", isExact: true),
        Shape(id: "shadowed", kind: .shadowed, frame: CGRect(x: 500, y: 200, width: 200, height: 100), caption: "200 × 100, shadow", isExact: true),
        Shape(id: "hairline", kind: .hairline, frame: CGRect(x: 40, y: 300, width: 300, height: 0.5), caption: "300 × 0.5", isExact: true),
        Shape(id: "pairLeft", kind: .pair, frame: CGRect(x: 40, y: 360, width: 60, height: 60), caption: nil, isExact: true),
        Shape(id: "pairRight", kind: .pair, frame: CGRect(x: 124, y: 360, width: 60, height: 60), caption: "60 × 60, 24 apart", isExact: true),
        Shape(id: "darkPanel", kind: .darkPanel, frame: CGRect(x: 240, y: 350, width: 220, height: 100), caption: "220 × 100 panel, 100 × 40 box", isExact: true),
        Shape(id: "onDark", kind: .onDark, frame: CGRect(x: 300, y: 380, width: 100, height: 40), caption: nil, isExact: true),
        Shape(id: "tiny2", kind: .tiny, frame: CGRect(x: 520, y: 370, width: 2, height: 2), caption: nil, isExact: true),
        Shape(id: "tiny1", kind: .tiny, frame: CGRect(x: 540, y: 370, width: 1, height: 1), caption: "2 × 2 and 1 × 1", isExact: true),
        Shape(id: "text", kind: .text, frame: CGRect(x: 600, y: 350, width: 260, height: 50), caption: nil, isExact: false),
    ]

    public static func shape(_ id: String) -> Shape? { shapes.first { $0.id == id } }
}
