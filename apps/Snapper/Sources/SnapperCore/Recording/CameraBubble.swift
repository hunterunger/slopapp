import CoreGraphics

/// The camera bubble's shape.
public enum BubbleShape: String, CaseIterable, Identifiable, Sendable {
    case circle
    /// 4:3, like the camera's own picture.
    case roundedRectangle

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .circle: "Circle"
        case .roundedRectangle: "Rounded Rectangle"
        }
    }

    /// Height for a bubble `width` wide.
    public func height(forWidth width: CGFloat) -> CGFloat {
        switch self {
        case .circle: width
        case .roundedRectangle: (width * 3 / 4).rounded()
        }
    }
}

/// Which corner of the recorded area the bubble sits in. Remembered between recordings.
public enum BubbleCorner: String, CaseIterable, Sendable {
    case bottomLeft, bottomRight, topLeft, topRight
}

/// Where the camera bubble goes and how big it can be. AppKit coordinates (y up).
public enum BubbleGeometry {
    public static let minimumWidth: CGFloat = 96
    public static let maximumWidth: CGFloat = 480
    public static let defaultWidth: CGFloat = 200
    /// The bubble's gap from the area's edge.
    public static let inset: CGFloat = 24
    /// Context-menu sizes.
    public static let presets: [(title: String, width: CGFloat)] = [("Small", 140), ("Medium", 200), ("Large", 300)]

    /// The widest the bubble may get inside `area`: half its shorter side, within the limits.
    public static func clampedWidth(_ width: CGFloat, shape: BubbleShape, in area: CGRect) -> CGFloat {
        let roomForWidth = area.width / 2
        let roomForHeight = shape == .circle ? area.height / 2 : area.height / 2 * 4 / 3
        let upper = max(minimumWidth, min(maximumWidth, roomForWidth, roomForHeight))
        return min(max(width, minimumWidth), upper).rounded()
    }

    /// The bubble in `corner` of `area`, `inset` in (less for a small area).
    public static func frame(corner: BubbleCorner, width: CGFloat, shape: BubbleShape, in area: CGRect) -> CGRect {
        let width = clampedWidth(width, shape: shape, in: area)
        let size = CGSize(width: width, height: shape.height(forWidth: width))
        let gap = min(inset, max(0, (min(area.width, area.height) - max(size.width, size.height)) / 4)).rounded()
        let x = corner == .bottomLeft || corner == .topLeft ? area.minX + gap : area.maxX - gap - size.width
        let y = corner == .bottomLeft || corner == .bottomRight ? area.minY + gap : area.maxY - gap - size.height
        return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
    }

    /// The corner of `area` nearest to the bubble's center (where it goes next time).
    public static func nearestCorner(of frame: CGRect, in area: CGRect) -> BubbleCorner {
        let left = frame.midX < area.midX
        let bottom = frame.midY < area.midY
        switch (left, bottom) {
        case (true, true): return .bottomLeft
        case (false, true): return .bottomRight
        case (true, false): return .topLeft
        case (false, false): return .topRight
        }
    }

    /// `frame` resized to `width` around its center, then kept inside `bounds` (the screen).
    public static func resized(_ frame: CGRect, toWidth width: CGFloat, shape: BubbleShape, area: CGRect, bounds: CGRect) -> CGRect {
        let width = clampedWidth(width, shape: shape, in: area)
        let size = CGSize(width: width, height: shape.height(forWidth: width))
        let resized = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        return kept(resized, inside: bounds)
    }

    /// `frame` moved (not resized) so it's inside `bounds`.
    public static func kept(_ frame: CGRect, inside bounds: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        return CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width, height: frame.height)
    }

    /// Corner radius for the rounded-rectangle shape (a circle is half its width).
    public static func cornerRadius(for size: CGSize, shape: BubbleShape) -> CGFloat {
        switch shape {
        case .circle: min(size.width, size.height) / 2
        case .roundedRectangle: (min(size.width, size.height) * 0.16).rounded()
        }
    }
}
