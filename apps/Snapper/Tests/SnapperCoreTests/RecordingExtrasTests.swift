import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import SnapperCore

private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) }

@Suite("Recording timeline")
struct RecordingTimelineTests {
    @Test func samplesBeforeTheFirstFrameAreDropped() throws {
        var timeline = RecordingTimeline()
        #expect(timeline.fileTime(for: t(100)) == nil)
        timeline.begin(at: t(100))
        timeline.begin(at: t(200)) // only the first frame starts the file
        #expect(timeline.fileTime(for: t(99.9)) == nil)
        #expect(try #require(timeline.fileTime(for: t(100.5))).seconds == 0.5)
    }

    @Test func pausesLeaveNoGapAndDropWhatHappensInThem() throws {
        var timeline = RecordingTimeline()
        timeline.begin(at: t(10))
        timeline.pause(at: t(12))
        #expect(timeline.isPaused)
        #expect(timeline.fileTime(for: t(13)) == nil)
        // A paused file is as long as it was when it paused.
        #expect(abs(timeline.duration(at: t(15)).seconds - 2) < 1e-6)
        timeline.resume(at: t(20))
        #expect(!timeline.isPaused)
        #expect(abs(try #require(timeline.fileTime(for: t(11))).seconds - 1) < 1e-6)
        #expect(abs(try #require(timeline.fileTime(for: t(20.5))).seconds - 2.5) < 1e-6)
        timeline.pause(at: t(21))
        timeline.resume(at: t(30))
        #expect(abs(try #require(timeline.fileTime(for: t(31))).seconds - 4) < 1e-6)
        #expect(abs(timeline.duration(at: t(32)).seconds - 5) < 1e-6)
        // A sample stamped just before the pause still counts.
        #expect(abs(try #require(timeline.fileTime(for: t(20.99))).seconds - 2.99) < 1e-6)
    }
}

@Suite("Audio samples and levels")
struct AudioTests {
    @Test func buffersRoundTripTheirSamplesAndCanMove() throws {
        var tone = ToneGenerator(frequency: 440, amplitude: 0.5)
        let samples = tone.next(4800)
        let buffer = try #require(AudioSamples.makeBuffer(samples, time: t(3)))
        #expect(CMSampleBufferGetNumSamples(buffer) == 4800)
        let read = try #require(AudioSamples.floats(in: buffer))
        #expect(read == samples)
        let moved = try #require(AudioSamples.retimed(buffer, to: t(1)))
        #expect(abs(CMSampleBufferGetPresentationTimeStamp(moved).seconds - 1) < 1e-6)
        #expect(AudioSamples.floats(in: moved) == samples)
    }

    @Test func levelsFollowLoudness() {
        var tone = ToneGenerator(frequency: 1000, amplitude: 0.5)
        let rms = AudioLevel.rms(tone.next(48_000))
        #expect(abs(rms - 0.5 / 2.0.squareRoot().float) < 0.01)
        #expect(AudioLevel.meter(rms: 0) == 0)
        #expect(AudioLevel.meter(rms: 1) == 1)
        #expect(AudioLevel.meter(rms: 0.001) == 0) // -60 dB: below the floor
        let quiet = AudioLevel.meter(rms: 0.01), loud = AudioLevel.meter(rms: 0.3)
        #expect(quiet > 0 && quiet < loud && loud < 1)
    }

    @Test func theMeterJumpsUpAndFallsBackSlowly() {
        var meter = LevelMeter()
        meter.feed(0.8, elapsed: 0.05)
        #expect(meter.value == 0.8)
        meter.feed(0, elapsed: 0.1)
        #expect(meter.value > 0.6 && meter.value < 0.8)
        meter.feed(0, elapsed: 2)
        #expect(meter.value == 0)
    }

    @Test func toneDetectionTellsFrequenciesApart() {
        var low = ToneGenerator(frequency: 440), high = ToneGenerator(frequency: 1000)
        let a = low.next(4800), b = high.next(4800)
        #expect(ToneGenerator.presence(of: 440, in: a, sampleRate: 48_000) > 0.8)
        #expect(ToneGenerator.presence(of: 1000, in: a, sampleRate: 48_000) < 0.05)
        let mixed = zip(a, b).map { $0 + $1 }
        #expect(ToneGenerator.presence(of: 440, in: mixed, sampleRate: 48_000) > 0.3)
        #expect(ToneGenerator.presence(of: 1000, in: mixed, sampleRate: 48_000) > 0.3)
    }
}

