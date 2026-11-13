import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

/// What a Matroska track becomes in an MP4: which codec, or why it can't come along.
enum MatroskaCodec: Equatable {
    enum Text: Equatable { case srt, ass, webvtt }

    case video(fourCC: String)
    case audio(fourCC: String)
    case pcm(float: Bool, bigEndian: Bool)
    case text(Text)
    /// Not something macOS can decode (or a picture-based subtitle), by the name people know.
    case unsupported(String)

    static func classify(_ track: MatroskaInfo.Track) -> MatroskaCodec {
        let id = track.codecID
        switch track.kind {
        case .video:
            switch id {
            case "V_MPEG4/ISO/AVC": return track.codecPrivate == nil ? .unsupported("H.264 video without its settings") : .video(fourCC: "avc1")
            case "V_MPEGH/ISO/HEVC": return track.codecPrivate == nil ? .unsupported("HEVC video without its settings") : .video(fourCC: "hvc1")
            case "V_AV1": return track.codecPrivate == nil ? .unsupported("AV1 video without its settings") : .video(fourCC: "av01")
            case "V_VP9": return .video(fourCC: "vp09")
            case "V_MPEG4/ISO/ASP", "V_MPEG4/ISO/SP", "V_MPEG4/ISO/AP": return .video(fourCC: "mp4v")
            case "V_VP8": return .unsupported("VP8 video")
            case "V_THEORA": return .unsupported("Theora video")
            case "V_MPEG1", "V_MPEG2": return .unsupported("MPEG-2 video")
            case "V_MS/VFW/FOURCC": return .unsupported("AVI-style video")
            case "V_PRORES": return .unsupported("ProRes video in MKV")
            default: return .unsupported(id.isEmpty ? "this video" : "\(id.dropFirst(2)) video")
            }
        case .audio:
            if id.hasPrefix("A_AAC") { return .audio(fourCC: "aac ") }
            switch id {
            case "A_AC3", "A_AC3/BSID9", "A_AC3/BSID10": return .audio(fourCC: "ac-3")
            case "A_EAC3": return .audio(fourCC: "ec-3")
            case "A_MPEG/L3": return .audio(fourCC: ".mp3")
            case "A_MPEG/L2": return .audio(fourCC: ".mp2")
            case "A_MPEG/L1": return .audio(fourCC: ".mp1")
            case "A_OPUS": return track.codecPrivate == nil ? .unsupported("Opus sound without its settings") : .audio(fourCC: "opus")
            case "A_FLAC": return track.codecPrivate.flatMap(CodecBoxes.flac) == nil ? .unsupported("FLAC sound without its settings") : .audio(fourCC: "flac")
            case "A_ALAC": return track.codecPrivate == nil ? .unsupported("Apple Lossless sound without its settings") : .audio(fourCC: "alac")
            case "A_VORBIS": return .unsupported("Vorbis sound in MKV")
            case "A_PCM/INT/LIT": return .pcm(float: false, bigEndian: false)
            case "A_PCM/INT/BIG": return .pcm(float: false, bigEndian: true)
            case "A_PCM/FLOAT/IEEE": return .pcm(float: true, bigEndian: false)
            case let dts where dts.hasPrefix("A_DTS"): return .unsupported("DTS sound")
            case "A_TRUEHD", "A_MLP": return .unsupported("Dolby TrueHD sound")
            default: return .unsupported(id.isEmpty ? "this sound" : "\(id.dropFirst(2)) sound")
            }
        case .subtitle:
            switch id {
            case "S_TEXT/UTF8", "S_TEXT/ASCII": return .text(.srt)
            case "S_TEXT/ASS", "S_TEXT/SSA", "S_ASS", "S_SSA": return .text(.ass)
            case "S_TEXT/WEBVTT", "D_WEBVTT/SUBTITLES": return .text(.webvtt)
            default: return .unsupported("picture-based subtitles")
            }
        case .other:
            return .unsupported("data")
        }
    }
}

/// Matroska → MP4 (or MOV), copying every track macOS can read, so the rest of Convert works
/// on it as on any other video. Text subtitles become MP4 text tracks.
public enum MatroskaBridge {
    static let extensions: Set<String> = ["mkv", "mka", "mk3d", "webm"]

