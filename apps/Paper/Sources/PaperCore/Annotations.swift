import AppKit
import PDFKit

public enum MarkupStyle: String, CaseIterable, Codable, Sendable {
    case highlight, underline, strikeOut

    public var title: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeOut: "Strikethrough"
        }
    }

    var subtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        }
    }
}

public enum ShapeKind: String, CaseIterable, Codable, Sendable {
    case rectangle, oval, line, arrow

    public var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .oval: "Oval"
        case .line: "Line"
        case .arrow: "Arrow"
        }
    }
}

/// Colors for page content. These are written into the PDF, so they're fixed sRGB values
/// (a document must look the same in every viewer), unlike the app's chrome.
public enum InkColor: String, CaseIterable, Codable, Sendable {
    case yellow, green, blue, pink, purple, red, black

    public var title: String { rawValue.capitalized }

    public var nsColor: NSColor {
        switch self {
        case .yellow: NSColor(srgbRed: 1.00, green: 0.88, blue: 0.20, alpha: 1)
        case .green: NSColor(srgbRed: 0.55, green: 0.90, blue: 0.40, alpha: 1)
        case .blue: NSColor(srgbRed: 0.45, green: 0.75, blue: 1.00, alpha: 1)
        case .pink: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.75, alpha: 1)
        case .purple: NSColor(srgbRed: 0.75, green: 0.60, blue: 1.00, alpha: 1)
        case .red: NSColor(srgbRed: 0.90, green: 0.15, blue: 0.15, alpha: 1)
        case .black: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        }
    }

    /// The five highlighter colors offered for text markup.
    public static let highlighters: [InkColor] = [.yellow, .green, .blue, .pink, .purple]

    /// The closest named color, so the style bar can show what's selected.
    public static func nearest(to color: NSColor?) -> InkColor? {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return nil }
        return allCases.min { distance($0.nsColor, rgb) < distance($1.nsColor, rgb) }
            .flatMap { distance($0.nsColor, rgb) < 0.05 ? $0 : nil }
    }

    static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return 9 }
        return pow(a.redComponent - b.redComponent, 2) + pow(a.greenComponent - b.greenComponent, 2) + pow(a.blueComponent - b.blueComponent, 2)
    }
}

/// Builds annotations the way Paper makes them. Every annotation carries the author name
/// and a modification date so other apps attribute it.
public struct AnnotationFactory {
    public var author: String?
    public var now: () -> Date

    public init(author: String?, now: @escaping () -> Date = Date.init) {
        self.author = author
        self.now = now
    }

    func stamp(_ annotation: PDFAnnotation) -> PDFAnnotation {
        if let author, !author.isEmpty { annotation.userName = author }
        annotation.modificationDate = now()
        return annotation
    }

