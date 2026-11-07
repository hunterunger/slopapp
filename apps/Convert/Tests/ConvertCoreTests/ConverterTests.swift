import AVFoundation
import ConvertFixtures
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ConvertCore

/// Real conversions of synthetic media, read back with AVFoundation / ImageIO.
@Suite(.serialized, .needsMediaEngine, .timeLimit(.minutes(5))) struct VideoConversionTests {
    @Test func movToMP4IsARepackageThatPlays() async throws {
        let input = try videoFixture("Screen Recording.mov")
        let before = try sha(input)
        let result = try report(try await converter().run(input))
        #expect(result.output.lastPathComponent == "Screen Recording.mp4")
        #expect(result.output.deletingLastPathComponent() == input.deletingLastPathComponent())
        #expect(result.repackaged)
        #expect(result.summary == "MP4 (H.264) · 640×360 · 0:02")
        let out = try await playBack(result.output)
        #expect(out.playable && out.videoCodec == "avc1" && out.audioCodec == "aac ")
        #expect(abs(out.duration - 2) < 0.1)
        #expect(try sha(input) == before)
        // Nothing else left behind.
        #expect(try visibleFiles(input.deletingLastPathComponent()) == ["Screen Recording.mov", "Screen Recording.mp4"])
    }

    @Test func hevcToH264ReencodesAndLooksTheSame() async throws {
        let input = try videoFixture { $0.codec = .hevc; $0.width = 1280; $0.height = 720 }
        let result = try report(try await converter().run(input))
        #expect(!result.repackaged)
        let out = try await playBack(result.output)
        #expect(out.videoCodec == "avc1" && out.displaySize == CGSize(width: 1280, height: 720))
        #expect(abs(out.duration - 2) < 0.1)
        for t in [0.2, 1.0, 1.8] {
            let a = try await averageColor(ofVideo: input, at: t)
            let b = try await averageColor(ofVideo: result.output, at: t)
            #expect(colorDistance(a, b) < 0.03, "frame at \(t)s differs: \(a) vs \(b)")
        }
    }

    @Test func qualityChangesTheSize() async throws {
        let input = try videoFixture { $0.codec = .hevc; $0.width = 1280; $0.height = 720; $0.quality = 1 }
        var sizes: [Int64] = []
        for quality in [Quality.smaller, .best] {
            let result = try report(try await converter { $0.quality = quality }.run(input))
            sizes.append(result.bytes)
        }
        #expect(sizes[0] < sizes[1])
    }

    @Test func portraitStaysUprightAndResizes() async throws {
        let input = try videoFixture { $0.width = 1280; $0.height = 720; $0.portrait = true; $0.codec = .hevc }
        let result = try report(try await converter { $0.size = .p480 }.run(input))
        let out = try await playBack(result.output)
        #expect(out.displaySize == CGSize(width: 480, height: 854), "\(String(describing: out.displaySize)) \(result.summary)")
        #expect(result.summary == "MP4 (H.264) · 480×854 · 0:02")
        let a = try await averageColor(ofVideo: input, at: 1)
        let b = try await averageColor(ofVideo: result.output, at: 1)
        #expect(colorDistance(a, b) < 0.04)
    }

    @Test func toHEVCAndProRes() async throws {
        let input = try videoFixture()
        let hevc = try report(try await converter { $0.video = .mp4HEVC }.run(input))
        #expect(try await playBack(hevc.output).videoCodec == "hvc1")
        let prores = try report(try await converter { $0.video = .movProRes }.run(input))
        // clip.mov is taken by the input, so ProRes lands in "clip 2.mov".
        #expect(prores.output.lastPathComponent == "clip 2.mov")
        let out = try await playBack(prores.output)
        #expect(out.videoCodec == "apcn" && out.audioCodec == "lpcm")
    }

    @Test func metadataIsKept() async throws {
        let input = try videoFixture { $0.metadata = true }
        for quality in [Quality.balanced, .smaller] {
            let result = try report(try await converter { $0.quality = quality }.run(input))
            let items = try await AVURLAsset(url: result.output).load(.metadata)
            var values: [String] = []
            for item in items {
                if let value = try? await item.load(.stringValue) { values.append(value) }
            }
            #expect(values.contains("Fixture Title"), "\(quality): \(values)")
            #expect(values.contains { $0.hasPrefix("+51.0447") }, "\(quality): \(values)")
        }
    }

    @Test func alreadyRightIsLeftAlone() async throws {
        let input = try videoFixture("Already.mp4") { $0.fileType = .mp4 }
        let result = try await converter().run(input)
        guard case .unchanged(let reason) = result else { Issue.record("expected unchanged"); return }
        #expect(reason == "Already MP4 (H.264). Nothing to change. To make it smaller, choose Smaller under Quality.")
        #expect(try visibleFiles(input.deletingLastPathComponent()) == ["Already.mp4"])
        // Smaller does re-encode it, next to it as "Already 2.mp4".
        let smaller = try report(try await converter { $0.quality = .smaller }.run(input))
        #expect(smaller.output.lastPathComponent == "Already 2.mp4")
    }

    @Test func convertingAgainReplacesItsOwnOutput() async throws {
        let input = try videoFixture { $0.codec = .hevc }
        let first = try report(try await converter().run(input))
        let again = try report(try await converter { $0.quality = .smaller }.run(input, replacing: first.output))
        #expect(again.output == first.output)
        #expect(try visibleFiles(input.deletingLastPathComponent()) == ["clip.mov", "clip.mp4"])
        // A different target makes a new file and leaves the old one.
        let gif = try report(try await converter { $0.video = .gif }.run(input, replacing: first.output))
        #expect(gif.output.lastPathComponent == "clip.gif")
        #expect(try visibleFiles(input.deletingLastPathComponent()) == ["clip.gif", "clip.mov", "clip.mp4"])
        // Never the input itself.
        let mp4 = try videoFixture("same.mp4") { $0.fileType = .mp4; $0.codec = .hevc }
        let redo = try report(try await converter().run(mp4, replacing: mp4))
        #expect(redo.output.lastPathComponent == "same 2.mp4")
    }

    @Test func neverOverwrites() async throws {
        let input = try videoFixture()
        let taken = input.deletingLastPathComponent().appendingPathComponent("clip.mp4")
        try Data("mine".utf8).write(to: taken)
        let first = try report(try await converter().run(input))
        let second = try report(try await converter().run(input))
        #expect(first.output.lastPathComponent == "clip 2.mp4")
        #expect(second.output.lastPathComponent == "clip 3.mp4")
        #expect(try String(contentsOf: taken, encoding: .utf8) == "mine")
    }

    @Test func gifLoopsAtTheRightSize() async throws {
        let input = try videoFixture { $0.width = 1280; $0.height = 720; $0.seconds = 2 }
        let result = try report(try await converter { $0.video = .gif }.run(input))
        #expect(result.output.pathExtension == "gif")
        #expect(imageFrameCount(result.output) == 24)
        let props = imageProperties(result.output)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 640)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 360)
        let source = CGImageSourceCreateWithURL(result.output as CFURL, nil)!
        let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = file?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gif?[kCGImagePropertyGIFLoopCount] as? Int == 0)
        let delays = (0..<24).map { index in
            let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let g = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        }
        #expect(abs(delays.reduce(0, +) - 2.0) < 0.02, "\(delays)")
        // The middle frame looks like the video's middle frame.
        let frame = CGImageSourceCreateImageAtIndex(source, 12, nil)!
        let video = try await averageColor(ofVideo: input, at: 1.0)
        #expect(colorDistance(averageColor(frame), video) < 0.06)
        #expect(result.notes == ["GIFs are capped at 640 px. Best makes them 800 px."])
    }

    @Test func audioFromVideo() async throws {
        let input = try videoFixture()
        let m4a = try report(try await converter { $0.video = .audioM4A }.run(input))
        let out = try await playBack(m4a.output)
        #expect(m4a.output.pathExtension == "m4a" && out.videoCodec == nil && out.audioCodec == "aac ")
        #expect(abs(out.duration - 2) < 0.1)
        let wav = try report(try await converter { $0.video = .audioWAV }.run(input))
        let w = try await playBack(wav.output)
        #expect(w.audioCodec == "lpcm" && w.bitsPerSample == 16)

        let silent = try videoFixture("silent.mp4") { $0.audioTracks = 0; $0.fileType = .mp4 }
        await #expect(throws: ConvertError.noSound(name: "silent.mp4")) {
            try await converter { $0.video = .audioM4A }.run(silent)
        }
        #expect(try visibleFiles(silent.deletingLastPathComponent()) == ["silent.mp4"])
    }

    @Test func twoSoundTracksAreMixed() async throws {
        let input = try videoFixture { $0.audioTracks = 2 }
        let result = try report(try await converter().run(input))
        let out = try await playBack(result.output)
        #expect(out.audioTracks == 1 && out.videoCodec == "avc1")
        #expect(result.notes == ["Its 2 sound tracks were mixed into one."])
    }

    @Test func hdrToH264IsToneMapped() async throws {
        let input = try videoFixture { $0.codec = .hevc; $0.hdr = true }
        let info = try await MediaProbe.probe(input)
        #expect(info.isHDR)
        let result = try report(try await converter().run(input))
        #expect(result.notes.contains("HDR was converted to standard range."))
        let out = try await playBack(result.output)
        #expect(out.videoCodec == "avc1")
        let b = try await averageColor(ofVideo: result.output, at: 1)
        // Not black, not blown out.
        #expect(b.r > 0.15 && b.r < 0.9 && b.b > 0.1)
    }

    @Test func hdrStaysHDRInHEVC() async throws {
        let input = try videoFixture { $0.codec = .hevc; $0.hdr = true }
        let result = try report(try await converter { $0.video = .mp4HEVC; $0.quality = .smaller }.run(input))
        #expect(!result.repackaged && result.notes.isEmpty)
        let track = try await AVURLAsset(url: result.output).loadTracks(withMediaType: .video)[0]
        let format = try await track.load(.formatDescriptions)[0]
        let ext = CMFormatDescriptionGetExtensions(format) as? [String: Any] ?? [:]
        #expect(ext[kCVImageBufferTransferFunctionKey as String] as? String == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
        #expect(try await track.load(.mediaCharacteristics).contains(.containsHDRVideo))
    }

    @Test func cancellingLeavesNothingBehind() async throws {
        let input = try videoFixture { $0.width = 1920; $0.height = 1080; $0.seconds = 8; $0.codec = .hevc }
        let folder = input.deletingLastPathComponent()
        let started = ProgressFlag()
        let task = Task {
            try await converter { $0.quality = .best }.run(input, progress: { if $0 > 0.05 { started.set() } })
        }
        while !started.value { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try visibleFiles(folder) == ["clip.mov"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["clip.mov"])
    }

    @Test func refusesWhatItCantRead() async throws {
        let mkv = try fixture("Movie.mkv") { try Data("nope".utf8).write(to: $0) }
        await #expect(throws: ConvertError.unreadableFormat(name: "Movie.mkv", format: "MKV")) {
            try await converter().run(mkv)
        }
        let broken = try fixture("Broken.mp4") { try Data(repeating: 7, count: 4096).write(to: $0) }
        await #expect(throws: ConvertError.damaged(name: "Broken.mp4")) {
            try await converter().run(broken)
        }
        let text = try fixture("Notes.txt") { try Data("hi".utf8).write(to: $0) }
        await #expect(throws: ConvertError.unsupported(name: "Notes.txt")) {
            try await converter().run(text)
        }
    }

    @Test func destinationProblemsAreExplained() async throws {
        let input = try videoFixture()
        let gone = URL(fileURLWithPath: "/tmp/convert-test/unit/missing-\(UUID().uuidString)")
        await #expect(throws: ConvertError.noFolder(folder: gone.lastPathComponent)) {
            try await converter { $0.destination = .folder(gone) }.run(input)
        }
        var readOnly = Converter(settings: ConvertSettings())
        readOnly.files = FailingFileStore(writable: false)
        await #expect(throws: ConvertError.cantWrite(folder: input.deletingLastPathComponent().lastPathComponent)) {
            try await readOnly.run(input)
        }
        var full = Converter(settings: ConvertSettings())
        full.files = FailingFileStore(failMove: true)
        await #expect(throws: ConvertError.diskFull(name: "clip.mp4")) { try await full.run(input) }
        #expect(try visibleFiles(input.deletingLastPathComponent()) == ["clip.mov"])

        // A chosen folder works, and dates can be kept.
        let out = try makeTempFolder()
        let old = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: input.path)
        let result = try report(try await converter { $0.destination = .folder(out); $0.keepDates = true }.run(input))
        #expect(result.output.deletingLastPathComponent().resolvingSymlinksInPath().path == out.resolvingSymlinksInPath().path)
        let date = try FileManager.default.attributesOfItem(atPath: result.output.path)[.modificationDate] as? Date
        #expect(date == old)
    }
}