    /// Whether this looks like a Matroska file (by name, then by its first bytes).
    public static func handles(_ url: URL) -> Bool {
        if extensions.contains(url.pathExtension.lowercased()) { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x1A, 0x45, 0xDF, 0xA3])
    }

    /// The tracks that come along, and notes about the ones that can't.
    struct Selection {
        var video: MatroskaInfo.Track?
        var audio: [MatroskaInfo.Track] = []
        var subtitles: [MatroskaInfo.Track] = []
        var notes: [String] = []
        /// Why the picture can't be read, when that's the only thing worth converting.
        var unreadableVideo: String?
    }

    static func select(_ info: MatroskaInfo, capabilities: DecoderCapabilities = .system) -> Selection {
        var selection = Selection()
        var dropped: [String] = []
        for track in info.tracks {
            let codec = MatroskaCodec.classify(track)
            switch (track.kind, codec) {
            case (.video, .video(let fourCC)):
                if !capabilities.canDecode(fourCC) {
                    if selection.video == nil, selection.unreadableVideo == nil {
                        selection.unreadableVideo = "\(Codecs.videoName(fourCC)) video"
                    }
                } else if selection.video == nil || (!(selection.video?.isEnabled ?? true) && track.isEnabled) {
                    selection.video = track
                }
            case (.video, .unsupported(let name)):
                if selection.video == nil, selection.unreadableVideo == nil { selection.unreadableVideo = name }
            case (.audio, .audio), (.audio, .pcm):
                selection.audio.append(track)
            case (.subtitle, .text):
                selection.subtitles.append(track)
            case (_, .unsupported(let name)):
                if track.kind != .other, !dropped.contains(name) { dropped.append(name) }
            default:
                break
            }
        }
        if selection.video != nil { selection.unreadableVideo = nil }
        for name in dropped {
            let what = name.hasSuffix("subtitles") ? name.prefix(1).uppercased() + name.dropFirst() : "Its \(name)"
            selection.notes.append("\(what) can't be read on a Mac, so \(name.hasSuffix("s") ? "they were" : "it was") left out.")
        }
        return selection
    }

    // MARK: Probing

    /// The file's facts, from its headers (nothing is copied).
    public static func probe(_ url: URL, capabilities: DecoderCapabilities = .system) throws -> MediaInfo {
        let name = url.lastPathComponent
        let reader: MatroskaReader
        do {
            reader = try MatroskaReader(url: url)
        } catch MatroskaError.encrypted {
            throw ConvertError.protected(name: name)
        } catch {
            throw ConvertError.damaged(name: name)
        }
        let info = reader.info
        let selection = select(info, capabilities: capabilities)
        if let unreadable = selection.unreadableVideo, selection.audio.isEmpty {
            throw ConvertError.unreadableCodec(name: name, codec: unreadable)
        }
        var media = MediaInfo(kind: selection.video == nil ? .audio : .video)
        media.duration = info.duration
        media.container = info.isWebM ? "WebM" : "MKV"
        if let unreadable = selection.unreadableVideo {
            // Sound we can read, under a picture we can't: convert the sound, and say so.
            media.sourceNotes.append("Its \(unreadable) can't be read on a Mac, so only the sound was kept.")
        }
        media.sourceNotes += selection.notes
        if let video = selection.video {
            media.width = video.pixelWidth
            media.height = video.pixelHeight
            if case .video(let fourCC) = MatroskaCodec.classify(video) { media.videoCodec = fourCC }
            if let ns = video.defaultDuration, ns > 0 { media.frameRate = (1e9 / Double(ns) * 1000).rounded() / 1000 }
            media.isHDR = video.transfer == 16 || video.transfer == 18
        }
        for (index, track) in selection.audio.enumerated() {
            var t = AudioTrackInfo(index: index, codec: audioFourCC(track), channels: track.channels,
                                   language: track.language.map(languageName))
            t.sampleRate = track.sampleRate
            t.bitsPerSample = track.bitDepth
            t.isEnabled = track.isEnabled
            media.audioTracks.append(t)
        }
        media.audioTrackCount = media.audioTracks.count
        if let first = media.audioTracks.first(where: \.isEnabled) ?? media.audioTracks.first {
            media.audioCodec = first.codec
            media.channels = first.channels
            media.sampleRate = first.sampleRate
            media.bitsPerSample = first.bitsPerSample
        }
        media.subtitleTracks = selection.subtitles.enumerated().map { index, track in
            SubtitleTrackInfo(index: index, format: "tx3g", language: track.language.map(languageName),
                              name: track.name, isForced: track.isForced)
        }
        if !media.hasVideo && !media.hasAudio { throw ConvertError.empty(name: name) }
        if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { media.fileBytes = Int64(bytes) }
        return media
    }

    static func audioFourCC(_ track: MatroskaInfo.Track) -> String? {
        switch MatroskaCodec.classify(track) {
        case .audio(let fourCC): fourCC
        case .pcm: "lpcm"
        default: nil
        }
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// The container `remux` writes for this file: MOV for uncompressed or MP3 sound, else MP4.
    public static func outputType(_ url: URL, capabilities: DecoderCapabilities = .system) throws -> AVFileType {
        let reader: MatroskaReader
        do { reader = try MatroskaReader(url: url) } catch { throw ConvertError.damaged(name: url.lastPathComponent) }
        return needsMOV(select(reader.info, capabilities: capabilities)) ? .mov : .mp4
    }

    /// Uncompressed and MPEG audio (MP3, MP2) only read back from MOV files.
    static func needsMOV(_ selection: Selection) -> Bool {
        selection.audio.contains {
            switch MatroskaCodec.classify($0) {
            case .pcm, .audio(fourCC: ".mp3"), .audio(fourCC: ".mp2"), .audio(fourCC: ".mp1"): true
            default: false
            }
        }
    }

    // MARK: Remuxing

    public struct Result: Sendable {
        public var notes: [String]
        public var fileType: AVFileType
    }

    /// Copies the tracks macOS can read into `output` (an MP4, or a MOV for uncompressed or
    /// MP3 sound). `maxVideoFrames` stops early (for a thumbnail or preview).
    public static func remux(_ input: URL, to output: URL, maxVideoFrames: Int? = nil,
                             capabilities: DecoderCapabilities = .system,
                             progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Result {
        let name = input.lastPathComponent
        let reader: MatroskaReader
        do {
            reader = try MatroskaReader(url: input)
        } catch MatroskaError.encrypted {
            throw ConvertError.protected(name: name)
        } catch {
            throw ConvertError.damaged(name: name)
        }
        var selection = select(reader.info, capabilities: capabilities)
        if maxVideoFrames != nil {
            selection.audio = []
            selection.subtitles = []
        }
        if selection.video == nil && selection.audio.isEmpty {
            throw ConvertError.unreadableCodec(name: name, codec: selection.unreadableVideo ?? "this file")
        }
        let session = try BridgeSession(reader: reader, selection: selection, output: output, name: name)
        try await session.run(maxVideoFrames: maxVideoFrames, progress: progress)
        return Result(notes: selection.notes, fileType: session.fileType)
    }
}

/// Which video decoders this Mac has. VP9 and AV1 depend on the chip.
public struct DecoderCapabilities: Sendable, Equatable {
    public var vp9: Bool
    public var av1: Bool

    public init(vp9: Bool, av1: Bool) {
        self.vp9 = vp9
        self.av1 = av1
    }

    public static let system: DecoderCapabilities = {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        return DecoderCapabilities(vp9: VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9),
                                   av1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
    }()

    public func canDecode(_ fourCC: String) -> Bool {
        switch fourCC {
        case "vp09": vp9
        case "av01": av1
        default: true
        }
    }
}

/// One remux: format descriptions, timing and the writer.
private final class BridgeSession {
    let reader: MatroskaReader
    let selection: MatroskaBridge.Selection
    let writer: AVAssetWriter
    let fileType: AVFileType
    let name: String
    private var lanes: [UInt64: Lane] = [:]
    private var order: [Lane] = []
    private var subtitleGroup: [AVAssetWriterInput] = []

    init(reader: MatroskaReader, selection: MatroskaBridge.Selection, output: URL, name: String) throws {
        self.reader = reader
        self.selection = selection
        self.name = name
        fileType = MatroskaBridge.needsMOV(selection) ? .mov : .mp4
        do {
            writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        } catch {
            throw ConvertError.cantWrite(folder: output.deletingLastPathComponent().lastPathComponent)
        }
    }

    /// One output track.
    final class Lane {
        let track: MatroskaInfo.Track
        let input: AVAssetWriterInput
        var format: CMFormatDescription?
        let kind: MatroskaInfo.TrackKind
        let codec: MatroskaCodec
        var pending: [CMSampleBuffer] = []
        var pendingBytes = 0
        // Video: frames held back to work out decode times (B-frames come before the
        // frames they're shown after).
        var reorder: [(frame: MatroskaFrame, pts: Int64)] = []
        var reorderPTS: [Int64] = []
        var dtsShift: Int64?
        var lastDTS: Int64 = .min
        // Audio: a running sample clock (Matroska rounds times to the millisecond).
        var nextAudioTime: Int64?
        var sampleRate: Double = 0
        var bytesPerFrame = 0
        // Text subtitles: the cue waiting to learn where the next one starts.
        var pendingCue: (start: Int64, end: Int64, text: String)?
        var subtitleEnd: Int64 = 0
        var framesWritten = 0
        var isFinished = false

        func finish() {
            guard !isFinished else { return }
            isFinished = true
            input.markAsFinished()
        }

        init(track: MatroskaInfo.Track, input: AVAssetWriterInput, kind: MatroskaInfo.TrackKind, codec: MatroskaCodec) {
            self.track = track
            self.input = input
            self.kind = kind
            self.codec = codec
        }
    }

    func run(maxVideoFrames: Int?, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await prepare()
        guard writer.startWriting() else {
            throw ConvertError.encodeFailed(name: name)
        }
        // Times are shifted so every decode time is ≥ 0; the session starts at the first
        // frame shown.
        let shift = videoShift
        writer.startSession(atSourceTime: CMTime(value: firstTime + shift, timescale: 1_000_000_000))
        let wanted = Set(order.map(\.track.number))
        let duration = reader.info.duration
        var lastReport = Date.distantPast
        var cancelled = false
        var failure: (any Error)?
        try reader.forEachFrame(tracks: wanted) { frame in
            if Task.isCancelled { cancelled = true; return false }
            guard let lane = lanes[frame.track] else { return true }
            do {
                try add(frame, to: lane, shift: shift)
                try drain(force: false)
            } catch {
                failure = error
                return false
            }
            if let maxVideoFrames, let video = order.first(where: { $0.kind == .video }), video.framesWritten >= maxVideoFrames {
                return false
            }
            if duration > 0, Date().timeIntervalSince(lastReport) > 0.2 {
                lastReport = Date()
                progress(min(0.99, max(0, Double(frame.time) / 1e9 / duration)))
            }
            return true
        }
        if cancelled || Task.isCancelled {
            writer.cancelWriting()
            throw CancellationError()
        }
        if let failure {
            writer.cancelWriting()
            throw failure
        }
        for lane in order { try flush(lane, shift: shift) }
        try drain(force: true)
        for lane in order { lane.finish() }
        await writer.finishWriting()
        guard writer.status == .completed else {
            log.error("bridge finish failed: \(String(describing: self.writer.error))")
            throw ConvertError.encodeFailed(name: name)
        }
        progress(1)
    }

    // MARK: Setup

    /// The earliest presentation time in the file and per-track first frames, for the
    /// format descriptions that need one (AC-3, E-AC-3, VP9).
    private var firstTime: Int64 = 0
    private var videoShift: Int64 = 0

    private func prepare() async throws {
        let tracks = [selection.video].compactMap { $0 } + selection.audio + selection.subtitles
        var firstFrames: [UInt64: MatroskaFrame] = [:]
        var firstVideoTimes: [Int64] = []
        var earliest: Int64?
        let videoNumber = selection.video?.number
        var scanned = 0
        try reader.forEachFrame(tracks: Set(tracks.map(\.number))) { frame in
            if firstFrames[frame.track] == nil { firstFrames[frame.track] = frame }
            if frame.track == videoNumber, firstVideoTimes.count < 32 { firstVideoTimes.append(frame.time) }
            if frame.track == videoNumber || selection.audio.contains(where: { $0.number == frame.track }) {
                earliest = min(earliest ?? frame.time, frame.time)
            }
            scanned += 1
            let needed = tracks.filter { $0.kind != .subtitle }.allSatisfy { firstFrames[$0.number] != nil }
            let videoDone = videoNumber == nil || firstVideoTimes.count >= 32
            return !(needed && videoDone) && scanned < 4000
        }
        firstTime = earliest ?? 0
        // How far decode times must sit before presentation times for the first frames.
        let sorted = firstVideoTimes.sorted()
        videoShift = zip(sorted, firstVideoTimes).map { $0 - $1 }.max().map { max(0, $0) } ?? 0

        for track in tracks {
            let codec = MatroskaCodec.classify(track)
            let first = firstFrames[track.number]
            switch track.kind {
            case .video:
                guard let format = try videoFormat(track, codec: codec, first: first) else { continue }
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                input.mediaTimeScale = 90_000
                try add(input, track: track, kind: .video, codec: codec, format: format)
            case .audio:
                guard first != nil || codec != .audio(fourCC: "ac-3") && codec != .audio(fourCC: "ec-3"),
                      let (format, rate, bytesPerFrame) = try audioFormat(track, codec: codec, first: first) else { continue }
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                if let language = track.language { setLanguage(input, language) }
                let lane = try add(input, track: track, kind: .audio, codec: codec, format: format)
                lane.sampleRate = rate
                lane.bytesPerFrame = bytesPerFrame
                if !track.isEnabled { input.marksOutputTrackAsEnabled = false }
            case .subtitle:
                let format = Tx3g.formatDescription()
                let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
                input.expectsMediaDataInRealTime = false
                if let language = track.language { setLanguage(input, language) }
                if (try? add(input, track: track, kind: .subtitle, codec: codec, format: format)) != nil {
                    subtitleGroup.append(input)
                }
            case .other:
                break
            }
        }
        if !subtitleGroup.isEmpty {
            // Off until the viewer turns them on, except forced ones (meant to always show).
            let forced = order.first { $0.kind == .subtitle && $0.track.isForced }?.input
            let group = AVAssetWriterInputGroup(inputs: subtitleGroup, defaultInput: forced)
            if writer.canAdd(group) { writer.add(group) }
        }
        if order.isEmpty { throw ConvertError.encodeFailed(name: name) }
    }

    @discardableResult
    private func add(_ input: AVAssetWriterInput, track: MatroskaInfo.Track, kind: MatroskaInfo.TrackKind,
                     codec: MatroskaCodec, format: CMFormatDescription) throws -> Lane {
        guard writer.canAdd(input) else {
            log.error("bridge can't add \(track.codecID)")
            throw ConvertError.encodeFailed(name: name)
        }
        writer.add(input)
        let lane = Lane(track: track, input: input, kind: kind, codec: codec)
        lane.format = format
        lanes[track.number] = lane
        order.append(lane)
        return lane
    }

    private func setLanguage(_ input: AVAssetWriterInput, _ language: String) {
        // ISO 639-2 ("eng") goes in the track header; BCP 47 ("en-US") in the extended tag.
        if language.count == 3, language.allSatisfy(\.isLetter) {
            input.languageCode = language
        } else {
            input.extendedLanguageTag = language
            if let base = language.split(separator: "-").first, base.count == 2 {
                input.languageCode = Locale.Language(identifier: String(base)).languageCode?.identifier(.alpha3) ?? nil
            }
        }
    }

    private func videoFormat(_ track: MatroskaInfo.Track, codec: MatroskaCodec, first: MatroskaFrame?) throws -> CMFormatDescription? {
        guard case .video(let fourCC) = codec else { return nil }
        var atoms: [String: Data] = [:]
        let codecPrivate = track.codecPrivate ?? Data()
        switch fourCC {
        case "avc1": atoms["avcC"] = codecPrivate
        case "hvc1": atoms["hvcC"] = codecPrivate
        case "av01": atoms["av1C"] = codecPrivate
        case "vp09":
            atoms["vpcC"] = CodecBoxes.vpcC(firstFrame: first?.data ?? Data(), primaries: track.primaries,
                                            transfer: track.transfer, matrix: track.matrix, fullRange: track.fullRange)
        case "mp4v":
            atoms["esds"] = Data([0, 0, 0, 0]) + CodecBoxes.esDescriptor(objectType: 0x20, streamType: 4, specificInfo: codecPrivate)
        default: return nil
        }
        var extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms as CFDictionary,
        ]
        if let p = track.primaries.flatMap(ColorTags.primaries) { extensions[kCVImageBufferColorPrimariesKey] = p }
        if let t = track.transfer.flatMap(ColorTags.transfer) { extensions[kCVImageBufferTransferFunctionKey] = t }
        if let m = track.matrix.flatMap(ColorTags.matrix) { extensions[kCVImageBufferYCbCrMatrixKey] = m }
        if track.fullRange { extensions[kCMFormatDescriptionExtension_FullRangeVideo] = true }
        if track.displayWidth > 0, track.displayHeight > 0, track.pixelWidth > 0, track.pixelHeight > 0,
           track.displayWidth * track.pixelHeight != track.displayHeight * track.pixelWidth {
            // Anamorphic: pixels aren't square.
            extensions[kCMFormatDescriptionExtension_PixelAspectRatio] = [
                kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing: track.displayWidth * track.pixelHeight,
                kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing: track.displayHeight * track.pixelWidth,
            ] as CFDictionary
        }
        var format: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: nil, codecType: FourCC.code(fourCC),
                                                    width: Int32(track.pixelWidth), height: Int32(track.pixelHeight),
                                                    extensions: extensions as CFDictionary, formatDescriptionOut: &format)
        guard status == noErr, let format else { throw ConvertError.damaged(name: name) }
        return format
    }

    /// The format, sample rate and (for PCM) bytes per frame.
    private func audioFormat(_ track: MatroskaInfo.Track, codec: MatroskaCodec,
                             first: MatroskaFrame?) throws -> (CMAudioFormatDescription, Double, Int)? {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = track.sampleRate
        asbd.mChannelsPerFrame = UInt32(track.channels)
        var cookie: Data?
        var layoutTag: AudioChannelLayoutTag?
        var bytesPerFrame = 0
        switch codec {
        case .audio(fourCC: "aac "):
            asbd.mFormatID = kAudioFormatMPEG4AAC
            asbd.mFramesPerPacket = 1024
            var config = track.codecPrivate ?? Data()
            if config.count < 2 {
                let profile = track.codecID.contains("MAIN") ? 1 : track.codecID.contains("SSR") ? 3 : track.codecID.contains("LTP") ? 4 : 2
                let core = track.codecID.contains("SBR") ? track.sampleRate / 2 : track.sampleRate
                config = CodecBoxes.audioSpecificConfig(objectType: profile, sampleRate: core, channels: track.channels)
            }
            if let parsed = CodecBoxes.parseAudioSpecificConfig(config), parsed.channels > 0 {
                asbd.mChannelsPerFrame = UInt32(parsed.channels == 7 ? 8 : parsed.channels)
            }
            cookie = CodecBoxes.esDescriptor(objectType: 0x40, streamType: 5, specificInfo: config)
            layoutTag = ChannelLayouts.aac(Int(asbd.mChannelsPerFrame))
        case .audio(fourCC: "ac-3"), .audio(fourCC: "ec-3"):
            guard let frame = first?.data,
                  let header = codec == .audio(fourCC: "ac-3") ? CodecBoxes.ac3(frame) : CodecBoxes.eac3(frame) else { return nil }
            asbd.mFormatID = codec == .audio(fourCC: "ac-3") ? kAudioFormatAC3 : kAudioFormatEnhancedAC3
            asbd.mFramesPerPacket = UInt32(header.samplesPerFrame)
            asbd.mSampleRate = header.sampleRate
            asbd.mChannelsPerFrame = UInt32(header.channels)
            cookie = header.cookie
            layoutTag = ChannelLayouts.ac3(header.channels)
        case .audio(fourCC: ".mp3"), .audio(fourCC: ".mp2"), .audio(fourCC: ".mp1"):
            asbd.mFormatID = codec == .audio(fourCC: ".mp3") ? kAudioFormatMPEGLayer3 : codec == .audio(fourCC: ".mp2") ? kAudioFormatMPEGLayer2 : kAudioFormatMPEGLayer1
            asbd.mFramesPerPacket = codec == .audio(fourCC: ".mp1") ? 384 : (track.sampleRate < 32000 && codec == .audio(fourCC: ".mp3") ? 576 : 1152)
        case .audio(fourCC: "opus"):
            guard let head = track.codecPrivate, let parsed = CodecBoxes.opusHead(head) else { return nil }
            asbd.mFormatID = kAudioFormatOpus
            asbd.mSampleRate = 48000
            asbd.mChannelsPerFrame = UInt32(parsed.channels)
            cookie = head
            layoutTag = ChannelLayouts.vorbisOrder(parsed.channels)
        case .audio(fourCC: "flac"):
            guard let flac = track.codecPrivate.flatMap(CodecBoxes.flac) else { return nil }
            asbd.mFormatID = kAudioFormatFLAC
            asbd.mSampleRate = flac.sampleRate
            asbd.mChannelsPerFrame = UInt32(flac.channels)
            asbd.mFramesPerPacket = 0
            asbd.mFormatFlags = [16: 1, 20: 2, 24: 3, 32: 4][flac.bitsPerSample] ?? 0
            cookie = flac.cookie
            layoutTag = ChannelLayouts.waveOrder(flac.channels)
        case .audio(fourCC: "alac"):
            asbd.mFormatID = kAudioFormatAppleLossless
            asbd.mFramesPerPacket = 4096
            cookie = track.codecPrivate
            layoutTag = ChannelLayouts.aac(track.channels)
        case .pcm(let float, let bigEndian):
            let bits = track.bitDepth > 0 ? track.bitDepth : (float ? 32 : 16)
            asbd.mFormatID = kAudioFormatLinearPCM
            asbd.mFormatFlags = (float ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger)
                | (bigEndian ? kAudioFormatFlagIsBigEndian : 0) | kAudioFormatFlagIsPacked
            asbd.mBitsPerChannel = UInt32(bits)
            bytesPerFrame = bits / 8 * track.channels
            asbd.mBytesPerFrame = UInt32(bytesPerFrame)
            asbd.mBytesPerPacket = UInt32(bytesPerFrame)
            asbd.mFramesPerPacket = 1
            layoutTag = ChannelLayouts.waveOrder(track.channels)
        default:
            return nil
        }
        var layout = AudioChannelLayout()
        if let layoutTag { layout.mChannelLayoutTag = layoutTag }
        var format: CMAudioFormatDescription?
        let status: OSStatus = withUnsafePointer(to: &layout) { layoutPointer in
            let cookieBytes = cookie ?? Data()
            return cookieBytes.withUnsafeBytes { raw in
                CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd,
                                               layoutSize: layoutTag == nil ? 0 : MemoryLayout<AudioChannelLayout>.size,
                                               layout: layoutTag == nil ? nil : layoutPointer,
                                               magicCookieSize: cookieBytes.count,
                                               magicCookie: cookieBytes.isEmpty ? nil : raw.baseAddress,
                                               extensions: nil, formatDescriptionOut: &format)
            }
        }
        guard status == noErr, let format else { return nil }
        return (format, asbd.mSampleRate, bytesPerFrame)
    }

    // MARK: Frames

    private func add(_ frame: MatroskaFrame, to lane: Lane, shift: Int64) throws {
        switch lane.kind {
        case .video:
            // Decode times are the presentation times in order: hold a few frames back, then
            // give the oldest frame the smallest time seen.
            lane.reorder.append((frame, frame.time))
            lane.reorderPTS.append(frame.time)
            if lane.reorder.count > 16 { try emitVideo(lane, shift: shift) }
        case .audio:
            try emitAudio(frame, lane: lane, shift: shift)
        case .subtitle:
            try addCue(frame, lane: lane, shift: shift)
        case .other:
            break
        }
    }

    private func emitVideo(_ lane: Lane, shift: Int64) throws {
        let (frame, pts) = lane.reorder.removeFirst()
        let smallest = lane.reorderPTS.indices.min { lane.reorderPTS[$0] < lane.reorderPTS[$1] }!
        var dts = lane.reorderPTS.remove(at: smallest)
        // Everything is shown `shift` later, so decode times (the sorted presentation times)
        // never come after their frame is shown. They must also keep going up.
        let shown = pts + shift
        if dts > shown { dts = shown }
        if lane.lastDTS != .min, dts <= lane.lastDTS { dts = lane.lastDTS + 1 }
        lane.lastDTS = dts
        let ns: Int32 = 1_000_000_000
        let duration = frame.duration ?? lane.track.defaultDuration.map(Int64.init)
        let timing = CMSampleTimingInfo(duration: duration.map { CMTime(value: $0, timescale: ns) } ?? .invalid,
                                        presentationTimeStamp: CMTime(value: shown, timescale: ns),
                                        decodeTimeStamp: CMTime(value: dts, timescale: ns))
        guard let sample = SampleBuffers.make(frame.data, format: lane.format, timing: timing, isKey: frame.isKey) else {
            throw ConvertError.damaged(name: name)
        }
        lane.framesWritten += 1
        queue(sample, bytes: frame.data.count, on: lane)
    }

    private func emitAudio(_ frame: MatroskaFrame, lane: Lane, shift: Int64) throws {
        guard let format = lane.format else { return }
        let ns = Int64(1_000_000_000)
        // Samples in this packet, when the codec says; otherwise the file's times are used.
        let frames = AudioPackets.frames(in: frame.data, codec: lane.codec, bytesPerFrame: lane.bytesPerFrame,
                                         format: format)
        var time = frame.time
        if let next = lane.nextAudioTime, abs(next - frame.time) < 50_000_000 {
            time = next // follow the sample clock unless the file jumps (a real gap)
        }
        let pts = CMTime(value: time + shift, timescale: 1_000_000_000)
        if let frames, lane.sampleRate > 0 {
            lane.nextAudioTime = time + Int64((Double(frames) / lane.sampleRate * Double(ns)).rounded())
        } else {
            lane.nextAudioTime = nil
        }
        guard let sample = SampleBuffers.audio(frame.data, format: format, pts: pts, frames: frames,
                                               bytesPerFrame: lane.bytesPerFrame, sampleRate: lane.sampleRate,
                                               fallbackDuration: frame.duration) else {
            throw ConvertError.damaged(name: name)
        }
        queue(sample, bytes: frame.data.count, on: lane)
    }

    private func addCue(_ frame: MatroskaFrame, lane: Lane, shift: Int64) throws {
        guard case .text(let kind) = lane.codec else { return }
        let text = SubtitleText.plain(String(decoding: frame.data, as: UTF8.self), format: kind)
        let start = frame.time + shift
        let end = start + (frame.duration ?? 3_000_000_000)
        if let pending = lane.pendingCue {
            writeCue(pending.start, min(pending.end, max(pending.start + 1, start)), pending.text, lane: lane)
        }
        lane.pendingCue = text.isEmpty ? nil : (start, end, text)
    }

    /// A cue, with an empty sample before it to fill any gap (text tracks must be continuous).
    private func writeCue(_ start: Int64, _ end: Int64, _ text: String, lane: Lane) {
        let sessionStart = firstTime + videoShift
        let from = max(lane.subtitleEnd, sessionStart)
        if start > from, let gap = Tx3g.sample("", start: from, end: start, format: lane.format) {
            queue(gap, bytes: 2, on: lane)
        }
        let begin = max(start, from)
        guard end > begin, let sample = Tx3g.sample(text, start: begin, end: end, format: lane.format) else { return }
        lane.subtitleEnd = end
        queue(sample, bytes: text.utf8.count + 2, on: lane)
    }

    private func flush(_ lane: Lane, shift: Int64) throws {
        while !lane.reorder.isEmpty { try emitVideo(lane, shift: shift) }
        if let cue = lane.pendingCue {
            writeCue(cue.start, cue.end, cue.text, lane: lane)
            lane.pendingCue = nil
        }
    }

    // MARK: Writing

    private func queue(_ sample: CMSampleBuffer, bytes: Int, on lane: Lane) {
        lane.pending.append(sample)
        lane.pendingBytes += bytes
    }

    /// Hands queued samples to the writer. The writer interleaves tracks, so it may refuse one
    /// until it has more of another; frames keep being read meanwhile, up to a limit.
    private func drain(force: Bool) throws {
        let limit = 256 << 20
        var stalls = 0
        while true {
            var progressed = false
            for lane in order where !lane.pending.isEmpty {
                while !lane.pending.isEmpty, lane.input.isReadyForMoreMediaData {
                    let sample = lane.pending.removeFirst()
                    lane.pendingBytes -= CMSampleBufferGetTotalSampleSize(sample)
                    guard lane.input.append(sample) else {
                        log.error("bridge append failed: \(String(describing: self.writer.error))")
                        throw ConvertError.encodeFailed(name: name)
                    }
                    progressed = true
                }
            }
            if writer.status == .failed {
                log.error("bridge writer failed: \(String(describing: self.writer.error))")
                throw ConvertError.encodeFailed(name: name)
            }
            if force {
                // The end: a track with nothing left is finished now, or the writer keeps
                // waiting for it (to interleave) and never takes the rest of the others.
                for lane in order where lane.pending.isEmpty && !lane.isFinished {
                    lane.finish()
                    progressed = true
                }
            }
            let queued = order.reduce(0) { $0 + $1.pendingBytes }
            let empty = order.allSatisfy { $0.pending.isEmpty }
            if empty || (!force && queued < limit) { return }
            if !progressed {
                stalls += 1
                if stalls > 20_000 { throw ConvertError.encodeFailed(name: name) } // ~20 s stuck
                Thread.sleep(forTimeInterval: 0.001)
            } else {
                stalls = 0
            }
        }
    }
}

