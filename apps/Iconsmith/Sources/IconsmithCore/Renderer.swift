import AppKit
import CoreText

/// The system icons a picture can go onto (the folder and the blank document), measured so
/// the picture lands in the right place. Drawn live, so they always match the running macOS.
public struct FolderArt: @unchecked Sendable {
    public let image: NSImage?
    public let layout: FolderLayout
    /// Average colour of the folder's front (nil when unknown).
    public let tone: RGBA?
    public let document: NSImage?
    public let documentLayout: DocumentLayout

    public init(image: NSImage?, layout: FolderLayout, tone: RGBA? = nil, document: NSImage? = nil,
                documentLayout: DocumentLayout = .standard) {
        self.image = image
        self.layout = layout
        self.tone = tone
        self.document = document
        self.documentLayout = documentLayout
    }

    public static let none = FolderArt(image: nil, layout: .standard)

    /// The running macOS's folder and document icons, measured. Call on the main thread
    /// (NSWorkspace).
    @MainActor public static func system() -> FolderArt {
        let folder = NSWorkspace.shared.icon(for: .folder)
        let document = NSWorkspace.shared.icon(for: .data)
        let measured = measure(folder)
        let page = measureBounds(document).map(DocumentLayout.init(bounds:))
        return FolderArt(image: folder, layout: measured?.layout ?? .standard, tone: measured?.tone,
                         document: document, documentLayout: page ?? .standard)
    }

    /// Opaque bounds of an icon in unit coordinates.
    static func measureBounds(_ image: NSImage) -> CGRect? {
        let n = 256
        guard let context = Bitmap.context(pixels: n) else { return nil }
        Bitmap.drawVector(image, in: CGRect(x: 0, y: 0, width: n, height: n), context: context)
        guard let data = context.data else { return nil }
        let row = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: row * n)
        guard let bounds = FolderLayout.opaqueBounds(alpha: { x, y in pixels[y * row + x * 4 + 3] }, width: n, height: n),
              bounds.width > 0.4, bounds.height > 0.4 else { return nil }
        return bounds
    }

    static func measure(_ image: NSImage) -> (layout: FolderLayout, tone: RGBA?)? {
        let n = 256
        guard let context = Bitmap.context(pixels: n) else { return nil }
        Bitmap.drawVector(image, in: CGRect(x: 0, y: 0, width: n, height: n), context: context)
        guard let data = context.data else { return nil }
        let row = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: row * n)
        // CGContext memory is top row first; rows may be padded.
        guard let bounds = FolderLayout.opaqueBounds(alpha: { x, y in pixels[y * row + x * 4 + 3] }, width: n, height: n),
              bounds.width > 0.5, bounds.height > 0.4 else { return nil }
        let layout = FolderLayout(bounds: bounds)
        // Average colour of the front, where a picture or symbol goes.
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        let area = layout.art
        let x0 = Int(area.minX * Double(n)), x1 = Int(area.maxX * Double(n))
        let y0 = Int((1 - area.maxY) * Double(n)), y1 = Int((1 - area.minY) * Double(n))
        for y in max(y0, 0)..<min(y1, n) {
            for x in max(x0, 0)..<min(x1, n) {
                let i = y * row + x * 4
                r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); a += Double(pixels[i + 3])
            }
        }
        let tone = a > 0 ? RGBA(min(r / a, 1), min(g / a, 1), min(b / a, 1)) : nil
        return (layout, tone)
    }
}

/// Which parts of the icon to draw (Android's adaptive layers draw them separately).
public struct RenderParts: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let picture = RenderParts(rawValue: 1)
    public static let text = RenderParts(rawValue: 2)
    public static let all: RenderParts = [.picture, .text]
}

/// Draws a source into an icon at any pixel size. Every size is drawn at its own pixel
/// size (vectors are redrawn, rasters resampled with high quality), so small icons stay sharp.
public struct IconRenderer: @unchecked Sendable {
    public let source: IconSource
    public let folder: FolderArt

