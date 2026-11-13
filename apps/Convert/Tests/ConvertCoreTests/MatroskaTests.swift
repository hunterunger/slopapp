import AVFoundation
import ConvertFixtures
import Foundation
import Testing
@testable import ConvertCore

private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
private func bytes(_ hex: String) -> Data {
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        data.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return data
}

/// The Matroska reader's byte handling and the codec records, checked against what
/// AVFoundation itself writes for the same streams.
@Suite struct MatroskaParsingTests {
    @Test func variableLengthIntegers() {
        #expect(EBMLReader.vint([0x81], at: 0, keepMarker: false)! == (1, 1))
        #expect(EBMLReader.vint([0x40, 0x02], at: 0, keepMarker: false)! == (2, 2))
        #expect(EBMLReader.vint([0x1A, 0x45, 0xDF, 0xA3], at: 0, keepMarker: true)! == (0x1A45_DFA3, 4))
        #expect(EBMLReader.vint([0x00], at: 0, keepMarker: false) == nil)
        #expect(EBMLReader.vint([0x40], at: 0, keepMarker: false) == nil) // cut short
    }

    @Test func unknownSizesAreRecognised() throws {
        let source = DataByteSource(Data([0x1F, 0x43, 0xB6, 0x75, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
        let element = try #require(try EBMLReader(source: source).element(at: 0))
        #expect(element.id == EBMLID.cluster && element.size == nil && element.dataStart == 12)
    }

    @Test func lacing() throws {
        // Xiph: 3 frames of 300, 2 and the rest (4).
        let xiph: [UInt8] = [2, 255, 45, 2] + Array(repeating: 1, count: 300) + [2, 2] + [3, 3, 3, 3]
        #expect(try MatroskaReader.unlace(xiph, from: 0, lacing: 1).map(\.count) == [300, 2, 4])
        // EBML: 3 frames of 5, 7 (+2) and the rest (1).
        let ebml: [UInt8] = [2, 0x85, 0xBF + 2] + Array(repeating: 9, count: 13)
        #expect(try MatroskaReader.unlace(ebml, from: 0, lacing: 3).map(\.count) == [5, 7, 1])
        // Fixed: 4 equal frames.
        #expect(try MatroskaReader.unlace([3] + Array(repeating: 0, count: 12), from: 0, lacing: 2).map(\.count) == [3, 3, 3, 3])
        #expect(throws: MatroskaError.self) { try MatroskaReader.unlace([3, 0, 0], from: 0, lacing: 2) }
    }

    @Test func notMatroska() {
        #expect(throws: MatroskaError.notMatroska) { try MatroskaReader(source: DataByteSource(Data("not really".utf8))) }
    }

    @Test func ac3AndEAC3CookiesMatchAVFoundations() throws {
        // The first frame of a 5.1 AC-3 stream, and the `dac3` box AVFoundation wrote for it.
        let ac3 = try #require(CodecBoxes.ac3(bytes("0b772b9a1e40ebf8")))
        #expect(hex(ac3.cookie) == "0000000b64616333103de0")
        #expect(ac3.channels == 6 && ac3.sampleRate == 48000 && ac3.samplesPerFrame == 1536)
        let eac3 = try #require(CodecBoxes.eac3(bytes("0b77037f3f87c000")))
        #expect(hex(eac3.cookie) == "0000000d646563330e00200f00")
        #expect(eac3.channels == 6 && eac3.samplesPerFrame == 1536)
        #expect(CodecBoxes.ac3(bytes("0000000000000000")) == nil)
    }

    @Test func flacCookieMatchesAVFoundations() throws {
        let streamInfo = "0400040000" + "00fc00018b0bb800f0000232800e9d7dce5ba2b3c21e0da827578eebfe"
        // Matroska stores "fLaC", then metadata blocks (here STREAMINFO, not marked last, and padding).
        let codecPrivate = Data("fLaC".utf8) + bytes("00000022" + streamInfo) + bytes("81000004") + Data(count: 4)
        let flac = try #require(CodecBoxes.flac(codecPrivate))
        #expect(hex(flac.cookie) == "0000003264664c6100000000" + "80000022" + streamInfo)
        #expect(flac.sampleRate == 48000 && flac.channels == 1 && flac.bitsPerSample == 16 && flac.maxBlockSize == 1024)
    }

    @Test func aacConfig() throws {
        let config = CodecBoxes.audioSpecificConfig(objectType: 2, sampleRate: 48000, channels: 2)
        #expect(hex(config) == "1190")
        let parsed = try #require(CodecBoxes.parseAudioSpecificConfig(config))
        #expect(parsed.objectType == 2 && parsed.sampleRate == 48000 && parsed.channels == 2)
        // ES_Descriptor ▸ DecoderConfig (AAC, audio) ▸ DecoderSpecificInfo = the config.
        let es = CodecBoxes.esDescriptor(objectType: 0x40, streamType: 5, specificInfo: config)
        #expect(es.first == 0x03 && hex(es).contains("0480808014401500") && hex(es).hasSuffix("05808080021190068080800102"))
    }

    @Test func vp9Config() {
        let config = CodecBoxes.vpcC(firstFrame: Data([0x82]), primaries: nil, transfer: nil, matrix: nil, fullRange: false)
        #expect(hex(config) == "010000000000820202020000")
        // Profile 2: 10-bit.
        let tenBit = CodecBoxes.vpcC(firstFrame: Data([0x90]), primaries: 9, transfer: 16, matrix: 9, fullRange: false)
        #expect(tenBit[4] == 2 && tenBit[6] >> 4 == 10 && tenBit[7] == 9 && tenBit[8] == 16)
    }

    @Test func packetLengths() {
        // Opus: config 31 (CELT 20 ms) × 1 frame; config 19 (CELT 20 ms) × 2; config 0 (SILK 10 ms) × 3.
        #expect(AudioPackets.opusFrames(Data([0xF8])) == 960)
        #expect(AudioPackets.opusFrames(Data([0x99])) == 1920)
        #expect(AudioPackets.opusFrames(Data([0x03, 0x03])) == 1440)
        // FLAC: block size code 10 (1024), and code 7 with the frame number coded in 2 bytes.
        #expect(AudioPackets.flacBlockSize(bytes("fff8aa08c28af5")) == 1024)
        #expect(AudioPackets.flacBlockSize(bytes("fff87a08c28c027f7c")) == 640)
        #expect(AudioPackets.flacBlockSize(bytes("fff87a08 0012 34".replacingOccurrences(of: " ", with: ""))) == 0x1234 + 1)
    }

    @Test func codecs() {
        func track(_ kind: MatroskaInfo.TrackKind, _ id: String, privateData: Data? = Data([1])) -> MatroskaInfo.Track {
            var t = MatroskaInfo.Track()
            t.kind = kind
            t.codecID = id
            t.codecPrivate = privateData
            return t
        }
        #expect(MatroskaCodec.classify(track(.video, "V_MPEG4/ISO/AVC")) == .video(fourCC: "avc1"))
        #expect(MatroskaCodec.classify(track(.video, "V_MPEGH/ISO/HEVC")) == .video(fourCC: "hvc1"))
        #expect(MatroskaCodec.classify(track(.video, "V_VP9", privateData: nil)) == .video(fourCC: "vp09"))
        #expect(MatroskaCodec.classify(track(.video, "V_VP8")) == .unsupported("VP8 video"))
        #expect(MatroskaCodec.classify(track(.audio, "A_AAC/MPEG4/LC/SBR", privateData: nil)) == .audio(fourCC: "aac "))
        #expect(MatroskaCodec.classify(track(.audio, "A_DTS")) == .unsupported("DTS sound"))
        #expect(MatroskaCodec.classify(track(.audio, "A_PCM/INT/LIT")) == .pcm(float: false, bigEndian: false))
        #expect(MatroskaCodec.classify(track(.subtitle, "S_TEXT/UTF8")) == .text(.srt))
        #expect(MatroskaCodec.classify(track(.subtitle, "S_HDMV/PGS")) == .unsupported("picture-based subtitles"))
    }

    @Test func selectionExplainsWhatIsLeftOut() {
        var info = MatroskaInfo()
        var video = MatroskaInfo.Track()
        video.kind = .video; video.number = 1; video.codecID = "V_AV1"; video.codecPrivate = Data([1])
        var dts = MatroskaInfo.Track()
        dts.kind = .audio; dts.number = 2; dts.codecID = "A_DTS"
        var ac3 = MatroskaInfo.Track()
        ac3.kind = .audio; ac3.number = 3; ac3.codecID = "A_AC3"
        var pgs = MatroskaInfo.Track()
        pgs.kind = .subtitle; pgs.number = 4; pgs.codecID = "S_HDMV/PGS"
        info.tracks = [video, dts, ac3, pgs]
        let withAV1 = MatroskaBridge.select(info, capabilities: DecoderCapabilities(vp9: true, av1: true))
        #expect(withAV1.video?.number == 1 && withAV1.audio.map(\.number) == [3] && withAV1.subtitles.isEmpty)
        #expect(withAV1.notes == ["Its DTS sound can't be read on a Mac, so it was left out.",
                                  "Picture-based subtitles can't be read on a Mac, so they were left out."])
        // A Mac with no AV1 decoder: only the sound comes along.
        let withoutAV1 = MatroskaBridge.select(info, capabilities: DecoderCapabilities(vp9: true, av1: false))
        #expect(withoutAV1.video == nil && withoutAV1.unreadableVideo == "AV1 video")
    }
}

@Suite struct SubtitleTextTests {
    @Test func plainText() {
        #expect(SubtitleText.plain("<i>Hello</i> &amp; <b>bye</b>\r\n<font color=\"red\">two</font>", format: .srt) == "Hello & bye\ntwo")
        #expect(SubtitleText.plain("3,0,Default,,0,0,0,,{\\an8}Top line\\NNext, with comma", format: .ass) == "Top line\nNext, with comma")
        #expect(SubtitleText.plain("<v Roger>Hi <c.yellow>there</c>", format: .webvtt) == "Hi there")
        #expect(SubtitleText.plain("  \n ", format: .srt).isEmpty)
    }

