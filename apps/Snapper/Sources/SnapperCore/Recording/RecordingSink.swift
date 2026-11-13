import AVFoundation
import CoreMedia
import Foundation

public enum RecordingError: LocalizedError, Sendable {
    case sourceGone
    case noFrames
    case writerFailed(String)
    case refusedInTestMode

    public var errorDescription: String? {
        switch self {
        case .sourceGone: "The screen or window to record isn't available anymore."
        case .noFrames: "Nothing was recorded."
        case .writerFailed(let reason): "Couldn't write the recording (\(reason))."
        case .refusedInTestMode: "Test mode records only the test scene."
        }
    }
}

/// Writes a recording: screen frames as H.264 and, when asked, the computer's sound and the
/// microphone as one AAC track each. Every sample goes through one `RecordingTimeline`, so the
/// tracks line up and a pause leaves no gap. Samples are stamped on the host clock.
///
/// `appendFrame` and `appendAudio` must be called on `queue` (ScreenCaptureKit delivers there);
/// `appendMicrophone` from anywhere.
public final class RecordingSink: @unchecked Sendable {
    public enum AudioTrack: Sendable { case computer, microphone }

    public static let sampleRate: Double = 48_000
    public let queue = DispatchQueue(label: "app.slopapp.snapper.recording")
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let computerAudio: AVAssetWriterInput?
    private let microphoneAudio: AVAssetWriterInput?
    // Touched only on `queue`.
    private var timeline = RecordingTimeline()
    private var lastTime: CMTime = .zero
    private var lastBuffer: CVPixelBuffer?
    private var frames = 0
    private var audioSamples: [AudioTrack: Int] = [:]
    private var finished = false

    public init(url: URL, width: Int, height: Int, options: RecordingOptions) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        self.writer = writer
        let bitRate = max(1_000_000, width * height * 3)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // The frames are sRGB (the stream asks for it): say so, or players treat them as
            // untagged video and show them more saturated than the screen.
            AVVideoColorPropertiesKey: RecordingSink.colorProperties,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: options.frameRate,
                AVVideoMaxKeyFrameIntervalKey: options.keyframeInterval,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw RecordingError.writerFailed("no video input") }
        writer.add(input)
        func audioInput(channels: Int) throws -> AVAssetWriterInput {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: AudioFormat.aac(channels: channels, sampleRate: RecordingSink.sampleRate))
            audio.expectsMediaDataInRealTime = true
            guard writer.canAdd(audio) else { throw RecordingError.writerFailed("no audio input") }
            writer.add(audio)
            return audio
        }
        computerAudio = options.audio.computer ? try audioInput(channels: 2) : nil
        microphoneAudio = options.audio.microphone ? try audioInput(channels: 1) : nil
    }

    /// sRGB: BT.709 primaries and matrix with the sRGB transfer function.
    public static let colorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String, // AVVideoTransferFunction_IEC_sRGB is macOS 15+
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ]

    public static var hostNow: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    public func setPaused(_ value: Bool, at time: CMTime = RecordingSink.hostNow) {
        queue.async { [self] in
            if value { timeline.pause(at: time) } else { timeline.resume(at: time) }
        }
    }

    /// A complete screen frame captured at host time `time`. On `queue`.
    public func appendFrame(_ buffer: CVPixelBuffer, at time: CMTime) {
        guard !finished else { return }
        if !timeline.hasStarted {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            timeline.begin(at: time)
        }
        guard let fileTime = timeline.fileTime(for: time) else { return }
        guard fileTime > lastTime || frames == 0, input.isReadyForMoreMediaData else { return }
        if adaptor.append(buffer, withPresentationTime: fileTime) {
            lastTime = fileTime
            lastBuffer = buffer
            frames += 1
        }
    }

    /// Sound stamped on the host clock. On `queue`.
    public func appendAudio(_ sampleBuffer: CMSampleBuffer, track: AudioTrack) {
        let audio = track == .computer ? computerAudio : microphoneAudio
        guard !finished, let audio, timeline.hasStarted, writer.status == .writing,
              let time = timeline.fileTime(for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
              audio.isReadyForMoreMediaData,
              let moved = AudioSamples.retimed(sampleBuffer, to: time), audio.append(moved) else { return }
        audioSamples[track, default: 0] += CMSampleBufferGetNumSamples(moved)
    }

    /// A microphone buffer, from any queue.
    public func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        // Handed over, not shared: nothing else touches the buffer after this.
        nonisolated(unsafe) let buffer = sampleBuffer
        queue.async { [self] in appendAudio(buffer, track: .microphone) }
    }

    /// Finishes the file at host time `end` (when Stop was pressed) and returns its duration.
    public func finish(at end: CMTime = RecordingSink.hostNow) async throws -> TimeInterval {
        let result: Result<TimeInterval, Error> = await withCheckedContinuation { continuation in
            queue.async { [self] in
                finished = true
                guard frames > 0, writer.status == .writing else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: .failure(RecordingError.noFrames))
                    return
                }
                // The screen may have been still at the end: repeat the last frame so the
                // file lasts until Stop was pressed (or until the pause).
                let length = timeline.duration(at: end)
                if let lastBuffer, length > lastTime, input.isReadyForMoreMediaData,
                   adaptor.append(lastBuffer, withPresentationTime: length) {
                    lastTime = length
                }
                input.markAsFinished()
                computerAudio?.markAsFinished()
                microphoneAudio?.markAsFinished()
                writer.endSession(atSourceTime: lastTime)
                let duration = lastTime.seconds
                let box = WriterBox(writer)
                writer.finishWriting {
                    if box.writer.status == .completed {
                        continuation.resume(returning: .success(duration))
                    } else {
                        continuation.resume(returning: .failure(RecordingError.writerFailed(box.writer.error?.localizedDescription ?? "unknown")))
                    }
                }
            }
        }
        return try result.get()
    }

    /// How many sound samples each track got (diagnostics and tests).
    public func audioSampleCounts() async -> [AudioTrack: Int] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: audioSamples) }
        }
    }

    public func discard() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                finished = true
                if writer.status == .writing { writer.cancelWriting() }
                try? FileManager.default.removeItem(at: url)
                continuation.resume()
            }
        }
    }
}

private final class WriterBox: @unchecked Sendable {
    let writer: AVAssetWriter
    init(_ writer: AVAssetWriter) { self.writer = writer }
}