final class ProgressFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}

@Suite(.timeLimit(.minutes(5))) struct AudioConversionTests {
    @Test func wavToM4A() async throws {
        let input = try fixture("Interview.wav") { try FixtureMaker.audio($0, seconds: 3) }
        var sizes: [Quality: Int64] = [:]
        for quality in Quality.allCases {
            let folder = try makeTempFolder()
            let r = try report(try await converter { $0.quality = quality; $0.destination = .folder(folder) }.run(input))
            sizes[quality] = r.bytes
        }
        // Constant bit rate: 96 / 160 / 256 kbps for 3 s of stereo, give or take the container.
        #expect(abs(Double(sizes[.smaller]!) * 8 / 3 - 96_000) < 12_000)
        #expect(abs(Double(sizes[.balanced]!) * 8 / 3 - 160_000) < 16_000)
        #expect(abs(Double(sizes[.best]!) * 8 / 3 - 256_000) < 24_000)
        let result = try report(try await converter().run(input))
        #expect(result.output.lastPathComponent == "Interview.m4a")
        #expect(result.summary == "M4A (AAC) · 160 kbps · 0:03")
        let out = try await playBack(result.output)
        #expect(out.audioCodec == "aac " && abs(out.duration - 3) < 0.1)
        let inputBytes = try FileManager.default.attributesOfItem(atPath: input.path)[.size] as! Int64
        #expect(result.bytes < inputBytes)
    }

    @Test func m4aToLosslessFormats() async throws {
        let input = try fixture("Memo.m4a") { try FixtureMaker.audio($0, seconds: 2, channels: 1) }
        let wav = try report(try await converter { $0.audio = .wav }.run(input))
        let w = try await playBack(wav.output)
        #expect(w.audioCodec == "lpcm" && w.bitsPerSample == 16 && abs(w.duration - 2) < 0.1)
        let aiff = try report(try await converter { $0.audio = .aiff }.run(input))
        #expect(aiff.output.pathExtension == "aiff")
        #expect(try await playBack(aiff.output).audioCodec == "lpcm")
        let alac = try report(try await converter { $0.audio = .alac }.run(input))
        // Memo.m4a is taken by the input.
        #expect(alac.output.lastPathComponent == "Memo 2.m4a")
        #expect(try await playBack(alac.output).audioCodec == "alac")
        // AAC → M4A (AAC) is already right.
        guard case .unchanged = try await converter().run(input) else { Issue.record("expected unchanged"); return }
    }

    @Test func keeps24Bit() async throws {
        let input = try fixture("Loop.aiff") { try FixtureMaker.audio($0, seconds: 1, bits: 24) }
        let wav = try report(try await converter { $0.audio = .wav }.run(input))
        #expect(try await playBack(wav.output).bitsPerSample == 24)
    }
}

