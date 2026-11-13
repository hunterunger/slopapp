import Foundation
import Testing
@testable import ConvertCore

func h264Clip(width: Int = 1920, height: Int = 1080, audio: String? = "aac ", bitRate: Double = 128_000) -> MediaInfo {
    sampleInfo { info in
        info.width = width; info.height = height
        info.videoCodec = "avc1"; info.frameRate = 30; info.duration = 10
        if let audio {
            info.audioCodec = audio; info.audioTrackCount = 1; info.channels = 2
            info.sampleRate = 44_100; info.audioBitRate = bitRate
        }
    }
}

@Suite struct PlannerTests {
    let settings = ConvertSettings()

    @Test func containerOnlyChangeIsARepackage() throws {
        let plan = try Planner.plan(h264Clip(), settings: settings, name: "clip.mov")
        #expect(plan.fileType == .mp4 && plan.fileExtension == "mp4")
        #expect(plan.video == .copy && plan.audio == .copy)
        #expect(plan.isRepackage && plan.notes.isEmpty)
        #expect(Planner.isNoOp(plan, info: h264Clip(), inputExtension: "mov") == false)
        #expect(Planner.isNoOp(plan, info: h264Clip(), inputExtension: "MP4") == true)
    }

    @Test func smallerAlwaysReencodesThePicture() throws {
        var s = settings
        s.quality = .smaller
        let plan = try Planner.plan(h264Clip(), settings: s, name: "clip.mov")
        guard case .encode(let e)? = plan.video else { Issue.record("expected encode"); return }
        #expect(e.codec == .h264 && e.width == 1920 && e.height == 1080)
        #expect(e.quality == QualityTable.videoQuality(.smaller))
        // 128 kbps AAC is above Smaller's 96 kbps (with headroom): re-encoded too.
        #expect(plan.audio == .encode(AudioEncoding(format: .aac(bitRate: 96_000), sampleRate: 44_100, channels: 2)))
        // Small AAC is copied even for Smaller.
        let small = try Planner.plan(h264Clip(bitRate: 96_000), settings: s, name: "clip.mov")
        #expect(small.audio == .copy)
    }

    @Test func otherCodecsAreReencoded() throws {
        var info = h264Clip()
        info.videoCodec = "hvc1"
        let plan = try Planner.plan(info, settings: settings, name: "clip.mov")
        guard case .encode(let e)? = plan.video else { Issue.record("expected encode"); return }
        #expect(e.codec == .h264 && e.quality == 0.55)
        #expect(plan.audio == .copy)
        var hevc = settings
        hevc.video = .mp4HEVC
        #expect(try Planner.plan(info, settings: hevc, name: "clip.mov").video == .copy)
    }

    @Test func sizeLimitFitsEitherWayRoundAndNeverEnlarges() throws {
        var s = settings
        s.size = .p720
        let landscape = try Planner.plan(h264Clip(), settings: s, name: "a.mov")
        guard case .encode(let e)? = landscape.video else { Issue.record("expected encode"); return }
        #expect((e.width, e.height) == (1280, 720))
        let portrait = try Planner.plan(h264Clip(width: 1080, height: 1920), settings: s, name: "a.mov")
        guard case .encode(let p)? = portrait.video else { Issue.record("expected encode"); return }
        #expect((p.width, p.height) == (720, 1280))
        // A small clip under a big limit: nothing to shrink, so it's copied.
        s.size = .p1080
        #expect(try Planner.plan(h264Clip(width: 640, height: 360), settings: s, name: "a.mov").video == .copy)
        #expect(Planner.fit(640, 360, in: SizeLimit.p2160.box) == (640, 360))
        #expect(Planner.fit(4032, 3024, in: SizeLimit.p1080.box) == (1440, 1080))
    }

    @Test func h264CapsHugeFramesAndSaysSo() throws {
        var info = h264Clip(width: 5120, height: 2880)
        info.videoCodec = "apcn"
        let plan = try Planner.plan(info, settings: settings, name: "a.mov")
        guard case .encode(let e)? = plan.video else { Issue.record("expected encode"); return }
        #expect((e.width, e.height) == (4096, 2304))
        #expect(plan.notes.first?.contains("4096×2304") == true)
        var hevc = settings
        hevc.video = .mp4HEVC
        guard case .encode(let h)? = try Planner.plan(info, settings: hevc, name: "a.mov").video else { return }
        #expect((h.width, h.height) == (5120, 2880))
    }

