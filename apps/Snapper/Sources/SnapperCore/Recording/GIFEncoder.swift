import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes animated GIFs (ImageIO).
public enum GIFEncoder {
    /// GIF options from Settings.
    public struct Options: Equatable, Sendable {
        public var frameRate: Int
        /// Longest side in pixels (frames are scaled down to fit).
        public var maxWidth: Int

        public init(frameRate: Int = 15, maxWidth: Int = 800) {
            self.frameRate = frameRate
            self.maxWidth = maxWidth
        }

        public static let frameRates = [10, 15, 20, 30]
        public static let widths = [480, 640, 800, 1024, 1280]
    }

    /// An animated GIF that loops forever. `delay` is seconds per frame.
    public static func data(frames: [CGImage], delay: Double) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
        ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The frame scaled to at most `maxWidth` pixels wide (aspect kept).
    public static func scaled(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let width = maxWidth
        let height = max(1, Int((CGFloat(image.height) * CGFloat(maxWidth) / CGFloat(image.width)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Frame times (seconds) to sample from a video of `duration` at `frameRate`.
    public static func sampleTimes(duration: Double, frameRate: Int) -> [Double] {
        guard duration > 0, frameRate > 0 else { return [0] }
        let step = 1 / Double(frameRate)
        return stride(from: 0, to: duration, by: step).map { $0 }
    }
}
