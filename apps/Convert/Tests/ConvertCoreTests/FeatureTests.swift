import AVFoundation
import AudioToolbox
import ConvertFixtures
import Foundation
import ImageIO
import Testing
@testable import ConvertCore

private func surround(_ channels: Int, codec: String = "ac-3") -> MediaInfo {
    var info = h264Clip()
    info.audioCodec = codec
    info.channels = channels
    info.sampleRate = 48_000
    return info
}

/// Surround, FLAC, crop, subtitles and file sizes: the planning rules.
@Suite struct FeaturePlanningTests {
    let settings = ConvertSettings()

    @Test func surroundIsKeptWhereTheFormatAllows() throws {
        // 5.1 AC-3 → AAC 5.1 at the surround rate, in AAC's channel order.
        let plan = try Planner.plan(surround(6), settings: settings, name: "a.mkv")
        #expect(plan.audio == .encode(AudioEncoding(format: .aac(bitRate: 384_000), sampleRate: 48_000, channels: 6,
                                                    layout: kAudioChannelLayoutTag_MPEG_5_1_D)))
        // 5.1 AAC is copied as it is.
        #expect(try Planner.plan(surround(6, codec: "aac "), settings: settings, name: "a.mov").audio == .copy)
        // 7.1: AAC 7.1; FLAC and WAV 7.1 in WAV order; Apple Lossless stops at 5.1 and says so.
        var s = settings
        s.audio = .m4a
        let eight = surround(8, codec: "lpcm")
        var audio = eight
        audio.kind = .audio; audio.videoCodec = nil
        #expect(try Planner.plan(audio, settings: s, name: "a.wav").audio
                == .encode(AudioEncoding(format: .aac(bitRate: 448_000), sampleRate: 48_000, channels: 8, layout: kAudioChannelLayoutTag_AAC_7_1)))
        s.audio = .flac
        let flac = try Planner.plan(audio, settings: s, name: "a.wav")
        #expect(flac.usesAudioFile && flac.fileExtension == "flac")
        #expect(flac.audio == .encode(AudioEncoding(format: .flac(bits: 16), sampleRate: 48_000, channels: 8, layout: kAudioChannelLayoutTag_MPEG_7_1_C)))
        s.audio = .alac
        let alac = try Planner.plan(audio, settings: s, name: "a.wav")
        guard case .encode(let a) = alac.audio else { Issue.record("expected encode"); return }
        #expect(a.channels == 6 && alac.notes == ["Apple Lossless keeps up to 5.1, so its 7.1 sound was mixed to 5.1."])
        // Odd counts become stereo, with a note.
        let four = try Planner.plan(surround(4), settings: settings, name: "a.mov")
        #expect(four.notes.contains("Its 4 sound channels were mixed to stereo."))
    }

    @Test func stereoMixDownIsAChoice() throws {
        let plan = try Planner.plan(surround(6, codec: "aac "), settings: settings, name: "a.mov", options: FileOptions(stereo: true))
        #expect(plan.audio == .encode(AudioEncoding(format: .aac(bitRate: 160_000), sampleRate: 48_000, channels: 2)))
    }

    @Test func flacTargets() throws {
        var s = settings
        s.audio = .flac
        let flac = sampleInfo(.audio) { i in
            i.audioCodec = "flac"; i.audioTrackCount = 1; i.channels = 2; i.sampleRate = 44_100; i.bitsPerSample = 16
        }
        let plan = try Planner.plan(flac, settings: s, name: "a.flac")
        #expect(Planner.isNoOp(plan, info: flac, inputExtension: "flac"))
        var wav = flac
        wav.audioCodec = "lpcm"
        #expect(!Planner.isNoOp(try Planner.plan(wav, settings: s, name: "a.wav"), info: wav, inputExtension: "wav"))
        #expect(Capabilities(writableImageTypes: [], canEncodeHEVC: true, canEncodeProRes: true, audioEncoders: ["aac "])
            .audioTargets == [.m4a, .alac, .wav, .aiff])
        #expect(AudioTarget.flac.title == "FLAC" && !AudioTarget.flac.usesQuality)
    }

    @Test func webPOnlyWhereImageIOWritesIt() {
        let none = Capabilities(writableImageTypes: ["public.jpeg", "public.png"], canEncodeHEVC: true, canEncodeProRes: true)
        #expect(!none.imageTargets.contains(.webp))
        let some = Capabilities(writableImageTypes: ["public.jpeg", "org.webmproject.webp"], canEncodeHEVC: true, canEncodeProRes: true)
        #expect(some.imageTargets == [.jpeg, .webp])
        // This Mac, today: ImageIO can't write WebP, so it isn't offered.
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        #expect(Capabilities.system.canWrite(.webp) == writable.contains("org.webmproject.webp"))
    }

    @Test func subtitlesAreKeptBurnedOrDropped() throws {
        var info = h264Clip()
        info.subtitleTracks = [SubtitleTrackInfo(index: 0, format: "tx3g", language: "English"),
                               SubtitleTrackInfo(index: 1, format: "c608")]
        let keep = try Planner.plan(info, settings: settings, name: "a.mov")
        #expect(keep.subtitles == .copy([0, 1]) && keep.video == .copy)
        #expect(Planner.isNoOp(keep, info: info, inputExtension: "mp4"))
        let none = try Planner.plan(info, settings: settings, name: "a.mp4", options: FileOptions(subtitles: .none))
        #expect(none.subtitles == .none && !Planner.isNoOp(none, info: info, inputExtension: "mp4"))
        let burn = try Planner.plan(info, settings: settings, name: "a.mp4", options: FileOptions(subtitles: .burn(0)))
        guard case .encode(let e)? = burn.video else { Issue.record("burning redraws the picture"); return }
        #expect(burn.subtitles == .burn(0) && e.upright && (e.width, e.height) == (1920, 1080))
        // Closed captions can't be drawn: burning them is ignored.
        let captions = try Planner.plan(info, settings: settings, name: "a.mp4", options: FileOptions(subtitles: .burn(1)))
        #expect(captions.subtitles == .none)
        // Sound only: no subtitles.
        var s = settings
        s.video = .audioM4A
        #expect(try Planner.plan(info, settings: s, name: "a.mp4").subtitles == .none)
    }

    @Test func cropRectangles() {
        let crop = CropRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        #expect(crop.pixels(width: 1920, height: 1080) == CGRect(x: 480, y: 108, width: 960, height: 864))
        // Even edges for video; never smaller than 2×2.
        let odd = CropRect(x: 0.3333, y: 0.3333, width: 0.3333, height: 0.3333).pixels(width: 101, height: 101, even: true)
        #expect(Int(odd.minX) % 2 == 0 && Int(odd.width) % 2 == 0 && Int(odd.height) % 2 == 0)
        #expect(CropRect(x: 0.5, y: 0.5, width: 0.0001, height: 0.0001).pixels(width: 100, height: 100, even: true).width == 2)
        // Clamped to the picture.
        let clamped = CropRect(x: -1, y: 0.9, width: 5, height: 5)
        #expect(clamped.x == 0 && clamped.width == 1 && abs(clamped.height - 0.1) < 1e-9)
        #expect(CropRect.whole.isWhole && !crop.isWhole)
        // Turning moves the rectangle with the picture, and back.
        let right = crop.turned(by: PictureTransform(quarterTurns: 1))
        #expect(abs(right.x - 0.1) < 1e-9 && abs(right.y - 0.25) < 1e-9 && abs(right.width - 0.8) < 1e-9)
        for turn in [PictureTransform(quarterTurns: 1), PictureTransform(quarterTurns: 2, mirrored: true), PictureTransform(quarterTurns: 3)] {
            let back = crop.turned(by: turn).unturned(by: turn)
            #expect(abs(back.x - crop.x) < 1e-9 && abs(back.y - crop.y) < 1e-9 && abs(back.width - crop.width) < 1e-9)
        }
        // 16:9 inside a 4:3 picture: full width, bars top and bottom.
        let wide = CropRect.centered(aspect: 16.0 / 9, width: 1440, height: 1080)
        #expect(wide.x == 0 && wide.width == 1 && abs(wide.height - 0.75) < 1e-9 && abs(wide.y - 0.125) < 1e-9)
    }

    @Test func findsBlackBars() throws {
        func frame(barTop: Int, barSide: Int, dark: Bool = false) -> CGImage {
            let ctx = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
            ctx.setFillColor(CGColor(gray: dark ? 0.05 : 0.6, alpha: 1))
            ctx.fill(CGRect(x: barSide, y: barTop, width: 1280 - 2 * barSide, height: 720 - 2 * barTop))
            return ctx.makeImage()!
        }
        // Letterboxed 2.35:1 in 16:9: 88 rows of black top and bottom.
        let found = try #require(BlackBars.detect([frame(barTop: 88, barSide: 0)]))
        #expect(found.pixels(width: 1280, height: 720, even: true) == CGRect(x: 0, y: 88, width: 1280, height: 544))
        // Pillarboxed too.
        let pillar = try #require(BlackBars.detect([frame(barTop: 0, barSide: 160)]))
        #expect(pillar.pixels(width: 1280, height: 720, even: true).width == 960)
        // A dark scene in one frame doesn't cut into the picture: the frames are combined.
        let both = try #require(BlackBars.detect([frame(barTop: 88, barSide: 0), frame(barTop: 200, barSide: 0)]))
        #expect(abs(both.y - 88.0 / 720) < 0.003)
        // No bars, or an all-black frame: nothing to remove.
        #expect(BlackBars.detect([frame(barTop: 0, barSide: 0)]) == nil)
        #expect(BlackBars.detect([frame(barTop: 0, barSide: 0, dark: true)]) == nil)
    }

    @Test func cropRedrawsAtTheCroppedSize() throws {
        let options = FileOptions(crop: CropRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let plan = try Planner.plan(h264Clip(), settings: settings, name: "a.mov", options: options)
        guard case .encode(let e)? = plan.video else { Issue.record("expected encode"); return }
        #expect(e.upright && (e.width, e.height) == (960, 540) && e.crop == CGRect(x: 0, y: 0, width: 960, height: 540))
        // Then turned: the cropped picture, on its side.
        var turned = options
        turned.transform = PictureTransform(quarterTurns: 1)
        guard case .encode(let t)? = try Planner.plan(h264Clip(), settings: settings, name: "a.mov", options: turned).video else { return }
        #expect((t.width, t.height) == (540, 960))
        #expect(options.editSignature != FileOptions().editSignature)
    }

    @Test func sizeBudget() {
        let limit = FileSizeLimit(megabytes: 25)
        #expect(limit.title == "Under 25 MB" && FileSizeLimit(megabytes: 2.5).title == "Under 2.5 MB" && limit.bytes == 25_000_000)
        // 60 s of 1080p with stereo: 25 MB buys about 3.1 Mbps, an eighth (snapped) of it for sound.
        let minute = SizeBudget.video(limit, duration: 60, width: 1920, height: 1080, frameRate: 30, audioChannels: 2, quality: .balanced)
        #expect(minute.audioBitRate == 160_000 && minute.box == nil && !minute.isTight)
        // Split up so slower compilers (CI) can type-check it.
        let totalBits = Double(minute.videoBitRate + (minute.audioBitRate ?? 0))
        let fileBytes: Double = totalBits * 60 / 8
        let target: Double = 25_000_000 * 0.94
        #expect(abs(fileBytes - target) < 2_000)
        // Ten minutes: too few bits for 1080p, so a smaller frame.
        let ten = SizeBudget.video(limit, duration: 600, width: 1920, height: 1080, frameRate: 30, audioChannels: 2, quality: .balanced)
        #expect(ten.box.map { $0.long < 1920 } == true && ten.audioBitRate == 64_000)
        // Never more than the source had.
        let small = SizeBudget.video(limit, duration: 10, width: 1280, height: 720, frameRate: 30, audioChannels: nil,
                                     quality: .balanced, sourceVideoBitRate: 2_000_000)
        #expect(small.videoBitRate == 2_000_000 && small.audioBitRate == nil)
        // An hour in 10 MB: rough, and it says so.
        #expect(SizeBudget.video(FileSizeLimit(megabytes: 10), duration: 3600, width: 1920, height: 1080, frameRate: 30,
                                 audioChannels: 2, quality: .balanced).isTight)
        #expect(SizeBudget.audio(FileSizeLimit(megabytes: 1), duration: 60, channels: 2) == 112_000)
        #expect(SizeBudget.snapAAC(130_000) == 128_000 && SizeBudget.snapAAC(10_000) == 32_000)
    }

    @Test func sizePlans() throws {
        var s = settings
        s.fileSize = FileSizeLimit(megabytes: 10)
        var big = h264Clip()
        big.fileBytes = 40_000_000
        big.duration = 60
        let plan = try Planner.plan(big, settings: s, name: "a.mov")
        guard case .encode(let e)? = plan.video else { Issue.record("expected encode"); return }
        #expect(e.bitRate != nil && e.quality == nil && plan.sizeLimit == s.fileSize)
        // Already small enough, and only the container changes: copied.
        var small = h264Clip()
        small.fileBytes = 3_000_000
        #expect(try Planner.plan(small, settings: s, name: "a.mov").isRepackage)
        // ProRes and lossless sound can't aim for a size, and say so.
        s.video = .movProRes
        #expect(try Planner.plan(big, settings: s, name: "a.mov").notes.contains("ProRes can't aim for a size, so it was made at full quality."))
        s.audio = .wav
        var audio = big
        audio.kind = .audio; audio.videoCodec = nil
        #expect(try Planner.plan(audio, settings: s, name: "a.mov").notes.contains("WAV is lossless, so it can't aim for a size."))
        // It's part of what makes a finished file out of date.
        var t = settings
        let before = t.signature(for: .video)
        t.fileSize = FileSizeLimit(megabytes: 25)
        #expect(t.signature(for: .video) != before)
        let decoded = try JSONDecoder().decode(ConvertSettings.self, from: JSONEncoder().encode(t))
        #expect(decoded.fileSize == t.fileSize)
    }

    @Test func retryGoesLower() throws {
        var s = settings
        s.fileSize = FileSizeLimit(megabytes: 10)
        var big = h264Clip()
        big.fileBytes = 40_000_000
        let plan = try Planner.plan(big, settings: s, name: "a.mov")
        guard case .encode(let e)? = plan.video, let rate = e.bitRate,
              let lower = plan.lowered(actual: 11_000_000, limit: s.fileSize!),
              case .encode(let l)? = lower.video, let lowerRate = l.bitRate else { Issue.record("expected a lower plan"); return }
        #expect(lowerRate < rate)
    }

    @Test func channelNames() {
        #expect(Channels.name(6) == "5.1" && Channels.name(8) == "7.1" && Channels.name(2) == "Stereo" && Channels.name(0) == nil)
        var info = surround(6)
        info.subtitleTracks = [SubtitleTrackInfo(index: 0, format: "tx3g"), SubtitleTrackInfo(index: 1, format: "tx3g")]
        #expect(info.cardLine.contains("AC-3 · 128 kbps · 5.1") && info.cardLine.contains("2 subtitles"))
    }

    @Test func oggIsTriedBeforeItIsRefused() async throws {
        // Named formats are only refused after AVFoundation fails to read them.
        let fake = try fixture("Song.ogg") { try Data("not an ogg file".utf8).write(to: $0) }
        await #expect(throws: ConvertError.unreadableFormat(name: "Song.ogg", format: "Ogg")) { try await MediaProbe.probe(fake) }
        let real = try fixture("Voice.flac") { try FixtureMaker.audio($0, seconds: 1) }
        #expect(try await MediaProbe.probe(real).audioCodec == "flac")
    }
}

