import CoreGraphics
import Foundation

// The annotation model. Coordinates are image points with the origin at the top-left and y
// down (a capture's pixels divided by its scale), so a 4 pt arrow looks the same on a Retina
// capture and a 1x one. The canvas view is flipped to match.

/// A drawing color. Annotation colors are image content, not UI, so they're fixed sRGB values
/// that look the same in light and dark mode and in the saved file.
public struct RGBA: Hashable, Sendable {
    public var red, green, blue, alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red, green, blue, alpha)
    }

    /// Relative luminance (sRGB, approximate), for picking a readable label color on top.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public var isLight: Bool { luminance > 0.6 }
}

/// The palette offered in the editor.
public struct PaletteColor: Hashable, Sendable, Identifiable {
    public var name: String
    public var color: RGBA
    public var id: String { name }

    public static let all: [PaletteColor] = [
        PaletteColor(name: "Red", color: RGBA(hex: 0xFF3B30)),
        PaletteColor(name: "Orange", color: RGBA(hex: 0xFF9500)),
        PaletteColor(name: "Yellow", color: RGBA(hex: 0xFFCC00)),
        PaletteColor(name: "Green", color: RGBA(hex: 0x34C759)),
        PaletteColor(name: "Blue", color: RGBA(hex: 0x007AFF)),
        PaletteColor(name: "Purple", color: RGBA(hex: 0xAF52DE)),
        PaletteColor(name: "Black", color: RGBA(hex: 0x000000)),
        PaletteColor(name: "White", color: RGBA(hex: 0xFFFFFF)),
    ]

    public static let `default` = all[0]

    public static func named(_ name: String) -> PaletteColor? {
        all.first { $0.name == name }
    }
}

/// Line thickness for shapes, in image points. Text size and counter size follow it.
public enum StrokeWidth: Int, Sendable, CaseIterable, Identifiable {
    case thin = 2
    case medium = 4
    case thick = 8

    public var id: Int { rawValue }
    public var points: CGFloat { CGFloat(rawValue) }
    public var title: String {
        switch self {
        case .thin: "Thin"
        case .medium: "Medium"
        case .thick: "Thick"
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .thin: 16
        case .medium: 24
        case .thick: 36
        }
    }

    public init(nearest points: CGFloat) {
        self = Self.allCases.min { abs($0.points - points) < abs($1.points - points) } ?? .medium
    }
}

/// An editor tool. Letters are the single-key shortcuts.
public enum Tool: String, Sendable, CaseIterable, Identifiable {
    case select, arrow, line, rectangle, ellipse, text, highlighter, pixelate, blur, counter, crop

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .highlighter: "Highlighter"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .counter: "Counter"
        case .crop: "Crop"
        }
    }

    public var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .text: "t"
        case .highlighter: "h"
        case .pixelate: "p"
        case .blur: "b"
        case .counter: "n"
        case .crop: "c"
        }
    }

    /// SF Symbol for the toolbar (in-app UI only).
    public var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
        case .counter: "1.circle"
        case .crop: "crop"
        }
    }

    public static func forKey(_ character: Character) -> Tool? {
        allCases.first { $0.key == Character(character.lowercased()) }
    }

    /// The annotation this tool draws (nil for select and crop).
    public var kind: AnnotationKind? {
        switch self {
        case .select, .crop: nil
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .text: .text
        case .highlighter: .highlighter
        case .pixelate: .pixelate
        case .blur: .blur
        case .counter: .counter
        }
    }
}

public enum AnnotationKind: String, Sendable, CaseIterable {
    case arrow, line, rectangle, ellipse, text, highlighter, pixelate, blur, counter

    /// Drawn from a drag between two points (start and end handles).
    public var isTwoPoint: Bool { self == .arrow || self == .line }
    /// Drawn as a box (four corner handles).
    public var isBox: Bool { self == .rectangle || self == .ellipse || self == .pixelate || self == .blur }
    /// Acts on the capture's pixels (drawn under every other mark).
    public var isRedaction: Bool { self == .pixelate || self == .blur }
    /// Uses the color setting.
    public var usesColor: Bool { self != .pixelate && self != .blur }
}