    public init(source: IconSource, folder: FolderArt = .none) {
        self.source = source
        self.folder = folder
    }

    /// The standard folder colour when the folder icon couldn't be measured.
    static let fallbackFolderTone = RGBA(0.45, 0.72, 0.93)

    /// What goes behind the picture, after resolving Automatic. Nil means transparent.
    public func background(for style: IconStyle) -> RGBA? {
        guard style.shape.hasOutline else { return nil }
        switch style.background {
        case .none: return nil
        case .color: return style.color
        // Every shape that has an outline gets a fill, so choosing it always shows it.
        case .automatic: return source.edges.color ?? .white
        }
    }

    /// The folder's colour: the user's, or the system's own.
    public func folderTone(for style: IconStyle) -> RGBA {
        style.tintsFolder ? style.color.opaque : (folder.tone ?? Self.fallbackFolderTone)
    }

    /// The text colour, after resolving Automatic.
    public func textColor(for style: IconStyle) -> RGBA {
        if let color = style.text.color { return color }
        if style.text.position == .badge { return (style.text.badgeColor ?? IconText.defaultBadge).contrasting }
        if style.shape.isFolder { return folderTone(for: style).symbolTone }
        if style.shape == .document { return RGBA(0.22, 0.22, 0.24) }
        if let background = background(for: style) { return background.contrasting }
        return RGBA(0.12, 0.12, 0.12)
    }

    /// Whether an opaque render of this style had to fill transparency with white
    /// (iOS, watchOS and touch icons can't be transparent).
    public func opaqueNeedsFill(_ style: IconStyle) -> Bool {
        var fullBleed = style
        fullBleed.shape = .square
        guard let background = background(for: fullBleed) else { return true }
        return !background.isOpaque
    }

    /// Renders the icon. `opaque` gives a full-bleed square with no alpha channel, the
    /// way iOS and watchOS expect it (the system applies its own mask). `parts` leaves out
    /// the picture or the text (Android's separate layers).
    public func render(_ style: IconStyle, pixels: Int, opaque: Bool = false, parts: RenderParts = .all) -> CGImage? {
        var style = style.clamped()
        if opaque { style.shape = .square }
        guard let context = Bitmap.context(pixels: pixels) else { return nil }
        let p = CGFloat(pixels)
        let full = CGRect(x: 0, y: 0, width: p, height: p)
        let shape = style.shape
        context.interpolationQuality = .high
        context.setShouldAntialias(true)

        if opaque {
            context.setFillColor((background(for: style) ?? .white).opaque.cgColor)
            context.fill(full)
        }
        if shape.isFolder, let image = folder.image {
            drawFolder(image, tint: style.tintsFolder ? style.color.opaque : nil, in: full, context: context)
        }
        if shape == .document, let document = folder.document {
            Bitmap.drawVector(document, in: full, context: context)
        }

        let unit = p / 1024
        context.saveGState()
        if shape == .macOSApp {
            // Soft drop shadow, as on Apple's own icons; it follows the tile (or the
            // picture's own outline when there's no background).
            context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                              color: CGColor(gray: 0, alpha: 0.3))
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if let clip = IconGeometry.clipPath(for: shape, pixels: p, folder: folder.layout, document: folder.documentLayout) {
            context.addPath(clip)
            context.clip()
        }
        if !opaque, let background = background(for: style) {
            context.setFillColor(background.cgColor)
            context.fill(full)
        }
        if parts.contains(.picture) {
            drawPicture(style, pixels: p, context: context)
        }
        let badge = style.text.position == .badge
        if parts.contains(.text), style.text.visible != nil, !badge {
            drawText(style, pixels: p, context: context)
        }
        context.endTransparencyLayer()
        context.restoreGState()
        // A badge sits over the outline's corner, like a notification badge, so it isn't clipped.
        if parts.contains(.text), style.text.visible != nil, badge {
            drawText(style, pixels: p, context: context)
        }

        guard let image = context.makeImage() else { return nil }
        return opaque ? Self.droppingAlpha(image) : image
    }

