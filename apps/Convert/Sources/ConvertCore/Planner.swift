import AVFoundation
import AudioToolbox
import Foundation

public enum VideoCodecChoice: String, Equatable, Sendable {
    case h264, hevc, proRes422

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .proRes422: .proRes422
        }
    }

    var copyable: Set<String> {
        switch self {
        case .h264: Codecs.h264
        case .hevc: Codecs.hevc
        case .proRes422: Codecs.proRes422
        }
    }
}

public struct VideoEncoding: Equatable, Sendable {
    public var codec: VideoCodecChoice
    /// Encoded size (before rotation), even numbers.
    public var width: Int
    public var height: Int
    /// `AVVideoQualityKey`, nil for ProRes (and when aiming at a size).
    public var quality: Double?
    /// Keep 10-bit HDR (HEVC Main10 / ProRes) instead of converting to standard range.
    public var keepHDR: Bool
    /// The source is HDR and the target can't carry it: tone-map to Rec. 709.
    public var toSDR: Bool
    public var frameRate: Double
    /// `width`×`height` is the picture as shown, drawn upright through `FrameCompositor`
    /// (for mirroring, cropping, burned-in subtitles, and merging clips of different
    /// sizes). Otherwise it's the stored size and the turn travels as the track's matrix.
    public var upright = false
    /// Average bits per second, when aiming at a file size (replaces `quality`).
    public var bitRate: Int?
    /// The part of the picture (as shown, before the turn) to keep, in pixels.
    public var crop: CGRect?
}

public enum VideoPlan: Equatable, Sendable {
    case copy
    case encode(VideoEncoding)
}

public enum AudioFormatChoice: Equatable, Sendable {
    case aac(bitRate: Int)
    case alac(bits: Int)
    case flac(bits: Int)
    case pcm(bits: Int, bigEndian: Bool)
}

public struct AudioEncoding: Equatable, Sendable {
    public var format: AudioFormatChoice
    public var sampleRate: Double
    public var channels: Int
    /// The channel layout for 5.1 and 7.1 (each format has its own), nil for mono and stereo.
    public var layout: AudioChannelLayoutTag?

    public init(format: AudioFormatChoice, sampleRate: Double, channels: Int, layout: AudioChannelLayoutTag? = nil) {
        self.format = format
        self.sampleRate = sampleRate
        self.channels = channels
        self.layout = layout
    }
}

public enum AudioPlan: Equatable, Sendable {
    case none
    case copy
    case encode(AudioEncoding)
}

/// What happens to a video's subtitle tracks.
public enum SubtitlePlan: Equatable, Sendable {
    case none
    /// Copied as they are (0-based indices among the subtitle tracks).
    case copy([Int])
    /// Drawn into the picture.
    case burn(Int)
}

/// What to do with one audio/video file: which container, and per track whether to copy
/// the compressed data as it is (fast, no quality loss) or decode and encode it.
public struct TranscodePlan: Equatable, Sendable {
    public var fileType: AVFileType
    public var fileExtension: String
    /// nil: no picture in the output.
    public var video: VideoPlan?
    public var audio: AudioPlan
    /// Shown on the row ("Scaled to 4096×2304, the most H.264 allows.").
    public var notes: [String] = []
    /// "MP4 (H.264)", for rows and messages.
    public var targetTitle: String
    /// The part to keep, if not all of it.
    public var trim: TrimRange?
    /// A turn (and mirror) to apply. Turns alone go in the track's matrix, so copying still
    /// works; a mirror is drawn into the picture (`VideoEncoding.upright`).
    public var transform: PictureTransform = .identity
    /// Which sound tracks to read.
    public var sound: SoundChoice = .all
    public var subtitles: SubtitlePlan = .none
    /// Written by `AudioFileWriter` (FLAC) instead of AVAssetWriter.
    public var usesAudioFile = false
    /// The size it must fit in, if any (checked after writing; a second try if it's over).
    public var sizeLimit: FileSizeLimit?

    /// Nothing is re-encoded: only the container changes.
    public var isRepackage: Bool {
        (video == nil || video == .copy) && (audio == .none || audio == .copy)
    }
}

/// Picks the container and per-track copy/encode for a file. Pure, so it's tested.
public enum Planner {
    /// The biggest frame H.264 encoders take (level 5.2).
    static let h264Box = (long: 4096, short: 2304)

