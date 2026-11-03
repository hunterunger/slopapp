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