/// Real conversions for the new features.
@Suite(.serialized, .needsMediaEngine, .timeLimit(.minutes(5))) struct FeatureConversionTests {
    @Test func surroundWAVToAACFLACAndStereo() async throws {
        let input = try fixture("Surround.wav") { try FixtureMaker.audio($0, seconds: 2, channels: 6, sampleRate: 48_000) }
        let aac = try report(try await converter().run(input))
        let a = try await playBack(aac.output)
        #expect(a.audioCodec == "aac " && aac.summary.contains("5.1"))
        #expect(try await channelCount(aac.output) == 6)
        let flac = try report(try await converter { $0.audio = .flac }.run(input))
        #expect(flac.output.pathExtension == "flac" && flac.summary == "FLAC · 5.1 · 0:02")
        #expect(try await channelCount(flac.output) == 6)
        let back = try await playBack(flac.output)
        #expect(back.audioCodec == "flac" && abs(back.duration - 2) < 0.05)
        // A 16-bit source stays 16-bit.
        let flacFormat = try #require(try await AVURLAsset(url: flac.output).loadTracks(withMediaType: .audio).first?.load(.formatDescriptions).first)
        #expect(CMAudioFormatDescriptionGetStreamBasicDescription(flacFormat)?.pointee.mFormatFlags == 1)
        // The centre channel (a 1320 Hz tone) stays in the centre: compare loudness per channel.
        let levels = try await channelLevels(flac.output)
        #expect(levels.count == 6 && levels.allSatisfy { $0 > 0.1 }, "\(levels)")
        let stereo = try report(try await converter().run(input, options: FileOptions(stereo: true)))
        #expect(try await channelCount(stereo.output) == 2)
    }

    @Test func sevenOneToAppleLosslessIsFiveOne() async throws {
        let input = try fixture("Theatre.wav") { try FixtureMaker.audio($0, seconds: 1, channels: 8, sampleRate: 48_000) }
        let alac = try report(try await converter { $0.audio = .alac }.run(input))
        #expect(try await channelCount(alac.output) == 6 && alac.notes.first?.contains("5.1") == true)
        let aac = try report(try await converter().run(input))
        #expect(try await channelCount(aac.output) == 8)
    }

    @Test func flacKeepsBitDepthAndTrims() async throws {
        let input = try fixture("Master.aiff") { try FixtureMaker.audio($0, seconds: 3, bits: 24) }
        let flac = try report(try await converter { $0.audio = .flac }.run(input, options: FileOptions(trim: TrimRange(start: 0.5, end: 2))))
        let back = try await playBack(flac.output)
        #expect(abs(back.duration - 1.5) < 0.05)
        let format = try #require(try await AVURLAsset(url: flac.output).loadTracks(withMediaType: .audio).first?.load(.formatDescriptions).first)
        #expect(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mFormatFlags == 3) // 24-bit source
        // FLAC → FLAC with nothing to change.
        let again = try await converter { $0.audio = .flac }.run(flac.output)
        #expect(again == .unchanged("Already FLAC. Nothing to change."))
    }

    @Test func cropsVideo() async throws {
        let input = try videoFixture { $0.width = 1280; $0.height = 720 }
        let crop = CropRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        let result = try report(try await converter().run(input, options: FileOptions(crop: crop)))
        let out = try await playBack(result.output)
        #expect(out.displaySize == CGSize(width: 640, height: 360) && result.notes.contains("Cropped to 640×360."))
        // The cropped picture is the top-right quarter of the original.
        let before = try await videoFrame(input, at: 1)
        let after = try await videoFrame(result.output, at: 1)
        #expect(colorDistance(averageColor(before, x: 0.5, y: 0, width: 0.5, height: 0.5), averageColor(after)) < 0.04)
    }

    @Test func cropsPhotosAndGIFs() async throws {
        let photo = try fixture("Photo.jpg") { try FixtureMaker.image($0, type: .jpeg, width: 800, height: 600) }
        let result = try report(try await converter { $0.image = .png }.run(photo, options: FileOptions(crop: CropRect(x: 0, y: 0.5, width: 0.5, height: 0.5))))
        let props = imageProperties(result.output)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 400 && props[kCGImagePropertyPixelHeight] as? Int == 300)
        // The red marker is in the bottom-left quarter, so the crop is mostly it and the gradient.
        let source = try #require(firstImage(photo))
        let cropped = try #require(firstImage(result.output))
        #expect(colorDistance(averageColor(source, x: 0, y: 0.5, width: 0.5, height: 0.5), averageColor(cropped)) < 0.03)
        let clip = try videoFixture { $0.width = 1280; $0.height = 720 }
        let gif = try report(try await converter { $0.video = .gif }.run(clip, options: FileOptions(crop: CropRect(x: 0, y: 0, width: 0.5, height: 1))))
        let gifProps = imageProperties(gif.output)
        let (w, h) = (gifProps[kCGImagePropertyPixelWidth] as? Int ?? 0, gifProps[kCGImagePropertyPixelHeight] as? Int ?? 0)
        let aspect: Double = Double(w) / Double(h)
        let expected: Double = 640.0 / 720
        #expect(abs(aspect - expected) < 0.02, "\(w)×\(h)")
    }

    @Test func videoFitsInASize() async throws {
        let input = try videoFixture { $0.width = 1280; $0.height = 720; $0.seconds = 4; $0.quality = 1; $0.codec = .hevc }
        // A third of the original: it has to be squeezed.
        let source = try #require(SystemFileStore().size(of: input))
        let limit = FileSizeLimit(megabytes: Double(source) / 3 / 1_000_000)
        let result = try report(try await converter { $0.fileSize = limit }.run(input))
        #expect(result.bytes <= limit.bytes, "\(result.bytes) bytes")
        #expect(try await playBack(result.output).playable)
    }

    @Test func soundFitsInASize() async throws {
        let input = try fixture("Talk.wav") { try FixtureMaker.audio($0, seconds: 20) }
        let limit = FileSizeLimit(megabytes: 0.2)
        let result = try report(try await converter { $0.fileSize = limit }.run(input))
        #expect(result.bytes <= limit.bytes && result.summary.contains("kbps"))
    }

    @Test func photosFitInASize() async throws {
        let photo = try fixture("Big.png") { try FixtureMaker.image($0, type: .png, width: 2400, height: 1800) }
        let limit = FileSizeLimit(megabytes: 0.05)
        let jpeg = try report(try await converter { $0.fileSize = limit }.run(photo))
        #expect(jpeg.bytes <= limit.bytes)
        let png = try report(try await converter { $0.image = .png; $0.fileSize = limit }.run(photo))
        #expect(png.bytes <= limit.bytes && png.notes.first?.hasPrefix("Made ") == true)
    }

    @Test func keepsAndBurnsMP4Subtitles() async throws {
        // An MP4 with a text track, made through the Matroska bridge.
        let mov = try videoFixture("source.mov")
        let mkv = mov.deletingLastPathComponent().appendingPathComponent("With Subs.mkv")
        try await MatroskaFixture.make(mkv, from: mov)
        let mp4 = try report(try await converter().run(mkv)).output
        let hevc = try report(try await converter { $0.video = .mp4HEVC }.run(mp4))
        #expect(try await SubtitleReader.cues(AVURLAsset(url: hevc.output), trackIndex: 0).map(\.text) == ["First line", "Second line"])
        let none = try report(try await converter { $0.video = .mp4HEVC }.run(mp4, options: FileOptions(subtitles: .none)))
        #expect(try await SubtitleReader.subtitleTracks(AVURLAsset(url: none.output)).isEmpty)
        let gif = try report(try await converter { $0.video = .gif }.run(mp4, options: FileOptions(subtitles: .burn(0))))
        #expect(gif.notes.contains("Subtitles are part of the picture."))
    }
}

func channelCount(_ url: URL) async throws -> Int {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
    let format = try #require(try await track.load(.formatDescriptions).first)
    return Int(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mChannelsPerFrame ?? 0)
}

/// Peak level per channel, decoded.
func channelLevels(_ url: URL) async throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    return (0..<Int(buffer.format.channelCount)).map { c in
        (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(buffer.floatChannelData![c][$1])) }
    }
}
