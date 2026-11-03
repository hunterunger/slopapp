import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The picture an icon is made from. Vectors (SVG, PDF, file icons) are redrawn at every
/// pixel size; rasters are decoded once (sRGB, 8-bit, upright) and resampled.
public struct IconSource: @unchecked Sendable {
    public enum Content {
        case raster(CGImage)
        case vector(NSImage)
    }

    public let content: Content
    /// Base name for exported files ("logo" for logo.svg).
    public let name: String
    /// The file it came from (nil when pasted).
    public let url: URL?
    /// Natural size: pixels for rasters, points for vectors.
    public let size: CGSize
    /// What the picture's border looks like; drives the automatic background and defaults.
    public let edges: EdgeInfo
    /// The source was a file or folder whose icon we took.
    public let isFileIcon: Bool

    public init(content: Content, name: String, url: URL?, size: CGSize, isFileIcon: Bool = false) {
        self.content = content
        self.name = name
        self.url = url
        self.size = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self.isFileIcon = isFileIcon
        self.edges = EdgeInfo.analyze(content)
    }

    public var aspect: CGFloat { size.width / size.height }

    /// The visible part of the picture (unit rect, origin bottom left). Transparent
    /// margins around logos and file icons are trimmed so every shape can place the
    /// picture itself, not its padding.
    public var contentBounds: CGRect { edges.bounds }

    /// Aspect of the visible part.
    public var contentAspect: CGFloat {
        let b = contentBounds
        return (b.width * size.width) / max(b.height * size.height, 0.0001)
    }

    public var isVector: Bool {
        if case .vector = content { return true }
        return false
    }

    /// Rasters smaller than this look soft at the large icon sizes.
    public static let smallThreshold: CGFloat = 512

    public var isSmall: Bool { !isVector && max(size.width, size.height) < Self.smallThreshold }

    /// The folder new exports are offered in.
    public var folder: URL? { url?.deletingLastPathComponent() }
}

/// What a picture's border looks like.
public struct EdgeInfo: Equatable, Sendable {
    /// Some of the border is see-through (a logo on transparency).
    public var isTransparent: Bool
    /// The border's average colour, when it's opaque.
    public var color: RGBA?
    /// Any pixel at all is see-through.
    public var hasAlpha: Bool
    /// The visible part (unit rect, origin bottom left); the whole picture when opaque.
    public var bounds: CGRect

    public init(isTransparent: Bool, color: RGBA?, hasAlpha: Bool, bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
        self.isTransparent = isTransparent
        self.color = color
        self.hasAlpha = hasAlpha
        self.bounds = bounds
    }

    static let sampleSize = 128

