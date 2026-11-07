import AVFoundation
import Foundation
import Testing
@testable import DictateCore

@Suite("Audio")
struct AudioTests {
    static func sine(hz: Float, seconds: Float, rate: Float = 16_000, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * sin(2 * .pi * hz * Float($0) / rate) }
    }

    func analyse(_ samples: [Float]) -> [AudioFeatures] {
        let extractor = FeatureExtractor()
        var out: [AudioFeatures] = []
        samples.withUnsafeBufferPointer { buffer in
            extractor.consume(buffer.baseAddress!, count: buffer.count) { out.append($0) }
        }
        return out
    }

    @Test func silenceIsQuiet() {
        let features = analyse(Array(repeating: 0, count: 16_000))
        #expect(features.count == 30)   // one window per 512 samples after the first 1024
        #expect(features.allSatisfy { $0.level == 0 && !$0.voiced && $0.onset == 0 })
        #expect(features.last?.index == 30)
    }

    @Test func aToneIsLoudVoicedAndLowBandHeavy() {
        let features = analyse(Self.sine(hz: 220, seconds: 1))
        let last = features.last!
        #expect(last.level > 0.8)
        #expect(last.voiced)
        // 220 Hz sits in the lowest bands.
        #expect(last.bands[0] + last.bands[1] > last.bands[5] + last.bands[6])
        #expect(last.brightness < 0.3)
    }

    @Test func pitchRisesAboveTheBaseline() {
        // A long low tone sets the baseline; a higher one reads as positive pitch.
        let features = analyse(Self.sine(hz: 150, seconds: 2) + Self.sine(hz: 260, seconds: 0.3))
        #expect(features.last!.pitch > 0.3)
    }

    @Test func hissIsBright() {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<16_000).map { _ in Float.random(in: -0.3...0.3, using: &generator) }
        #expect(analyse(noise).last!.brightness > 0.6)
    }

    @Test func decodesAStereo44kFileTo16kMono() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let frames = AVAudioFrameCount(44_100)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            let tone = Self.sine(hz: 440, seconds: 1, rate: 44_100)
            for channel in 0..<2 {
                tone.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: tone.count) }
            }
            try file.write(from: buffer)
        }
        let samples = try await AudioDecoder.decode(url: url)
        #expect(abs(samples.count - 16_000) < 200)
        // Downmixing keeps the level in the same range (the exact gain is AVFoundation's call).
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.3 && peak <= 1.0, "peak \(peak)")
        #expect(AudioDecoder.durationText(sampleCount: samples.count) == "0:01")
    }

    @Test func notAudioSaysSo() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("notes.txt")
        try Data("just text".utf8).write(to: url)
        await #expect(throws: AudioDecoder.DecodeError.unreadable("notes.txt")) {
            _ = try await AudioDecoder.decode(url: url)
        }
    }

    @Test func durations() {
        #expect(AudioDecoder.durationText(sampleCount: 16_000 * 65) == "1:05")
        #expect(AudioDecoder.durationText(sampleCount: 16_000 * 3_725) == "1:02:05")
    }
}
