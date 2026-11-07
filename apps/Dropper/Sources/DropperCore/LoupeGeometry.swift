import CoreGraphics
import Foundation

/// The precise picker's magnifier: its size and zoom steps, and the pixel it points at.
/// Works in image pixels so arrow keys move exactly one physical pixel on any display.
public struct LoupeGeometry: Equatable, Sendable {
    /// Diameters in points, smallest to largest.
    public static let diameters: [CGFloat] = [104, 136, 168, 208, 256]
    /// On-screen size of one magnified pixel, in points.
    public static let cellSizes: [CGFloat] = [6, 8, 11, 14, 18]

    public var sizeStep: Int
    public var zoomStep: Int

    public init(sizeStep: Int = 1, zoomStep: Int = 1) {
        self.sizeStep = Self.clampStep(sizeStep, Self.diameters)
        self.zoomStep = Self.clampStep(zoomStep, Self.cellSizes)
    }

    public var diameter: CGFloat { Self.diameters[sizeStep] }
    public var cellSize: CGFloat { Self.cellSizes[zoomStep] }

    /// Pixels across the loupe: odd, so one sits exactly in the middle.
    public var cells: Int {
        let n = Int((diameter / cellSize).rounded(.up))
        return n % 2 == 0 ? n + 1 : n
    }

    public mutating func grow() { sizeStep = min(sizeStep + 1, Self.diameters.count - 1) }
    public mutating func shrink() { sizeStep = max(sizeStep - 1, 0) }
    public mutating func zoomIn() { zoomStep = min(zoomStep + 1, Self.cellSizes.count - 1) }
    public mutating func zoomOut() { zoomStep = max(zoomStep - 1, 0) }

    /// The image-pixel square around `center` that the loupe shows (may hang off the image;
    /// the caller draws only the part that exists).
    public func sampleRect(around center: PixelPoint) -> (x: Int, y: Int, side: Int) {
        let half = cells / 2
        return (center.x - half, center.y - half, cells)
    }

    private static func clampStep(_ step: Int, _ list: [CGFloat]) -> Int {
        min(max(step, 0), list.count - 1)
    }
}

/// A pixel in a display image: origin top-left, y down.
public struct PixelPoint: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The pixel under a screen-local point (AppKit, y up) on a display `height` points tall.
    public static func under(local point: CGPoint, height: CGFloat, scale: CGFloat) -> PixelPoint {
        PixelPoint(x: Int((point.x * scale).rounded(.down)), y: Int(((height - point.y) * scale).rounded(.down)))
    }

    /// The middle of this pixel as a screen-local point (AppKit, y up).
    public func localCenter(height: CGFloat, scale: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(x) + 0.5) / scale, y: height - (CGFloat(y) + 0.5) / scale)
    }

    /// Moved by (dx, dy) pixels (y down), kept inside a `width` × `height` image.
    public func nudged(dx: Int, dy: Int, width: Int, height: Int) -> PixelPoint {
        PixelPoint(x: min(max(x + dx, 0), max(width - 1, 0)), y: min(max(y + dy, 0), max(height - 1, 0)))
    }
}

/// What one press of an arrow key does in the picker: 1 pixel, or 10 with Shift.
public enum PickerNudge {
    public static func delta(keyCode: UInt16, shift: Bool) -> (dx: Int, dy: Int)? {
        let step = shift ? 10 : 1
        switch keyCode {
        case 123: return (-step, 0) // left
        case 124: return (step, 0) // right
        case 125: return (0, step) // down (image y grows downwards)
        case 126: return (0, -step) // up
        default: return nil
        }
    }
}