    /// One markup annotation covering several lines (one quad per line).
    public func markup(_ style: MarkupStyle, color: NSColor, lineRects: [CGRect]) -> PDFAnnotation? {
        let rects = lineRects.filter { $0.width > 0 && $0.height > 0 }
        guard let first = rects.first else { return nil }
        let bounds = rects.dropFirst().reduce(first) { $0.union($1) }
        let annotation = PDFAnnotation(bounds: bounds, forType: style.subtype, withProperties: nil)
        annotation.color = color
        annotation.quadrilateralPoints = rects.flatMap { rect -> [NSValue] in
            let r = rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
                    CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)].map { NSValue(point: $0) }
        }
        return stamp(annotation)
    }

    public func shape(_ kind: ShapeKind, from start: CGPoint, to end: CGPoint, color: NSColor,
                      fill: NSColor?, lineWidth: CGFloat) -> PDFAnnotation {
        let border = PDFBorder()
        border.lineWidth = lineWidth
        switch kind {
        case .rectangle, .oval:
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: max(abs(end.x - start.x), 2), height: max(abs(end.y - start.y), 2))
            let annotation = PDFAnnotation(bounds: rect, forType: kind == .rectangle ? .square : .circle, withProperties: nil)
            annotation.color = color
            annotation.interiorColor = fill
            annotation.border = border
            return stamp(annotation)
        case .line, .arrow:
            let pad = max(lineWidth * 4, 8)
            let bounds = CGRect(x: min(start.x, end.x) - pad, y: min(start.y, end.y) - pad,
                                width: abs(end.x - start.x) + pad * 2, height: abs(end.y - start.y) + pad * 2)
            let annotation = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            annotation.startPoint = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
            annotation.endPoint = CGPoint(x: end.x - bounds.minX, y: end.y - bounds.minY)
            annotation.endLineStyle = kind == .arrow ? .openArrow : .none
            annotation.color = color
            annotation.border = border
            return stamp(annotation)
        }
    }

    /// A text box whose top-left corner is at `topLeft`.
    public func textBox(_ text: String, topLeft: CGPoint, fontSize: CGFloat, color: NSColor) -> PDFAnnotation {
        let font = NSFont.systemFont(ofSize: fontSize)
        let size = TextBoxLayout.size(for: text, font: font)
        let bounds = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = font
        annotation.fontColor = color
        annotation.color = .clear
        annotation.alignment = .left
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        return stamp(annotation)
    }

    public func note(_ text: String, at point: CGPoint) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20),
                                       forType: .text, withProperties: nil)
        annotation.contents = text
        annotation.iconType = .comment
        annotation.color = InkColor.yellow.nsColor
        return stamp(annotation)
    }

    /// Freehand strokes (page space) as one ink annotation.
    public func ink(_ strokes: [[CGPoint]], color: NSColor, lineWidth: CGFloat) -> PDFAnnotation? {
        let points = strokes.flatMap { $0 }
        guard let firstPoint = points.first else { return nil }
        var box = CGRect(origin: firstPoint, size: .zero)
        for point in points { box = box.union(CGRect(origin: point, size: .zero)) }
        let bounds = box.insetBy(dx: -lineWidth * 2 - 1, dy: -lineWidth * 2 - 1)
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        for stroke in strokes where !stroke.isEmpty {
            let local = stroke.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
            annotation.add(InkSmoothing.path(through: local, lineWidth: lineWidth))
        }
        annotation.color = color
        let border = PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border
        return stamp(annotation)
    }
}

public enum TextBoxLayout {
    /// The box a text box needs: its text plus a small inset, at least one empty line tall.
    public static func size(for text: String, font: NSFont) -> CGSize {
        let measured = (text.isEmpty ? "M" : text as NSString).boundingRect(
            with: CGSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let width = max(ceil(measured.width) + 10, 40)
        let height = max(ceil(measured.height), lineHeight) + 6
        return CGSize(width: width, height: height)
    }
}

/// Smooth strokes: quadratic curves through the midpoints of the sampled points.
public enum InkSmoothing {
    public static func path(through points: [CGPoint], lineWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.line(to: CGPoint(x: first.x + 0.1, y: first.y))
            return path
        }
        if points.count == 2 {
            path.line(to: points[1])
            return path
        }
        for index in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[index].x + points[index + 1].x) / 2, y: (points[index].y + points[index + 1].y) / 2)
            path.curve(to: mid, controlPoint1: points[index], controlPoint2: points[index])
        }
        path.line(to: points[points.count - 1])
        return path
    }
}

/// Moving and resizing annotations of every kind Paper edits.
public enum AnnotationGeometry {
    public static func isMarkup(_ annotation: PDFAnnotation) -> Bool {
        ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(annotation.type ?? "")
    }

    public static func isWidget(_ annotation: PDFAnnotation) -> Bool { annotation.type == "Widget" }
    public static func isLink(_ annotation: PDFAnnotation) -> Bool { annotation.type == "Link" }

    /// Whether Paper lets the person select this annotation and move it.
    public static func isEditable(_ annotation: PDFAnnotation) -> Bool {
        !isWidget(annotation) && !isLink(annotation) && annotation.type != "Popup"
    }

    /// Text markup follows the text, so it can be selected and recolored but not resized.
    public static func isResizable(_ annotation: PDFAnnotation) -> Bool {
        isEditable(annotation) && !isMarkup(annotation) && annotation.type != "Text"
    }

    public static func move(_ annotation: PDFAnnotation, by delta: CGVector) {
        annotation.bounds = annotation.bounds.offsetBy(dx: delta.dx, dy: delta.dy)
    }

