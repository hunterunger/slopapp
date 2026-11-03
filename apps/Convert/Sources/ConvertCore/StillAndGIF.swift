import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

/// What this Mac can write, checked at runtime so menus only offer what works (AVIF and
/// HEVC depend on the macOS version and the Mac). Injected so tests can pretend.
public struct Capabilities: Sendable, Equatable {
    public var writableImageTypes: Set<String>
    public var canEncodeHEVC: Bool
    public var canEncodeProRes: Bool

    public init(writableImageTypes: Set<String>, canEncodeHEVC: Bool, canEncodeProRes: Bool) {
        self.writableImageTypes = writableImageTypes
        self.canEncodeHEVC = canEncodeHEVC
        self.canEncodeProRes = canEncodeProRes
    }

    public static let system: Capabilities = {
        var encoders: CFArray?
        VTCopyVideoEncoderList(nil, &encoders)
        let codecs = Set(((encoders as? [[String: Any]]) ?? []).compactMap {
            ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value
        })
        return Capabilities(
            writableImageTypes: Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []),
            canEncodeHEVC: codecs.contains(kCMVideoCodecType_HEVC),
            canEncodeProRes: codecs.contains(kCMVideoCodecType_AppleProRes422)
        )
    }()

    public func canWrite(_ target: ImageTarget) -> Bool {
        writableImageTypes.contains(target.type.identifier)
    }

    public func canWrite(_ target: VideoTarget) -> Bool {
        switch target {
        case .mp4HEVC: canEncodeHEVC
        case .movProRes: canEncodeProRes
        case .gif: writableImageTypes.contains(UTType.gif.identifier)
        default: true
        }
    }

    public var imageTargets: [ImageTarget] { ImageTarget.allCases.filter(canWrite) }
    public var videoTargets: [VideoTarget] { VideoTarget.allCases.filter(canWrite) }
}

/// Still images through ImageIO: decode, optionally shrink, re-encode, keep metadata and
/// orientation.
enum ImageConverter {
    struct Result {
        var width: Int
        var height: Int
        var notes: [String]
    }

    /// True when the output would be the same format at the same size: nothing to do.
    static func isNoOp(_ info: MediaInfo, inputType: UTType?, target: ImageTarget, size: SizeLimit) -> Bool {
        guard let inputType, info.frameCount == 1 else { return false }
        let same = inputType.conforms(to: target.type)
            || (target == .heic && inputType.conforms(to: .heif))
        let (w, h) = Planner.fit(info.width, info.height, in: size.box)
        return same && w == info.width && h == info.height
    }

    static func convert(_ url: URL, to output: URL, target: ImageTarget, quality: Quality, size: SizeLimit,
                        progress: (Double) -> Void) throws -> Result {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw ConvertError.damaged(name: name) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        var notes: [String] = []
        if CGImageSourceGetCount(source) > 1 { notes.append("Only the first frame was kept.") }

        let (fitW, fitH) = Planner.fit(width, height, in: size.box)
        let resizing = fitW < width || fitH < height
        let decoded: CGImage?
        if resizing {
            // Decode straight to the smaller size, upright.
            decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(fitW, fitH),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        } else {
            decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        guard var image = decoded else { throw ConvertError.damaged(name: name) }
        progress(0.4)
        try Task.checkCancellation()

        if target == .jpeg, hasAlpha(image) {
            image = flattened(image) ?? image
        }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, target.type.identifier as CFString, 1, nil)
        else { throw ConvertError.encodeFailed(name: name) }

        // Keep camera, location and other metadata; fix up what changed.
        let outOrientation: UInt32 = resizing ? 1 : orientation
        var options: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyTIFFDictionary, kCGImagePropertyMakerAppleDictionary,
                    kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let value = properties[key] { options[key] = value }
        }
        options[kCGImagePropertyOrientation] = outOrientation
        if var tiff = options[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = outOrientation
            if target == .tiff { tiff[kCGImagePropertyTIFFCompression] = 5 } // LZW
            options[kCGImagePropertyTIFFDictionary] = tiff
        } else if target == .tiff {
            options[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]
        }
        if resizing, var exif = options[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            options[kCGImagePropertyExifDictionary] = exif
        }
        if target.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = QualityTable.imageQuality(quality, target: target)
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        // iPhone HDR photos keep their brightness (gain map) when the size doesn't change.
        if !resizing, target == .heic || target == .jpeg {
            var auxTypes = [kCGImageAuxiliaryDataTypeHDRGainMap]
            if #available(macOS 15, *) { auxTypes.insert(kCGImageAuxiliaryDataTypeISOGainMap, at: 0) }
            for auxType in auxTypes {
                if let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxType) {
                    CGImageDestinationAddAuxiliaryDataInfo(destination, auxType, info)
                    break
                }
            }
        }
        progress(0.7)
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else { throw ConvertError.encodeFailed(name: name) }
        let rotated = !resizing && orientation >= 5 && orientation <= 8
        return Result(width: rotated ? image.height : image.width, height: rotated ? image.width : image.height, notes: notes)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Composites onto white for JPEG, which has no transparency.
    static func flattened(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}

