import CoreGraphics

/// Window layout math: halves, maximize, center, next display, coordinate flips and the
/// minimum-size readback. Pure geometry, no Accessibility calls.
///
/// Written to move into SlopKit as a shared `WindowLayout` module (docs/research/triggers.md:
/// Tiles can reuse it if it's ever built). Everything here uses Accessibility's coordinate
/// space: origin at the top left of the primary display, y growing downwards.
public enum WindowLayout {
    /// AppKit's bottom-left rect (`NSScreen.frame`) → Accessibility's top-left space.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen showing most of the window (by area), else the one nearest its centre.
    public static func screenIndex(for window: CGRect, in screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat) = (0, -1)
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(window)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > best.area { best = (index, area) }
        }
        if best.area > 0 { return best.index }
        let centre = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min { distance(centre, screens[$0]) < distance(centre, screens[$1]) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Where the window should go. `visible` is the usable area of its screen (menu bar and
    /// Dock removed); `nextVisible` the usable area of the next screen, for `.nextDisplay`.
    /// Returns nil for moves that aren't a frame (`.minimize`) or can't happen.
    public static func target(for move: WindowMove, window: CGRect, visible: CGRect, nextVisible: CGRect? = nil) -> CGRect? {
        let v = visible.integral
        if let area = move.area { return rect(area, in: v) }
        switch move {
        case .center:
            let size = CGSize(width: min(window.width, v.width), height: min(window.height, v.height))
            return CGRect(x: (v.midX - size.width / 2).rounded(), y: (v.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
        case .minimize, .fullScreen:
            return nil
        case .nextDisplay:
            guard let next = nextVisible?.integral, next != v else { return nil }
            if isMaximized(window, in: v) { return next }
            // Same relative position and size on the next screen, kept inside it.
            let scaleX = next.width / max(v.width, 1)
            let scaleY = next.height / max(v.height, 1)
            let width = min((window.width * scaleX).rounded(), next.width)
            let height = min((window.height * scaleY).rounded(), next.height)
            let x = next.minX + ((window.minX - v.minX) * scaleX).rounded()
            let y = next.minY + ((window.minY - v.minY) * scaleY).rounded()
            return clamp(CGRect(x: x, y: y, width: width, height: height), into: next)
        default:
            return nil
        }
    }

    /// A fraction of the usable area in points. Inner edges round down, so neighbouring areas
    /// (left and right half, the three thirds) meet exactly with no gap or overlap.
    public static func rect(_ area: UnitRect, in visible: CGRect) -> CGRect {
        let v = visible.integral
        func edge(_ fraction: Double, _ length: CGFloat) -> CGFloat {
            fraction >= 0.9999 ? length : (length * CGFloat(fraction)).rounded(.down)
        }
        let left = edge(area.x, v.width)
        let right = edge(area.x + area.width, v.width)
        let top = edge(area.y, v.height)
        let bottom = edge(area.y + area.height, v.height)
        return CGRect(x: v.minX + left, y: v.minY + top, width: max(right - left, 1), height: max(bottom - top, 1))
    }

    /// Within a couple of points of filling the usable area.
    public static func isMaximized(_ window: CGRect, in visible: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(window.minX - visible.minX) <= tolerance && abs(window.minY - visible.minY) <= tolerance
            && abs(window.width - visible.width) <= tolerance && abs(window.height - visible.height) <= tolerance
    }

    /// After setting the frame, apps with a minimum size may end up bigger than asked. Keep
    /// the edge the move was about (left half stays on the left edge, and so on) and keep the
    /// window on screen.
    public static func settle(actual size: CGSize, target: CGRect, move: WindowMove, visible: CGRect) -> CGRect {
        settle(actual: size, target: target, area: move.area, visible: visible)
    }

    /// The same for any area: a window that touches only the right (bottom) edge keeps that
    /// edge, one that touches only the left (top) keeps that, and anything else stays centred
    /// on the target. Nil `area` (center, next display) centres.
    public static func settle(actual size: CGSize, target: CGRect, area: UnitRect?, visible: CGRect) -> CGRect {
        var frame = CGRect(origin: target.origin, size: size)
        let full = area.map { $0.width >= 0.9999 && $0.height >= 0.9999 } ?? true
        if size.width > target.width {
            let touchesLeft = area.map { $0.x <= 0.0001 } ?? false
            let touchesRight = area.map { $0.x + $0.width >= 0.9999 } ?? false
            if touchesRight && !touchesLeft { frame.origin.x = target.maxX - size.width }
            else if full || !(touchesLeft && !touchesRight) { frame.origin.x = target.midX - size.width / 2 }
        }
        if size.height > target.height {
            let touchesTop = area.map { $0.y <= 0.0001 } ?? false
            let touchesBottom = area.map { $0.y + $0.height >= 0.9999 } ?? false
            if touchesBottom && !touchesTop { frame.origin.y = target.maxY - size.height }
            else if full || !(touchesTop && !touchesBottom) { frame.origin.y = target.midY - size.height / 2 }
        }
        return clamp(frame.integral, into: visible)
    }

    /// Moves (never resizes) `frame` so as much of it as possible is inside `area`.
    public static func clamp(_ frame: CGRect, into area: CGRect) -> CGRect {
        var result = frame
        if result.maxX > area.maxX { result.origin.x = area.maxX - result.width }
        if result.minX < area.minX { result.origin.x = area.minX }
        if result.maxY > area.maxY { result.origin.y = area.maxY - result.height }
        if result.minY < area.minY { result.origin.y = area.minY }
        return result
    }

    /// The screen after `index`, wrapping. Screens should be in a stable order (left to right).
    public static func nextIndex(after index: Int, count: Int) -> Int? {
        count > 1 ? (index + 1) % count : nil
    }

    /// Sorts screens left to right, then top to bottom, so "next display" moves predictably.
    public static func ordered(_ screens: [CGRect]) -> [Int] {
        screens.indices.sorted { a, b in
            screens[a].minX != screens[b].minX ? screens[a].minX < screens[b].minX : screens[a].minY < screens[b].minY
        }
    }
}
