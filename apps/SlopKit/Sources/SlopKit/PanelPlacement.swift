import CoreGraphics

/// Where a floating panel appears. Pure geometry, so it's unit-tested.
/// All rects are in AppKit screen coordinates (origin bottom-left, y up).
public enum PanelPlacement: Sendable, Equatable {
    /// Centered under the cursor (above it if there's no room). For choosers.
    case nearMouse
    /// Horizontally centered, a third of the way down the screen. For search panels.
    case center
    /// Tucked into a corner of the screen. For post-action thumbnails.
    case corner(Corner)

    public enum Corner: Sendable, Equatable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    /// Gap between the cursor and a `.nearMouse` panel.
    public static let cursorGap: CGFloat = Spacing.m

    /// The panel frame for `size`, kept fully inside `visibleFrame` (inset by `margin`).
    public func frame(size: CGSize, mouse: CGPoint, visibleFrame: CGRect, margin: CGFloat = Spacing.l) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
        var origin: CGPoint
        switch self {
        case .nearMouse:
            origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - Self.cursorGap - size.height)
            if origin.y < bounds.minY {
                origin.y = mouse.y + Self.cursorGap
            }
        case .center:
            origin = CGPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - visibleFrame.height / 3 - size.height / 2
            )
        case .corner(let corner):
            switch corner {
            case .topLeading: origin = CGPoint(x: bounds.minX, y: bounds.maxY - size.height)
            case .topTrailing: origin = CGPoint(x: bounds.maxX - size.width, y: bounds.maxY - size.height)
            case .bottomLeading: origin = CGPoint(x: bounds.minX, y: bounds.minY)
            case .bottomTrailing: origin = CGPoint(x: bounds.maxX - size.width, y: bounds.minY)
            }
        }
        // Clamp so the panel never spills off screen.
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }
}