/// Samples per audio packet, where the codec makes it knowable.
enum AudioPackets {
    static func frames(in data: Data, codec: MatroskaCodec, bytesPerFrame: Int, format: CMAudioFormatDescription) -> Int? {
        switch codec {
        case .pcm: return bytesPerFrame > 0 ? data.count / bytesPerFrame : nil
        case .audio(fourCC: "opus"): return opusFrames(data)
        case .audio(fourCC: "flac"): return flacBlockSize(data)
        default:
            let perPacket = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mFramesPerPacket ?? 0
            return perPacket > 0 ? Int(perPacket) : nil
        }
    }

    /// From an Opus packet's TOC byte (RFC 6716 §3.1), at 48 kHz.
    static func opusFrames(_ data: Data) -> Int? {
        guard let toc = data.first else { return nil }
        let config = Int(toc >> 3)
        let size: Int = switch config {
        case 0...11: [480, 960, 1920, 2880][config % 4]
        case 12...15: [480, 960][config % 2]
        default: [120, 240, 480, 960][config % 4]
        }
        let count: Int
        switch toc & 0x03 {
        case 0: count = 1
        case 1, 2: count = 2
        default:
            guard data.count > 1 else { return nil }
            count = Int(data[data.startIndex + 1] & 0x3F)
        }
        return size * count
    }

