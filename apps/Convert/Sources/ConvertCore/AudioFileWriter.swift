import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation

/// Writes decoded sound into a sound file of a format AVAssetWriter has no container for
/// (FLAC). An MP3 encoder (none ships with macOS) would be another `AudioFileEncoder`.
public protocol AudioFileEncoder: AnyObject {
    /// Interleaved 32-bit float at the file's rate and channel count.
    var processingFormat: AVAudioFormat { get }
    func write(_ buffer: AVAudioPCMBuffer) throws
    /// Writes out anything buffered and closes the file.
    func finish() throws
}

/// The system's encoders through `ExtAudioFile` (FLAC). Not `AVAudioFile`: it writes 24-bit
/// FLAC whatever it's asked for, and a 16-bit source should stay 16-bit.
final class SystemAudioFileEncoder: AudioFileEncoder {
    private var file: ExtAudioFileRef?
    let processingFormat: AVAudioFormat

    init(url: URL, encoding: AudioEncoding) throws {
        guard case .flac(let bits) = encoding.format else { throw AudioFileWriterError.unsupported }
        let channels = UInt32(encoding.channels)
        // FLAC keeps the source's bit depth in its format flags (1 = 16-bit … 4 = 32-bit).
        var fileFormat = AudioStreamBasicDescription(
            mSampleRate: encoding.sampleRate, mFormatID: kAudioFormatFLAC,
            mFormatFlags: [16: 1, 20: 2, 24: 3, 32: 4][bits] ?? 1, mBytesPerPacket: 0, mFramesPerPacket: 0,
            mBytesPerFrame: 0, mChannelsPerFrame: channels, mBitsPerChannel: 0, mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = encoding.layout ?? (channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo)
        var created: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(url as CFURL, kAudioFileFLACType, &fileFormat, &layout,
                                               AudioFileFlags.eraseFile.rawValue, &created)
        guard status == noErr, let created else { throw AudioFileWriterError.status(status) }
        guard let avLayout = AVAudioChannelLayout(layoutTag: layout.mChannelLayoutTag) else {
            ExtAudioFileDispose(created)
            throw AudioFileWriterError.unsupported
        }
        let client = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: encoding.sampleRate, interleaved: true,
                                   channelLayout: avLayout)
        var clientDescription = client.streamDescription.pointee
        status = ExtAudioFileSetProperty(created, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientDescription)
        guard status == noErr else {
            ExtAudioFileDispose(created)
            throw AudioFileWriterError.status(status)
        }
        file = created
        processingFormat = client
    }

    deinit { if let file { ExtAudioFileDispose(file) } }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let file else { return }
        let status = ExtAudioFileWrite(file, buffer.frameLength, buffer.audioBufferList)
        guard status == noErr else { throw AudioFileWriterError.status(status) }
    }

    func finish() throws {
        guard let file else { return }
        self.file = nil
        let status = ExtAudioFileDispose(file)
        guard status == noErr else { throw AudioFileWriterError.status(status) }
    }
}

enum AudioFileWriterError: Error {
    case unsupported
    case status(OSStatus)
}

/// Reads (and mixes) a file's sound, decoded, and feeds an `AudioFileEncoder`.
struct AudioFileTranscoder {
    let asset: AVAsset
    let plan: TranscodePlan
    let output: URL
    let name: String
    var makeEncoder: (URL, AudioEncoding) throws -> any AudioFileEncoder = { try SystemAudioFileEncoder(url: $0, encoding: $1) }

    func run(progress: @escaping @Sendable (Double) -> Void) async throws -> [String] {
        guard case .encode(let encoding) = plan.audio else { throw ConvertError.encodeFailed(name: name) }
        let all = try await asset.loadTracks(withMediaType: .audio)
        var tracks: [AVAssetTrack] = []
        switch plan.sound {
        case .all:
            for track in all where (try? await track.load(.isEnabled)) ?? true { tracks.append(track) }
            if tracks.isEmpty, let first = all.first { tracks = [first] }
        case .track(let index):
            if all.indices.contains(index) { tracks = [all[index]] }
        case .none:
            break
        }
        guard !tracks.isEmpty else { throw ConvertError.noSound(name: name) }
        let duration = try await asset.load(.duration)
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw ConvertError.damaged(name: name) }
        var settings = Transcoder.floatPCM(sampleRate: encoding.sampleRate, channels: encoding.channels)
        if let layout = encoding.layout { settings[AVChannelLayoutKey] = Transcoder.layoutData(layout) }
        let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        mix.alwaysCopiesSampleData = false
        guard reader.canAdd(mix) else { throw ConvertError.encodeFailed(name: name) }
        reader.add(mix)
        let start = plan.trim?.start ?? 0
        if let trim = plan.trim {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: trim.start, preferredTimescale: 600),
                                           end: CMTime(seconds: trim.end, preferredTimescale: 600))
        }
        let seconds = plan.trim?.duration ?? (duration.isNumeric ? duration.seconds : 0)
        let encoder: any AudioFileEncoder
        do { encoder = try makeEncoder(output, encoding) } catch {
            log.error("audio file encoder failed to open: \(error)")
            throw ConvertError.encodeFailed(name: name)
        }
        guard reader.startReading() else { throw ConvertError.damaged(name: name) }
        let format = encoder.processingFormat
        var lastReport = Date.distantPast
        while let sample = mix.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            try autoreleasepool {
                let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
                guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                buffer.frameLength = frames
                let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                                          into: buffer.mutableAudioBufferList)
                guard status == noErr else { throw ConvertError.damaged(name: name) }
                do { try encoder.write(buffer) } catch {
                    log.error("audio file write failed: \(error)")
                    throw ConvertError.diskFull(name: output.lastPathComponent)
                }
            }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            if seconds > 0, time.isNumeric, Date().timeIntervalSince(lastReport) > 0.1 {
                lastReport = Date()
                progress(min(0.99, max(0, time.seconds - start) / seconds))
            }
        }
        if reader.status == .failed { throw ConvertError.damaged(name: name) }
        do { try encoder.finish() } catch { throw ConvertError.encodeFailed(name: name) }
        progress(1)
        return []
    }
}
