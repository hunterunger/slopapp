import AudioToolbox
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
    /// Audio encoders by FourCC ("flac", "aac "…), from AudioToolbox.
    public var audioEncoders: Set<String>
    public var decoders: DecoderCapabilities

    public init(writableImageTypes: Set<String>, canEncodeHEVC: Bool, canEncodeProRes: Bool,
                audioEncoders: Set<String> = ["aac ", "alac", "lpcm", "flac"],
                decoders: DecoderCapabilities = DecoderCapabilities(vp9: true, av1: true)) {
        self.writableImageTypes = writableImageTypes
        self.canEncodeHEVC = canEncodeHEVC
        self.canEncodeProRes = canEncodeProRes
        self.audioEncoders = audioEncoders
        self.decoders = decoders
    }

    /// AudioToolbox's encoders, by FourCC.
    static func systemAudioEncoders() -> Set<String> {
        var size: UInt32 = 0
        guard AudioFormatGetPropertyInfo(kAudioFormatProperty_EncodeFormatIDs, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(size) / 4)
        guard AudioFormatGetProperty(kAudioFormatProperty_EncodeFormatIDs, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids.map(Codecs.fourCC))
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
            canEncodeProRes: codecs.contains(kCMVideoCodecType_AppleProRes422),
            audioEncoders: systemAudioEncoders(),
            decoders: .system
        )
    }()

    public func canWrite(_ target: AudioTarget) -> Bool {
        switch target {
        case .flac: audioEncoders.contains("flac")
        default: true
        }
    }

    public var audioTargets: [AudioTarget] { AudioTarget.allCases.filter(canWrite) }

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
    static func isNoOp(_ info: MediaInfo, inputType: UTType?, target: ImageTarget, size: SizeLimit,
                       fileSize: FileSizeLimit? = nil) -> Bool {
        guard let inputType, info.frameCount == 1 else { return false }
        if let fileSize, info.fileBytes == 0 || info.fileBytes > fileSize.bytes { return false }
        let same = inputType.conforms(to: target.type)
            || (target == .heic && inputType.conforms(to: .heif))
        let (w, h) = Planner.fit(info.width, info.height, in: size.box)
        return same && w == info.width && h == info.height
    }

    static func convert(_ url: URL, to output: URL, target: ImageTarget, quality: Quality, size: SizeLimit,
                        turn: PictureTransform = .identity, crop: CropRect? = nil, fileSize: FileSizeLimit? = nil,
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

        // A crop is in the picture as shown (upright).
        let rotated = orientation >= 5 && orientation <= 8
        let (uprightW, uprightH) = rotated ? (height, width) : (width, height)
        let cropPixels = crop.flatMap { $0.isWhole ? nil : $0.pixels(width: uprightW, height: uprightH) }
        let (fitW, fitH) = cropPixels.map { Planner.fit(Int($0.width), Int($0.height), in: size.box) }
            ?? Planner.fit(width, height, in: size.box)
        // Turned, mirrored or cropped pictures are decoded upright and redrawn, like resized ones.
        let resizing = fitW < width || fitH < height || !turn.isIdentity || cropPixels != nil
        let decoded: CGImage?
        if let cropPixels {
            // Upright at full size, then the crop, then down to the size limit.
            decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(uprightW, uprightH),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
                .flatMap { $0.cropping(to: cropPixels) }
                .flatMap { fitW < Int(cropPixels.width) ? scaled($0, width: fitW, height: fitH) : $0 }
        } else if resizing {
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
        if !turn.isIdentity {
            guard let turned = turned(image, by: turn) else { throw ConvertError.encodeFailed(name: name) }
            image = turned
        }
        progress(0.4)
        try Task.checkCancellation()

        if target == .jpeg, hasAlpha(image) {
            image = flattened(image) ?? image
        }

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
        let auxSource: CGImageSource? = !resizing && (target == .heic || target == .jpeg) ? source : nil

        /// Encodes `picture` at a lossy quality into a destination.
        func encode(_ picture: CGImage, quality q: Double, into destination: CGImageDestination) {
            var options = options
            if resizing || picture.width != image.width, var exif = options[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = picture.width
                exif[kCGImagePropertyExifPixelYDimension] = picture.height
                options[kCGImagePropertyExifDictionary] = exif
            }
            if target.isLossy { options[kCGImageDestinationLossyCompressionQuality] = q }
            CGImageDestinationAddImage(destination, picture, options as CFDictionary)
            // iPhone HDR photos keep their brightness (gain map) when the size doesn't change.
            if let auxSource, picture.width == image.width {
                var auxTypes = [kCGImageAuxiliaryDataTypeHDRGainMap]
                if #available(macOS 15, *) { auxTypes.insert(kCGImageAuxiliaryDataTypeISOGainMap, at: 0) }
                for auxType in auxTypes {
                    if let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(auxSource, 0, auxType) {
                        CGImageDestinationAddAuxiliaryDataInfo(destination, auxType, info)
                        break
                    }
                }
            }
        }
        let wanted = QualityTable.imageQuality(quality, target: target)

        if let fileSize, !(target.isLossy == false && fileSize.bytes <= 0) {
            // Aim at a size: the best quality that fits, then smaller pictures if none does.
            func data(_ picture: CGImage, _ q: Double) -> Data? {
                let buffer = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(buffer, target.type.identifier as CFString, 1, nil)
                else { return nil }
                encode(picture, quality: q, into: destination)
                return CGImageDestinationFinalize(destination) ? buffer as Data : nil
            }
            let limit = Int(fileSize.bytes)
            var picture = image
            var chosen: Data?
            var lowered = false
            for _ in 0..<6 {
                try Task.checkCancellation()
                guard let first = data(picture, wanted) else { throw ConvertError.encodeFailed(name: name) }
                if first.count <= limit { chosen = first; break }
                var tooBig = first.count
                if target.isLossy {
                    // Binary search between a floor and the asked-for quality.
                    var low = 0.1, high = wanted
                    var best: Data?
                    for _ in 0..<7 {
                        let mid = (low + high) / 2
                        guard let candidate = data(picture, mid) else { break }
                        if candidate.count <= limit { best = candidate; low = mid } else { high = mid; tooBig = candidate.count }
                    }
                    if let best { chosen = best; lowered = true; break }
                }
                // Even the lowest quality is too big: a smaller picture.
                let scale = max(0.3, min(0.9, (Double(limit) / Double(tooBig)).squareRoot() * 0.95))
                guard let smaller = scaled(picture, width: max(1, Int(Double(picture.width) * scale)),
                                           height: max(1, Int(Double(picture.height) * scale))) else { break }
                picture = smaller
            }
            guard let chosen else {
                throw ConvertError.cantFit(name: name, size: fileSize.title)
            }
            progress(0.8)
            do { try chosen.write(to: output) } catch { throw ConvertError.diskFull(name: output.lastPathComponent) }
            if picture.width != image.width {
                notes.append("Made \(picture.width)×\(picture.height) to fit in \(FileSizeLimit.number(fileSize.megabytes)) MB.")
            } else if lowered {
                notes.append("Quality lowered to fit in \(FileSizeLimit.number(fileSize.megabytes)) MB.")
            }
            return Result(width: picture.width, height: picture.height, notes: notes)
        }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, target.type.identifier as CFString, 1, nil)
        else { throw ConvertError.encodeFailed(name: name) }
        encode(image, quality: wanted, into: destination)
        progress(0.7)
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else { throw ConvertError.encodeFailed(name: name) }
        let shownRotated = !resizing && rotated
        return Result(width: shownRotated ? image.height : image.width, height: shownRotated ? image.width : image.height, notes: notes)
    }

    /// The picture drawn at a new size.
    static func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha: CGImageAlphaInfo = hasAlpha(image) ? .premultipliedLast : .noneSkipLast
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: image.bitsPerComponent > 8 ? 16 : 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// The picture turned and/or mirrored, drawn into a new bitmap.
    static func turned(_ image: CGImage, by turn: PictureTransform) -> CGImage? {
        let (w, h) = turn.swapsSides ? (image.height, image.width) : (image.width, image.height)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha: CGImageAlphaInfo = hasAlpha(image) ? .premultipliedLast : .noneSkipLast
        let bits = image.bitsPerComponent > 8 ? 16 : 8
        let info = alpha.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: bits, bytesPerRow: 0,
                                  space: space, bitmapInfo: info) else { return nil }
        // CoreGraphics has y up; the turn is defined with y down, so flip around it.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(h))
        let down = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(image.height))
        ctx.concatenate(down.concatenating(turn.affine(width: Double(image.width), height: Double(image.height)))
            .concatenating(flip))
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
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
    static func shape(_ info: MediaInfo, quality: Quality, size: SizeLimit,
                      turn: PictureTransform = .identity, crop: CropRect? = nil) -> (width: Int, height: Int, fps: Double) {
        let q = QualityTable.gif(quality)
        let long = min(q.longEdge, size.box?.long ?? Int.max)
        var (cw, ch) = (info.displayWidth, info.displayHeight)
        if let crop {
            let pixels = crop.pixels(width: cw, height: ch)
            (cw, ch) = (Int(pixels.width), Int(pixels.height))
        }
        let (dw, dh) = turn.swapsSides ? (ch, cw) : (cw, ch)
        let (w, h) = Planner.fit(dw, dh, in: (long, long))
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

    static func make(_ asset: AVURLAsset, info: MediaInfo, quality: Quality, size: SizeLimit,
                     trim: TrimRange? = nil, turn: PictureTransform = .identity, crop: CropRect? = nil,
                     subtitles: SubtitleOverlay? = nil, shape fixed: (width: Int, height: Int, fps: Double)? = nil,
                     to output: URL, name: String, progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        let shape = fixed ?? shape(info, quality: quality, size: size, turn: turn, crop: crop)
        let step = 1 / shape.fps
        let start = trim.map { $0.isWhole(of: info.duration) ? 0 : $0.start } ?? 0
        let end = trim.map { $0.isWhole(of: info.duration) ? info.duration : min($0.end, info.duration) } ?? info.duration
        let count = max(1, Int(((end - start) / step).rounded(.down)))
        let times = (0..<count).map { CMTime(seconds: start + Double($0) * step, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if !turn.isIdentity || crop != nil || subtitles != nil, let track = try await asset.loadTracks(withMediaType: .video).first {
            // Turned, mirrored, cropped or captioned: draw the frames through a composition,
            // straight at the GIF's size.
            let (natural, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
            let cropPixels = crop.map { $0.pixels(width: info.displayWidth, height: info.displayHeight) }
            generator.videoComposition = Transcoder.uprightComposition(
                track: track, naturalSize: natural, sourceTransform: transform, turn: turn, crop: cropPixels,
                renderSize: CGSize(width: shape.width, height: shape.height),
                frameRate: Double(rate), duration: try await asset.load(.duration), subtitles: subtitles)
        }
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