/// Video → looping GIF: frames from AVAssetImageGenerator, written one by one with ImageIO.
enum GIFMaker {
    struct Result {
        var width: Int
        var height: Int
        var frames: Int
    }

    /// Long edge and frame rate for this clip: the Quality's values, the Size limit if
    /// smaller, never bigger than the source.
    static func shape(_ info: MediaInfo, quality: Quality, size: SizeLimit) -> (width: Int, height: Int, fps: Double) {
        let q = QualityTable.gif(quality)
        let long = min(q.longEdge, size.box?.long ?? Int.max)
        let (w, h) = Planner.fit(info.displayWidth, info.displayHeight, in: (long, long))
        let fps = info.frameRate > 0 ? min(Double(q.fps), info.frameRate) : Double(q.fps)
        return (w, h, fps)
    }

    /// Frame delays in seconds, rounded to GIF's 1/100 s steps without drifting: the
    /// rounding error carries over, so 12 fps alternates 0.08 and 0.09.
    static func delays(count: Int, fps: Double) -> [Double] {
        var result: [Double] = []
        var exact = 0.0
        var written = 0
        for _ in 0..<count {
            exact += 100 / fps
            let next = Int(exact.rounded())
            result.append(Double(max(2, next - written)) / 100)
            written = max(next, written + 2)
        }
        return result
    }

    static func make(_ asset: AVURLAsset, info: MediaInfo, quality: Quality, size: SizeLimit, to output: URL,
                     name: String, progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        let shape = shape(info, quality: quality, size: size)
        let step = 1 / shape.fps
        let count = max(1, Int((info.duration / step).rounded(.down)))
        let times = (0..<count).map { CMTime(seconds: Double($0) * step, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: shape.width, height: shape.height)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)

        let writer = try GIFStreamWriter(url: output, width: shape.width, height: shape.height)
        var finished = false
        defer { if !finished { writer.abandon() } }

        let delays = delays(count: count, fps: shape.fps)
        var written = 0
        var last: CGImage?
        var outSize = (shape.width, shape.height)
        for await result in generator.images(for: times) {
            if Task.isCancelled {
                generator.cancelAllCGImageGeneration()
                throw CancellationError()
            }
            // A frame that can't be decoded repeats the one before, so timing stays right.
            guard let image = (try? result.image) ?? last else { continue }
            last = image
            outSize = (image.width, image.height)
            do {
                try autoreleasepool { try writer.add(image, delay: delays[written]) }
            } catch GIFStreamWriter.Failure.write {
                throw ConvertError.diskFull(name: output.lastPathComponent)
            } catch {
                throw ConvertError.encodeFailed(name: name)
            }
            written += 1
            progress(Double(written) / Double(count) * 0.98)
        }
        try Task.checkCancellation()
        guard written == count else { throw ConvertError.damaged(name: name) }
        do {
            try writer.finish()
            finished = true
        } catch {
            throw ConvertError.diskFull(name: output.lastPathComponent)
        }
        return Result(width: outSize.0, height: outSize.1, frames: written)
    }
}
