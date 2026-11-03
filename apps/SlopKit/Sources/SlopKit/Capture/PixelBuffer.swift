import CoreGraphics

/// An image decoded to 8-bit RGBA (sRGB, premultiplied), for reading pixels directly:
/// edge detection in Ruler, color picking in Dropper, leak checks in tests.
///
///     guard let pixels = frozen.pixels() else { return }
///     let left = pixels.rgba(x: 10, y: 20)
///     let edge = pixels.luminance(x: 11, y: 20) - pixels.luminance(x: 10, y: 20)
public final class PixelBuffer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    /// Row-major RGBA bytes, top row first, `width * 4` bytes per row.
    public let bytes: [UInt8]

    public init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        bytes = data
    }

    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// The pixel at (x, y) from the top-left. Out-of-range reads return clear black.
    public func rgba(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard contains(x: x, y: y) else { return (0, 0, 0, 0) }
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// Relative luminance 0...1 (Rec. 709 weights on the stored sRGB values).
    public func luminance(x: Int, y: Int) -> Double {
        let p = rgba(x: x, y: y)
        return (0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255
    }

    /// How many pixels outside `keep` (pixel rects, top-left origin) are not fully clear.
    /// Tests use it to prove a test-mode capture contains nothing but the test scene.
    public func visiblePixels(outside keep: [CGRect]) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard bytes[i] != 0 || bytes[i + 1] != 0 || bytes[i + 2] != 0 || bytes[i + 3] != 0 else { continue }
                let center = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                if !keep.contains(where: { $0.contains(center) }) { count += 1 }
            }
        }
        return count
    }
}