    @Test func oddSizesBecomeEven() throws {
        var info = h264Clip(width: 1279, height: 721)
        info.videoCodec = "apcn"
        guard case .encode(let e)? = try Planner.plan(info, settings: settings, name: "a.mov").video else { return }
        #expect((e.width, e.height) == (1278, 720))
    }

    @Test func hdrToneMapsForH264AndStaysHDRInHEVC() throws {
        var info = h264Clip()
        info.videoCodec = "hvc1"; info.isHDR = true
        let toH264 = try Planner.plan(info, settings: settings, name: "a.mov")
        guard case .encode(let e)? = toH264.video else { return }
        #expect(e.toSDR && !e.keepHDR)
        #expect(toH264.notes.contains("HDR was converted to standard range."))
        var hevc = settings
        hevc.video = .mp4HEVC; hevc.quality = .smaller
        guard case .encode(let h)? = try Planner.plan(info, settings: hevc, name: "a.mov").video else { return }
        #expect(h.keepHDR && !h.toSDR)
    }

    @Test func audioOnlyTargetsNeedSound() throws {
        var s = settings
        s.video = .audioM4A
        #expect(throws: ConvertError.noSound(name: "silent.mp4")) {
            try Planner.plan(h264Clip(audio: nil), settings: s, name: "silent.mp4")
        }
        let plan = try Planner.plan(h264Clip(), settings: s, name: "clip.mov")
        #expect(plan.video == nil && plan.audio == .copy && plan.fileExtension == "m4a")
        s.video = .audioWAV
        let wav = try Planner.plan(h264Clip(), settings: s, name: "clip.mov")
        #expect(wav.audio == .encode(AudioEncoding(format: .pcm(bits: 16, bigEndian: false), sampleRate: 44_100, channels: 2)))
    }

    @Test func severalSoundTracksAreMixed() throws {
        var info = h264Clip()
        info.audioTrackCount = 2
        let plan = try Planner.plan(info, settings: settings, name: "a.mov")
        #expect(plan.video == .copy)
        guard case .encode = plan.audio else { Issue.record("expected a mix"); return }
        #expect(plan.notes == ["Its 2 sound tracks were mixed into one."])
    }

    @Test func audioTargets() throws {
        let wav24 = sampleInfo(.audio) { i in
            i.audioCodec = "lpcm"; i.audioTrackCount = 1; i.channels = 2; i.sampleRate = 96_000; i.bitsPerSample = 24
        }
        var s = settings
        // AAC tops out at 48 kHz.
        guard case .encode(let aac) = try Planner.plan(wav24, settings: s, name: "a.wav").audio else { return }
        #expect(aac.sampleRate == 48_000 && aac.format == .aac(bitRate: 160_000))
        s.audio = .aiff
        let aiff = try Planner.plan(wav24, settings: s, name: "a.wav")
        #expect(aiff.audio == .encode(AudioEncoding(format: .pcm(bits: 24, bigEndian: true), sampleRate: 96_000, channels: 2)))
        #expect(aiff.fileExtension == "aiff")
        s.audio = .wav
        let wav = try Planner.plan(wav24, settings: s, name: "a.wav")
        #expect(Planner.isNoOp(wav, info: wav24, inputExtension: "wav"))
        #expect(!Planner.isNoOp(aiff, info: wav24, inputExtension: "wav"))
        s.audio = .alac
        var alac = wav24
        alac.audioCodec = "alac"
        #expect(try Planner.plan(alac, settings: s, name: "a.m4a").audio == .copy)
        // Mono stays mono, at half the bit rate.
        var mono = wav24
        mono.channels = 1; mono.sampleRate = 44_100
        s.audio = .m4a
        #expect(try Planner.plan(mono, settings: s, name: "a.wav").audio
                == .encode(AudioEncoding(format: .aac(bitRate: 80_000), sampleRate: 44_100, channels: 1)))
    }

    @Test func proResKeepsPCMSound() throws {
        var s = settings
        s.video = .movProRes
        let plan = try Planner.plan(h264Clip(), settings: s, name: "a.mov")
        #expect(plan.fileExtension == "mov")
        guard case .encode(let e)? = plan.video else { return }
        #expect(e.codec == .proRes422 && e.quality == nil)
        #expect(plan.audio == .encode(AudioEncoding(format: .pcm(bits: 16, bigEndian: false), sampleRate: 44_100, channels: 2)))
    }

    @Test func gifShapeAndTiming() {
        let clip = h264Clip(width: 1280, height: 720)
        #expect(GIFMaker.shape(clip, quality: .balanced, size: .original) == (640, 360, 12))
        #expect(GIFMaker.shape(clip, quality: .smaller, size: .original) == (480, 270, 10))
        var portrait = clip
        portrait.isRotated = true
        #expect(GIFMaker.shape(portrait, quality: .balanced, size: .original) == (360, 640, 12))
        let tiny = h264Clip(width: 320, height: 180)
        #expect(GIFMaker.shape(tiny, quality: .best, size: .original) == (320, 180, 15))
        var slow = clip
        slow.frameRate = 8
        #expect(GIFMaker.shape(slow, quality: .best, size: .p480).fps == 8)
        #expect(GIFMaker.shape(clip, quality: .best, size: .p480).width == 800)

        let delays = GIFMaker.delays(count: 24, fps: 12)
        #expect(abs(delays.reduce(0, +) - 2.0) < 0.011)
        #expect(Set(delays) == [0.08, 0.09])
        #expect(GIFMaker.delays(count: 10, fps: 60).allSatisfy { $0 >= 0.02 })
    }

    @Test func settingsDecodeLeniently() throws {
        let json = #"{"video":"webm","audio":"wav","quality":"best"}"#
        let s = try JSONDecoder().decode(ConvertSettings.self, from: Data(json.utf8))
        #expect(s.video == .mp4H264 && s.audio == .wav && s.quality == .best && s.image == .jpeg)
        let round = try JSONDecoder().decode(ConvertSettings.self, from: JSONEncoder().encode(s))
        #expect(round == s)
    }

    @Test func wording() {
        #expect(Durations.string(7.4) == "0:07")
        #expect(Durations.string(134) == "2:14")
        #expect(Durations.string(3723) == "1:02:03")
        var info = h264Clip(width: 1080, height: 1920)
        info.isRotated = true
        info.videoCodec = "hvc1"
        #expect(info.summary == "HEVC · 1920×1080 · 0:10")
        #expect(Codecs.audioName(".mp3") == "MP3")
        #expect(MediaTypes.unreadableFormatName(for: URL(fileURLWithPath: "/a/b.WMV")) == "WMV")
        // MKV and WebM have their own reader now.
        #expect(MediaTypes.unreadableFormatName(for: URL(fileURLWithPath: "/a/b.mkv")) == nil)
        #expect(MediaTypes.kind(of: URL(fileURLWithPath: "/a/b.mov")) == .video)
        #expect(MediaTypes.kind(of: URL(fileURLWithPath: "/a/b.mp3")) == .audio)
        #expect(MediaTypes.kind(of: URL(fileURLWithPath: "/a/b.heic")) == .image)
        #expect(MediaTypes.kind(of: URL(fileURLWithPath: "/a/b.txt")) == nil)
        #expect(ConvertError.unreadableFormat(name: "a.mkv", format: "MKV").errorDescription
                == "Convert can't read MKV files. macOS has no reader for them.")
    }

    @Test func signaturesOnlyChangeWithWhatMatters() {
        var s = ConvertSettings()
        let video = s.signature(for: .video), audio = s.signature(for: .audio), image = s.signature(for: .image)
        s.image = .png
        #expect(s.signature(for: .video) == video && s.signature(for: .image) != image)
        s.size = .p720
        #expect(s.signature(for: .audio) == audio && s.signature(for: .video) != video)
        // PNG is lossless: quality doesn't change it.
        let png = s.signature(for: .image)
        s.quality = .best
        #expect(s.signature(for: .image) == png && s.signature(for: .audio) != audio)
        #expect(ConvertError.damaged(name: "a").isFinal && !ConvertError.noSound(name: "a").isFinal)
    }

    @Test func candidatesFollowFinder() {
        let url = URL(fileURLWithPath: "/tmp/x/clip.mp4")
        let c = OutputPlanner.candidates(for: url, limit: 3).map(\.lastPathComponent)
        #expect(c == ["clip.mp4", "clip 2.mp4", "clip 3.mp4"])
        let folder = URL(fileURLWithPath: "/tmp/out")
        #expect(OutputPlanner.preferredURL(for: URL(fileURLWithPath: "/tmp/x/a.b.mov"), ext: "mp4", destination: .folder(folder)).path
                == "/tmp/out/a.b.mp4")
    }
}