    public static func plan(_ original: MediaInfo, settings defaults: ConvertSettings, name: String,
                            options: FileOptions = FileOptions()) throws -> TranscodePlan {
        let settings = defaults.applying(options)
        let info = original.choosingSound(options.sound)
        // What the size budget works with: the part that's kept.
        let kept = info.trimmed(options.trim)
        var plan: TranscodePlan
        switch info.kind {
        case .video:
            if let audioTarget = settings.video.audioTarget {
                plan = try audioPlan(kept, target: audioTarget, quality: settings.quality, name: name,
                                     title: settings.video.title, stereo: options.stereo, size: settings.fileSize)
            } else {
                plan = videoPlan(kept, target: settings.video, settings: settings, options: options)
            }
        case .audio:
            plan = try audioPlan(kept, target: settings.audio, quality: settings.quality, name: name,
                                 title: settings.audio.title, stereo: options.stereo, size: settings.fileSize)
        case .image:
            preconditionFailure("Images don't use AVFoundation plans")
        }
        if let trim = options.trim, !trim.isWhole(of: original.duration) {
            plan.trim = TrimRange(start: trim.start, end: min(trim.end, original.duration))
        }
        plan.sound = options.sound
        plan.notes = original.sourceNotes + plan.notes
        return plan
    }

    /// Whether this plan would just make a copy of the input under a new name: same
    /// container, nothing re-encoded. Then we write nothing and say so.
    public static func isNoOp(_ plan: TranscodePlan, info: MediaInfo, inputExtension: String) -> Bool {
        guard plan.notes.isEmpty, plan.trim == nil, plan.transform.isIdentity, plan.sound == .all,
              sameExtension(inputExtension, plan.fileExtension) else { return false }
        if case .burn = plan.subtitles { return false }
        if plan.subtitles == .none, !info.subtitleTracks.isEmpty, plan.video != nil { return false }
        if case .copy(let kept) = plan.subtitles, kept.count != info.subtitleTracks.count { return false }
        if plan.isRepackage { return true }
        // WAV → WAV / AIFF → AIFF / FLAC → FLAC of plain PCM: decoding and re-writing changes nothing.
        if plan.video == nil, case .encode(let e) = plan.audio, info.audioTrackCount == 1,
           info.sampleRate == e.sampleRate, info.channels == e.channels {
            switch (e.format, Codecs.audioName(info.audioCodec ?? "")) {
            case (.pcm(let bits, _), "PCM"), (.flac(let bits), "FLAC"):
                return info.bitsPerSample == bits
            default:
                return false
            }
        }
        return false
    }

    static func sameExtension(_ a: String, _ b: String) -> Bool {
        let aliases = ["aif": "aiff", "jpeg": "jpg", "tif": "tiff", "heif": "heic"]
        let x = a.lowercased(), y = b.lowercased()
        return (aliases[x] ?? x) == (aliases[y] ?? y)
    }

    // MARK: Video