    /// From a FLAC frame header's block size code.
    static func flacBlockSize(_ data: Data) -> Int? {
        let b = [UInt8](data.prefix(16))
        guard b.count >= 4, b[0] == 0xFF, b[1] & 0xFC == 0xF8 else { return nil }
        let code = Int(b[2] >> 4)
        switch code {
        case 1: return 192
        case 2...5: return 576 << (code - 2)
        case 8...15: return 256 << (code - 8)
        case 6, 7:
            // After the UTF-8-style coded frame/sample number.
            var index = 4
            let lead = b[index]
            // A lead byte's leading ones give the coded number's length (0xxxxxxx is one byte).
            index += lead < 0x80 ? 1 : max(1, (~lead).leadingZeroBitCount)
            guard index + (code == 7 ? 1 : 0) < b.count else { return nil }
            return code == 6 ? Int(b[index]) + 1 : (Int(b[index]) << 8 | Int(b[index + 1])) + 1
        default: return nil
        }
    }
}

/// Core Media sample buffers from bytes.
enum SampleBuffers {
    static func block(_ data: Data) -> CMBlockBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let status = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        return status == noErr ? block : nil
    }

    static func make(_ data: Data, format: CMFormatDescription?, timing: CMSampleTimingInfo, isKey: Bool) -> CMSampleBuffer? {
        guard !data.isEmpty, let block = block(data) else { return nil }
        var timing = timing
        var size = data.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if !isKey, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    static func audio(_ data: Data, format: CMAudioFormatDescription, pts: CMTime, frames: Int?, bytesPerFrame: Int,
                      sampleRate: Double, fallbackDuration: Int64?) -> CMSampleBuffer? {
        guard !data.isEmpty, let block = block(data) else { return nil }
        var sample: CMSampleBuffer?
        if bytesPerFrame > 0 {
            // Uncompressed: one sample per audio frame.
            let count = data.count / bytesPerFrame
            guard count > 0, CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
                presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sample) == noErr else { return nil }
            return sample
        }
        let perPacket = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mFramesPerPacket ?? 0
        var packet = AudioStreamPacketDescription(mStartOffset: 0,
                                                  mVariableFramesInPacket: perPacket == 0 ? UInt32(frames ?? 0) : 0,
                                                  mDataByteSize: UInt32(data.count))
        if perPacket == 0, frames == nil {
            // No way to count samples (rare): use the file's time for the packet.
            guard let fallbackDuration, sampleRate > 0 else { return nil }
            packet.mVariableFramesInPacket = UInt32((Double(fallbackDuration) / 1e9 * sampleRate).rounded())
        }
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            presentationTimeStamp: pts, packetDescriptions: &packet, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}