@Suite(.timeLimit(.minutes(5))) struct ImageConversionTests {
    @Test(.needsMediaEngine) func heicToJPEGKeepsMetadata() async throws {
        let input = try fixture("Photo.heic") { try FixtureMaker.image($0, type: .heic, width: 1600, height: 1200) }
        let result = try report(try await converter().run(input))
        #expect(result.output.lastPathComponent == "Photo.jpg")
        #expect(result.summary == "JPEG · 1600×1200")
        let props = imageProperties(result.output)
        #expect(props[kCGImagePropertyGPSDictionary] != nil)
        #expect(colorDistance(averageColor(firstImage(input)!), averageColor(firstImage(result.output)!)) < 0.03)
    }

    @Test func transparentPNGToJPEGGoesOnWhite() async throws {
        let input = try fixture("Logo.png") { try FixtureMaker.image($0, type: .png, width: 300, height: 300, alpha: true) }
        let result = try report(try await converter().run(input))
        let image = firstImage(result.output)!
        // The left third was transparent: it's white now, not black.
        let crop = image.cropping(to: CGRect(x: 10, y: 100, width: 60, height: 100))!
        let c = averageColor(crop)
        #expect(c.r > 0.95 && c.g > 0.95 && c.b > 0.95)
    }

    @Test(.needsMediaEngine) func orientationIsKeptOrBakedIn() async throws {
        let input = try fixture("Sideways.jpg") { try FixtureMaker.image($0, type: .jpeg, width: 1200, height: 900, orientation: 6) }
        let png = try report(try await converter { $0.image = .png }.run(input))
        #expect(imageProperties(png.output)[kCGImagePropertyOrientation] as? Int == 6)
        #expect(png.summary == "PNG · 900×1200")
        let small = try report(try await converter { $0.image = .heic; $0.size = .p480 }.run(input))
        let props = imageProperties(small.output)
        #expect(props[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 480)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 640)
    }

    @Test func sameFormatIsLeftAloneUnlessResized() async throws {
        let input = try fixture("a.jpeg") { try FixtureMaker.image($0, type: .jpeg) }
        guard case .unchanged(let reason) = try await converter().run(input) else { Issue.record("expected unchanged"); return }
        #expect(reason == "Already JPEG. Nothing to change.")
        let smaller = try report(try await converter { $0.size = .p480 }.run(input))
        #expect(smaller.output.lastPathComponent == "a.jpg")
    }

    @Test(.needsMediaEngine) func animatedGIFBecomesAVideo() async throws {
        let input = try fixture("Animated.gif") { try FixtureMaker.image($0, type: .gif, width: 201, height: 150, frames: 4) }
        let info = try await MediaProbe.probe(input)
        #expect(info.kind == .video && info.isAnimatedImage && abs(info.duration - 0.8) < 0.01)
        #expect(info.summary == "Animated GIF · 201×150 · 0:01")
        let mp4 = try report(try await converter().run(input))
        #expect(mp4.output.lastPathComponent == "Animated.mp4")
        let out = try await playBack(mp4.output)
        #expect(out.videoCodec == "avc1" && out.displaySize == CGSize(width: 200, height: 150))
        #expect(abs(out.duration - 0.8) < 0.05)
        let frame = try await averageColor(ofVideo: mp4.output, at: 0.1)
        let gifFrame = averageColor(firstImage(input)!)
        #expect(colorDistance(frame, gifFrame) < 0.05, "\(frame) vs \(gifFrame)")
        // Already a GIF; no sound to extract.
        guard case .unchanged = try await converter({ $0.video = .gif }).run(input) else { Issue.record("expected unchanged"); return }
        await #expect(throws: ConvertError.noSound(name: "Animated.gif")) { try await converter { $0.video = .audioM4A }.run(input) }
    }

    @Test func formatsThisMacCantWriteAreRefused() async throws {
        let input = try fixture("a.png") { try FixtureMaker.image($0, type: .png) }
        var c = converter { $0.image = .avif }
        c.capabilities = Capabilities(writableImageTypes: ["public.jpeg"], canEncodeHEVC: true, canEncodeProRes: true)
        await #expect(throws: ConvertError.cantWriteFormat(format: "AVIF", kind: .image)) { try await c.run(input) }
        #expect(c.capabilities.imageTargets == [.jpeg])
    }
}
