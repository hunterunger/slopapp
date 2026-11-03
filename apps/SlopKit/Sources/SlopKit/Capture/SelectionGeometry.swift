import CoreGraphics

// Pure geometry for a drag-to-select region overlay (`RegionOverlay`), shared by the
// screen-capture apps (Snapper, Ruler, Dropper, Snip). No AppKit.
//
// All points are in one screen's local coordinates (AppKit: origin bottom-left, y up, in
// points). The overlay converts to pixels only when cropping (see `ScreenCoordinates`).

/// Modifier behaviour while dragging out a selection.
public struct SelectionModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Shift: keep the selection square.
    public static let square = SelectionModifiers(rawValue: 1 << 0)
    /// Option: grow from the anchor as the center.
    public static let fromCenter = SelectionModifiers(rawValue: 1 << 1)
}

/// A selection being dragged out: where the drag started and where the pointer is now.
public struct SelectionDrag: Sendable, Equatable {
    public var anchor: CGPoint
    public var current: CGPoint

    public init(anchor: CGPoint, current: CGPoint? = nil) {
        self.anchor = anchor
        self.current = current ?? anchor
    }

    /// Moves the pointer. With `moving` (Space held) the whole selection follows the pointer
    /// instead of resizing, like macOS's own screenshot tool.
    public mutating func update(to point: CGPoint, moving: Bool) {
        if moving {
            let dx = point.x - current.x, dy = point.y - current.y
            anchor.x += dx
            anchor.y += dy
        }
        current = point
    }

    /// The selection rect, honoring modifiers and kept inside `bounds`.
    public func rect(modifiers: SelectionModifiers = [], bounds: CGRect) -> CGRect {
        SelectionGeometry.rect(anchor: anchor, current: current, modifiers: modifiers, bounds: bounds)
    }
}

public enum SelectionGeometry {
    /// Selections smaller than this (in points, either side) count as a click, not a capture.
    public static let minimumSide: CGFloat = 3

    /// The rect spanned by `anchor` and `current` with modifiers applied, clamped to `bounds`
    /// and snapped to whole points so captures don't straddle pixels.
    public static func rect(anchor: CGPoint, current: CGPoint, modifiers: SelectionModifiers, bounds: CGRect) -> CGRect {
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y
        if modifiers.contains(.square) {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        var rect: CGRect
        if modifiers.contains(.fromCenter) {
            rect = CGRect(x: anchor.x - abs(dx), y: anchor.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        } else {
            rect = CGRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy), width: abs(dx), height: abs(dy))
        }
        return snapped(rect).intersection(bounds).standardized.nonNull
    }

    /// Rounds every edge of a rect to the nearest whole point.
    public static func snapped(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded(), maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether a selection is big enough to capture.
    public static func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// Moves `rect` by `delta`, keeping it fully inside `bounds`.
    public static func moved(_ rect: CGRect, by delta: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: delta.dx, dy: delta.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// The pointer step for an arrow key: 1 pt, or 10 pt with Shift.
    public static func nudge(for arrow: ArrowKey, large: Bool) -> CGVector {
        let step: CGFloat = large ? 10 : 1
        switch arrow {
        case .left: return CGVector(dx: -step, dy: 0)
        case .right: return CGVector(dx: step, dy: 0)
        case .up: return CGVector(dx: 0, dy: step)
        case .down: return CGVector(dx: 0, dy: -step)
        }
    }

    /// The "W × H" readout for a selection.
    public static func sizeLabel(_ rect: CGRect) -> String {
        "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }

    /// Where to put a label of `size` next to `selection`: below its bottom-right corner if
    /// there's room, else inside it, never off `bounds`.
    public static func labelOrigin(size: CGSize, for selection: CGRect, bounds: CGRect, gap: CGFloat = 6) -> CGPoint {
        var origin = CGPoint(x: selection.maxX - size.width, y: selection.minY - gap - size.height)
        if origin.y < bounds.minY { origin.y = selection.minY + gap }
        origin.x = min(max(origin.x, bounds.minX + gap), bounds.maxX - size.width - gap)
        origin.y = min(max(origin.y, bounds.minY + gap), bounds.maxY - size.height - gap)
        return origin
    }

    /// Where to put the magnifier (of `size`) for a pointer at `point`: down-right of the
    /// pointer, flipped to the other side near the edges.
    public static func magnifierOrigin(size: CGSize, pointer: CGPoint, bounds: CGRect, offset: CGFloat = 24) -> CGPoint {
        var x = pointer.x + offset
        var y = pointer.y - offset - size.height
        if x + size.width > bounds.maxX { x = pointer.x - offset - size.width }
        if y < bounds.minY { y = pointer.y + offset }
        return CGPoint(x: x, y: y)
    }
}

/// An arrow key, from its macOS virtual key code.
public enum ArrowKey: Sendable {
    case left, right, up, down

    /// macOS virtual key codes for the arrow keys.
    public init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }
}

extension CGRect {
    /// `.zero` instead of `.null` (empty intersections), so callers don't trip on infinities.
    var nonNull: CGRect { isNull ? .zero : self }
}