    static func videoPlan(_ info: MediaInfo, target: VideoTarget, settings: ConvertSettings,
                          options: FileOptions = FileOptions()) -> TranscodePlan {
        let transform = options.transform
        let codec: VideoCodecChoice
        let fileType: AVFileType
        let ext: String
        switch target {
        case .mp4HEVC: (codec, fileType, ext) = (.hevc, .mp4, "mp4")
        case .movProRes: (codec, fileType, ext) = (.proRes422, .mov, "mov")
        default: (codec, fileType, ext) = (.h264, .mp4, "mp4")
        }
        var notes: [String] = []

        // Subtitles: kept as tracks, drawn in, or left out.
        var subtitles = SubtitlePlan.none
        var burning = false
        switch options.subtitles {
        case .keep where !info.subtitleTracks.isEmpty:
            subtitles = .copy(info.subtitleTracks.map(\.index))
        case .burn(let index) where info.subtitleTracks.contains { $0.index == index && $0.canBurn }:
            subtitles = .burn(index)
            burning = true
        default:
            break
        }

        // The picture as shown, cropped: what the frame size works from.
        let crop = options.crop.flatMap { $0.isWhole ? nil : $0 }
        let cropPixels = crop?.pixels(width: info.displayWidth, height: info.displayHeight, even: true)
        let redraw = transform.mirrored || cropPixels != nil || burning

        // A size to fit in sets the bit rate, and may make the frame smaller.
        let limit = codec == .proRes422 ? nil : settings.fileSize
        if codec == .proRes422, settings.fileSize != nil { notes.append("ProRes can't aim for a size, so it was made at full quality.") }
        var box = settings.size.box
        var budget: SizeBudget.Video?
        let fitsAlready = limit.map { info.fileBytes > 0 && info.fileBytes <= $0.bytes } ?? false
        if let limit, !fitsAlready || redraw {
            let (w, h) = cropPixels.map { (Int($0.width), Int($0.height)) } ?? (info.displayWidth, info.displayHeight)
            let shown = Planner.fit(w, h, in: box)
            let b = SizeBudget.video(limit, duration: info.duration, width: shown.0, height: shown.1, frameRate: info.frameRate,
                                     audioChannels: info.hasAudio ? layout(info, format: .aac, stereo: options.stereo).channels : nil,
                                     quality: settings.quality, sourceVideoBitRate: info.videoBitRate,
                                     codecEfficiency: codec == .hevc ? 1.4 : 1)
            budget = b
            if let smaller = b.box { box = box.map { $0.long < smaller.long ? $0 : smaller } ?? smaller }
        }

        var (width, height) = fit(info.width, info.height, in: box, even: true)
        let resized = width < info.width || height < info.height
        var capped = false
        if codec == .h264 {
            let (w, h) = fit(width, height, in: h264Box, even: true)
            if w < width || h < height {
                (width, height) = (w, h)
                capped = true
            }
        }
        let quality = settings.quality
        let video: VideoPlan
        let copyable = info.videoCodec.map(codec.copyable.contains) ?? false
        let qualityValue: Double? = codec == .proRes422 || budget != nil ? nil : QualityTable.videoQuality(quality)
        if redraw {
            // Mirrored, cropped or captioned pictures are drawn upright into the new file:
            // size is as shown.
            var (w, h) = cropPixels.map { (Int($0.width), Int($0.height)) } ?? (info.displayWidth, info.displayHeight)
            if transform.swapsSides { swap(&w, &h) }
            (w, h) = fit(w, h, in: box, even: true)
            if codec == .h264 {
                let fitted = fit(w, h, in: h264Box, even: true)
                if fitted.0 < w || fitted.1 < h {
                    (w, h) = fitted
                    notes.append("Scaled to \(even(w))×\(even(h)), the most H.264 allows. Choose HEVC to keep the full size.")
                }
            }
            video = .encode(VideoEncoding(
                codec: codec, width: even(w), height: even(h), quality: qualityValue,
                keepHDR: false, toSDR: info.isHDR, frameRate: info.frameRate, upright: true,
                bitRate: budget?.videoBitRate, crop: cropPixels
            ))
            if info.isHDR { notes.append("HDR was converted to standard range.") }
            if burning { notes.append("Subtitles are part of the picture.") }
        } else if copyable && !resized && (quality != .smaller || codec == .proRes422) && (budget == nil) {
            video = .copy
        } else {
            let toSDR = info.isHDR && codec == .h264
            video = .encode(VideoEncoding(
                codec: codec, width: even(width), height: even(height), quality: qualityValue,
                keepHDR: info.isHDR && !toSDR, toSDR: toSDR, frameRate: info.frameRate, bitRate: budget?.videoBitRate
            ))
            if capped {
                notes.append("Scaled to \(even(width))×\(even(height)), the most H.264 allows. Choose HEVC to keep the full size.")
            }
            if toSDR { notes.append("HDR was converted to standard range.") }
        }
        if let limit, let budget {
            if let smaller = budget.box, case .encode(let e) = video {
                let (w, h) = info.isRotated && !e.upright ? (e.height, e.width) : (e.width, e.height)
                if smaller.long < (settings.size.box?.long ?? .max) { notes.append("Scaled to \(w)×\(h) to fit in \(FileSizeLimit.number(limit.megabytes)) MB.") }
            }
            if budget.isTight { notes.append(SizeBudget.tightNote(limit, duration: info.duration)) }
        }

        var audio: AudioPlan
        var audioNote: String?
        if !info.hasAudio {
            audio = .none
        } else if codec == .proRes422 {
            let l = layout(info, format: .pcm, stereo: options.stereo)
            audioNote = l.note
            audio = .encode(AudioEncoding(format: .pcm(bits: info.bitsPerSample >= 24 ? 24 : 16, bigEndian: false),
                                          sampleRate: pcmRate(info.sampleRate), channels: l.channels, layout: l.tag))
        } else {
            (audio, audioNote) = aacPlan(info, quality: quality, stereo: options.stereo)
            if let rate = budget?.audioBitRate {
                let isAAC = info.audioCodec.map(Codecs.aac.contains) ?? false
                let small = isAAC && info.audioBitRate > 0 && info.audioBitRate <= Double(rate) * 1.1
                if !(audio == .copy && small) {
                    let l = layout(info, format: .aac, stereo: options.stereo)
                    audio = .encode(AudioEncoding(format: .aac(bitRate: rate), sampleRate: aacRate(info.sampleRate),
                                                  channels: l.channels, layout: l.tag))
                }
            }
        }
        if let audioNote { notes.append(audioNote) }
        if info.audioTrackCount > 1 && audio != .none {
            notes.append("Its \(info.audioTrackCount) sound tracks were mixed into one.")
        }
        var plan = TranscodePlan(fileType: fileType, fileExtension: ext, video: video, audio: audio, notes: notes,
                                 targetTitle: target.title, transform: transform, subtitles: subtitles)
        plan.sizeLimit = budget == nil ? nil : limit
        return plan
    }