@Suite("Keystroke caption")
struct KeystrokeTests {
    private let four = KeyStroke(keyCode: 21, key: "4", typed: "$", modifiers: [.command, .shift, .option, .control])

    @Test func labelsUseMacModifierOrderAndKeyNames() {
        #expect(four.label == "⌃⌥⇧⌘4")
        #expect(KeyStroke(keyCode: 6, key: "z", modifiers: [.command]).label == "⌘Z")
        #expect(KeyStroke(keyCode: 48, key: "\t", modifiers: [.shift]).label == "⇧⇥")
        #expect(KeyStroke(keyCode: 49, key: " ", modifiers: [.command]).label == "⌘Space")
        #expect(KeyStroke(keyCode: 36, key: "\r").label == "↩")
        #expect(KeyStroke(keyCode: 122, key: "").label == "F1")
    }

    @Test func typingIsNotAShortcut() {
        #expect(!KeyStroke(keyCode: 0, key: "a").isShortcut)
        #expect(!KeyStroke(keyCode: 0, key: "a", typed: "A", modifiers: [.shift]).isShortcut)
        #expect(!KeyStroke(keyCode: 49, key: " ").isShortcut)
        #expect(KeyStroke(keyCode: 0, key: "a", modifiers: [.option]).isShortcut)
        #expect(KeyStroke(keyCode: 53, key: "\u{1b}").isShortcut)
    }

    @Test func shortcutsOnlyNeverShowsTyping() {
        var caption = KeystrokeCaption(mode: .shortcuts)
        let changed = caption.feed(KeyStroke(keyCode: 6, key: "z", modifiers: [.command]), at: 0)
        #expect(changed)
        #expect(caption.text == "⌘Z")
        caption.feed(KeyStroke(keyCode: 6, key: "z", modifiers: [.command]), at: 0.2)
        caption.feed(KeyStroke(keyCode: 6, key: "z", modifiers: [.command], isRepeat: true), at: 0.3)
        #expect(caption.text == "⌘Z ×3")
        // Typing clears the last shortcut and shows nothing.
        caption.feed(KeyStroke(keyCode: 35, key: "p"), at: 0.5)
        #expect(caption.text == nil)
        caption.feed(KeyStroke(keyCode: 31, key: "o"), at: 0.6)
        #expect(caption.text == nil)
    }

    @Test func allKeysShowsARunOfTyping() {
        var caption = KeystrokeCaption(mode: .allKeys, holdTime: 1)
        for (index, key) in "hi there".enumerated() {
            caption.feed(KeyStroke(keyCode: key == " " ? 49 : 0, key: String(key)), at: Double(index) * 0.1)
        }
        #expect(caption.text == "hi there")
        caption.feed(KeyStroke(keyCode: 0, key: "a", typed: "A", modifiers: [.shift]), at: 0.9)
        #expect(caption.text == "hi thereA")
        // A shortcut replaces the run…
        caption.feed(KeyStroke(keyCode: 1, key: "s", modifiers: [.command]), at: 1.0)
        #expect(caption.text == "⌘S")
        // …and a pause longer than the hold time starts afresh.
        caption.feed(KeyStroke(keyCode: 0, key: "x"), at: 3)
        #expect(caption.text == "x")
        caption.maxTypingLength = 4
        for key in "abcdef" { caption.feed(KeyStroke(keyCode: 0, key: String(key)), at: 3.1) }
        #expect(caption.text == "cdef")
    }

    @Test func theCaptionClearsAfterItsHoldTime() {
        var caption = KeystrokeCaption(mode: .shortcuts, holdTime: 1.5)
        caption.feed(four, at: 10)
        let early = caption.expire(at: 11)
        #expect(!early && caption.text != nil)
        let due = caption.expire(at: 11.6)
        #expect(due && caption.text == nil)
        let again = caption.expire(at: 12)
        #expect(!again)
    }
}

@Suite("Camera bubble")
struct CameraBubbleTests {
    private let area = CGRect(x: 100, y: 50, width: 1200, height: 800)

