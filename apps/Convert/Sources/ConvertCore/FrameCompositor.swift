import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

/// Everything one redrawn picture needs: where the stored pixels go (turned, mirrored,
/// cropped, scaled), and the subtitles to draw on top.
final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    /// Stored pixels (y down) → output pixels (y down).
    let transform: CGAffineTransform
    let renderSize: CGSize
    let subtitles: SubtitleOverlay?

    init(trackID: CMPersistentTrackID, timeRange: CMTimeRange, transform: CGAffineTransform, renderSize: CGSize,
         subtitles: SubtitleOverlay?) {
        self.trackID = trackID
        self.timeRange = timeRange
        self.transform = transform
        self.renderSize = renderSize
        self.subtitles = subtitles
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Draws frames with Core Image: the instruction's transform, black where the picture
/// doesn't reach, then any subtitle line. Pixel values pass through untouched (no colour
/// matching), as AVFoundation's own compositor does; the output is tagged Rec. 709.
final class FrameCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull(),
                                                     .outputColorSpace: NSNull()])

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
                  let source = request.sourceFrame(byTrackID: instruction.trackID),
                  let output = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decodeFailed.rawValue))
                return
            }
            let size = instruction.renderSize
            let image = Self.compose(source: CIImage(cvPixelBuffer: source), sourceHeight: Double(CVPixelBufferGetHeight(source)),
                                     transform: instruction.transform, renderSize: size)
            var composed = image
            if let subtitles = instruction.subtitles,
               let line = subtitles.image(at: request.compositionTime.seconds, width: Int(size.width), height: Int(size.height)) {
                composed = CIImage(cgImage: line.image)
                    .transformed(by: CGAffineTransform(translationX: line.origin.x, y: line.origin.y))
                    .composited(over: composed)
            }
            Self.context.render(composed, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: nil)
            request.finish(withComposedVideoFrame: output)
        }
    }

    /// The source frame placed in the output: `transform` is y-down (as track matrices and
    /// `PictureTransform.affine` are); Core Image is y-up, so flip around both heights.
    static func compose(source: CIImage, sourceHeight: Double, transform: CGAffineTransform, renderSize: CGSize) -> CIImage {
        let flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
        let placed = source.transformed(by: flipIn.concatenating(transform).concatenating(flipOut), highQualityDownsample: true)
        let frame = CGRect(origin: .zero, size: renderSize)
        return placed.composited(over: CIImage(color: CIColor.black).cropped(to: frame)).cropped(to: frame)
    }
}

extension Transcoder {
    /// Where a track's stored pixels go in an upright, cropped, turned and scaled picture.
    /// `crop` is in the picture as the file shows it (after its own rotation), before `turn`.
    static func uprightTransform(naturalSize: CGSize, sourceTransform: CGAffineTransform, turn: PictureTransform,
                                 crop: CGRect?, renderSize: CGSize) -> CGAffineTransform {
        let shown = CGRect(origin: .zero, size: naturalSize).applying(sourceTransform)
        var t = sourceTransform.concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
        var (w, h) = (abs(shown.width), abs(shown.height))
        if let crop {
            t = t.concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            (w, h) = (crop.width, crop.height)
        }
        t = t.concatenating(turn.affine(width: w, height: h))
        if turn.swapsSides { swap(&w, &h) }
        return t.concatenating(CGAffineTransform(scaleX: renderSize.width / max(1, w), y: renderSize.height / max(1, h)))
    }

    /// A composition that draws one video track through `FrameCompositor`.
    static func uprightComposition(track: AVAssetTrack, naturalSize: CGSize, sourceTransform: CGAffineTransform,
                                   turn: PictureTransform, crop: CGRect? = nil, renderSize: CGSize, frameRate: Double,
                                   duration: CMTime, subtitles: SubtitleOverlay? = nil) -> AVVideoComposition {
        let transform = uprightTransform(naturalSize: naturalSize, sourceTransform: sourceTransform, turn: turn,
                                         crop: crop, renderSize: renderSize)
        let instruction = FrameInstruction(trackID: track.trackID, timeRange: CMTimeRange(start: .zero, duration: duration),
                                           transform: transform, renderSize: renderSize, subtitles: subtitles)
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = FrameCompositor.self
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? min(120, frameRate.rounded()) : 30))
        composition.instructions = [instruction]
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return composition
    }
}
