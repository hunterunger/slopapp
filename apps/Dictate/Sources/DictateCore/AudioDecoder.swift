@preconcurrency import AVFoundation
import Foundation

/// Decodes any audio or video file AVFoundation can read (m4a, mp3, wav, aiff, caf, flac,
/// mp4, mov…) into 16 kHz mono Float32 samples, the input both speech engines expect.
/// Streams the file in chunks, so an hour-long recording doesn't need it all in memory twice.
public enum AudioDecoder {
    public static let sampleRate: Double = 16_000

    public enum DecodeError: LocalizedError, Equatable {
        case unreadable(String)
        case noAudio(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                "Couldn't read “\(name)”. It may not be an audio or video file, or it may be damaged."
            case .noAudio(let name):
                "“\(name)” has no sound to transcribe."
            case .failed(let name):
                "Couldn't decode the sound in “\(name)”. Try converting it to M4A or WAV first."
            }
        }
    }

    /// Samples at 16 kHz mono.
    public static func decode(url: URL) async throws -> [Float] {
        let name = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw DecodeError.unreadable(name)
        }
        guard !tracks.isEmpty else {
            // A file AVFoundation can't open at all also has no tracks: tell them apart.
            let playable = (try? await asset.load(.isReadable)) ?? false
            throw playable ? DecodeError.noAudio(name) : DecodeError.unreadable(name)
        }
        return try read(asset: asset, tracks: tracks, name: name)
    }

    private static func read(asset: AVAsset, tracks: [AVAssetTrack], name: String) throws -> [Float] {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw DecodeError.unreadable(name)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        // A mix output downmixes every audio track (and every channel) to one.
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw DecodeError.failed(name) }
        reader.add(output)
        guard reader.startReading() else { throw DecodeError.failed(name) }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            let status = samples.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
            guard status == kCMBlockBufferNoErr else { throw DecodeError.failed(name) }
        }
        guard reader.status == .completed else { throw DecodeError.failed(name) }
        return samples
    }

    /// "1:05" for 65 seconds of samples, "1:02:05" past an hour.
    public static func durationText(sampleCount: Int) -> String {
        let total = Int((Double(sampleCount) / sampleRate).rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
