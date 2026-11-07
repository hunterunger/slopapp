import AVFoundation
import CoreImage
import ScreenCaptureKit
import SnapperCore

/// Records part of the screen to an H.264 MP4. Behind a protocol so the flow can be faked.
@MainActor
protocol ScreenRecording: AnyObject {
    /// Starts streaming `plan` into a new MP4 at `url`. `keepWindows`: our own windows to
    /// keep in a display recording (pins); every other window of ours is left out.
    func start(plan: RecordingPlan, options: RecordingOptions, keepWindows: Set<CGWindowID>, to url: URL) async throws
    func setPaused(_ paused: Bool)
    /// Stops and finishes the file. Returns the recorded duration in seconds.
    func stop() async throws -> TimeInterval
    /// Stops and throws the file away.
    func cancel() async
}

enum RecordingError: LocalizedError {
    case sourceGone
    case noFrames
    case writerFailed(String)
    case refusedInTestMode

    var errorDescription: String? {
        switch self {
        case .sourceGone: "The screen or window to record isn't available anymore."
        case .noFrames: "Nothing was recorded."
        case .writerFailed(let reason): "Couldn't write the recording (\(reason))."
        case .refusedInTestMode: "Test mode records only the test scene."
        }
    }
}

/// ScreenCaptureKit stream → AVAssetWriter.
@MainActor
final class StreamRecorder: ScreenRecording {
    private var stream: SCStream?
    private var sink: RecordingSink?

    func start(plan: RecordingPlan, options: RecordingOptions, keepWindows: Set<CGWindowID>, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        switch plan.source {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw RecordingError.sourceGone }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let own = content.applications.filter { $0.processID == ownPID }
            let keep = content.windows.filter { $0.owningApplication?.processID == ownPID && keepWindows.contains($0.windowID) }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: keep)
        case .window(let id):
            // One window on its own: nothing else on screen can appear in the stream.
            guard let window = content.windows.first(where: { $0.windowID == id }) else { throw RecordingError.sourceGone }
            filter = SCContentFilter(desktopIndependentWindow: window)
        }
        let scale = options.scaleToOneX ? 1 : CGFloat(filter.pointPixelScale)
        let size = RecordingPlan.pixelSize(for: plan.sourceRect, scale: scale)
        let config = SCStreamConfiguration()
        config.sourceRect = plan.sourceRect
        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.frameRate)))
        config.showsCursor = options.showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 8
        config.capturesAudio = false
        config.scalesToFit = false

        let sink = try RecordingSink(url: url, width: size.width, height: size.height, frameRate: options.frameRate)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        self.stream = stream
        self.sink = sink
    }

    func setPaused(_ paused: Bool) {
        sink?.setPaused(paused)
    }

    func stop() async throws -> TimeInterval {
        guard let stream, let sink else { throw RecordingError.noFrames }
        self.stream = nil
        self.sink = nil
        try? await stream.stopCapture()
        return try await sink.finish()
    }

    func cancel() async {
        guard let stream, let sink else { return }
        self.stream = nil
        self.sink = nil
        try? await stream.stopCapture()
        await sink.discard()
    }
}

/// Receives frames on its own queue and appends them to the writer. Pausing drops frames
/// and shifts later timestamps back, so the file has no gap.
final class RecordingSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.slopapp.snapper.recording")
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    // Touched only on `queue`.
    private var startTime: CMTime?
    private var lastTime: CMTime = .zero
    private var lastBuffer: CVPixelBuffer?
    private var paused = false
    private var pausedAt: CMTime?
    private var pausedTotal: CMTime = .zero
    private var frames = 0

    init(url: URL, width: Int, height: Int, frameRate: Int) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitRate = max(1_000_000, width * height * 3)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw RecordingError.writerFailed("no video input") }
        writer.add(input)
        super.init()
    }

    func setPaused(_ value: Bool) {
        queue.async { [self] in
            guard value != paused else { return }
            paused = value
            if value {
                pausedAt = lastTime
            } else if pausedAt != nil {
                // The next frame decides how long the pause was (see `stream`).
                pausedAt = .invalid
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, !paused else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if startTime == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            startTime = now
        }
        guard let startTime else { return }
        if pausedAt == .invalid {
            // Resumed: the gap since the last kept frame (minus one frame) doesn't count.
            let raw = CMTimeSubtract(CMTimeSubtract(now, startTime), pausedTotal)
            let gap = CMTimeSubtract(raw, lastTime)
            pausedTotal = CMTimeAdd(pausedTotal, CMTimeMaximum(.zero, CMTimeSubtract(gap, CMTime(value: 1, timescale: 30))))
            pausedAt = nil
        }
        let time = CMTimeSubtract(CMTimeSubtract(now, startTime), pausedTotal)
        guard time > lastTime || frames == 0, input.isReadyForMoreMediaData else { return }
        if adaptor.append(buffer, withPresentationTime: time) {
            lastTime = time
            lastBuffer = buffer
            frames += 1
        }
    }

    /// Finishes the file and returns its duration.
    func finish() async throws -> TimeInterval {
        let result: Result<TimeInterval, Error> = await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard frames > 0, writer.status == .writing else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: .failure(RecordingError.noFrames))
                    return
                }
                // The screen may have been still at the end: repeat the last frame so the
                // file lasts until Stop was pressed.
                if let startTime, let lastBuffer, !paused, input.isReadyForMoreMediaData {
                    let now = CMTimeSubtract(CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), startTime), pausedTotal)
                    if now > lastTime, adaptor.append(lastBuffer, withPresentationTime: now) { lastTime = now }
                }
                input.markAsFinished()
                writer.endSession(atSourceTime: lastTime)
                let duration = lastTime.seconds
                writer.finishWriting { [writer] in
                    if writer.status == .completed {
                        continuation.resume(returning: .success(duration))
                    } else {
                        continuation.resume(returning: .failure(RecordingError.writerFailed(writer.error?.localizedDescription ?? "unknown")))
                    }
                }
            }
        }
        return try result.get()
    }

    func discard() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if writer.status == .writing { writer.cancelWriting() }
                try? FileManager.default.removeItem(at: url)
                continuation.resume()
            }
        }
    }
}

/// Frames out of a finished recording: the poster and GIF conversion.
enum VideoFrames {
    static func poster(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        return try? await generator.image(at: .zero).image
    }

    /// Converts a recording to an animated GIF next to it. Returns the GIF's URL.
    static func makeGIF(from url: URL, options: GIFEncoder.Options) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(value: 1, timescale: CMTimeScale(max(2, options.frameRate * 2)))
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        generator.maximumSize = CGSize(width: options.maxWidth, height: options.maxWidth * 4)
        let times = GIFEncoder.sampleTimes(duration: duration, frameRate: options.frameRate)
            .map { CMTime(seconds: $0, preferredTimescale: 600) }
        var frames: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image, let scaled = GIFEncoder.scaled(image, maxWidth: options.maxWidth) {
                frames.append(scaled)
            }
        }
        let gifURL = url.deletingPathExtension().appendingPathExtension("gif")
        let delay = 1 / Double(max(1, options.frameRate))
        let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            guard let data = GIFEncoder.data(frames: frames, delay: delay) else { throw RecordingError.writerFailed("GIF") }
            return data
        }.value
        try data.write(to: gifURL, options: .atomic)
        return gifURL
    }
}
