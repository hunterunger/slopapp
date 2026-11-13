import AVFoundation
import CoreImage
import ScreenCaptureKit
import SnapperCore

/// Records part of the screen to an H.264 MP4, with the computer's sound and the microphone
/// as AAC when asked. Behind a protocol so the flow can be faked.
@MainActor
protocol ScreenRecording: AnyObject {
    /// Starts streaming `plan` into a new MP4 at `url`. `keepWindows`: our own windows to
    /// keep in the recording (pins, the camera bubble, the click and key overlay); every other
    /// window of ours is left out. `microphone`: where the microphone's samples come from when
    /// `options.audio.microphone` is on.
    func start(plan: RecordingPlan, options: RecordingOptions, keepWindows: Set<CGWindowID>,
               microphone: SampleTap?, to url: URL) async throws
    func setPaused(_ paused: Bool)
    /// Stops and finishes the file. Returns the recorded duration in seconds.
    func stop() async throws -> TimeInterval
    /// Stops and throws the file away.
    func cancel() async
}

/// ScreenCaptureKit stream (+ microphone) → AVAssetWriter.
@MainActor
final class StreamRecorder: ScreenRecording {
    private var stream: SCStream?
    private var sink: RecordingSink?
    private var output: StreamOutput?
    private var microphone: SampleTap?
    private var url: URL?

    func start(plan: RecordingPlan, options: RecordingOptions, keepWindows: Set<CGWindowID>,
               microphone: SampleTap?, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let filter: SCContentFilter
        var testMode = false
        var sourceRect = plan.sourceRect
        switch plan.source {
        case .display(let id):
            guard let display = content.displays.first(where: { $0.displayID == id }) else { throw RecordingError.sourceGone }
            let own = content.applications.filter { $0.processID == ownPID }
            let keep = content.windows.filter { $0.owningApplication?.processID == ownPID && keepWindows.contains($0.windowID) }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: keep)
        case .testScene(let sceneID, let displayID):
            // Only our own windows: the scene and the overlays. Nothing else on screen, not
            // even surfaces no app owns, can be in the stream.
            guard let scene = content.windows.first(where: { $0.windowID == sceneID && $0.owningApplication?.processID == ownPID }) else {
                Diagnostics.record("test scene not shareable displays=\(content.displays.count) windows=\(content.windows.count)")
                throw RecordingError.sourceGone
            }
            if let display = content.displays.first(where: { $0.displayID == displayID }) {
                let windows = content.windows.filter {
                    $0.owningApplication?.processID == ownPID && ($0.windowID == sceneID || keepWindows.contains($0.windowID))
                }
                filter = SCContentFilter(display: display, including: windows)
            } else {
                // The display isn't shareable (asleep or locked): the scene window on its own,
                // without the overlays, so scripted tests of sound, pause and trim still run.
                filter = SCContentFilter(desktopIndependentWindow: scene)
                sourceRect = plan.screenRect.offsetBy(dx: -scene.frame.minX, dy: -scene.frame.minY)
                Diagnostics.record("test scene recorded as a window (display not shareable)")
            }
            testMode = true
        }
        let scale = options.scaleToOneX ? 1 : CGFloat(filter.pointPixelScale)
        let size = RecordingPlan.pixelSize(for: sourceRect, scale: scale)
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.frameRate)))
        config.showsCursor = options.showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 8
        config.scalesToFit = false
        config.capturesAudio = options.audio.computer
        if options.audio.computer {
            config.sampleRate = Int(RecordingSink.sampleRate)
            config.channelCount = 2
            // Snapper's own sounds stay out, except the test scene's tone in test mode (the
            // stream there holds only our windows, so it's the only sound it can hear).
            config.excludesCurrentProcessAudio = !testMode
        }

        let sink = try RecordingSink(url: url, width: size.width, height: size.height, options: options)
        let output = StreamOutput(sink: sink)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sink.queue)
        if options.audio.computer {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sink.queue)
        }
        if options.audio.microphone, let microphone {
            microphone.setConsumer { [sink] buffer in sink.appendMicrophone(buffer) }
            self.microphone = microphone
        }
        do {
            try await stream.startCapture()
        } catch {
            self.microphone?.setConsumer(nil)
            self.microphone = nil
            await sink.discard()
            throw error
        }
        self.stream = stream
        self.sink = sink
        self.output = output
        self.url = url
    }

    func setPaused(_ paused: Bool) {
        sink?.setPaused(paused)
    }

    func stop() async throws -> TimeInterval {
        guard let stream, let sink, let url else { throw RecordingError.noFrames }
        self.stream = nil
        self.sink = nil
        microphone?.setConsumer(nil)
        microphone = nil
        try? await stream.stopCapture()
        let duration = try await sink.finish()
        // Two sound tracks (computer + microphone): mix them into one, since most players
        // and chat apps play only the first. The picture is copied, not re-encoded.
        if await MediaEditor.audioTrackCount(url) > 1 {
            let started = Diagnostics.now()
            let mixed = url.deletingLastPathComponent().appendingPathComponent(".mixing.mp4")
            do {
                try await MediaEditor.mixAudio(url, output: mixed)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: mixed)
                Diagnostics.record("recording audio mixed ms=\(Diagnostics.milliseconds(since: started))")
            } catch {
                // The two-track file still plays everywhere QuickTime does: keep it.
                try? FileManager.default.removeItem(at: mixed)
                Diagnostics.record("recording audio mix failed error=\(error)")
            }
        }
        return duration
    }

    func cancel() async {
        guard let stream, let sink else { return }
        self.stream = nil
        self.sink = nil
        microphone?.setConsumer(nil)
        microphone = nil
        try? await stream.stopCapture()
        await sink.discard()
    }
}

/// Hands ScreenCaptureKit's frames and sound to the sink (on the sink's queue).
final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let sink: RecordingSink

    init(sink: RecordingSink) { self.sink = sink }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
                  let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            sink.appendFrame(buffer, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        case .audio:
            sink.appendAudio(sampleBuffer, track: .computer)
        default:
            break
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