    @Test func itSitsInsideTheChosenCorner() {
        let bottomLeft = BubbleGeometry.frame(corner: .bottomLeft, width: 200, shape: .circle, in: area)
        #expect(bottomLeft == CGRect(x: 124, y: 74, width: 200, height: 200))
        let topRight = BubbleGeometry.frame(corner: .topRight, width: 200, shape: .roundedRectangle, in: area)
        #expect(topRight == CGRect(x: 1076, y: 676, width: 200, height: 150))
        for corner in BubbleCorner.allCases {
            let frame = BubbleGeometry.frame(corner: corner, width: 200, shape: .circle, in: area)
            #expect(area.contains(frame))
            #expect(BubbleGeometry.nearestCorner(of: frame, in: area) == corner)
        }
    }

    @Test func aSmallAreaGetsASmallerBubble() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 200)
        let frame = BubbleGeometry.frame(corner: .bottomRight, width: 300, shape: .circle, in: small)
        #expect(frame.width == 100 && frame.height == 100)
        #expect(small.contains(frame))
        // Never below the minimum, even in a tiny area.
        #expect(BubbleGeometry.clampedWidth(10, shape: .circle, in: CGRect(x: 0, y: 0, width: 50, height: 50)) == BubbleGeometry.minimumWidth)
        #expect(BubbleGeometry.clampedWidth(2000, shape: .circle, in: CGRect(x: 0, y: 0, width: 4000, height: 3000)) == BubbleGeometry.maximumWidth)
    }

    @Test func resizingKeepsTheCenterAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 600, y: 400, width: 200, height: 200)
        let bigger = BubbleGeometry.resized(frame, toWidth: 300, shape: .circle, area: screen, bounds: screen)
        #expect(bigger == CGRect(x: 550, y: 350, width: 300, height: 300))
        let corner = BubbleGeometry.resized(CGRect(x: 0, y: 0, width: 200, height: 200), toWidth: 300, shape: .circle, area: screen, bounds: screen)
        #expect(corner.origin == .zero && corner.width == 300)
        #expect(BubbleGeometry.cornerRadius(for: CGSize(width: 200, height: 200), shape: .circle) == 100)
        #expect(BubbleGeometry.cornerRadius(for: CGSize(width: 200, height: 150), shape: .roundedRectangle) == 24)
    }
}

@Suite("Recording options")
struct RecordingOptionTests {
    @Test func gifsAreAlwaysSilent() {
        let options = RecordingOptions(frameRate: 60, audio: RecordingAudio(computer: true, microphone: true))
        #expect(options.audio.needsMixing && options.audio.trackCount == 2)
        #expect(options.forRecording(gif: true).audio.isSilent)
        #expect(options.forRecording(gif: false).audio == options.audio)
        #expect(options.keyframeInterval == 60)
        #expect(!RecordingAudio(microphone: true).needsMixing)
    }

    @Test func testModeOnASecondDisplayIsDisplayLocal() throws {
        let display = (id: CGDirectDisplayID(2), frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
        let scene = (id: CGWindowID(9), frame: CGRect(x: 1640, y: 100, width: 1000, height: 680))
        let plan = try #require(RecordingPlan.make(selection: CGRect(x: 1700, y: 200, width: 400, height: 300), display: display, testScene: scene))
        #expect(plan.source == .testScene(window: 9, display: 2))
        #expect(plan.sourceRect == CGRect(x: 260, y: 200, width: 400, height: 300))
        #expect(plan.screenRect == CGRect(x: 1700, y: 200, width: 400, height: 300))
    }
}

@Suite("Trimming and mixing recordings")
struct MediaEditingTests {
    @Test func trimRangesAreClampedAndNeverTooShort() throws {
        let range = try #require(TrimRange(start: -1, end: 20, duration: 10))
        #expect(range.start == 0 && range.end == 10)
        #expect(range.isWhole(of: 10))
        #expect(TrimRange(start: 3, end: 3.2, duration: 10) == nil)
        let part = try #require(TrimRange(start: 2, end: 5, duration: 10))
        #expect(!part.isWhole(of: 10) && part.length == 3)
    }

    @Test func mixingMakesOneSoundTrackWithBothSounds() async throws {
        let folder = try TestMedia.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("two-tracks.mp4")
        try await TestMedia.makeVideo(at: source, seconds: 2, tones: [440, 1000])
        #expect(await MediaEditor.audioTrackCount(source) == 2)
        let mixed = folder.appendingPathComponent("mixed.mp4")
        try await MediaEditor.mixAudio(source, output: mixed)
        #expect(await MediaEditor.audioTrackCount(mixed) == 1)
        let asset = AVURLAsset(url: mixed)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(await MediaEditor.duration(of: mixed) - 2) < 0.15)
        let samples = try await TestMedia.audioSamples(of: asset, from: 0.5, seconds: 0.5)
        #expect(ToneGenerator.presence(of: 440, in: samples, sampleRate: 48_000) > 0.2)
        #expect(ToneGenerator.presence(of: 1000, in: samples, sampleRate: 48_000) > 0.2)
    }

