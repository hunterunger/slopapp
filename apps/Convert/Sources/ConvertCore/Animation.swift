import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import VideoToolbox

/// Animated images (GIF, PNG, WebP, HEICS) to video or GIF, frame by frame with ImageIO.
enum AnimationConverter {
    struct Result {
        var width: Int
        var height: Int
    }

    /// Each frame's display time in seconds, as browsers show them: delays under 0.02 s
    /// (often written as 0) play at 0.1 s. Empty when the file has no timing.
    static func delays(_ source: CGImageSource) -> [Double] {
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return [] }
        let dictionaries = [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary,
                            kCGImagePropertyWebPDictionary, kCGImagePropertyHEICSDictionary]
        let unclamped = [kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyAPNGUnclampedDelayTime,
                         kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyHEICSUnclampedDelayTime]
        let clamped = [kCGImagePropertyGIFDelayTime, kCGImagePropertyAPNGDelayTime,
                       kCGImagePropertyWebPDelayTime, kCGImagePropertyHEICSDelayTime]
        var result: [Double] = []
        for index in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            var delay: Double?
            for (i, key) in dictionaries.enumerated() {
                guard let dict = props[key] as? [CFString: Any] else { continue }
                delay = (dict[unclamped[i]] as? Double) ?? (dict[clamped[i]] as? Double)
                break
            }
            guard let delay else { return [] }
            result.append(delay < 0.02 ? 0.1 : delay)
        }
        return result
    }

    static func source(_ url: URL, name: String) throws -> (CGImageSource, [Double]) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ConvertError.damaged(name: name) }
        let delays = delays(source)
        guard !delays.isEmpty else { throw ConvertError.damaged(name: name) }
        return (source, delays)
    }

    static func toVideo(_ url: URL, info: MediaInfo, target: VideoTarget, fileType: AVFileType, quality: Quality,
                        size: SizeLimit, to output: URL, name: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        let (source, delays) = try source(url, name: name)
        let (width, height) = Planner.fit(info.width, info.height, in: size.box ?? Planner.h264Box, even: true)
        let (w, h) = (Planner.even(width), Planner.even(height))
        let codec: AVVideoCodecType = switch target {
        case .mp4HEVC: .hevc
        case .movProRes: .proRes422
        default: .h264
        }
        // Drawn in sRGB and tagged with the sRGB transfer function, so players show the
        // image's colours (untagged or Rec. 709-tagged came out visibly lighter).
        var settings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: w, AVVideoHeightKey: h,
                                       AVVideoColorPropertiesKey: [
                                           AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                           AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
                                           AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                                       ]]
        if codec != .proRes422 {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoQualityKey: QualityTable.videoQuality(quality)]
        }
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: output, fileType: fileType) } catch {
            throw ConvertError.cantWrite(folder: output.deletingLastPathComponent().lastPathComponent)
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw ConvertError.encodeFailed(name: name) }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ConvertError.encodeFailed(name: name) }
        writer.startSession(atSourceTime: .zero)

        var time = 0.0
        do {
            for (index, delay) in delays.enumerated() {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw ConvertError.encodeFailed(name: name) }
                    try await Task.sleep(for: .milliseconds(2))
                }
                try autoreleasepool {
                    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
                          let pool = adaptor.pixelBufferPool
                    else { throw ConvertError.damaged(name: name) }
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    guard let buffer, draw(image, into: buffer),
                          adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
                    else { throw ConvertError.encodeFailed(name: name) }
                }
                time += delay
                progress(Double(index + 1) / Double(delays.count) * 0.95)
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else { throw ConvertError.encodeFailed(name: name) }
        return Result(width: w, height: h)
    }

    static func toGIF(_ url: URL, info: MediaInfo, quality: Quality, size: SizeLimit, to output: URL, name: String,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        let (source, delays) = try source(url, name: name)
        let shape = GIFMaker.shape(info, quality: quality, size: size)
        let writer: GIFStreamWriter
        do { writer = try GIFStreamWriter(url: output, width: shape.width, height: shape.height) } catch {
            throw ConvertError.cantWrite(folder: output.deletingLastPathComponent().lastPathComponent)
        }
        var finished = false
        defer { if !finished { writer.abandon() } }
        for (index, delay) in delays.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(shape.width, shape.height),
                ] as CFDictionary) else { throw ConvertError.damaged(name: name) }
                do { try writer.add(frame, delay: delay) } catch { throw ConvertError.encodeFailed(name: name) }
            }
            progress(Double(index + 1) / Double(delays.count) * 0.95)
        }
        do { try writer.finish(); finished = true } catch { throw ConvertError.diskFull(name: output.lastPathComponent) }
        return Result(width: shape.width, height: shape.height)
    }

    /// Draws a frame onto white (video has no transparency), filling the buffer.
    static func draw(_ image: CGImage, into buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return false }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        return true
    }
}