    // MARK: Audio

    static func audioPlan(_ info: MediaInfo, target: AudioTarget, quality: Quality, name: String, title: String,
                          stereo: Bool = false, size: FileSizeLimit? = nil) throws -> TranscodePlan {
        guard info.hasAudio else { throw ConvertError.noSound(name: name) }
        var audio: AudioPlan
        var notes: [String] = []
        let bits = info.bitsPerSample >= 24 ? 24 : 16
        var limit: FileSizeLimit?
        switch target {
        case .m4a:
            let note: String?
            (audio, note) = aacPlan(info, quality: quality, stereo: stereo)
            if let note { notes.append(note) }
            if let size, !(info.fileBytes > 0 && info.fileBytes <= size.bytes && audio == .copy) {
                let l = layout(info, format: .aac, stereo: stereo)
                let rate = SizeBudget.audio(size, duration: info.duration, channels: l.channels)
                audio = .encode(AudioEncoding(format: .aac(bitRate: rate), sampleRate: aacRate(info.sampleRate),
                                              channels: l.channels, layout: l.tag))
                limit = size
                if SizeBudget.soundAloneTooBig(size, duration: info.duration, channels: l.channels) {
                    notes.append(SizeBudget.tightNote(size, duration: info.duration))
                }
            }
        case .alac:
            let l = layout(info, format: .alac, stereo: stereo)
            if let note = l.note { notes.append(note) }
            audio = info.audioTrackCount == 1 && info.audioCodec.map(Codecs.alac.contains) == true && l.channels == info.channels
                ? .copy
                : .encode(AudioEncoding(format: .alac(bits: bits), sampleRate: pcmRate(info.sampleRate), channels: l.channels, layout: l.tag))
        case .flac:
            let l = layout(info, format: .flac, stereo: stereo)
            if let note = l.note { notes.append(note) }
            audio = .encode(AudioEncoding(format: .flac(bits: bits), sampleRate: pcmRate(info.sampleRate), channels: l.channels, layout: l.tag))
        case .wav, .aiff:
            let l = layout(info, format: .pcm, stereo: stereo)
            if let note = l.note { notes.append(note) }
            audio = .encode(AudioEncoding(format: .pcm(bits: bits, bigEndian: target == .aiff),
                                          sampleRate: pcmRate(info.sampleRate), channels: l.channels, layout: l.tag))
        }
        if size != nil, target != .m4a {
            notes.append("\(target.title) is lossless, so it can't aim for a size.")
        }
        if info.audioTrackCount > 1 { notes.append("Its \(info.audioTrackCount) sound tracks were mixed into one.") }
        var plan = TranscodePlan(fileType: target.fileType, fileExtension: target.fileExtension, video: nil,
                                 audio: audio, notes: notes, targetTitle: title)
        plan.usesAudioFile = target.usesAudioFile
        plan.sizeLimit = limit
        return plan
    }