    @Test func trimmingKeepsOnlyTheRangeWithoutReencoding() async throws {
        let folder = try TestMedia.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4")
        try await TestMedia.makeVideo(at: source, seconds: 3, tones: [440])
        let output = folder.appendingPathComponent("trimmed.mp4")
        let range = try #require(TrimRange(start: 1, end: 2.5, duration: 3))
        try await MediaEditor.trim(source, to: range, output: output)
        #expect(abs(await MediaEditor.duration(of: output) - 1.5) < 0.1)
        let asset = AVURLAsset(url: output)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        // Passthrough: the same H.264 samples, not a new encode.
        let format = try #require(try await video.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }
}

@Suite("History: trimmed recordings")
struct HistoryTrimTests {
    @Test func aTrimKeepsTheUntrimmedRecordingUntilRestored() async throws {
        let folder = try TestMedia.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(root: folder.appendingPathComponent("History"))
        let first = folder.appendingPathComponent("first.mp4"), second = folder.appendingPathComponent("second.mp4")
        try Data("untrimmed".utf8).write(to: first)
        try Data("trimmed".utf8).write(to: second)
        let poster = TestImages.solid(width: 40, height: 30, red: 1, green: 0, blue: 0)
        let entry = try await store.add(HistoryCapture(id: UUID(), createdAt: Date(), kind: .recording, scale: 2, image: poster, original: nil,
                                                       media: first, duration: 10, format: .png, baseName: "Recording 1", source: nil))
        #expect(store.untrimmedURL(for: entry) == nil)
        let trimmed = try #require(try await store.replaceMedia(entry.id, with: second, duration: 4, poster: poster))
        #expect(trimmed.duration == 4)
        #expect(trimmed.fileName == entry.fileName)
        #expect(try String(contentsOf: store.fileURL(for: trimmed), encoding: .utf8) == "trimmed")
        let untrimmed = try #require(store.untrimmedURL(for: trimmed))
        #expect(try String(contentsOf: untrimmed, encoding: .utf8) == "untrimmed")
        // A second trim keeps the first original.
        let again = try #require(try await store.replaceMedia(entry.id, with: second, duration: 2, poster: poster))
        #expect(try String(contentsOf: try #require(store.untrimmedURL(for: again)), encoding: .utf8) == "untrimmed")
        let restored = try #require(try await store.restoreUntrimmed(entry.id, duration: 10, poster: poster))
        #expect(restored.originalFileName == nil && restored.duration == 10)
        #expect(try String(contentsOf: store.fileURL(for: restored), encoding: .utf8) == "untrimmed")
        #expect(HistoryStore.safeName("untrimmed") == "Capture")
    }
}

/// Small generated videos for the media tests: an H.264 picture that changes every frame and
/// one AAC track per tone.
enum TestMedia {
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapper-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeVideo(at url: URL, seconds: Double, tones: [Double], fps: Int = 10) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120,
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: fps],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120,
        ])
        writer.add(video)
        let audio = tones.map { _ in AVAssetWriterInput(mediaType: .audio, outputSettings: AudioFormat.aac(channels: 1)) }
        audio.forEach { writer.add($0) }
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var generators = tones.map { ToneGenerator(frequency: $0) }
        let block = 4800 // 0.1 s
        let frames = Int(seconds * Double(fps))
        let blocks = Int(seconds * 48_000) / block
        var frame = 0
        var written = [Int](repeating: 0, count: audio.count)
        while frame < frames || written.contains(where: { $0 < blocks }) {
            // Feed every input the writer is ready for, each on its own (it interleaves
            // non-real-time inputs, so waiting for several of them at once can deadlock).
            var progressed = false
            if frame < frames, video.isReadyForMoreMediaData {
                let buffer = try #require(pixelBuffer(shade: UInt8(frame * 255 / max(1, frames)), pool: adaptor.pixelBufferPool))
                #expect(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))))
                frame += 1
                progressed = true
            }
            for (index, input) in audio.enumerated() where written[index] < blocks && input.isReadyForMoreMediaData {
                let time = CMTime(value: CMTimeValue(written[index] * block), timescale: 48_000)
                #expect(input.append(try #require(AudioSamples.makeBuffer(generators[index].next(block), time: time))))
                written[index] += 1
                progressed = true
            }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        video.markAsFinished()
        audio.forEach { $0.markAsFinished() }
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    private static func pixelBuffer(shade: UInt8, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        if buffer == nil { CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32BGRA, nil, &buffer) }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Mono Float32 samples from `start` for `seconds`.
    static func audioSamples(of asset: AVAsset, from start: Double, seconds: Double) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: seconds, preferredTimescale: 600))
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.startReading()
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            samples += AudioSamples.floats(in: buffer) ?? []
        }
        return Array(samples.prefix(Int(seconds * 48_000)))
    }
}

