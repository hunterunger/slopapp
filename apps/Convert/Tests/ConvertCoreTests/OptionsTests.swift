import AVFoundation
import ConvertFixtures
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ConvertCore

/// Per-file options, presets and after-actions: pure logic, fast, runs everywhere.
@Suite struct OptionsLogicTests {
    @Test func transformsComposeLikeTurnsAndFlips() {
        let id = PictureTransform.identity
        #expect(id.rotatedRight().rotatedRight().rotatedRight().rotatedRight() == id)
        #expect(id.rotatedLeft() == PictureTransform(quarterTurns: 3))
        #expect(id.flippedHorizontally().flippedHorizontally() == id)
        #expect(id.flippedVertically().flippedVertically() == id)
        // Both flips make a half turn.
        #expect(id.flippedHorizontally().flippedVertically() == PictureTransform(quarterTurns: 2))
        // Mirror, then turn right: that's not the same as turn right, then mirror.
        #expect(id.flippedHorizontally().rotatedRight() != id.rotatedRight().flippedHorizontally())
        #expect(id.rotatedRight().swapsSides && !id.flippedVertically().swapsSides)
        #expect(id.rotatedRight().flippedHorizontally().title == "Turned left and mirrored")
    }

    @Test func exifOrientationsRoundTripAndMatchTheirMatrices() {
        for value in 1...8 {
            #expect(PictureTransform(exifOrientation: value).exifOrientation == value)
        }
        // 6 = turned right: the top-left corner of a 4×2 picture lands at the top right.
        let right = PictureTransform(exifOrientation: 6).affine(width: 4, height: 2)
        #expect(CGPoint(x: 0, y: 0).applying(right) == CGPoint(x: 2, y: 0))
        // 5 = transpose: x and y trade places.
        let transpose = PictureTransform(exifOrientation: 5).affine(width: 4, height: 2)
        #expect(CGPoint(x: 3, y: 1).applying(transpose) == CGPoint(x: 1, y: 3))
        // Composition agrees with matrix multiplication.
        let a = PictureTransform(quarterTurns: 1, mirrored: true), b = PictureTransform(quarterTurns: 3)
        let viaMatrices = b.affine(width: 4, height: 2).concatenating(a.affine(width: 2, height: 4))
        let composed = a.after(b).affine(width: 4, height: 2)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 1, y: 2)] {
            #expect(p.applying(viaMatrices) == p.applying(composed))
        }
    }

    @Test func fileFormatsOverrideTheDefaults() {
        var settings = ConvertSettings()
        let options = FileOptions(video: .mp4HEVC, image: .png)
        let applied = settings.applying(options)
        #expect(applied.video == .mp4HEVC && applied.image == .png && applied.audio == .m4a)
        #expect(options.hasOwnFormat(for: .video) && !options.hasOwnFormat(for: .audio))
        // Signatures change with a file's edits, so its earlier result counts as out of date.
        let plain = settings.signature(for: .video, options: FileOptions())
        #expect(plain == settings.signature(for: .video))
        #expect(settings.signature(for: .video, options: FileOptions(trim: TrimRange(start: 1, end: 2))) != plain)
        #expect(settings.signature(for: .video, options: FileOptions(transform: .identity.rotatedRight())) != plain)
        #expect(settings.signature(for: .video, options: FileOptions(sound: .none)) != plain)
        settings.video = .mp4HEVC
        #expect(settings.signature(for: .video) == ConvertSettings().signature(for: .video, options: options))
        // Options survive a round trip through JSON (the app keeps them per file).
        let full = FileOptions(audio: .wav, trim: TrimRange(start: 1.5, end: 9), transform: PictureTransform(quarterTurns: 3, mirrored: true),
                               sound: .track(1))
        let decoded = try? JSONDecoder().decode(FileOptions.self, from: JSONEncoder().encode(full))
        #expect(decoded == full)
    }

    @Test func cardLines() {
        let video = sampleInfo {
            $0.width = 1920; $0.height = 1080; $0.videoCodec = "hvc1"; $0.isHDR = true; $0.frameRate = 29.97; $0.duration = 134
            $0.audioCodec = "aac "; $0.audioBitRate = 160_400; $0.channels = 2; $0.audioTrackCount = 1
        }
        #expect(video.cardLine == "1920×1080 · HEVC · HDR · 29.97 fps · AAC · 160 kbps · Stereo · 2:14")
        let sound = sampleInfo(.audio) { $0.audioCodec = "lpcm"; $0.sampleRate = 44_100; $0.bitsPerSample = 24; $0.channels = 1; $0.duration = 5 }
        #expect(sound.cardLine == "PCM · 44.1 kHz · 24-bit · Mono · 0:05")
        let photo = sampleInfo(.image) { $0.imageFormat = "HEIC"; $0.width = 4032; $0.height = 3024; $0.isRotated = true }
        #expect(photo.cardLine == "HEIC · 3024×4032")
    }

    @Test func trimRanges() {
        let trim = TrimRange(start: 2.04, end: 75.5)
        #expect(trim.title == "0:02.0 – 1:15.5")
        #expect(TrimRange(start: 5, end: 3).duration == 0)
        #expect(TrimRange(start: 0, end: 10).isWhole(of: 10) && !trim.isWhole(of: 80))
        #expect(Durations.precise(3723.25) == "1:02:03.3")
    }

    @Test func plansFollowTheFileOptions() throws {
        let info = sampleInfo {
            $0.width = 1920; $0.height = 1080; $0.videoCodec = "avc1"; $0.duration = 60; $0.frameRate = 30
            $0.audioCodec = "aac "; $0.audioTrackCount = 2; $0.channels = 2; $0.sampleRate = 48_000; $0.audioBitRate = 160_000
            $0.audioTracks = [AudioTrackInfo(index: 0, codec: "aac ", channels: 2), AudioTrackInfo(index: 1, codec: "lpcm", channels: 1)]
        }
        let settings = ConvertSettings()
        // A turn alone still copies: it travels as the track's matrix.
        let turned = try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(transform: .identity.rotatedRight()))
        #expect(turned.video == .copy && turned.transform.quarterTurns == 1)
        #expect(!Planner.isNoOp(turned, info: info, inputExtension: "mp4"))
        // A mirror is drawn into the picture, upright, at the size as shown.
        let mirrored = try Planner.plan(info, settings: settings, name: "a.mov",
                                        options: FileOptions(transform: .identity.flippedHorizontally().rotatedRight()))
        guard case .encode(let e)? = mirrored.video else { Issue.record("expected encode"); return }
        #expect(e.upright && e.width == 1080 && e.height == 1920)
        // Trims are kept (clamped to the file), whole-file trims dropped.
        let trimmed = try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(trim: TrimRange(start: 10, end: 90)))
        #expect(trimmed.trim == TrimRange(start: 10, end: 60) && trimmed.video == .copy)
        #expect(try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(trim: TrimRange(start: 0, end: 60))).trim == nil)
        // Sound: one chosen track is planned on its own facts; none means no sound.
        let second = try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(sound: .track(1)))
        #expect(second.notes.isEmpty)
        guard case .encode(let a) = second.audio else { Issue.record("expected the PCM track to be encoded"); return }
        #expect(a.channels == 1)
        let first = try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(sound: .track(0)))
        #expect(first.audio == .copy)
        let silent = try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(sound: .none))
        #expect(silent.audio == .none && silent.notes.isEmpty)
        #expect(throws: ConvertError.noSound(name: "a.mov")) {
            try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(video: .audioM4A, sound: .none))
        }
        // The file's own format wins.
        let own = try Planner.plan(info, settings: settings, name: "a.mov", options: FileOptions(video: .movProRes))
        #expect(own.fileExtension == "mov" && own.targetTitle == "MOV (ProRes 422)")
    }

    @Test func presetsApplyAndSave() {
        var settings = ConvertSettings()
        settings.destination = .folder(URL(fileURLWithPath: "/tmp/x"))
        let web = Preset.builtIn.first { $0.id == "builtin.web" }!
        settings.apply(web)
        #expect(settings.video == .mp4H264 && settings.size == .p720 && settings.quality == .smaller)
        #expect(settings.destination == .folder(URL(fileURLWithPath: "/tmp/x")))
        #expect(web.matches(settings) && !Preset.builtIn[0].matches(settings))

        var library = PresetLibrary()
        let saved = library.save("  Podcast ", from: settings)
        #expect(saved.name == "Podcast" && library.saved.count == 1)
        settings.audio = .wav
        library.save("podcast", from: settings)
        #expect(library.saved.count == 1 && library.saved[0].audio == .wav && library.saved[0].id == saved.id)
        library.save("Archive", from: settings)
        library.rename(saved.id, to: "Show")
        #expect(library.saved.map(\.name) == ["Show", "Archive"])
        library.move(fromOffsets: [1], toOffset: 0)
        #expect(library.saved.map(\.name) == ["Archive", "Show"])
        library.delete(saved.id)
        #expect(library.saved.map(\.name) == ["Archive"])
        let noProRes = Capabilities(writableImageTypes: ["public.jpeg", "public.png", "public.heic", "public.tiff", "com.compuserve.gif"],
                                    canEncodeHEVC: true, canEncodeProRes: false)
        #expect(!Preset.available(noProRes).contains { $0.video == .movProRes })
    }

    @Test func originalsOnlyGoToTheTrashWhenTheNewFileIsThere() throws {
        let folder = try makeTempFolder()
        let original = folder.appendingPathComponent("a.wav"), output = folder.appendingPathComponent("a.m4a")
        try Data([1, 2, 3]).write(to: original)
        let trasher = FakeTrasher()
        // No output yet.
        #expect(!AfterConversion.trashOriginal(original, output: output, trasher: trasher))
        try Data().write(to: output)
        // An empty output doesn't count.
        #expect(!AfterConversion.trashOriginal(original, output: output, trasher: trasher))
        try Data([9]).write(to: output)
        #expect(!AfterConversion.trashOriginal(original, output: original, trasher: trasher))
        #expect(AfterConversion.trashOriginal(original, output: output, trasher: trasher))
        #expect(trasher.trashed == [original])
        #expect(FileManager.default.fileExists(atPath: original.path)) // the fake moved nothing
    }
}