    static func analyze(_ content: IconSource.Content) -> EdgeInfo {
        let n = sampleSize
        guard let context = Bitmap.context(pixels: n) else { return EdgeInfo(isTransparent: false, color: nil, hasAlpha: false) }
        let rect = CGRect(x: 0, y: 0, width: n, height: n)
        switch content {
        case .raster(let image):
            context.interpolationQuality = .medium
            context.draw(image, in: rect)
        case .vector(let image):
            Bitmap.drawVector(image, in: rect, context: context)
        }
        guard let data = context.data else { return EdgeInfo(isTransparent: false, color: nil, hasAlpha: false) }
        let row = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: row * n)
        return analyze(pixels: { x, y in
            let i = y * row + x * 4
            return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }, size: n)
    }

    /// Pure core of the analysis: `pixel(x, y)` returns premultiplied RGBA8.
    static func analyze(pixels pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8), size n: Int) -> EdgeInfo {
        var hasAlpha = false
        for y in 0..<n {
            for x in 0..<n where pixel(x, y).3 < 250 {
                hasAlpha = true
                break
            }
            if hasAlpha { break }
        }
        var visible = CGRect(x: 0, y: 0, width: 1, height: 1)
        if hasAlpha, let found = FolderLayout.opaqueBounds(alpha: { pixel($0, $1).3 }, width: n, height: n, threshold: 8) {
            // Widen by half a sample on each side so anti-aliased edges aren't cut.
            let pad = 0.5 / Double(n)
            visible = found.insetBy(dx: -pad, dy: -pad).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0, count = 0.0, seeThrough = 0.0
        for i in 0..<n {
            for (x, y) in [(i, 0), (i, n - 1), (0, i), (n - 1, i)] {
                let p = pixel(x, y)
                r += Double(p.0); g += Double(p.1); b += Double(p.2); a += Double(p.3)
                if p.3 < 230 { seeThrough += 1 }
                count += 1
            }
        }
        // A tenth of the border see-through counts as a transparent picture (logos with a
        // little anti-aliased edge still fill the frame; cut-outs and glyphs don't).
        let isTransparent = seeThrough / count > 0.1
        guard !isTransparent, a > 0 else {
            return EdgeInfo(isTransparent: isTransparent, color: nil, hasAlpha: hasAlpha, bounds: isTransparent ? visible : CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let color = RGBA(min(r / a, 1), min(g / a, 1), min(b / a, 1))
        return EdgeInfo(isTransparent: false, color: color, hasAlpha: hasAlpha)
    }
}

/// Icons of files, folders and apps (NSWorkspace in the app, a fake in tests).
public protocol FileIconProvider: Sendable {
    func icon(forFile url: URL) -> NSImage?
}

public struct WorkspaceIconProvider: FileIconProvider {
    public init() {}
    public func icon(forFile url: URL) -> NSImage? {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

public enum SourceError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case missing(String)
    case noImageOnClipboard

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            "Couldn’t read “\(name)”. It may be damaged or in a format Iconsmith can’t open. Try exporting it as PNG first."
        case .missing(let name):
            "“\(name)” isn’t there any more. It may have been moved or deleted."
        case .noImageOnClipboard:
            "There’s no picture on the clipboard. Copy an image or an image file, then paste again."
        }
    }
}

public enum SourceLoader {
    /// Largest raster we keep. Icons top out at 1024 px; the headroom covers zooming in.
    public static let maxRasterPixels = 2048

    /// Loads a dropped or chosen file. Images and vectors become the picture; anything
    /// else (folders, apps, documents) contributes its icon.
    public static func load(_ url: URL, icons: FileIconProvider = WorkspaceIconProvider()) throws -> IconSource {
        let url = (try? URL(resolvingAliasFileAt: url)) ?? url
        let displayName = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else { throw SourceError.missing(displayName) }
        let name = url.deletingPathExtension().lastPathComponent
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .svg) || type.conforms(to: .pdf) {
            guard let image = NSImage(contentsOf: url), image.isValid else { throw SourceError.unreadable(displayName) }
            return IconSource(content: .vector(image), name: name, url: url, size: vectorSize(image))
        }
        if let type, type.conforms(to: .image) {
            guard let image = decodeRaster(url) else { throw SourceError.unreadable(displayName) }
            return IconSource(content: .raster(image), name: name, url: url,
                              size: CGSize(width: image.width, height: image.height))
        }
        guard let icon = icons.icon(forFile: url) else { throw SourceError.unreadable(displayName) }
        return IconSource(content: .vector(icon), name: name, url: url, size: CGSize(width: 1024, height: 1024), isFileIcon: true)
    }

    /// A pasted image (no file).
    public static func load(image: NSImage, name: String = "Pasted Image") throws -> IconSource {
        guard image.isValid else { throw SourceError.noImageOnClipboard }
        if let data = image.tiffRepresentation, let raster = decodeRaster(data: data) {
            return IconSource(content: .raster(raster), name: name, url: nil,
                              size: CGSize(width: raster.width, height: raster.height))
        }
        return IconSource(content: .vector(image), name: name, url: nil, size: vectorSize(image))
    }

    static func vectorSize(_ image: NSImage) -> CGSize {
        let size = image.size
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 1024, height: 1024)
    }

    static func decodeRaster(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return decodeRaster(source)
    }

    static func decodeRaster(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decodeRaster(source)
    }

    /// The largest frame (icns and ico hold several sizes; GIFs and WebPs use the first
    /// frame either way), upright, at most `maxRasterPixels`, normalized to sRGB 8-bit.
    static func decodeRaster(_ source: CGImageSource) -> CGImage? {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var best = 0, bestPixels = 0
        let type = CGImageSourceGetType(source) as String?
        if type == UTType.icns.identifier || type == "com.microsoft.ico" {
            for index in 0..<count {
                let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let pixels = (props?[kCGImagePropertyPixelWidth] as? Int ?? 0) * (props?[kCGImagePropertyPixelHeight] as? Int ?? 0)
                if pixels > bestPixels { best = index; bestPixels = pixels }
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxRasterPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, best, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, best, nil) else { return nil }
        return Bitmap.normalized(image)
    }
}

/// RGBA8 sRGB bitmap helpers shared by loading, analysis and rendering.
public enum Bitmap {
    public static func context(pixels: Int) -> CGContext? {
        context(width: pixels, height: pixels)
    }

    public static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Redraws any image (CMYK, 16-bit, HDR, indexed) as sRGB RGBA8 so every later step
    /// sees one format.
    static func normalized(_ image: CGImage) -> CGImage? {
        if image.bitsPerComponent == 8, image.colorSpace?.name == CGColorSpace.sRGB,
           image.alphaInfo == .premultipliedLast || image.alphaInfo == .noneSkipLast {
            return image
        }
        guard let context = context(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Draws an NSImage (vector or multi-resolution) into a Core Graphics context.
    static func drawVector(_ image: NSImage, in rect: CGRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
