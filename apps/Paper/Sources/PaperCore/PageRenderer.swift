import AppKit
import PDFKit

/// Renders pages and regions of pages to bitmaps. Used by the redaction verifier, the
/// rasterize fallback, image export and thumbnails.
public enum PageRenderer {
    /// Renders `region` (page space, unrotated) at `scale` pixels per point.
    /// Draws on white. Rotation is ignored so page space maps straight onto the bitmap.
    public static func render(_ page: PDFPage, region: CGRect, scale: CGFloat,
                              annotations: Bool = true, fill: CGColor? = CGColor(gray: 1, alpha: 1)) -> CGImage? {
        let media = page.bounds(for: .mediaBox)
        let width = max(1, Int((region.width * scale).rounded(.up)))
        let height = max(1, Int((region.height * scale).rounded(.up)))
        guard width <= 20_000, height <= 20_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if let fill {
            context.setFillColor(fill)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.scaleBy(x: scale, y: scale)
        // draw(with: .mediaBox) puts the media box origin at (0, 0); move the region there.
        context.translateBy(x: media.minX - region.minX, y: media.minY - region.minY)
        let rotation = page.rotation
        let showedAnnotations = page.displaysAnnotations
        page.rotation = 0
        page.displaysAnnotations = annotations
        page.draw(with: .mediaBox, to: context)
        page.rotation = rotation
        page.displaysAnnotations = showedAnnotations
        return context.makeImage()
    }

    /// Whether every pixel in `image` is (nearly) the same color. A redacted region must be.
    public static func isUniform(_ image: CGImage, tolerance: Int = 24) -> Bool {
        guard let pixels = rgba(image) else { return false }
        var low = [255, 255, 255], high = [0, 0, 0]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                let value = Int(pixels[index + channel])
                low[channel] = min(low[channel], value)
                high[channel] = max(high[channel], value)
            }
        }
        return (0..<3).allSatisfy { high[$0] - low[$0] <= tolerance }
    }

    /// The share of pixels that had content before (darker than page white) and look the
    /// same after (every channel within `tolerance`).
    public static func survivingFraction(before: CGImage, after: CGImage, tolerance: Int = 12) -> Double {
        guard before.width == after.width, before.height == after.height,
              let a = rgba(before), let b = rgba(after), !a.isEmpty else { return 1 }
        var surviving = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            let isBackground = a[index] > 240 && a[index + 1] > 240 && a[index + 2] > 240
            guard !isBackground else { continue }
            if abs(Int(a[index]) - Int(b[index])) <= tolerance,
               abs(Int(a[index + 1]) - Int(b[index + 1])) <= tolerance,
               abs(Int(a[index + 2]) - Int(b[index + 2])) <= tolerance {
                surviving += 1
            }
        }
        return Double(surviving) / Double(a.count / 4)
    }

    /// Average brightness 0...1, for tests and checks ("is this box black?").
    public static func meanLuminance(_ image: CGImage) -> Double {
        guard let pixels = rgba(image), !pixels.isEmpty else { return 1 }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return total / Double(pixels.count / 4) / 255
    }

    static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// A copy of `page` as a single image (no text left), with `blackRects` painted over.
    /// Keeps the media box, crop box and rotation. The redaction fallback (research P6).
    public static func rasterizedPage(from page: PDFPage, blackRects: [CGRect], dpi: CGFloat = 300) -> PDFPage? {
        let media = page.bounds(for: .mediaBox)
        // Cap huge pages so a 200-inch poster doesn't allocate gigabytes.
        let scale = min(dpi / 72, 12_000 / max(media.width, media.height, 1))
        guard let image = render(page, region: media, scale: scale) else { return nil }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for rect in blackRects {
            let local = rect.offsetBy(dx: -media.minX, dy: -media.minY)
            context.fill(CGRect(x: local.minX * scale, y: local.minY * scale,
                                width: local.width * scale, height: local.height * scale))
        }
        guard let painted = context.makeImage() else { return nil }
        let nsImage = NSImage(cgImage: painted, size: media.size)
        guard let newPage = PDFPage(image: nsImage, options: [.mediaBox: media]) else { return nil }
        newPage.setBounds(page.bounds(for: .cropBox), for: .cropBox)
        newPage.rotation = page.rotation
        return newPage
    }
}
