import CoreGraphics
import Foundation

/// A backdrop behind a capture: a gradient or plain color with padding, rounded corners and
/// a shadow, for captures that go into docs, slides and posts. Part of the document, so it
/// stays editable and undoable like any annotation.
public struct CaptureBackground: Equatable, Sendable, Codable {
    public enum Fill: Equatable, Sendable, Codable {
        case gradient(GradientPreset)
        case solid(RGBAValue)
    }

    public var fill: Fill
    /// Space around the capture, in image points.
    public var padding: CGFloat
    /// Corner radius of the capture, in image points (0 = square).
    public var cornerRadius: CGFloat
    /// Shadow strength, 0…1.
    public var shadow: CGFloat

    public init(fill: Fill = .gradient(.dusk), padding: CGFloat = 64, cornerRadius: CGFloat = 12, shadow: CGFloat = 0.5) {
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    public static let paddingRange: ClosedRange<CGFloat> = 0...240
    public static let cornerRange: ClosedRange<CGFloat> = 0...48

    /// Clamped to the slider ranges.
    public var clamped: CaptureBackground {
        var copy = self
        copy.padding = min(max(padding, Self.paddingRange.lowerBound), Self.paddingRange.upperBound)
        copy.cornerRadius = min(max(cornerRadius, Self.cornerRange.lowerBound), Self.cornerRange.upperBound)
        copy.shadow = min(max(shadow, 0), 1)
        return copy
    }

    /// Names for `solidColors`, for VoiceOver.
    public static let solidColorNames = ["White", "Light Gray", "Gray", "Black", "Red", "Orange", "Yellow", "Green",
                                         "Teal", "Blue", "Indigo", "Purple"]

    /// Plain colors offered next to the gradients.
    public static let solidColors: [RGBA] = [
        RGBA(hex: 0xFFFFFF), RGBA(hex: 0xF2F2F7), RGBA(hex: 0x8E8E93), RGBA(hex: 0x1C1C1E),
        RGBA(hex: 0xFF3B30), RGBA(hex: 0xFF9500), RGBA(hex: 0xFFCC00), RGBA(hex: 0x34C759),
        RGBA(hex: 0x30B0C7), RGBA(hex: 0x007AFF), RGBA(hex: 0x5856D6), RGBA(hex: 0xAF52DE),
    ]
}

/// RGBA as a Codable value (RGBA itself stays a plain struct).
public struct RGBAValue: Equatable, Sendable, Codable {
    public var red, green, blue, alpha: Double
    public init(_ c: RGBA) { red = c.red; green = c.green; blue = c.blue; alpha = c.alpha }
    public var rgba: RGBA { RGBA(red, green, blue, alpha) }
}

/// Our own gradient backdrops (two stops at an angle).
public enum GradientPreset: String, Sendable, CaseIterable, Codable, Identifiable {
    case dusk, ocean, sunrise, mint, lavender, peach, sky, graphite

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var colors: (RGBA, RGBA) {
        switch self {
        case .dusk: (RGBA(hex: 0x4338CA), RGBA(hex: 0xDB2777))
        case .ocean: (RGBA(hex: 0x0EA5E9), RGBA(hex: 0x1E3A8A))
        case .sunrise: (RGBA(hex: 0xF59E0B), RGBA(hex: 0xEC4899))
        case .mint: (RGBA(hex: 0x34D399), RGBA(hex: 0x0D9488))
        case .lavender: (RGBA(hex: 0xC4B5FD), RGBA(hex: 0x7C3AED))
        case .peach: (RGBA(hex: 0xFED7AA), RGBA(hex: 0xFB7185))
        case .sky: (RGBA(hex: 0xBAE6FD), RGBA(hex: 0x6366F1))
        case .graphite: (RGBA(hex: 0x6B7280), RGBA(hex: 0x111827))
        }
    }
}

extension CaptureBackground {
    /// Fills `rect` (any coordinate space) with the backdrop.
    public func drawFill(in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        switch fill {
        case .solid(let color):
            context.setFillColor(color.rgba.cgColor)
            context.fill(rect)
        case .gradient(let preset):
            let (a, b) = preset.colors
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let gradient = CGGradient(colorsSpace: space, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1]) else { return }
            context.clip(to: rect)
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
}

/// Freehand strokes drawn as smooth curves through the pointer samples.
public enum Freehand {
    /// Quadratic curves through the midpoints of the samples: smooth, and it still passes
    /// through the first and last point.
    public static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }
        for i in 1..<(points.count - 1) {
            let p = points[i], next = points[i + 1]
            path.addQuadCurve(to: CGPoint(x: (p.x + next.x) / 2, y: (p.y + next.y) / 2), control: p)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// Drops samples closer than `spacing` to the previous kept one (keeps the last), so
    /// slow drags don't make jittery strokes.
    public static func thinned(_ points: [CGPoint], spacing: CGFloat = 1.5) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var kept = [points[0]]
        for p in points.dropFirst().dropLast() where hypot(p.x - kept[kept.count - 1].x, p.y - kept[kept.count - 1].y) >= spacing {
            kept.append(p)
        }
        kept.append(points[points.count - 1])
        return kept
    }
}
