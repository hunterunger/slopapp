import CoreGraphics

/// Conversions between the coordinate spaces a screen capture touches:
///
/// - **AppKit global** (`NSScreen.frame`, `NSEvent.mouseLocation`): origin at the bottom-left
///   of the primary display, y up, points.
/// - **Quartz global** (`CGWindowList`, `SCWindow.frame`, `SCDisplay.frame`): origin at the
///   top-left of the primary display, y down, points.
/// - **Screen-local**: AppKit coordinates relative to one screen's origin.
/// - **Image pixels**: a capture of one screen, origin top-left, y down, pixels.
public enum ScreenCoordinates {
    /// AppKit global ⇄ Quartz global. The same flip works both ways.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// A screen-local rect (AppKit, points) as a pixel rect in a capture of that screen.
    public static func pixelRect(local rect: CGRect, screenSize: CGSize, scale: CGFloat) -> CGRect {
        let flipped = CGRect(x: rect.minX, y: screenSize.height - rect.maxY, width: rect.width, height: rect.height)
        return CGRect(
            x: (flipped.minX * scale).rounded(),
            y: (flipped.minY * scale).rounded(),
            width: (flipped.width * scale).rounded(),
            height: (flipped.height * scale).rounded()
        )
    }

    /// A screen-local point (AppKit) as a pixel position in a capture of that screen.
    public static func pixelPoint(local point: CGPoint, screenSize: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(x: (point.x * scale).rounded(.down), y: ((screenSize.height - point.y) * scale).rounded(.down))
    }

    /// A Quartz-global rect as screen-local AppKit coordinates for the screen whose AppKit
    /// frame is `screenFrame`.
    public static func local(fromQuartz rect: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight).offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }
}
