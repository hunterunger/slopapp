import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Makes everything but a picture's subject transparent. Vision in the app (on-device), a
/// fake in tests.
public protocol BackgroundRemoving: Sendable {
    /// A greyscale mask the size of `image`: 255 keeps a pixel, 0 removes it.
    func subjectMask(for image: CGImage) throws -> [UInt8]
}

public enum CutoutError: Error, LocalizedError, Equatable {
    case noSubject
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .noSubject:
            "Iconsmith couldn’t find a subject to keep. Removing the background works best on photos of people, animals and objects."
        case .failed(let message):
            "Removing the background didn’t work (\(message))."
        }
    }
}

/// Vision's subject lifting (macOS 14+), the same on-device model as “Copy Subject”.
public struct VisionBackgroundRemover: BackgroundRemoving {
    public init() {}

    public func subjectMask(for image: CGImage) throws -> [UInt8] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { throw CutoutError.failed(error.localizedDescription) }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { throw CutoutError.noSubject }
        let buffer: CVPixelBuffer
        do {
            buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        } catch {
            throw CutoutError.failed(error.localizedDescription)
        }
        return try Self.bytes(of: buffer, width: image.width, height: image.height)
    }

    /// The mask buffer (one float or byte per pixel) as bytes, rows top to bottom.
    static func bytes(of buffer: CVPixelBuffer, width: Int, height: Int) throws -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw CutoutError.failed("no mask") }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let sy = min(y * h / max(height, 1), h - 1)
            for x in 0..<width {
                let sx = min(x * w / max(width, 1), w - 1)
                let value: Double
                if format == kCVPixelFormatType_OneComponent32Float {
                    value = Double(base.advanced(by: sy * row + sx * 4).assumingMemoryBound(to: Float32.self).pointee)
                } else {
                    value = Double(base.advanced(by: sy * row + sx).assumingMemoryBound(to: UInt8.self).pointee) / 255
                }
                out[y * width + x] = UInt8((min(max(value, 0), 1) * 255).rounded())
            }
        }
        return out
    }
}

public enum Cutout {
    /// Largest side a vector source is drawn at before cutting it out.
    static let vectorPixels = 1024

    /// The source with its background removed: a new raster source marked as a cut-out.
    public static func make(from source: IconSource, remover: BackgroundRemoving) throws -> IconSource {
        guard let image = raster(source) else { throw CutoutError.failed("couldn’t read the picture") }
        let mask = try remover.subjectMask(for: image)
        guard mask.contains(where: { $0 > 16 }) else { throw CutoutError.noSubject }
        guard let cut = apply(mask: mask, to: image) else { throw CutoutError.failed("couldn’t apply the mask") }
        return IconSource(content: .raster(cut), name: source.name, url: source.url,
                          size: CGSize(width: cut.width, height: cut.height), isFileIcon: source.isFileIcon, isCutout: true)
    }

    /// The picture as pixels (vectors drawn at up to 1024 px on their long side).
    static func raster(_ source: IconSource) -> CGImage? {
        switch source.content {
        case .raster(let image): return image
        case .vector(let image):
            let scale = Double(vectorPixels) / max(source.size.width, source.size.height)
            let w = max(Int((source.size.width * scale).rounded()), 1), h = max(Int((source.size.height * scale).rounded()), 1)
            guard let context = Bitmap.context(width: w, height: h) else { return nil }
            Bitmap.drawVector(image, in: CGRect(x: 0, y: 0, width: w, height: h), context: context)
            return context.makeImage()
        }
    }

    /// `image` with each pixel's alpha multiplied by the mask (rows top to bottom).
    public static func apply(mask: [UInt8], to image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard mask.count == w * h, let gray = IconRenderer.grayImage(mask, width: w, height: h),
              let context = Bitmap.context(width: w, height: h) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        context.clip(to: rect, mask: gray)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
