import CoreGraphics

/// Where the fill-in form goes: just below the caret (or the focused field), above it when
/// there's no room below, kept on screen. AppKit coordinates (origin bottom-left, y up).
public enum CaretPlacement {
    public static let gap: CGFloat = 8
    public static let margin: CGFloat = 12

    /// `anchor`: the caret's rect, or the focused field's. `leading`: align the panel's left
    /// edge with the anchor (a caret) rather than centring it (a whole field).
    public static func frame(size: CGSize, anchor: CGRect, visibleFrame: CGRect, leading: Bool = true) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
        var origin = CGPoint(x: leading ? anchor.minX : anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        if origin.y < bounds.minY { origin.y = anchor.maxY + gap }
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    /// Accessibility's rects are top-left based on the main screen; AppKit's bottom-left.
    public static func appKitRect(fromAccessibility rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
