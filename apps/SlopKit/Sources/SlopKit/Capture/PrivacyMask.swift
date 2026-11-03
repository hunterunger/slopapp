import CoreGraphics

/// Keeps only the given areas of a capture and makes everything else fully transparent.
///
/// Test mode uses it as a hard guarantee: ScreenCaptureKit filters work per app, and the
/// menu bar, clock and some system surfaces belong to no app, so a filter alone can't keep
/// them out. Masking by the kept windows' frames can.
public enum PrivacyMask {
    /// `keep` rects are in image pixels, top-left origin. Returns nil if drawing fails.
    public static func apply(to image: CGImage, keeping keep: [CGRect]) -> CGImage? {
        let width = image.width, height = image.height
        let space = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // CG is bottom-left: flip each top-left rect, snapped inward to whole pixels.
        let clips = keep.compactMap { rect -> CGRect? in
            let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
            let inner = CGRect(x: flipped.minX.rounded(.up), y: flipped.minY.rounded(.up),
                               width: 0, height: 0)
            let snapped = CGRect(x: inner.minX, y: inner.minY,
                                 width: flipped.maxX.rounded(.down) - inner.minX, height: flipped.maxY.rounded(.down) - inner.minY)
                .intersection(bounds)
            return snapped.isNull || snapped.isEmpty ? nil : snapped
        }
        guard !clips.isEmpty else { return context.makeImage() } // nothing kept: all transparent
        context.clip(to: clips)
        context.draw(image, in: bounds)
        return context.makeImage()
    }
}
