import CoreGraphics
import Foundation

/// Turns a photo or scan of a signature into a saved `Signature`.
///
/// PDFKit can't write a custom image appearance for an annotation (a custom-drawn stamp is
/// saved with PDFKit's default stamp look, research P21), so an image signature is stored the
/// way drawn ones are: as one Ink annotation. The light background is knocked out by a
/// luminance threshold, the ink is cropped, and each row band of ink becomes horizontal
/// strokes as thick as the band. The result is a vector silhouette of the signature in the
/// chosen ink color that places, resizes and flattens like a drawn signature.
public enum SignatureImport {
    /// The ink mask of an image: true where a pixel is darker than `threshold` (0...1).
    public struct Mask: Equatable, Sendable {
        public var width: Int
        public var height: Int
        /// Row-major, row 0 at the top.
        public var bits: [Bool]

        public subscript(x: Int, y: Int) -> Bool { bits[y * width + x] }

        public var inkCount: Int { bits.reduce(0) { $0 + ($1 ? 1 : 0) } }
    }

    /// Longest side the image is reduced to before tracing. Enough for a crisp signature at
    /// any size it's placed at, small enough to keep the annotation light.
    public static let maxWidth = 600
    /// At most this many bands of strokes from top to bottom.
    public static let maxBands = 140
    /// Stroke thickness relative to the band height.
    public static let overlap: CGFloat = 1.5

    /// Grayscale luminance 0...1 per pixel (transparent pixels count as white paper).
    public static func luminance(of image: CGImage, maxWidth: Int = SignatureImport.maxWidth) -> (width: Int, height: Int, values: [Float])? {
        let scale = min(1, CGFloat(maxWidth) / CGFloat(max(image.width, 1)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext memory is top row first.
        return (width, height, pixels.map { Float($0) / 255 })
    }

    /// A threshold between paper and ink (Otsu's method), nudged toward the paper so faint
    /// pen strokes survive. Photos of paper are rarely pure white.
    public static func suggestedThreshold(_ values: [Float]) -> Float {
        var histogram = [Int](repeating: 0, count: 256)
        for value in values { histogram[min(255, max(0, Int(value * 255)))] += 1 }
        let total = values.count
        guard total > 0 else { return 0.5 }
        var sum = 0.0
        for index in 0..<256 { sum += Double(index * histogram[index]) }
        var sumBackground = 0.0, weightBackground = 0, best = 0.0, threshold = 128
        for index in 0..<256 {
            weightBackground += histogram[index]
            guard weightBackground > 0 else { continue }
            let weightForeground = total - weightBackground
            guard weightForeground > 0 else { break }
            sumBackground += Double(index * histogram[index])
            let meanBackground = sumBackground / Double(weightBackground)
            let meanForeground = (sum - sumBackground) / Double(weightForeground)
            let between = Double(weightBackground) * Double(weightForeground) * pow(meanBackground - meanForeground, 2)
            if between > best { best = between; threshold = index }
        }
        return min(0.85, max(0.2, Float(threshold) / 255 + 0.04))
    }

    /// Ink pixels, with lone specks (no ink neighbour) dropped and the result cropped to the ink.
    public static func mask(width: Int, height: Int, values: [Float], threshold: Float) -> Mask? {
        var bits = values.map { $0 < threshold }
        // Drop isolated pixels: scanner dust shouldn't stretch the crop.
        var cleaned = bits
        for y in 0..<height {
            for x in 0..<width where bits[y * width + x] {
                var neighbours = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < width, ny < height, bits[ny * width + nx] { neighbours += 1 }
                    }
                }
                if neighbours == 0 { cleaned[y * width + x] = false }
            }
        }
        bits = cleaned
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bits[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let croppedWidth = maxX - minX + 1, croppedHeight = maxY - minY + 1
        var cropped = [Bool](repeating: false, count: croppedWidth * croppedHeight)
        for y in 0..<croppedHeight {
            for x in 0..<croppedWidth { cropped[y * croppedWidth + x] = bits[(y + minY) * width + (x + minX)] }
        }
        return Mask(width: croppedWidth, height: croppedHeight, bits: cropped)
    }

    /// Horizontal ink runs per band, as a `Signature` (normalized: width 1, y up).
    public static func signature(from mask: Mask, kind: Signature.Kind = .signature, created: Date = Date()) -> Signature? {
        guard mask.width >= 4 || mask.height >= 4, mask.inkCount >= 8 else { return nil }
        let band = max(1, Int((Double(mask.height) / Double(maxBands)).rounded(.up)))
        let scale = CGFloat(mask.width)
        let bandHeight = CGFloat(band) / scale
        // Bands overlap a little: abutting antialiased edges would show as faint stripes.
        let lineWidth = bandHeight * overlap
        var strokes: [[CGPoint]] = []
        var top = 0
        while top < mask.height {
            let rows = top..<min(top + band, mask.height)
            // A column has ink in this band when any of its rows does.
            var x = 0
            while x < mask.width {
                guard rows.contains(where: { mask[x, $0] }) else { x += 1; continue }
                let start = x
                while x < mask.width, rows.contains(where: { mask[x, $0] }) { x += 1 }
                // y up: band centre measured from the bottom of the mask.
                let centre = CGFloat(mask.height) - (CGFloat(rows.lowerBound) + CGFloat(rows.count) / 2)
                let y = centre / scale
                // Strokes have round caps half a band wide; pull the ends in to match the ink.
                let inset = min(lineWidth / 2, CGFloat(x - start) / scale / 2)
                strokes.append([CGPoint(x: CGFloat(start) / scale + inset, y: y),
                                CGPoint(x: CGFloat(x) / scale - inset, y: y)])
            }
            top += band
        }
        guard !strokes.isEmpty else { return nil }
        let aspect = CGFloat(mask.width) / CGFloat(mask.height)
        return Signature(kind: kind, created: created, strokes: strokes, aspect: aspect, lineWidth: lineWidth)
    }

    /// The whole import with an automatic threshold. `threshold` overrides it (0...1).
    public static func signature(from image: CGImage, threshold: Float? = nil, kind: Signature.Kind = .signature) -> Signature? {
        guard let gray = luminance(of: image) else { return nil }
        let level = threshold ?? suggestedThreshold(gray.values)
        guard let mask = mask(width: gray.width, height: gray.height, values: gray.values, threshold: level) else { return nil }
        return signature(from: mask, kind: kind)
    }
}