    // MARK: Picture

    /// Where the picture is drawn (`draw`: the whole picture, so that its visible part lands
    /// on `art`), before rotation.
    func pictureRects(_ style: IconStyle, pixels p: CGFloat) -> (art: CGRect, draw: CGRect) {
        // As Is keeps the picture exactly as drawn, margins and all; every other shape
        // places the visible part.
        let trim = style.shape != .asIs && source.edges.isTransparent
        var content = IconGeometry.contentRect(for: style.shape, logo: trim, folder: folder.layout, document: folder.documentLayout)
        if style.text.visible != nil, style.text.position == .top || style.text.position == .bottom {
            // Make room for a label above or below: the picture shrinks away from it.
            let text = IconGeometry.textRect(for: style.shape, folder: folder.layout, document: folder.documentLayout)
            let shift = text.height * 0.16 * (style.text.position == .top ? -1 : 1)
            content = CGRect(x: content.midX - content.width * 0.36, y: content.midY - content.height * 0.36 + shift,
                             width: content.width * 0.72, height: content.height * 0.72)
        }
        let art = IconGeometry.artRect(aspect: trim ? source.contentAspect : source.aspect, style: style, content: content).scaled(by: p)
        return (art, trim ? Self.fullRect(placing: source.contentBounds, in: art) : art)
    }

    private func drawPicture(_ style: IconStyle, pixels p: CGFloat, context: CGContext) {
        let (art, rect) = pictureRects(style, pixels: p)
        if style.shape == .folderSymbol {
            guard let mask = pictureMask(style, art: art, rect: rect, pixels: Int(p)) else { return }
            pressInto(context, mask: mask, pixels: p, tone: folderTone(for: style).symbolTone)
            return
        }
        context.saveGState()
        Self.rotate(context, degrees: style.rotation, about: CGPoint(x: art.midX, y: art.midY))
        if style.shape == .folder || style.shape == .document {
            // A photo on a folder or page reads better with softly rounded corners.
            let radius = min(art.width, art.height) * 0.06
            context.addPath(CGPath(roundedRect: art, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        draw(into: context, rect: rect)
        context.restoreGState()
    }

    static func rotate(_ context: CGContext, degrees: Double, about center: CGPoint) {
        guard degrees != 0 else { return }
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: degrees * .pi / 180)
        context.translateBy(x: -center.x, y: -center.y)
    }

    /// The rect to draw the whole picture in so that its `bounds` part lands on `target`.
    static func fullRect(placing bounds: CGRect, in target: CGRect) -> CGRect {
        let width = target.width / max(bounds.width, 0.0001)
        let height = target.height / max(bounds.height, 0.0001)
        return CGRect(x: target.minX - bounds.minX * width, y: target.minY - bounds.minY * height, width: width, height: height)
    }

    private func draw(into context: CGContext, rect: CGRect) {
        switch source.content {
        case .raster(let image): context.draw(image, in: rect)
        case .vector(let image): Bitmap.drawVector(image, in: rect, context: context)
        }
    }

    /// A greyscale mask of the picture's ink: its opaque parts when it has a transparent
    /// background (logos), else its dark parts (a black logo on white, a photo).
    func pictureMask(_ style: IconStyle, art: CGRect, rect: CGRect, pixels n: Int) -> CGImage? {
        guard let context = Bitmap.context(pixels: n) else { return nil }
        context.interpolationQuality = .high
        Self.rotate(context, degrees: style.rotation, about: CGPoint(x: art.midX, y: art.midY))
        draw(into: context, rect: rect)
        guard let data = context.data else { return nil }
        let row = context.bytesPerRow
        let rgba = data.bindMemory(to: UInt8.self, capacity: row * n)
        let byAlpha = source.edges.isTransparent
        var gray = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let i = y * row + x * 4
                let a = Int(rgba[i + 3])
                guard a > 0 else { continue }
                if byAlpha {
                    // Near-white details inside a logo are holes in the symbol, like the
                    // cut-outs in Apple's own folder symbols.
                    let lum = (Int(rgba[i]) * 77 + Int(rgba[i + 1]) * 150 + Int(rgba[i + 2]) * 29) >> 8
                    let unpremultiplied = Double(lum) / Double(a)
                    let keep = min(max((0.97 - unpremultiplied) / 0.07, 0), 1)
                    gray[y * n + x] = UInt8(Double(a) * keep)
                } else {
                    // Premultiplied: luminance of the colour times alpha; ink = alpha - that.
                    let lum = (Int(rgba[i]) * 77 + Int(rgba[i + 1]) * 150 + Int(rgba[i + 2]) * 29) >> 8
                    gray[y * n + x] = UInt8(max(a - lum, 0))
                }
            }
        }
        return Self.grayImage(gray, width: n, height: n)
    }

