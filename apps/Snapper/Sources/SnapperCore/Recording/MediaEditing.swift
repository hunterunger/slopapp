import AVFoundation
import CoreMedia

/// The part of a recording to keep.
public struct TrimRange: Equatable, Sendable {
    public static let minimumLength: Double = 0.5

    public let start: Double
    public let end: Double
    public var length: Double { end - start }

    /// Clamped to `0…duration`; nil when what's left is shorter than `minimumLength`.
    public init?(start: Double, end: Double, duration: Double) {
        let start = max(0, min(start, duration)), end = max(0, min(end, duration))
        guard end - start >= Self.minimumLength else { return nil }
        self.start = start
        self.end = end
    }

    /// Within a frame of the whole recording: nothing to trim.
    public func isWhole(of duration: Double, tolerance: Double = 1.0 / 30) -> Bool {
        start <= tolerance && end >= duration - tolerance
    }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }
}

public enum MediaEditingError: LocalizedError {
    case cantExport(String)
    case nothingToMix

    public var errorDescription: String? {
        switch self {
        case .cantExport(let reason): "Couldn't write the video (\(reason))."
        case .nothingToMix: "The recording has no sound to mix."
        }
    }
}

/// Edits to finished recordings, without re-encoding the picture.
public enum MediaEditor {
    /// Copies `range` of `url` to `output` without re-encoding (passthrough). The cut starts
    /// at the keyframe before `range.start`; the file's edit list hides the frames before it,
    /// so players start exactly at the trim point.
    public static func trim(_ url: URL, to range: TrimRange, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MediaEditingError.cantExport("no export session")
        }
        session.timeRange = range.timeRange
        session.shouldOptimizeForNetworkUse = true
        if #available(macOS 15, *) {
            try await session.export(to: output, as: .mp4)
        } else {
            session.outputURL = output
            session.outputFileType = .mp4
            await session.export()
            if session.status != .completed {
                throw MediaEditingError.cantExport(session.error?.localizedDescription ?? "status \(session.status.rawValue)")
            }
        }
    }

    /// Writes `url` to `output` with all its audio tracks mixed into one AAC track (the
    /// computer's sound and the microphone). The picture is copied as is.
    public static func mixAudio(_ url: URL, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw MediaEditingError.nothingToMix }
        let duration = try await asset.load(.duration)
        var videoHint: CMFormatDescription?
        var transform = CGAffineTransform.identity
        if let video = videoTracks.first {
            videoHint = try await video.load(.formatDescriptions).first
            transform = try await video.load(.preferredTransform)
        }
        try await Task.detached(priority: .userInitiated) {
            try Remux.run(asset: asset, video: videoTracks.first, videoHint: videoHint, transform: transform,
                          audio: audioTracks, duration: duration, output: output)
        }.value
    }

    /// How many audio tracks a file has.
    public static func audioTrackCount(_ url: URL) async -> Int {
        (try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).count) ?? 0
    }

    /// Duration in seconds.
    public static func duration(of url: URL) async -> Double {
        (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
    }
}

/// AVAssetReader → AVAssetWriter: video passthrough, audio tracks mixed down.
private enum Remux {
    static let sampleRate: Double = 48_000

    static func run(asset: AVAsset, video: AVAssetTrack?, videoHint: CMFormatDescription?, transform: CGAffineTransform,
                    audio: [AVAssetTrack], duration: CMTime, output: URL) throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = []
        if let video {
            let out = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            out.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoHint)
            input.transform = transform
            guard reader.canAdd(out), writer.canAdd(input) else { throw MediaEditingError.cantExport("video track") }
            reader.add(out)
            writer.add(input)
            pairs.append((out, input))
        }
        let mixOut = AVAssetReaderAudioMixOutput(audioTracks: audio, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: AudioFormat.aac(channels: 2))
        guard reader.canAdd(mixOut), writer.canAdd(audioInput) else { throw MediaEditingError.cantExport("audio track") }
        reader.add(mixOut)
        writer.add(audioInput)
        pairs.append((mixOut, audioInput))

        guard reader.startReading() else { throw MediaEditingError.cantExport(reader.error?.localizedDescription ?? "reader") }
        guard writer.startWriting() else { throw MediaEditingError.cantExport(writer.error?.localizedDescription ?? "writer") }
        writer.startSession(atSourceTime: .zero)

        // Each track to its end on its own queue: the writer interleaves them (the inputs
        // aren't real-time, so it waits for whichever is behind).
        let group = DispatchGroup()
        let session = Unchecked(reader)
        for (index, pair) in pairs.enumerated() {
            group.enter()
            let queue = DispatchQueue(label: "app.slopapp.snapper.remux.\(index)")
            let track = Unchecked(pair)
            pair.1.requestMediaDataWhenReady(on: queue) {
                let (out, input) = track.value
                while input.isReadyForMoreMediaData {
                    let sample = out.copyNextSampleBuffer()
                    if let sample, input.append(sample) { continue }
                    if sample != nil { session.value.cancelReading() } // the writer failed
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
        group.wait()
        if reader.status == .failed {
            writer.cancelWriting()
            throw MediaEditingError.cantExport(reader.error?.localizedDescription ?? "reading")
        }
        writer.endSession(atSourceTime: duration)
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw MediaEditingError.cantExport(writer.error?.localizedDescription ?? "writing")
        }
    }
}

/// Hands AVFoundation objects to their own serial queue (each is used from one queue only).
private final class Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Writer settings for recordings' sound.
public enum AudioFormat {
    public static func aac(channels: Int, sampleRate: Double = 48_000) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 160_000 : 96_000,
        ]
    }
}
