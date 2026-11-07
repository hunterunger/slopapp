import AVFoundation
import CoreMedia
import Foundation
import os
import VideoToolbox

/// Reads an asset and writes it in a new container, copying or re-encoding each track as the
/// plan says. AVAssetReader → AVAssetWriter, streamed (memory stays flat for any length),
/// video and audio fed side by side (feeding one to the end first deadlocks the writer,
/// which interleaves them). Cancels within a sample of `Task` cancellation.
let log = Logger(subsystem: "app.slopapp.convert", category: "convert")

final class Transcoder: @unchecked Sendable {
    private let asset: AVAsset
    private let plan: TranscodePlan
    private let output: URL
    private let name: String
    /// A ready-made composition (merging): read every video track through it.
    private let videoComposition: AVVideoComposition?
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    init(asset: AVAsset, plan: TranscodePlan, output: URL, name: String, videoComposition: AVVideoComposition? = nil) {
        self.asset = asset
        self.plan = plan
        self.output = output
        self.name = name
        self.videoComposition = videoComposition
    }

    /// Returns notes for the row (e.g. that an undecodable ending was left out).
    @discardableResult
    func run(progress: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        let tracks = try await asset.load(.tracks)
        let duration = try await asset.load(.duration)
        let fullSeconds = duration.isNumeric && duration.seconds > 0 ? duration.seconds : 0
        let videoTrack = try await firstEnabled(tracks.filter { $0.mediaType == .video })
        let allAudio = tracks.filter { $0.mediaType == .audio }
        var audioTracks: [AVAssetTrack] = []
        switch plan.sound {
        case .all:
            for track in allAudio where (try? await track.load(.isEnabled)) ?? true { audioTracks.append(track) }
            if audioTracks.isEmpty, let first = allAudio.first { audioTracks = [first] }
        case .track(let index):
            if allAudio.indices.contains(index) { audioTracks = [allAudio[index]] }
        case .none:
            break
        }
        // Progress and the "bad ending" check count from the trim's start.
        let start = plan.trim?.start ?? 0
        let seconds = plan.trim.map { min($0.end, fullSeconds > 0 ? fullSeconds : $0.end) - $0.start } ?? fullSeconds

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: output, fileType: plan.fileType)
        } catch {
            log.error("reader/writer setup failed for \(self.name, privacy: .private): \(error)")
            throw ConvertError.damaged(name: name)
        }
        writer.shouldOptimizeForNetworkUse = plan.fileType == .mp4 || plan.fileType == .mov || plan.fileType == .m4a

        var pairs: [Pair] = []
        defer { activePairs.withLock { $0 = [] } }
        if let videoPlan = plan.video {
            guard let videoTrack else { throw ConvertError.damaged(name: name) }
            pairs.append(try await videoPair(videoPlan, track: videoTrack, reader: reader, writer: writer))
        }
        if plan.audio != .none {
            guard !audioTracks.isEmpty else { throw ConvertError.noSound(name: name) }
            pairs.append(try await audioPair(plan.audio, tracks: audioTracks, reader: reader, writer: writer))
        }
        if let urlAsset = asset as? AVURLAsset {
            writer.metadata = await Self.metadata(of: urlAsset, for: plan.fileType)
        }
        if let trim = plan.trim {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: trim.start, preferredTimescale: 600),
                                           end: CMTime(seconds: trim.end, preferredTimescale: 600))
        }

        guard reader.startReading() else {
            log.error("startReading failed: \(String(describing: reader.error))")
            throw ConvertError.damaged(name: name)
        }
        guard writer.startWriting() else {
            log.error("startWriting failed: \(String(describing: writer.error))")
            throw mapWriterError(writer.error)
        }
        // The new file starts where the trim does: earlier samples (a copied clip's lead-in
        // from the previous key frame) are cut by the file's edit list.
        writer.startSession(atSourceTime: CMTime(seconds: start, preferredTimescale: 600))

        let feeds = pairs
        activePairs.withLock { $0 = feeds }
        await withTaskCancellationHandler {
            await feed(feeds, start: start, seconds: seconds, writer: writer, progress: progress)
        } onCancel: {
            cancelled.withLock { $0 = true }
            abortAll()
        }
        // Let any sample being appended right now land before we finish or cancel.
        for pair in pairs { pair.queue.sync {} }

        if cancelled.withLock({ $0 }) || Task.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            throw CancellationError()
        }
        var notes: [String] = []
        if reader.status == .failed {
            log.error("reading failed: \(String(describing: reader.error))")
            // Files cut short by a recorder or a download often have a few bad frames at
            // the very end. Keep everything before them rather than failing the file.
            let reached = (pairs.first?.lastTime ?? 0) - start
            guard seconds > 0, reached >= seconds * 0.97, writer.status == .writing else {
                writer.cancelWriting()
                throw ConvertError.damaged(name: name)
            }
            notes.append("The last \(Self.shortDuration(seconds - reached)) couldn't be read, so \(seconds - reached < 1.5 ? "it was" : "they were") left out.")
        }
        if writer.status == .failed || pairs.contains(where: \.failed) {
            let error = writer.error
            log.error("writing failed: \(String(describing: error))")
            writer.cancelWriting()
            throw mapWriterError(error)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            log.error("finishing failed: \(String(describing: writer.error))")
            throw mapWriterError(writer.error)
        }
        progress(1)
        return notes
    }

    static func shortDuration(_ seconds: Double) -> String {
        seconds < 1.5 ? "moment" : "\(Int(seconds.rounded())) seconds"
    }

    // MARK: Tracks

    final class Pair: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
        let queue: DispatchQueue
        var failed = false
        /// Presentation time of the last sample appended, in seconds.
        var lastTime: Double = 0
        private let state = OSAllocatedUnfairLock<(finished: Bool, continuation: CheckedContinuation<Void, Never>?)>(
            initialState: (false, nil))

        func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
            let resumeNow = state.withLock { s -> Bool in
                if s.finished { return true }
                s.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }

        var isFinished: Bool { state.withLock { $0.finished } }

        /// Resumes the waiting feed, once.
        func finish() {
            let continuation = state.withLock { s -> CheckedContinuation<Void, Never>? in
                guard !s.finished else { return nil }
                s.finished = true
                defer { s.continuation = nil }
                return s.continuation
            }
            continuation?.resume()
        }

        init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String) {
            self.output = output
            self.input = input
            self.queue = DispatchQueue(label: "app.slopapp.convert.\(label)", qos: .userInitiated)
        }
    }

    private func videoPair(_ plan: VideoPlan, track: AVAssetTrack, reader: AVAssetReader, writer: AVAssetWriter) async throws -> Pair {
        let (formats, sourceTransform, naturalSize, frameRate) = try await track.load(.formatDescriptions, .preferredTransform, .naturalSize, .nominalFrameRate)
        // A turn travels as the track's matrix (lossless, like a phone's own rotation).
        let shown = CGRect(origin: .zero, size: naturalSize).applying(sourceTransform)
        let transform = self.plan.transform.isIdentity || self.plan.transform.mirrored
            ? sourceTransform
            : sourceTransform.concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
                .concatenating(self.plan.transform.affine(width: abs(shown.width), height: abs(shown.height)))
        let readerOutput: AVAssetReaderOutput
        let input: AVAssetWriterInput
        switch plan {
        case .copy:
            readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
        case .encode(let e):
            var readSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: e.keepHDR
                    ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                    : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ]
            if e.toSDR { readSettings[AVVideoColorPropertiesKey] = Self.rec709 }
            var composition = videoComposition
            if composition == nil, e.upright {
                composition = Self.uprightComposition(
                    track: track, naturalSize: naturalSize, sourceTransform: sourceTransform, turn: self.plan.transform,
                    renderSize: CGSize(width: e.width, height: e.height), frameRate: Double(frameRate),
                    duration: try await asset.load(.duration))
            }
            if let composition {
                // Drawn through a composition: every video track, upright, at the render size.
                let videoTracks = videoComposition == nil ? [track] : try await asset.loadTracks(withMediaType: .video)
                let composed = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                ])
                composed.videoComposition = composition
                readerOutput = composed
            } else {
                readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readSettings)
            }

            var compression: [String: Any] = [:]
            if let quality = e.quality { compression[AVVideoQualityKey] = quality }
            if e.frameRate > 0 { compression[AVVideoExpectedSourceFrameRateKey] = e.frameRate }
            switch e.codec {
            case .h264: compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            case .hevc:
                compression[AVVideoProfileLevelKey] = e.keepHDR
                    ? kVTProfileLevel_HEVC_Main10_AutoLevel as String
                    : kVTProfileLevel_HEVC_Main_AutoLevel as String
            case .proRes422: break
            }
            var settings: [String: Any] = [
                AVVideoCodecKey: e.codec.avCodec,
                AVVideoWidthKey: e.width,
                AVVideoHeightKey: e.height,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            ]
            if !compression.isEmpty { settings[AVVideoCompressionPropertiesKey] = compression }
            if e.toSDR || e.upright {
                settings[AVVideoColorPropertiesKey] = Self.rec709
            } else if let colors = formats.first.flatMap(Self.colorProperties) {
                settings[AVVideoColorPropertiesKey] = colors
            }
            guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
                throw ConvertError.encodeFailed(name: name)
            }
            input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        }
        readerOutput.alwaysCopiesSampleData = false
        if case .encode(let e) = plan, e.upright {
            input.transform = .identity
        } else {
            input.transform = transform
        }
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(readerOutput), writer.canAdd(input) else { throw ConvertError.encodeFailed(name: name) }
        reader.add(readerOutput)
        writer.add(input)
        return Pair(output: readerOutput, input: input, label: "video")
    }

    private func audioPair(_ plan: AudioPlan, tracks: [AVAssetTrack], reader: AVAssetReader, writer: AVAssetWriter) async throws -> Pair {
        let readerOutput: AVAssetReaderOutput
        let input: AVAssetWriterInput
        switch plan {
        case .none:
            preconditionFailure("no audio pair for .none")
        case .copy:
            let formats = try await tracks[0].load(.formatDescriptions)
            readerOutput = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: nil)
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formats.first)
        case .encode(let e):
            // Decode (and mix every enabled track) to float PCM at the target rate and layout.
            let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: e.sampleRate,
                AVNumberOfChannelsKey: e.channels,
            ])
            readerOutput = mix
            var settings: [String: Any] = [
                AVSampleRateKey: e.sampleRate,
                AVNumberOfChannelsKey: e.channels,
            ]
            switch e.format {
            case .aac(let bitRate):
                settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
                settings[AVEncoderBitRateKey] = bitRate
                // Constant: "256 kbps" means 256 kbps. The encoder's default undershoots a lot
                // on simple sound (a tone came out at ~50 kbps when asked for 160).
                settings[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_Constant
            case .alac(let bits):
                settings[AVFormatIDKey] = kAudioFormatAppleLossless
                settings[AVEncoderBitDepthHintKey] = bits
            case .pcm(let bits, let bigEndian):
                settings[AVFormatIDKey] = kAudioFormatLinearPCM
                settings[AVLinearPCMBitDepthKey] = bits
                settings[AVLinearPCMIsFloatKey] = false
                settings[AVLinearPCMIsBigEndianKey] = bigEndian
                settings[AVLinearPCMIsNonInterleaved] = false
            }
            guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
                throw ConvertError.encodeFailed(name: name)
            }
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        }
        readerOutput.alwaysCopiesSampleData = false
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(readerOutput), writer.canAdd(input) else { throw ConvertError.encodeFailed(name: name) }
        reader.add(readerOutput)
        writer.add(input)
        return Pair(output: readerOutput, input: input, label: "audio")
    }

    /// Feeds one track until the reader runs dry, the writer refuses, or we're cancelled.
    private func pump(_ pair: Pair, report: (@Sendable (CMTime) -> Void)?) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            pair.setContinuation(done)
            pair.input.requestMediaDataWhenReady(on: pair.queue) { [self] in
                while pair.input.isReadyForMoreMediaData {
                    if pair.isFinished { return }
                    if cancelled.withLock({ $0 }) {
                        pair.input.markAsFinished()
                        pair.finish()
                        return
                    }
                    let more: Bool = autoreleasepool {
                        guard let sample = pair.output.copyNextSampleBuffer() else {
                            pair.input.markAsFinished()
                            return false
                        }
                        if !pair.input.append(sample) {
                            pair.failed = true
                            return false
                        }
                        let time = CMSampleBufferGetPresentationTimeStamp(sample)
                        if time.isNumeric { pair.lastTime = max(pair.lastTime, time.seconds) }
                        report?(time)
                        return true
                    }
                    if !more {
                        pair.finish()
                        // A failed writer never asks the other tracks for more: stop them too.
                        if pair.failed { abortAll() }
                        return
                    }
                }
            }
        }
    }

    private let activePairs = OSAllocatedUnfairLock<[Pair]>(initialState: [])

    /// Ends every track's feed now (the writer failed or we're cancelled).
    private func abortAll() {
        activePairs.withLock { $0 }.forEach { $0.finish() }
    }

    /// Runs every track's feed side by side. The picture drives progress (it's most of the
    /// work); the sound does when there's no picture.
    private func feed(_ pairs: [Pair], start: Double, seconds: Double, writer: AVAssetWriter,
                      progress: @escaping @Sendable (Double) -> Void) async {
        nonisolated(unsafe) let writer = writer
        await withTaskGroup(of: Void.self) { group in
            for (index, pair) in pairs.enumerated() {
                var report: (@Sendable (CMTime) -> Void)?
                if index == 0, seconds > 0 {
                    report = { time in
                        if time.isNumeric { progress(min(0.99, max(0, time.seconds - start) / seconds)) }
                    }
                }
                let reporter = report
                group.addTask { await self.pump(pair, report: reporter) }
            }
            // A writer that fails (an encoder that gives up, a full disk) stops asking its
            // inputs for more, so their feeds would wait forever. Watch for it and stop them.
            group.addTask {
                while !pairs.allSatisfy(\.isFinished) {
                    if writer.status == .failed {
                        for pair in pairs { pair.failed = true }
                        self.abortAll()
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    private func firstEnabled(_ tracks: [AVAssetTrack]) async throws -> AVAssetTrack? {
        for track in tracks where (try? await track.load(.isEnabled)) ?? true {
            return track
        }
        return tracks.first
    }

    // MARK: Helpers

    /// Draws one video track upright (its own rotation, then `turn`), scaled to `renderSize`.
    static func uprightComposition(track: AVAssetTrack, naturalSize: CGSize, sourceTransform: CGAffineTransform,
                                   turn: PictureTransform, renderSize: CGSize, frameRate: Double,
                                   duration: CMTime) -> AVVideoComposition {
        let shown = CGRect(origin: .zero, size: naturalSize).applying(sourceTransform)
        var (w, h) = (abs(shown.width), abs(shown.height))
        var t = sourceTransform.concatenating(CGAffineTransform(translationX: -shown.minX, y: -shown.minY))
        t = t.concatenating(turn.affine(width: w, height: h))
        if turn.swapsSides { swap(&w, &h) }
        t = t.concatenating(CGAffineTransform(scaleX: renderSize.width / max(1, w), y: renderSize.height / max(1, h)))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(t, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate > 0 ? min(120, frameRate.rounded()) : 30))
        composition.instructions = [instruction]
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return composition
    }

    static var rec709: [String: Any] { [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ] }

    /// The source's color tags, so a re-encode keeps them (HDR stays HDR in HEVC).
    static func colorProperties(_ format: CMFormatDescription) -> [String: Any]? {
        let ext = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        guard let primaries = ext[kCVImageBufferColorPrimariesKey as String] as? String,
              let transfer = ext[kCVImageBufferTransferFunctionKey as String] as? String,
              let matrix = ext[kCVImageBufferYCbCrMatrixKey as String] as? String
        else { return nil }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
    }

    /// Title, artist, dates, location and so on, for containers that carry them.
    static func metadata(of asset: AVURLAsset, for fileType: AVFileType) async -> [AVMetadataItem] {
        guard [.mp4, .mov, .m4a].contains(fileType) else { return [] }
        let items = (try? await asset.load(.metadata)) ?? []
        let spaces: Set<AVMetadataKeySpace> = [.common, .quickTimeMetadata, .iTunes, .quickTimeUserData]
        return items.filter { $0.keySpace.map(spaces.contains) ?? false }
    }

    private func mapWriterError(_ error: (any Error)?) -> ConvertError {
        guard let error = error as NSError? else { return .encodeFailed(name: name) }
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        if error.code == AVError.diskFull.rawValue || error.code == NSFileWriteOutOfSpaceError
            || underlying?.code == Int(ENOSPC) || underlying?.code == NSFileWriteOutOfSpaceError {
            return .diskFull(name: output.lastPathComponent)
        }
        return .encodeFailed(name: name)
    }
}