    /// Drops a saved appearance stream so PDFKit draws the annotation from its current
    /// properties. Annotations loaded from a file keep their old `/AP` otherwise, and a
    /// resized or recolored box would still draw at its old size or color.
    public static func invalidateAppearance(_ annotation: PDFAnnotation) {
        guard !isWidget(annotation) else { return }
        annotation.removeValue(forAnnotationKey: .appearanceDictionary)
    }

    /// Resizes to `newBounds`, scaling ink strokes and line ends to match.
    public static func resize(_ annotation: PDFAnnotation, to newBounds: CGRect) {
        invalidateAppearance(annotation)
        let old = annotation.bounds
        let target = newBounds.standardized
        guard old.width > 0, old.height > 0, target.width >= 1, target.height >= 1 else { return }
        let sx = target.width / old.width, sy = target.height / old.height
        switch annotation.type ?? "" {
        case "Ink":
            let paths = annotation.paths ?? []
            // Image signatures are bands of horizontal strokes: their thickness has to follow
            // the height, or resizing opens gaps between the bands.
            let bands = isBanded(paths)
            for path in paths { annotation.remove(path) }
            annotation.bounds = target
            for path in paths {
                let scaled = path.copy() as! NSBezierPath
                scaled.transform(using: AffineTransform(scaleByX: sx, byY: sy))
                if bands { scaled.lineWidth = path.lineWidth * sy }
                annotation.add(scaled)
            }
            if bands, let border = annotation.border { border.lineWidth *= sy }
        case "Line":
            let start = annotation.startPoint, end = annotation.endPoint
            annotation.bounds = target
            annotation.startPoint = CGPoint(x: start.x * sx, y: start.y * sy)
            annotation.endPoint = CGPoint(x: end.x * sx, y: end.y * sy)
        default:
            annotation.bounds = target
        }
    }

    /// Ink made of many straight horizontal strokes (an imported image signature).
    static func isBanded(_ paths: [NSBezierPath]) -> Bool {
        guard paths.count >= 8 else { return false }
        return paths.allSatisfy { path in
            guard path.elementCount == 2 else { return false }
            var a = [CGPoint](repeating: .zero, count: 3), b = [CGPoint](repeating: .zero, count: 3)
            path.element(at: 0, associatedPoints: &a)
            path.element(at: 1, associatedPoints: &b)
            return abs(a[0].y - b[0].y) < 0.001
        }
    }

    /// The rect from dragging the corner `handle` of `bounds` to `point`.
    /// Handles: 0 bottom-left, 1 bottom-right, 2 top-left, 3 top-right (page space, y up).
    public static func dragging(handle: Int, of bounds: CGRect, to point: CGPoint, keepAspect: Bool, minSize: CGFloat = 4) -> CGRect {
        let anchor: CGPoint
        switch handle {
        case 0: anchor = CGPoint(x: bounds.maxX, y: bounds.maxY)
        case 1: anchor = CGPoint(x: bounds.minX, y: bounds.maxY)
        case 2: anchor = CGPoint(x: bounds.maxX, y: bounds.minY)
        default: anchor = CGPoint(x: bounds.minX, y: bounds.minY)
        }
        var width = max(abs(point.x - anchor.x), minSize)
        var height = max(abs(point.y - anchor.y), minSize)
        if keepAspect, bounds.width > 0, bounds.height > 0 {
            let aspect = bounds.width / bounds.height
            if width / height > aspect { height = width / aspect } else { width = height * aspect }
        }
        let goesLeft = handle == 0 || handle == 2
        let goesDown = handle == 0 || handle == 1
        return CGRect(x: goesLeft ? anchor.x - width : anchor.x,
                      y: goesDown ? anchor.y - height : anchor.y,
                      width: width, height: height)
    }

    /// Shift-constrain a drag: squares/circles for boxes, 45° steps for lines.
    public static func constrained(from start: CGPoint, to end: CGPoint, kind: ShapeKind) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        switch kind {
        case .rectangle, .oval:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        case .line, .arrow:
            let length = hypot(dx, dy)
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
    }
}
