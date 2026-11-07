import CoreGraphics

/// Sizing and opacity rules for pinned captures.
public enum PinGeometry {
    public static let minimumOpacity: Double = 0.1
    public static let minimumSide: CGFloat = 48
    public static let zoomStep: CGFloat = 1.25

    /// Opacity for a digit key: 1 = 10% … 9 = 90%, 0 = 100%.
    public static func opacity(forDigit digit: Int) -> Double? {
        guard (0...9).contains(digit) else { return nil }
        return digit == 0 ? 1 : Double(digit) / 10
    }

    public static func clampedOpacity(_ value: Double) -> Double {
        min(1, max(minimumOpacity, value))
    }

    /// The pin's first size: the capture's size in points, shrunk to fit `visible` (with a
    /// margin) and kept proportional.
    public static func initialSize(imagePoints: CGSize, visible: CGSize, margin: CGFloat = 40) -> CGSize {
        fit(imagePoints, into: CGSize(width: visible.width - margin * 2, height: visible.height - margin * 2))
    }

    /// `size` scaled by `factor`, proportional, at least `minimumSide` on the short side and
    /// no bigger than `limit`.
    public static func zoomed(_ size: CGSize, by factor: CGFloat, limit: CGSize) -> CGSize {
        var target = CGSize(width: size.width * factor, height: size.height * factor)
        let shortSide = min(target.width, target.height)
        if shortSide < minimumSide, shortSide > 0 {
            let grow = minimumSide / shortSide
            target = CGSize(width: target.width * grow, height: target.height * grow)
        }
        return fit(target, into: limit)
    }

    /// Scales `size` down (never up) to fit `box`, keeping its aspect ratio.
    public static func fit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return size }
        let scale = min(1, box.width / size.width, box.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// A frame of `size` centered on `center`.
    public static func frame(size: CGSize, centeredAt center: CGPoint) -> CGRect {
        CGRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }
}

/// Whether an image fills its rectangle. Window captures with a shadow or a transparent
/// margin don't: a pin draws its border and rounded corners only around images that do, so
/// no frame floats around a window's transparent shadow.
public enum ImageEdges {
    public static func areOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return false }
        // The four corners and the middle of each edge.
        let points = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w / 2, 0), (w / 2, h - 1), (0, h / 2), (w - 1, h / 2)]
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return true }
        for (x, y) in points {
            guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return false }
            let ok = pixel.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            if !ok || pixel[3] < 128 { return false }
        }
        return true
    }
}