    static func grayImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Fills `mask` with `tone`, with a faint light edge underneath so it looks pressed in.
    private func pressInto(_ context: CGContext, mask: CGImage, pixels p: CGFloat, tone: RGBA) {
        let full = CGRect(x: 0, y: 0, width: p, height: p)
        let edge = 2.5 * p / 1024
        if edge >= 0.5 {
            context.saveGState()
            context.clip(to: full.offsetBy(dx: 0, dy: -edge), mask: mask)
            context.setFillColor(CGColor(gray: 1, alpha: 0.4))
            context.fill(full)
            context.restoreGState()
        }
        context.saveGState()
        context.clip(to: full, mask: mask)
        context.setFillColor(tone.cgColor)
        context.fill(full)
        context.restoreGState()
    }

    // MARK: Folder

    /// Draws the folder, recoloured when there's a tint (shading kept, colour replaced).
    private func drawFolder(_ image: NSImage, tint: RGBA?, in rect: CGRect, context: CGContext) {
        guard let tint else {
            Bitmap.drawVector(image, in: rect, context: context)
            return
        }
        // The folder's own brightness, so multiplying its grey by the tint gives the tint.
        let tone = folder.tone ?? Self.fallbackFolderTone
        let level = max(0.3 * tone.red + 0.59 * tone.green + 0.11 * tone.blue, 0.2)
        // Grey × tint/level gives the tint where the folder has its usual brightness: multiply
        // for channels darker than the folder (a floor keeps shading on black), colour dodge
        // (grey / (1 − d)) for brighter ones.
        func scale(_ c: Double) -> Double { min(max(c / level, 0.18), 1) }
        func dodge(_ c: Double) -> Double { c > level ? 1 - level / c : 0 }
        let boost = RGBA(scale(tint.red), scale(tint.green), scale(tint.blue))
        let lift = RGBA(dodge(tint.red), dodge(tint.green), dodge(tint.blue))
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        Bitmap.drawVector(image, in: rect, context: context)
        context.setBlendMode(.saturation)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(rect)
        context.setBlendMode(.multiply)
        context.setFillColor(boost.cgColor)
        context.fill(rect)
        if lift.red > 0 || lift.green > 0 || lift.blue > 0 {
            context.setBlendMode(.colorDodge)
            context.setFillColor(lift.cgColor)
            context.fill(rect)
        }
        // The fills covered the transparent corners too: keep only the folder's shape.
        Bitmap.drawVector(image, in: rect, context: context, operation: .destinationIn)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: Text

    /// The font for icon text at a point size.
    static func font(_ text: IconText, size: CGFloat) -> CTFont {
        let weight: NSFont.Weight = switch text.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign = switch text.design {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
        if let descriptor = base.fontDescriptor.withDesign(design), let font = NSFont(descriptor: descriptor, size: size) {
            return font as CTFont
        }
        return base as CTFont
    }

    static func line(_ string: String, font: CTFont, color: RGBA) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// The text's area and the font size that fills it.
    func textLayout(_ style: IconStyle, pixels p: CGFloat) -> (area: CGRect, size: CGFloat, badge: CGRect?) {
        let text = style.text
        let base = IconGeometry.textRect(for: style.shape, folder: folder.layout, document: folder.documentLayout).scaled(by: p)
        var area = base
        var badge: CGRect?
        var fill: CGFloat = 0.42
        switch text.position {
        case .center: break
        case .top:
            area = CGRect(x: base.minX, y: base.maxY - base.height * 0.32, width: base.width, height: base.height * 0.32)
            fill = 0.8
        case .bottom:
            area = CGRect(x: base.minX, y: base.minY, width: base.width, height: base.height * 0.32)
            fill = 0.8
        case .badge:
            let d = min(base.width, base.height) * 0.5
            let circle = CGRect(x: min(base.maxX - d * 0.8, p - d), y: max(base.minY - d * 0.2, 0), width: d, height: d)
            badge = circle
            area = circle.insetBy(dx: d * 0.17, dy: d * 0.17)
            fill = 0.72
        }
        guard let string = text.visible else { return (area, 0, badge) }
        var size: CGFloat
        if text.autoSize {
            size = area.height * fill
        } else {
            size = (badge?.height ?? base.height) * text.size
        }
        // Never wider than its area (auto) or the icon (manual).
        let width = CTLineGetTypographicBounds(Self.line(string, font: Self.font(text, size: max(size, 1)), color: .black), nil, nil, nil)
        let limit = (text.autoSize ? area.width : (badge?.width ?? p)) * 0.94
        if width > limit, width > 0 { size *= limit / width }
        return (area, max(size, 1), badge)
    }

    private func drawText(_ style: IconStyle, pixels p: CGFloat, context: CGContext) {
        guard let string = style.text.visible else { return }
        let (area, size, badge) = textLayout(style, pixels: p)
        if let badge {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -p * 0.006), blur: p * 0.012, color: CGColor(gray: 0, alpha: 0.3))
            context.setFillColor((style.text.badgeColor ?? IconText.defaultBadge).cgColor)
            context.fillEllipse(in: badge)
            context.restoreGState()
        }
        let font = Self.font(style.text, size: size)
        let color = textColor(for: style)
        let line = Self.line(string, font: font, color: color)
        let bounds = CTLineGetImageBounds(line, context)
        let origin = CGPoint(x: area.midX - bounds.midX, y: area.midY - bounds.midY)
        context.saveGState()
        context.textMatrix = .identity
        if style.shape.isFolder && style.text.position != .badge && style.text.color == nil {
            // Pressed into the folder, like a symbol.
            let edge = 2.5 * p / 1024
            if edge >= 0.5 {
                context.textPosition = CGPoint(x: origin.x, y: origin.y - edge)
                CTLineDraw(Self.line(string, font: font, color: RGBA(1, 1, 1, 0.4)), context)
            }
        }
        context.textPosition = origin
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: Output helpers

    /// The same pixels without an alpha channel (App Store icons must not have one).
    static func droppingAlpha(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// The image laid on a solid colour, with no alpha channel (JPEG, tinted icons).
    static func flattened(_ image: CGImage, on color: RGBA) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(color.opaque.cgColor)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// Greyscale copy (luminance), alpha kept: iOS tinted icons.
    static func grayscale(_ image: CGImage) -> CGImage? {
        guard let context = Bitmap.context(width: image.width, height: image.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        context.setBlendMode(.saturation)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(rect)
        context.setBlendMode(.destinationIn)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// An NSImage holding every macOS icon size, each drawn at its own pixel size: what
    /// Finder gets when the icon is applied to a file or folder.
    public func multiResolutionImage(_ style: IconStyle) -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            guard let cg = render(style, pixels: pixels) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: 512, height: 512)
            image.addRepresentation(rep)
        }
        return image
    }
}
