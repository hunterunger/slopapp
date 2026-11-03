// Ruler measures in the pixels of a frozen display image. Everything in RulerCore uses
// image pixel coordinates: origin at the top-left, y down, whole pixels.
//
// Rects use *boundary* coordinates: `minX` is the line before the first pixel, `maxX` the
// line after the last one, so `maxX - minX` is the width in pixels.

/// One pixel position (top-left origin).
public struct PixelPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// A rect between pixel boundaries (top-left origin, half-open: pixels `minX..<maxX`).
public struct PixelRect: Hashable, Sendable, CustomStringConvertible {
    public var minX: Int
    public var minY: Int
    public var maxX: Int
    public var maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(minX: x, minY: y, maxX: x + width, maxY: y + height)
    }

    public var width: Int { maxX - minX }
    public var height: Int { maxY - minY }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func contains(_ point: PixelPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func contains(_ other: PixelRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }

    /// The overlap, or nil if none.
    public func intersection(_ other: PixelRect) -> PixelRect? {
        let result = PixelRect(minX: max(minX, other.minX), minY: max(minY, other.minY),
                               maxX: min(maxX, other.maxX), maxY: min(maxY, other.maxY))
        return result.isEmpty ? nil : result
    }

    public func insetBy(_ amount: Int) -> PixelRect {
        PixelRect(minX: minX + amount, minY: minY + amount, maxX: maxX - amount, maxY: maxY - amount)
    }

    public var description: String { "(\(minX),\(minY) \(width)×\(height))" }
}

/// Which way a guide line runs.
public enum GuideAxis: String, Sendable, Hashable {
    /// A horizontal line: its position is a y boundary.
    case horizontal
    /// A vertical line: its position is an x boundary.
    case vertical
}