/// Channel layouts by codec convention.
enum ChannelLayouts {
    static func aac(_ channels: Int) -> AudioChannelLayoutTag? {
        switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        case 3: kAudioChannelLayoutTag_MPEG_3_0_B
        case 4: kAudioChannelLayoutTag_MPEG_4_0_B
        case 5: kAudioChannelLayoutTag_MPEG_5_0_D
        case 6: kAudioChannelLayoutTag_MPEG_5_1_D
        case 8: kAudioChannelLayoutTag_MPEG_7_1_B
        default: nil
        }
    }

    static func ac3(_ channels: Int) -> AudioChannelLayoutTag? {
        switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        case 6: kAudioChannelLayoutTag_MPEG_5_1_C
        default: nil
        }
    }

    /// Opus and Vorbis order: L C R Ls Rs LFE…
    static func vorbisOrder(_ channels: Int) -> AudioChannelLayoutTag? {
        switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        case 6: kAudioChannelLayoutTag_MPEG_5_1_C
        default: nil
        }
    }

    /// WAV and FLAC order: L R C LFE Ls Rs (Rls Rrs).
    static func waveOrder(_ channels: Int) -> AudioChannelLayoutTag? {
        switch channels {
        case 1: kAudioChannelLayoutTag_Mono
        case 2: kAudioChannelLayoutTag_Stereo
        case 6: kAudioChannelLayoutTag_MPEG_5_1_A
        case 8: kAudioChannelLayoutTag_MPEG_7_1_C
        default: nil
        }
    }
}

/// Matroska's colour codes (ISO/IEC 23091-2) as Core Video's names.
enum ColorTags {
    static func primaries(_ code: Int) -> CFString? {
        switch code {
        case 1: kCVImageBufferColorPrimaries_ITU_R_709_2
        case 9: kCVImageBufferColorPrimaries_ITU_R_2020
        case 12: kCVImageBufferColorPrimaries_P3_D65
        case 5, 6: kCVImageBufferColorPrimaries_SMPTE_C
        default: nil
        }
    }

    static func transfer(_ code: Int) -> CFString? {
        switch code {
        case 1, 6, 14, 15: kCVImageBufferTransferFunction_ITU_R_709_2
        case 16: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        case 18: kCVImageBufferTransferFunction_ITU_R_2100_HLG
        case 13: kCVImageBufferTransferFunction_sRGB
        default: nil
        }
    }

    static func matrix(_ code: Int) -> CFString? {
        switch code {
        case 1: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        case 5, 6: kCVImageBufferYCbCrMatrix_ITU_R_601_4
        case 9, 10: kCVImageBufferYCbCrMatrix_ITU_R_2020
        default: nil
        }
    }
}

enum FourCC {
    static func code(_ string: String) -> FourCharCode {
        string.utf8.prefix(4).reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
