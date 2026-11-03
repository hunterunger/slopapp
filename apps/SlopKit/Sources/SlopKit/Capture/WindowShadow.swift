import CoreGraphics

/// Adds a soft drop shadow on a transparent margin around a window capture.
///
/// ScreenCaptureKit can include the system shadow, but then it squeezes window + shadow into
/// the window's own size. Capturing the window alone at its exact size and drawing the shadow
/// here keeps the window pixel-perfect.
public enum WindowShadow {
    /// Margins around the window, in points (more below, where the shadow falls).
    public static let margin = (top: CGFloat(30), side: CGFloat(44), bottom: CGFloat(60))
    public static let blur: CGFloat = 34
    public static let offset: CGFloat = 18
    public static let opacity: CGFloat = 0.45

    public static func paddedSize(width: Int, height: Int, scale: CGFloat) -> (width: Int, height: Int) {
        (width + Int((margin.side * 2 * scale).rounded()),
         height + Int(((margin.top + margin.bottom) * scale).rounded()))
    }

    public static func apply(to window: CGImage, scale: CGFloat) -> CGImage? {
        let size = paddedSize(width: window.width, height: window.height, scale: scale)
        let space = window.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CG's origin is bottom-left: the bigger bottom margin is at y = 0.
        let rect = CGRect(x: (margin.side * scale).rounded(), y: (margin.bottom * scale).rounded(),
                          width: CGFloat(window.width), height: CGFloat(window.height))
        context.setShadow(offset: CGSize(width: 0, height: -offset * scale), blur: blur * scale,
                          color: CGColor(gray: 0, alpha: opacity))
        context.draw(window, in: rect)
        return context.makeImage()
    }
}