    @Test func tx3gRoundTrip() throws {
        let format = Tx3g.formatDescription()
        #expect(CMFormatDescriptionGetMediaSubType(format) == kCMTextFormatType_3GText)
        let sample = try #require(Tx3g.sample("Grüße", start: 1_000_000_000, end: 2_500_000_000, format: format))
        #expect(CMSampleBufferGetPresentationTimeStamp(sample).seconds == 1)
        #expect(abs(CMSampleBufferGetDuration(sample).seconds - 1.5) < 0.001)
        let block = try #require(CMSampleBufferGetDataBuffer(sample))
        var data = Data(count: CMBlockBufferGetDataLength(block))
        _ = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
        #expect(Tx3g.text(data) == "Grüße")
        #expect(Tx3g.text(Data([0, 0])) == "")
    }

    @Test func overlayFindsTheCueShowing() {
        let overlay = SubtitleOverlay(cues: [SubtitleCue(start: 1, end: 2, text: "a"), SubtitleCue(start: 3, end: 4, text: "b")])
        #expect(overlay.cueIndex(at: 0.5) == nil)
        #expect(overlay.cueIndex(at: 1.5) == 0)
        #expect(overlay.cueIndex(at: 2.5) == nil)
        #expect(overlay.cueIndex(at: 3.0) == 1)
        let line = overlay.image(at: 1.5, width: 1280, height: 720)
        #expect(line != nil && line!.image.width < 1280 && line!.origin.y > 0)
    }