    /// AAC: copied when it already is AAC (unless asked to shrink it or mix it to stereo).
    static func aacPlan(_ info: MediaInfo, quality: Quality, stereo: Bool = false) -> (AudioPlan, String?) {
        let l = layout(info, format: .aac, stereo: stereo)
        let bitRate = QualityTable.aacBitRate(quality, channels: l.channels)
        let isAAC = info.audioCodec.map(Codecs.aac.contains) ?? false
        // Re-encoding AAC loses a little each time, so copy it unless asked to shrink it.
        let smallEnough = info.audioBitRate > 0 && info.audioBitRate <= Double(bitRate) * 1.25
        if isAAC && info.audioTrackCount == 1 && l.channels == info.channels && (quality != .smaller || smallEnough) {
            return (.copy, nil)
        }
        return (.encode(AudioEncoding(format: .aac(bitRate: bitRate), sampleRate: aacRate(info.sampleRate),
                                      channels: l.channels, layout: l.tag)), l.note)
    }

    enum LayoutFamily { case aac, alac, flac, pcm }

    /// How many channels a format keeps, and their layout: mono and stereo as they are, 5.1
    /// and 7.1 kept (Apple Lossless stops at 5.1), anything else mixed to stereo.
    static func layout(_ info: MediaInfo, format: LayoutFamily, stereo: Bool) -> (channels: Int, tag: AudioChannelLayoutTag?, note: String?) {
        let n = info.channels
        if n <= 2 { return (n == 1 ? 1 : 2, nil, nil) }
        if stereo { return (2, nil, nil) }
        switch n {
        case 6:
            return (6, format == .aac || format == .alac ? kAudioChannelLayoutTag_MPEG_5_1_D : kAudioChannelLayoutTag_MPEG_5_1_A, nil)
        case 7, 8:
            switch format {
            case .aac: return (8, kAudioChannelLayoutTag_AAC_7_1, nil)
            case .alac: return (6, kAudioChannelLayoutTag_MPEG_5_1_D, "Apple Lossless keeps up to 5.1, so its 7.1 sound was mixed to 5.1.")
            case .flac, .pcm: return (8, kAudioChannelLayoutTag_MPEG_7_1_C, nil)
            }
        default:
            return (2, nil, "Its \(n) sound channels were mixed to stereo.")
        }
    }

    /// Mono stays mono; everything else becomes stereo.
    static func channels(_ info: MediaInfo) -> Int {
        info.channels == 1 ? 1 : 2
    }

    /// AAC takes up to 48 kHz.
    static func aacRate(_ rate: Double) -> Double {
        guard rate > 0 else { return 44_100 }
        if rate <= 48_000 { return rate }
        return rate.truncatingRemainder(dividingBy: 44_100) == 0 ? 44_100 : 48_000
    }

    static func pcmRate(_ rate: Double) -> Double {
        rate > 0 ? rate : 44_100
    }

    // MARK: Sizes

    /// Fits a size into a box (either way round), keeping the aspect ratio. Never enlarges.
    /// With `even`, scaled sizes round to the nearest even number (video encoders want
    /// even sizes) without leaving the box: 1280×720 into 480p is 854×480.
    public static func fit(_ width: Int, _ height: Int, in box: (long: Int, short: Int)?, even: Bool = false) -> (Int, Int) {
        guard let box, width > 0, height > 0 else { return (width, height) }
        let (long, short) = width >= height ? (width, height) : (height, width)
        let scale = min(1, Double(box.long) / Double(long), Double(box.short) / Double(short))
        guard scale < 1 else { return (width, height) }
        func round(_ value: Double, limit: Int) -> Int {
            guard even else { return max(2, Int(value.rounded())) }
            let nearest = 2 * Int((value / 2).rounded())
            return max(2, nearest > limit ? nearest - 2 : nearest)
        }
        let (longLimit, shortLimit) = width >= height ? (box.long, box.short) : (box.short, box.long)
        return (round(Double(width) * scale, limit: longLimit), round(Double(height) * scale, limit: shortLimit))
    }

    /// Video encoders want even sizes.
    static func even(_ value: Int) -> Int {
        max(2, value - value % 2)
    }
}
