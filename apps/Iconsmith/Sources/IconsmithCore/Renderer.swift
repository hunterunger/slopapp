import AppKit

/// The system folder icon and where a picture goes on it.
public struct FolderArt: @unchecked Sendable {
    public let image: NSImage?
    public let layout: FolderLayout

    public init(image: NSImage?, layout: FolderLayout) {
        self.image = image
        self.layout = layout
    }

    public static let none = FolderArt(image: nil, layout: .standard)

    /// The running macOS's folder icon, measured so the picture lands on its front panel.
    /// Call on the main thread (NSWorkspace).
    @MainActor public static func system() -> FolderArt {
        let image = NSWorkspace.shared.icon(for: .folder)
        return FolderArt(image: image, layout: measure(image) ?? .standard)
    }

    static func measure(_ image: NSImage) -> FolderLayout? {
        let n = 256
        guard let context = Bitmap.context(pixels: n) else { return nil }
        Bitmap.drawVector(image, in: CGRect(x: 0, y: 0, width: n, height: n), context: context)
        guard let data = context.data else { return nil }
        let row = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: row * n)
        // CGContext memory is top row first; rows may be padded.
        guard let bounds = FolderLayout.opaqueBounds(alpha: { x, y in pixels[y * row + x * 4 + 3] }, width: n, height: n),
              bounds.width > 0.5, bounds.height > 0.4 else { return nil }
        return FolderLayout(bounds: bounds)
    }
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

    /// What goes behind the picture, after resolving Automatic. Nil means transparent.
    public func background(for style: IconStyle) -> RGBA? {
        guard style.shape.usesBackground else { return nil }
        switch style.background {
        case .none: return nil
        case .color: return style.color
        // Every shape that has an outline gets a fill, so choosing it always shows it.
        case .automatic: return source.edges.color ?? .white
        }
    }

    /// Whether an opaque render of this style had to fill transparency with white
    /// (iOS, watchOS and touch icons can't be transparent).
    public func opaqueNeedsFill(_ style: IconStyle) -> Bool {
        let fullBleed = IconStyle(shape: .square, scale: style.scale, offset: style.offset, fill: style.fill,
                                  background: style.background, color: style.color)
        guard let background = background(for: fullBleed) else { return true }
        return !background.isOpaque
    }

    /// Renders the icon. `opaque` gives a full-bleed square with no alpha channel, the
    /// way iOS and watchOS expect it (the system applies its own mask).
    public func render(_ style: IconStyle, pixels: Int, opaque: Bool = false) -> CGImage? {
        var style = style.clamped()
        if opaque { style.shape = .square }
        guard let context = Bitmap.context(pixels: pixels) else { return nil }
        let p = CGFloat(pixels)
        context.interpolationQuality = .high
        context.setShouldAntialias(true)

        if opaque {
            context.setFillColor((background(for: style) ?? .white).opaque.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: p, height: p))
        }
        if style.shape == .folder, let image = folder.image {
            Bitmap.drawVector(image, in: CGRect(x: 0, y: 0, width: p, height: p), context: context)
        }

        let unit = p / 1024
        if style.shape == .macOSApp {
            // Soft drop shadow, as on Apple's own icons; it follows the tile (or the
            // picture's own outline when there's no background).
            context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                              color: CGColor(gray: 0, alpha: 0.3))
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if let clip = IconGeometry.clipPath(for: style.shape, pixels: p, folder: folder.layout) {
            context.addPath(clip)
            context.clip()
        }
        if !opaque, let background = background(for: style) {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: p, height: p))
        }
        // As Is keeps the picture exactly as drawn, margins and all; every other shape
        // places the visible part.
        let trim = style.shape != .asIs && source.edges.isTransparent
        let content = IconGeometry.contentRect(for: style.shape, logo: trim, folder: folder.layout)
        let art = IconGeometry.artRect(aspect: trim ? source.contentAspect : source.aspect, style: style, content: content).scaled(by: p)
        if style.shape == .folder {
            // A photo on a folder reads better with softly rounded corners.
            let radius = min(art.width, art.height) * 0.06
            context.addPath(CGPath(roundedRect: art, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        draw(into: context, rect: trim ? Self.fullRect(placing: source.contentBounds, in: art) : art)
        context.endTransparencyLayer()

        guard let image = context.makeImage() else { return nil }
        return opaque ? Self.droppingAlpha(image) : image
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

    /// The same pixels without an alpha channel (App Store icons must not have one).
    static func droppingAlpha(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
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