/// Options applied to real files. Audio and PNG run everywhere; video needs a media engine.
@Suite(.timeLimit(.minutes(5))) struct OptionsMediaTests {
    @Test func trimmedSound() async throws {
        let input = try fixture("Interview.wav") { try FixtureMaker.audio($0, seconds: 6) }
        let result = try report(try await converter().run(input, options: FileOptions(trim: TrimRange(start: 1.5, end: 4))))
        let out = try await playBack(result.output)
        #expect(abs(out.duration - 2.5) < 0.1, "\(out.duration)")
        #expect(result.summary == "M4A (AAC) · 160 kbps · 0:03")
        #expect(result.notes.contains("Trimmed to 0:01.5 – 0:04.0."))
        // Lossless too.
        let wav = try report(try await converter { $0.audio = .aiff }.run(input, options: FileOptions(trim: TrimRange(start: 0, end: 1))))
        #expect(abs(try await playBack(wav.output).duration - 1) < 0.02)
    }

    @Test func eachFileCanHaveItsOwnFormat() async throws {
        let input = try fixture("Loop.wav") { try FixtureMaker.audio($0, seconds: 1) }
        let alac = try report(try await converter().run(input, options: FileOptions(audio: .alac)))
        #expect(alac.output.pathExtension == "m4a")
        #expect(try await playBack(alac.output).audioCodec == "alac")
        let photo = try fixture("Shot.png") { try FixtureMaker.image($0, type: .png, width: 300, height: 200) }
        let tiff = try report(try await converter().run(photo, options: FileOptions(image: .tiff)))
        #expect(tiff.output.pathExtension == "tiff")
    }

    @Test func turnedAndMirroredImages() async throws {
        // The fixture has a red marker in its top-left corner.
        let input = try fixture("Marker.png") { try FixtureMaker.image($0, type: .png, width: 300, height: 200) }
        let right = try report(try await converter { $0.image = .png }.run(input, options: FileOptions(transform: .identity.rotatedRight())))
        #expect(right.summary == "PNG · 200×300")
        let turned = firstImage(right.output)!
        #expect(turned.width == 200 && turned.height == 300)
        // Turned right, the top-left corner is now the top-right one.
        let topRight = averageColor(turned, x: 0.78, y: 0.08, width: 0.12, height: 0.15)
        let topLeft = averageColor(turned, x: 0.03, y: 0.03, width: 0.25, height: 0.15)
        #expect(topRight.r > 0.6 && topRight.g < 0.3, "\(topRight)")
        #expect(topLeft.g > 0.4, "\(topLeft)")
        // Mirrored: the marker is at the top right, size unchanged; same format isn't "already PNG".
        let mirror = try report(try await converter { $0.image = .png }.run(input, options: FileOptions(transform: .identity.flippedHorizontally())))
        let flipped = firstImage(mirror.output)!
        #expect(flipped.width == 300 && flipped.height == 200)
        let marker = averageColor(flipped, x: 0.78, y: 0.1, width: 0.15, height: 0.12)
        #expect(marker.r > 0.6 && marker.g < 0.3, "\(marker)")
        #expect(imageProperties(mirror.output)[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
    }

    @Test(.needsMediaEngine) func trimmedVideoIsCopiedAndStartsAtTheCut() async throws {
        let input = try videoFixture { $0.seconds = 4 }
        let result = try report(try await converter().run(input, options: FileOptions(trim: TrimRange(start: 1, end: 3))))
        #expect(result.repackaged)
        let out = try await playBack(result.output)
        #expect(abs(out.duration - 2) < 0.1, "\(out.duration)")
        // The first frame shown is the one at 1 s in the original.
        let a = try await averageColor(ofVideo: input, at: 1.2)
        let b = try await averageColor(ofVideo: result.output, at: 0.2)
        #expect(colorDistance(a, b) < 0.03, "\(a) vs \(b)")
        // Re-encoded trims too.
        let small = try report(try await converter { $0.quality = .smaller }.run(input, options: FileOptions(trim: TrimRange(start: 2, end: 3.5))))
        #expect(abs(try await playBack(small.output).duration - 1.5) < 0.1)
    }

    @Test(.needsMediaEngine) func turnedVideoIsLosslessAndMirroredIsRedrawn() async throws {
        let input = try videoFixture { $0.width = 640; $0.height = 360 }
        let turned = try report(try await converter().run(input, options: FileOptions(transform: .identity.rotatedLeft())))
        #expect(turned.repackaged && turned.summary == "MP4 (H.264) · 360×640 · 0:02")
        #expect(try await playBack(turned.output).displaySize == CGSize(width: 360, height: 640))
        let source = try await videoFrame(input, at: 1)
        let left = try await videoFrame(turned.output, at: 1)
        // Turned left: the source's left edge is now the bottom.
        #expect(colorDistance(averageColor(source, x: 0, y: 0, width: 0.1, height: 1),
                              averageColor(left, x: 0, y: 0.9, width: 1, height: 0.1)) < 0.05)

        let mirrored = try report(try await converter().run(input, options: FileOptions(transform: .identity.flippedHorizontally())))
        #expect(!mirrored.repackaged)
        let out = try await playBack(mirrored.output)
        #expect(out.displaySize == CGSize(width: 640, height: 360) && abs(out.duration - 2) < 0.1)
        let flipped = try await videoFrame(mirrored.output, at: 1)
        // Left and right trade places (the gradient runs left to right).
        let srcLeft = averageColor(source, x: 0, y: 0.1, width: 0.1, height: 0.15)
        let outRight = averageColor(flipped, x: 0.9, y: 0.1, width: 0.1, height: 0.15)
        #expect(colorDistance(srcLeft, outRight) < 0.06, "\(srcLeft) vs \(outRight)")
    }

    @Test(.needsMediaEngine) func soundTrackChoice() async throws {
        let input = try videoFixture { $0.audioTracks = 2 }
        let info = try await MediaProbe.probe(input)
        #expect(info.audioTracks.count == 2 && info.audioTracks[1].title.hasPrefix("Track 2"))
        let second = try report(try await converter().run(input, options: FileOptions(sound: .track(1))))
        #expect(!second.notes.contains { $0.contains("mixed") })
        #expect(try await playBack(second.output).audioTracks == 1)
        let silent = try report(try await converter().run(input, options: FileOptions(sound: .none)))
        let out = try await playBack(silent.output)
        #expect(out.audioTracks == 0 && out.videoCodec == "avc1")
    }

    @Test(.needsMediaEngine) func gifFromATrimmedTurnedClip() async throws {
        let input = try videoFixture { $0.seconds = 3 }
        let result = try report(try await converter { $0.video = .gif }.run(
            input, options: FileOptions(trim: TrimRange(start: 1, end: 2), transform: .identity.rotatedRight())))
        #expect(result.summary == "GIF · 360×640 · 0:01")
        #expect(imageFrameCount(result.output) == 12)
    }

    @Test(.needsMediaEngine) func mergingVideosOfDifferentShapes() async throws {
        let a = try videoFixture("Part 1.mov") { $0.width = 640; $0.height = 360; $0.seconds = 2 }
        let b = try videoFixture("Part 2.mov") { $0.width = 360; $0.height = 640; $0.seconds = 1; $0.audioTracks = 0 }
        let c = try videoFixture("Part 3.mov") { $0.width = 640; $0.height = 360; $0.seconds = 1; $0.codec = .hevc }
        let result = try await converter().merge([a, b, c])
        #expect(result.output.lastPathComponent == "Part 1 Merged.mp4")
        #expect(result.output.deletingLastPathComponent() == a.deletingLastPathComponent())
        #expect(result.summary == "MP4 (H.264) · 640×360 · 0:04")
        #expect(result.notes.contains("Merged from 3 files.") && result.notes.contains { $0.contains("black bars") })
        let out = try await playBack(result.output)
        #expect(abs(out.duration - 4) < 0.15 && out.videoCodec == "avc1" && out.audioTracks == 1)
        #expect(out.displaySize == CGSize(width: 640, height: 360))
        // The portrait part sits in the middle with black bars at the sides.
        let middle = try await videoFrame(result.output, at: 2.5)
        let side = averageColor(middle, x: 0, y: 0.3, width: 0.1, height: 0.4)
        #expect(side.r < 0.05 && side.g < 0.05 && side.b < 0.05, "\(side)")
        // Merging again doesn't overwrite.
        #expect(try await converter().merge([a, b]).output.lastPathComponent == "Part 1 Merged 2.mp4")
    }

    @Test func mergingSound() async throws {
        let folder = try makeTempFolder()
        let a = folder.appendingPathComponent("Intro.wav"), b = folder.appendingPathComponent("Talk.m4a")
        try FixtureMaker.audio(a, seconds: 1)
        try FixtureMaker.audio(b, seconds: 2, channels: 1)
        let result = try await converter().merge([a, b])
        #expect(result.output.lastPathComponent == "Intro Merged.m4a")
        let out = try await playBack(result.output)
        #expect(out.audioCodec == "aac " && abs(out.duration - 3) < 0.1)
        let wav = try await converter { $0.audio = .wav }.merge([b, a])
        #expect(wav.output.lastPathComponent == "Talk Merged.wav")
        #expect(abs(try await playBack(wav.output).duration - 3) < 0.05)
    }

    @Test func mergeRefusesWhatItCantJoin() async throws {
        let folder = try makeTempFolder()
        let a = folder.appendingPathComponent("a.wav"), p = folder.appendingPathComponent("p.png")
        try FixtureMaker.audio(a, seconds: 1)
        try FixtureMaker.image(p, type: .png, width: 50, height: 50)
        await #expect(throws: ConvertError.cantMerge(reason: "Choose two or more files to merge.")) { try await converter().merge([a]) }
        await #expect(throws: ConvertError.cantMerge(reason: "Only videos and sound files can be merged.")) { try await converter().merge([a, p]) }
        #expect(try visibleFiles(folder) == ["a.wav", "p.png"])
    }
}