    @Test func trackTitles() {
        #expect(SubtitleTrackInfo(index: 0, format: "tx3g", language: "English").title == "English")
        #expect(SubtitleTrackInfo(index: 1, format: "tx3g").title == "Subtitles 2")
        #expect(SubtitleTrackInfo(index: 0, format: "tx3g", language: "French", isForced: true).title == "French (Forced)")
        #expect(!SubtitleTrackInfo(index: 0, format: "c608").canBurn)
    }
}

/// MKV files made from our own synthetic clips, converted for real.
@Suite(.serialized, .needsMediaEngine, .timeLimit(.minutes(5))) struct MatroskaConversionTests {
    func mkv(_ name: String = "Recording.mkv", _ configure: (inout MatroskaFixture.Spec) -> Void = { _ in }) async throws -> (mkv: URL, mov: URL) {
        let mov = try videoFixture("source.mov") { $0.seconds = 2 }
        var spec = MatroskaFixture.Spec()
        configure(&spec)
        let url = mov.deletingLastPathComponent().appendingPathComponent(name)
        try await MatroskaFixture.make(url, from: mov, spec: spec)
        return (url, mov)
    }

    @Test func probesFromItsHeaders() async throws {
        let (url, _) = try await mkv()
        let info = try await MediaProbe.probe(url)
        #expect(info.kind == .video && info.container == "MKV" && info.videoCodec == "avc1")
        #expect((info.width, info.height) == (640, 360) && info.audioCodec == "aac " && info.channels == 2)
        #expect(info.subtitleTracks.map(\.title) == [Locale.current.localizedString(forLanguageCode: "eng") ?? "eng"])
        #expect(abs(info.duration - 2) < 0.1)
    }

    @Test func toMP4IsOnePassAndLooksTheSame() async throws {
        let (url, mov) = try await mkv()
        let result = try report(try await converter().run(url))
        #expect(result.output.lastPathComponent == "Recording.mp4" && result.repackaged)
        let out = try await playBack(result.output)
        #expect(out.videoCodec == "avc1" && out.audioCodec == "aac " && out.playable)
        #expect(abs(out.duration - 2) < 0.1)
        for t in [0.3, 1.0, 1.7] {
            let a = try await averageColor(ofVideo: mov, at: t)
            let b = try await averageColor(ofVideo: result.output, at: t)
            #expect(colorDistance(a, b) < 0.02, "frame at \(t)s: \(a) vs \(b)")
        }
        // The subtitles came along as an MP4 text track, in English, with their text.
        let asset = AVURLAsset(url: result.output)
        let subtitles = try await SubtitleReader.subtitleTracks(asset)
        #expect(subtitles.count == 1)
        #expect(try await subtitles.first?.load(.languageCode) == "eng")
        let cues = try await SubtitleReader.cues(asset, trackIndex: 0)
        #expect(cues.map(\.text) == ["First line", "Second line"])
        #expect(abs((cues.first?.start ?? 0) - 0.2) < 0.05 && abs((cues.first?.end ?? 0) - 0.9) < 0.05)
        // Nothing but the new file next to the original (no leftover intermediate).
        #expect(try visibleFiles(url.deletingLastPathComponent()) == ["Recording.mkv", "Recording.mp4", "source.mov"])
    }

    @Test func lacedSoundAndOpenEndedClusters() async throws {
        let (url, _) = try await mkv { $0.lacedAudio = true; $0.unknownSizeClusters = true; $0.subtitles = [] }
        let result = try report(try await converter { $0.video = .mp4HEVC }.run(url))
        let out = try await playBack(result.output)
        #expect(out.videoCodec == "hvc1" && out.audioCodec == "aac " && abs(out.duration - 2) < 0.1)
    }

    @Test func burnsSubtitlesIntoThePicture() async throws {
        let (url, mov) = try await mkv { $0.subtitles = [(0, 2, "WWWWWWWWWW")] }
        let result = try report(try await converter().run(url, options: FileOptions(subtitles: .burn(0))))
        #expect(result.notes.contains("Subtitles are part of the picture."))
        #expect(try await SubtitleReader.subtitleTracks(AVURLAsset(url: result.output)).isEmpty)
        let before = try await videoFrame(mov, at: 1)
        let after = try await videoFrame(result.output, at: 1)
        // The caption sits in the bottom middle; the top is untouched.
        let bottom = (averageColor(before, x: 0.35, y: 0.84, width: 0.3, height: 0.06),
                      averageColor(after, x: 0.35, y: 0.84, width: 0.3, height: 0.06))
        #expect(colorDistance(bottom.0, bottom.1) > 0.05, "caption missing: \(bottom)")
        #expect(colorDistance(averageColor(before, x: 0.1, y: 0.1, width: 0.3, height: 0.3),
                              averageColor(after, x: 0.1, y: 0.1, width: 0.3, height: 0.3)) < 0.04)
    }

    @Test func soundOnlyFromMKA() async throws {
        let (url, _) = try await mkv("Song.mkv")
        let result = try report(try await converter { $0.video = .audioM4A }.run(url))
        #expect(result.output.pathExtension == "m4a")
        #expect(try await playBack(result.output).audioCodec == "aac ")
    }

    @Test func notReallyMatroska() async throws {
        let url = try fixture("Movie.mkv") { try Data("not really a matroska file".utf8).write(to: $0) }
        await #expect(throws: ConvertError.damaged(name: "Movie.mkv")) { try await converter().run(url) }
    }
}