/// One mark on the capture.
public struct Annotation: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: AnnotationKind
    /// Two-point and box kinds: the drag's start. Text: the top-left of the text. Counter: the center.
    public var start: CGPoint
    public var end: CGPoint
    /// Highlighter strokes.
    public var points: [CGPoint]
    public var color: RGBA
    public var width: CGFloat
    public var text: String
    /// Counters: their step number (kept in creation order by `AnnotationEditor`).
    public var number: Int

    public init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint? = nil, points: [CGPoint] = [],
                color: RGBA = PaletteColor.default.color, width: CGFloat = StrokeWidth.medium.points, text: String = "", number: Int = 0) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end ?? start
        self.points = points
        self.color = color
        self.width = width
        self.text = text
        self.number = number
    }

    /// The box spanned by start and end.
    public var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    public var fontSize: CGFloat { StrokeWidth(nearest: width).fontSize }

    public var counterRadius: CGFloat { 10 + width * 1.5 }

    public var highlighterWidth: CGFloat { max(14, width * 4) }

    /// Whether this annotation would leave no visible mark (a click without a drag).
    public var isEmpty: Bool {
        switch kind {
        case .arrow, .line: hypot(end.x - start.x, end.y - start.y) < 4
        case .rectangle, .ellipse, .pixelate, .blur: rect.width < 4 || rect.height < 4
        case .highlighter: points.count < 2
        case .text: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .counter: false
        }
    }

    // MARK: Geometry

    /// The area the annotation covers, for selection outlines and hit testing.
    /// `textSize` measures text (the renderer supplies it).
    public func bounds(textSize: (Annotation) -> CGSize = TextMetrics.size) -> CGRect {
        switch kind {
        case .arrow, .line:
            return rect.insetBy(dx: -width * 2, dy: -width * 2)
        case .rectangle, .ellipse:
            return rect.insetBy(dx: -width / 2, dy: -width / 2)
        case .pixelate, .blur:
            return rect
        case .highlighter:
            guard let first = points.first else { return .zero }
            var box = CGRect(origin: first, size: .zero)
            for point in points.dropFirst() { box = box.union(CGRect(origin: point, size: .zero)) }
            return box.insetBy(dx: -highlighterWidth / 2, dy: -highlighterWidth / 2)
        case .text:
            return CGRect(origin: start, size: textSize(self))
        case .counter:
            return CGRect(x: start.x - counterRadius, y: start.y - counterRadius, width: counterRadius * 2, height: counterRadius * 2)
        }
    }

    /// Whether `point` grabs this annotation. `loose` (the Select tool) accepts anywhere in
    /// the bounds; drawing tools only accept the visible stroke, so you can still draw a new
    /// box inside an existing one.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat, loose: Bool, textSize: (Annotation) -> CGSize = TextMetrics.size) -> Bool {
        let box = bounds(textSize: textSize)
        if loose { return box.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        switch kind {
        case .arrow, .line:
            return Self.distance(from: point, toSegment: start, end) <= width / 2 + tolerance
        case .rectangle:
            let outer = rect.insetBy(dx: -(width / 2 + tolerance), dy: -(width / 2 + tolerance))
            let inner = rect.insetBy(dx: width / 2 + tolerance, dy: width / 2 + tolerance)
            return outer.contains(point) && (inner.isNull || inner.isEmpty || !inner.contains(point))
        case .ellipse:
            let rx = rect.width / 2, ry = rect.height / 2
            guard rx > 0, ry > 0 else { return false }
            let nx = (point.x - rect.midX) / rx, ny = (point.y - rect.midY) / ry
            let r = (nx * nx + ny * ny).squareRoot()
            let slack = (width / 2 + tolerance) / min(rx, ry)
            return abs(r - 1) <= slack
        case .highlighter:
            guard points.count > 1 else { return false }
            return zip(points, points.dropFirst()).contains {
                Self.distance(from: point, toSegment: $0, $1) <= highlighterWidth / 2 + tolerance
            }
        case .pixelate, .blur, .text, .counter:
            return box.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    /// The drag handles: start and end for lines, four corners for boxes, none otherwise.
    public var handles: [Handle] {
        if kind.isTwoPoint { return [.start, .end] }
        if kind.isBox { return [.topLeft, .topRight, .bottomLeft, .bottomRight] }
        return []
    }

    public enum Handle: Sendable, CaseIterable {
        case start, end, topLeft, topRight, bottomLeft, bottomRight
    }

    public func position(of handle: Handle) -> CGPoint {
        let r = rect
        switch handle {
        case .start: return start
        case .end: return end
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    /// The annotation with `handle` dragged to `point`.
    public func moving(_ handle: Handle, to point: CGPoint) -> Annotation {
        var copy = self
        switch handle {
        case .start: copy.start = point
        case .end: copy.end = point
        default:
            let r = rect
            var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
            switch handle {
            case .topLeft: minX = point.x; minY = point.y
            case .topRight: maxX = point.x; minY = point.y
            case .bottomLeft: minX = point.x; maxY = point.y
            case .bottomRight: maxX = point.x; maxY = point.y
            default: break
            }
            copy.start = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
            copy.end = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
        }
        return copy
    }

    /// The annotation shifted by `delta`.
    public func moved(by delta: CGVector) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        copy.end = CGPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        copy.points = points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
        return copy
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// A text annotation moved so its box stays inside `bounds` (the image), so text typed
    /// near an edge doesn't run off and get cut. Other kinds are returned unchanged.
    public func keptInside(_ bounds: CGRect, textSize: (Annotation) -> CGSize = TextMetrics.size) -> Annotation {
        guard kind == .text else { return self }
        let size = textSize(self)
        var copy = self
        copy.start.x = max(bounds.minX, min(start.x, bounds.maxX - size.width))
        copy.start.y = max(bounds.minY, min(start.y, bounds.maxY - size.height))
        copy.end = copy.start
        return copy
    }

    /// For Shift while drawing: snaps `end` so the line from `start` is horizontal, vertical
    /// or at 45°; for boxes, makes them square.
    public static func constrained(start: CGPoint, end: CGPoint, kind: AnnotationKind) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        if kind.isBox || kind == .highlighter {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        let angle = atan2(dy, dx)
        let snappedAngle = (angle / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + cos(snappedAngle) * length, y: start.y + sin(snappedAngle) * length)
    }
}