private extension Double {
    var float: Float { Float(self) }
}

@Suite("Recording sink")
struct RecordingSinkTests {
    /// Frames at 20 fps and both sound tracks for 3 s of host time, paused from 1 s to 2 s:
    /// the file is 2 s long, has two sound tracks that mix down into one with both tones.
    @Test func framesAndSoundLineUpAndAPauseLeavesNoGap() async throws {
        let folder = try TestMedia.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("recording.mp4")
        let options = RecordingOptions(frameRate: 20, audio: RecordingAudio(computer: true, microphone: true))
        let sink = try RecordingSink(url: url, width: 160, height: 120, options: options)
        let start = 5000.0
        var computer = ToneGenerator(frequency: 440), microphone = ToneGenerator(frequency: 1000)
        var pool: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32BGRA, nil, &pool)
        let frame = try #require(pool)
        sink.setPaused(true, at: t(start + 1))
        sink.setPaused(false, at: t(start + 2))
        // 10 ms steps: a frame every 50 ms, sound every step; fed a little faster than real time.
        for step in 0..<300 {
            let time = start + Double(step) / 100
            let computerBlock = AudioSamples.makeBuffer(computer.next(480).flatMap { [$0, $0] }, channels: 2, time: t(time))
            let microphoneBlock = AudioSamples.makeBuffer(microphone.next(480), time: t(time))
            nonisolated(unsafe) let pixels = frame
            nonisolated(unsafe) let block = computerBlock
            sink.queue.sync {
                if step % 5 == 0 { sink.appendFrame(pixels, at: t(time)) }
                if let block { sink.appendAudio(block, track: .computer) }
            }
            if let microphoneBlock { sink.appendMicrophone(microphoneBlock) }
            if step % 10 == 0 { try await Task.sleep(for: .milliseconds(2)) }
        }
        let duration = try await sink.finish(at: t(start + 3))
        #expect(abs(duration - 2) < 0.06)
        let counts = await sink.audioSampleCounts()
        #expect((counts[.computer] ?? 0) > 48_000 * 3 / 2 && (counts[.microphone] ?? 0) > 48_000 * 3 / 2)
        #expect(await MediaEditor.audioTrackCount(url) == 2)
        // Tagged sRGB, so players show the colours the screen had.
        let video = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let format = try #require(try await video.load(.formatDescriptions).first)
        let extensions = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        #expect(extensions[kCVImageBufferColorPrimariesKey as String] as? String == kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
        #expect(extensions[kCVImageBufferTransferFunctionKey as String] as? String == kCVImageBufferTransferFunction_sRGB as String)
        let mixed = folder.appendingPathComponent("mixed.mp4")
        try await MediaEditor.mixAudio(url, output: mixed)
        #expect(await MediaEditor.audioTrackCount(mixed) == 1)
        #expect(abs(await MediaEditor.duration(of: mixed) - 2) < 0.1)
        // Both tones, on either side of where the pause was cut out.
        for from in [0.3, 1.3] {
            let samples = try await TestMedia.audioSamples(of: AVURLAsset(url: mixed), from: from, seconds: 0.4)
            #expect(ToneGenerator.presence(of: 440, in: samples, sampleRate: 48_000) > 0.2)
            #expect(ToneGenerator.presence(of: 1000, in: samples, sampleRate: 48_000) > 0.2)
        }
    }

    @Test func nothingRecordedIsAnError() async throws {
        let folder = try TestMedia.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("empty.mp4")
        let sink = try RecordingSink(url: url, width: 160, height: 120, options: RecordingOptions())
        await #expect(throws: RecordingError.self) { try await sink.finish() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
