import CoreGraphics
import Foundation
import SlopKit

/// Builds one tall image from frames of the same area taken while its content scrolls down.
///
/// Each new frame is matched against the previous one: the content moved up by `dy` pixels
/// when the bottom `h - dy` rows of the previous frame equal the top rows of the new one.
/// Rows are compared by a compact signature (average brightness in vertical bands), so a
/// match over a 2000-pixel-tall frame takes a few milliseconds.
public struct ScrollStitcher: Sendable {
    public enum AddResult: Equatable, Sendable {
        /// The content moved up; this many new rows were added at the bottom.
        case appended(Int)
        /// Nothing moved (or it moved back up): the frame was ignored.
        case unchanged
        /// The frame couldn't be lined up with the previous one (scrolled too far at once).
        case noMatch
        /// The result reached `maxHeight`; stop.
        case full
    }

    /// Frames are this size; others are rejected.
    public let width: Int
    public let frameHeight: Int
    /// The tallest result allowed, in pixels.
    public let maxHeight: Int
    private var strips: [CGImageBox] = []
    private var lastSignature: [[Float]]
    public private(set) var height: Int

    static let bands = 48

    public init?(first: CGImage, maxHeight: Int = 40_000) {
        guard let signature = Self.signature(first) else { return nil }
        width = first.width
        frameHeight = first.height
        self.maxHeight = maxHeight
        strips = [CGImageBox(first)]
        lastSignature = signature
        height = first.height
    }

    public var frameCount: Int { strips.count }

    public mutating func add(_ frame: CGImage) -> AddResult {
        guard height < maxHeight else { return .full }
        guard frame.width == width, frame.height == frameHeight, let signature = Self.signature(frame) else { return .noMatch }
        guard let match = Self.offset(previous: lastSignature, next: signature) else { return .noMatch }
        guard match > 0 else { return .unchanged }
        let rows = min(match, maxHeight - height)
        guard rows > 0, let strip = frame.cropping(to: CGRect(x: 0, y: frameHeight - rows, width: width, height: rows)) else { return .full }
        strips.append(CGImageBox(strip))
        height += rows
        lastSignature = signature
        return height >= maxHeight ? .full : .appended(rows)
    }

    /// The stitched image so far.
    public func image() -> CGImage? {
        let space = strips.first?.image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var top = 0
        for strip in strips {
            let h = strip.image.height
            // CG is bottom-left: a strip `top` rows down sits at y = height - top - h.
            context.draw(strip.image, in: CGRect(x: 0, y: height - top - h, width: width, height: h))
            top += h
        }
        return context.makeImage()
    }

    // MARK: Matching

    /// Per row: the average brightness (0…1) in `bands` vertical bands.
    static func signature(_ image: CGImage) -> [[Float]]? {
        guard let pixels = PixelBuffer(image) else { return nil }
        let w = pixels.width, h = pixels.height
        let bands = min(Self.bands, max(1, w))
        var rows: [[Float]] = []
        rows.reserveCapacity(h)
        pixels.bytes.withUnsafeBufferPointer { bytes in
            for y in 0..<h {
                var row = [Float](repeating: 0, count: bands)
                for b in 0..<bands {
                    let x0 = b * w / bands, x1 = max(x0 + 1, (b + 1) * w / bands)
                    var sum: Float = 0
                    var x = x0
                    while x < x1 {
                        let i = (y * w + x) * 4
                        sum += 0.2126 * Float(bytes[i]) + 0.7152 * Float(bytes[i + 1]) + 0.0722 * Float(bytes[i + 2])
                        x += 1
                    }
                    row[b] = sum / Float(x1 - x0) / 255
                }
                rows.append(row)
            }
        }
        return rows
    }

    /// How far the content moved up from `previous` to `next`, in rows, or nil if no offset
    /// lines them up. 0 means unchanged.
    static func offset(previous: [[Float]], next: [[Float]], tolerance: Float = 0.012) -> Int? {
        let h = min(previous.count, next.count)
        guard h > 4 else { return nil }
        let minOverlap = max(8, h / 6)
        func error(_ dy: Int, limit: Float) -> Float {
            let overlap = h - dy
            let step = overlap > 400 ? 2 : 1
            var total: Float = 0
            var count = 0
            var r = 0
            while r < overlap {
                let a = previous[r + dy], b = next[r]
                var d: Float = 0
                for i in 0..<a.count { d += abs(a[i] - b[i]) }
                total += d / Float(a.count)
                count += 1
                // Give up early on hopeless offsets.
                if count % 32 == 0, total / Float(count) > limit * 4 { return .infinity }
                r += step
            }
            return total / Float(max(count, 1))
        }
        if error(0, limit: tolerance) <= tolerance / 4 { return 0 }
        var best: (dy: Int, error: Float)?
        for dy in 1...(h - minOverlap) {
            let e = error(dy, limit: best?.error ?? tolerance)
            if e < (best?.error ?? .infinity) { best = (dy, e) }
        }
        guard let best, best.error <= tolerance else { return nil }
        return best.dy
    }
}

/// CGImage is thread-safe once made; this lets the stitcher be Sendable.
struct CGImageBox: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
