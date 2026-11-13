import CoreGraphics
import Foundation

/// Finds black bars (letterboxing and pillarboxing) around a picture.
public enum BlackBars {
    /// The picture inside the bars, over all `frames` (so a dark scene in one frame doesn't
    /// cut into the picture), or nil when there are none worth removing.
    public static func detect(_ frames: [CGImage]) -> CropRect? {
        var found: CropRect?
        for frame in frames {
            guard let rect = detect(frame) else { return nil }
            found = found.map { union($0, rect) } ?? rect
        }
        guard let found, !found.isWhole, found.width > 0.2, found.height > 0.2,
              found.x > 0.01 || found.y > 0.01 || found.width < 0.98 || found.height < 0.98 else { return nil }
        return found
    }

    /// One frame: rows and columns from each edge that are (almost) black.
    static func detect(_ image: CGImage) -> CropRect? {
        // Rows at (up to) the picture's own height, so the edge lands on the right line.
        let h = max(2, min(image.height, 720)), w = 256
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        // Row 0 of the bitmap is the top of the picture.
        func dark(row: Int) -> Bool { (0..<w).allSatisfy { pixels[row * w + $0] < threshold } }
        func dark(column: Int) -> Bool { (0..<h).allSatisfy { pixels[$0 * w + column] < threshold } }
        var top = 0, bottom = h - 1, left = 0, right = w - 1
        while top < bottom, dark(row: top) { top += 1 }
        while bottom > top, dark(row: bottom) { bottom -= 1 }
        while left < right, dark(column: left) { left += 1 }
        while right > left, dark(column: right) { right -= 1 }
        guard bottom > top, right > left else { return nil } // all black: nothing to go on
        return CropRect(x: Double(left) / Double(w), y: Double(top) / Double(h),
                        width: Double(right - left + 1) / Double(w), height: Double(bottom - top + 1) / Double(h))
    }

    /// Below this (of 255) a pixel counts as black; compression noise in bars stays under it.
    static let threshold: UInt8 = 24

    static func union(_ a: CropRect, _ b: CropRect) -> CropRect {
        let x = min(a.x, b.x), y = min(a.y, b.y)
        return CropRect(x: x, y: y, width: max(a.x + a.width, b.x + b.width) - x, height: max(a.y + a.height, b.y + b.height) - y)
    }
}

/// Drawing helpers the window's sheets share with conversion.
public enum PictureDrawing {
    /// The picture turned and/or mirrored, as the converted file will show it.
    public static func turned(_ image: CGImage, by turn: PictureTransform) -> CGImage? {
        turn.isIdentity ? image : ImageConverter.turned(image, by: turn)
    }
}
