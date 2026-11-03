import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Text measurement for text annotations (bold system font at the annotation's size).
public enum TextMetrics {
    static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func lines(of text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        return lines.isEmpty ? [""] : lines
    }

    static func attributed(_ line: String, font: CTFont, color: CGColor) -> CFAttributedString {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        return CFAttributedStringCreate(nil, line as CFString, attributes as CFDictionary)
    }

    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        return (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
    }

    /// The size a text annotation takes up, in image points.
    @Sendable public static func size(_ annotation: Annotation) -> CGSize {
        size(of: annotation.text, fontSize: annotation.fontSize)
    }

    public static func size(of text: String, fontSize: CGFloat) -> CGSize {
        let font = font(size: fontSize)
        let lines = lines(of: text)
        var width: CGFloat = 0
        for line in lines {
            let ctLine = CTLineCreateWithAttributedString(attributed(line, font: font, color: CGColor(gray: 0, alpha: 1)))
            width = max(width, CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)))
        }
        return CGSize(width: max(width.rounded(.up), fontSize / 2), height: lineHeight(fontSize: fontSize) * CGFloat(lines.count))
    }
}

/// Draws a capture with its annotations: on screen (the canvas) and for export.
///
/// Drawing happens in image points with y down: callers set the context's transform so one
/// unit is one image point and the origin is the image's top-left.
public final class AnnotationRenderer {
    public let base: CGImage
    /// Pixels per image point (2 for Retina captures).
    public let scale: CGFloat
    private var redactionCache: [String: CGImage] = [:]
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = max(scale, 0.1)
    }

    public var imageSize: CGSize {
        CGSize(width: CGFloat(base.width) / scale, height: CGFloat(base.height) / scale)
    }

    // MARK: Export

    /// The finished image at full resolution: annotations burned in, cropped.
    public func render(_ document: AnnotationDocument) -> CGImage? {
        let visible = document.visibleRect
        let width = Int((visible.width * scale).rounded()), height = Int((visible.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        let space = base.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        context.interpolationQuality = .high
        draw(document, in: context)
        return context.makeImage()
    }

    // MARK: Drawing

    /// Draws the capture and every annotation (except `skipping`, e.g. text being edited).
    ///
    /// Blur and pixelate act on the capture itself, so they're drawn first, right on the
    /// image; every other mark sits on top whatever order it was added in. (A redaction
    /// drawn later would otherwise wipe out arrows and text underneath it.)
    public func draw(_ document: AnnotationDocument, in context: CGContext, skipping: UUID? = nil) {
        drawImage(base, in: CGRect(origin: .zero, size: imageSize), context: context)
        let visible = document.annotations.filter { $0.id != skipping }
        for annotation in visible where annotation.kind.isRedaction { draw(annotation, in: context) }
        for annotation in visible where !annotation.kind.isRedaction { draw(annotation, in: context) }
    }

    public func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let color = annotation.color.cgColor
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.kind {
        case .pixelate, .blur:
            drawRedaction(annotation, in: context)
        case .highlighter:
            guard annotation.points.count > 1 else { return }
            context.setBlendMode(.multiply)
            context.setStrokeColor(annotation.color.withAlpha(0.45).cgColor)
            context.setLineWidth(annotation.highlighterWidth)
            context.addLines(between: annotation.points)
            context.strokePath()
        case .line:
            applyShadow(context)
            context.setStrokeColor(color)
            context.setLineWidth(annotation.width)
            context.addLines(between: [annotation.start, annotation.end])
            context.strokePath()
        case .arrow:
            applyShadow(context)
            drawArrow(annotation, color: color, in: context)
        case .rectangle:
            applyShadow(context)
            context.setStrokeColor(color)
            context.setLineWidth(annotation.width)
            let radius = min(annotation.width, annotation.rect.width / 2, annotation.rect.height / 2)
            context.addPath(CGPath(roundedRect: annotation.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
        case .ellipse:
            applyShadow(context)
            context.setStrokeColor(color)
            context.setLineWidth(annotation.width)
            context.strokeEllipse(in: annotation.rect)
        case .text:
            applyShadow(context)
            drawText(annotation.text, at: annotation.start, fontSize: annotation.fontSize, color: color, in: context)
        case .counter:
            applyShadow(context)
            let r = annotation.counterRadius
            let circle = CGRect(x: annotation.start.x - r, y: annotation.start.y - r, width: r * 2, height: r * 2)
            context.setFillColor(color)
            context.fillEllipse(in: circle)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            let label = "\(annotation.number)"
            let fontSize = r * 1.1
            let size = TextMetrics.size(of: label, fontSize: fontSize)
            let textColor = annotation.color.isLight ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
            drawText(label, at: CGPoint(x: annotation.start.x - size.width / 2, y: annotation.start.y - size.height / 2),
                     fontSize: fontSize, color: textColor, in: context)
        }
    }

    private func applyShadow(_ context: CGContext) {
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: CGColor(gray: 0, alpha: 0.35))
    }

    private func drawArrow(_ a: Annotation, color: CGColor, in context: CGContext) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let ux = dx / length, uy = dy / length
        let headLength = min(max(12, a.width * 3.5), length)
        let headHalfWidth = headLength * 0.5
        let base = CGPoint(x: a.end.x - ux * headLength, y: a.end.y - uy * headLength)
        // Shaft stops inside the head so the round cap doesn't poke through the tip.
        let shaftEnd = CGPoint(x: a.end.x - ux * headLength * 0.6, y: a.end.y - uy * headLength * 0.6)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(a.width)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addLines(between: [a.start, shaftEnd])
        context.strokePath()
        context.move(to: a.end)
        context.addLine(to: CGPoint(x: base.x - uy * headHalfWidth, y: base.y + ux * headHalfWidth))
        context.addLine(to: CGPoint(x: base.x + uy * headHalfWidth, y: base.y - ux * headHalfWidth))
        context.closePath()
        context.fillPath()
        context.endTransparencyLayer()
    }

    /// Draws text with its top-left at `origin` in a y-down context.
    public func drawText(_ text: String, at origin: CGPoint, fontSize: CGFloat, color: CGColor, in context: CGContext) {
        let font = TextMetrics.font(size: fontSize)
        let lineHeight = TextMetrics.lineHeight(fontSize: fontSize)
        let ascent = CTFontGetAscent(font)
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in TextMetrics.lines(of: text).enumerated() {
            let ctLine = CTLineCreateWithAttributedString(TextMetrics.attributed(line, font: font, color: color))
            context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent + lineHeight * CGFloat(index))
            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
    }

    /// Draws `image` upright into `rect` of a y-down context.
    public func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    // MARK: Redaction

    /// Pixelate or blur the capture under the box. Reads the original capture, so stacking
    /// annotations never leaks through.
    private func drawRedaction(_ a: Annotation, in context: CGContext) {
        let rect = a.rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1, let patch = redactedPatch(kind: a.kind, rect: rect) else { return }
        drawImage(patch, in: rect, context: context)
    }

    /// Pixelate block size in image points: at least 10, a fifth of the box's short side.
    public static func pixelBlock(for rect: CGRect) -> CGFloat {
        max(10, (min(rect.width, rect.height) / 5).rounded())
    }

    /// The redacted pixels for `rect` (image points), cached by kind and rect.
    public func redactedPatch(kind: AnnotationKind, rect: CGRect) -> CGImage? {
        let pixels = CGRect(x: (rect.minX * scale).rounded(), y: (rect.minY * scale).rounded(),
                            width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        let key = "\(kind.rawValue):\(Int(pixels.minX)),\(Int(pixels.minY)),\(Int(pixels.width)),\(Int(pixels.height))"
        if let cached = redactionCache[key] { return cached }
        guard pixels.width >= 1, pixels.height >= 1, let source = base.cropping(to: pixels) else { return nil }
        let input = CIImage(cgImage: source)
        let extent = input.extent
        let output: CIImage?
        switch kind {
        case .pixelate:
            let filter = CIFilter(name: "CIPixellate")
            filter?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            // Blocks grow with the box so big text can't be read back either.
            filter?.setValue(Self.pixelBlock(for: rect) * scale, forKey: kCIInputScaleKey)
            filter?.setValue(CIVector(x: extent.minX, y: extent.minY), forKey: kCIInputCenterKey)
            output = filter?.outputImage?.cropped(to: extent)
        case .blur:
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(12 * scale, forKey: kCIInputRadiusKey)
            output = filter?.outputImage?.cropped(to: extent)
        default:
            output = nil
        }
        guard let output, let image = Self.ciContext.createCGImage(output, from: extent) else { return nil }
        if redactionCache.count > 64 { redactionCache.removeAll() }
        redactionCache[key] = image
        return image
    }
}
