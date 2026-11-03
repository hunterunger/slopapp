import AVFoundation
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
    /// `AVVideoQualityKey`, nil for ProRes.
    public var quality: Double?
    /// Keep 10-bit HDR (HEVC Main10 / ProRes) instead of converting to standard range.
    public var keepHDR: Bool
    /// The source is HDR and the target can't carry it: tone-map to Rec. 709.
    public var toSDR: Bool
    public var frameRate: Double
}

public enum VideoPlan: Equatable, Sendable {
    case copy
    case encode(VideoEncoding)
}

public enum AudioFormatChoice: Equatable, Sendable {
    case aac(bitRate: Int)
    case alac(bits: Int)
    case pcm(bits: Int, bigEndian: Bool)
}

public struct AudioEncoding: Equatable, Sendable {
    public var format: AudioFormatChoice
    public var sampleRate: Double
    public var channels: Int
}

public enum AudioPlan: Equatable, Sendable {
    case none
    case copy
    case encode(AudioEncoding)
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

    /// Nothing is re-encoded: only the container changes.
    public var isRepackage: Bool {
        (video == nil || video == .copy) && (audio == .none || audio == .copy)
    }
}

/// Picks the container and per-track copy/encode for a file. Pure, so it's tested.
public enum Planner {
    /// The biggest frame H.264 encoders take (level 5.2).
    static let h264Box = (long: 4096, short: 2304)

    public static func plan(_ info: MediaInfo, settings: ConvertSettings, name: String) throws -> TranscodePlan {
        switch info.kind {
        case .video:
            if let audioTarget = settings.video.audioTarget {
                return try audioPlan(info, target: audioTarget, quality: settings.quality, name: name,
                                     title: settings.video.title)
            }
            return videoPlan(info, target: settings.video, settings: settings)
        case .audio:
            return try audioPlan(info, target: settings.audio, quality: settings.quality, name: name,
                                 title: settings.audio.title)
        case .image:
            preconditionFailure("Images don't use AVFoundation plans")
        }
    }

    /// Whether this plan would just make a copy of the input under a new name: same
    /// container, nothing re-encoded. Then we write nothing and say so.
    public static func isNoOp(_ plan: TranscodePlan, info: MediaInfo, inputExtension: String) -> Bool {
        guard plan.notes.isEmpty, sameExtension(inputExtension, plan.fileExtension) else { return false }
        if plan.isRepackage { return true }
        // WAV → WAV / AIFF → AIFF of plain PCM: decoding and re-writing changes nothing.
        if plan.video == nil, case .encode(let e) = plan.audio, case .pcm(let bits, _) = e.format,
           Codecs.audioName(info.audioCodec ?? "") == "PCM", info.audioTrackCount == 1,
           info.bitsPerSample == bits, info.sampleRate == e.sampleRate, info.channels == e.channels {
            return true
        }
        return false
    }

    static func sameExtension(_ a: String, _ b: String) -> Bool {
        let aliases = ["aif": "aiff", "jpeg": "jpg", "tif": "tiff", "heif": "heic"]
        let x = a.lowercased(), y = b.lowercased()
        return (aliases[x] ?? x) == (aliases[y] ?? y)
    }

    // MARK: Video

    static func videoPlan(_ info: MediaInfo, target: VideoTarget, settings: ConvertSettings) -> TranscodePlan {
        let codec: VideoCodecChoice
        let fileType: AVFileType
        let ext: String
        switch target {
        case .mp4HEVC: (codec, fileType, ext) = (.hevc, .mp4, "mp4")
        case .movProRes: (codec, fileType, ext) = (.proRes422, .mov, "mov")
        default: (codec, fileType, ext) = (.h264, .mp4, "mp4")
        }
        var notes: [String] = []

        var (width, height) = fit(info.width, info.height, in: settings.size.box, even: true)
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
        if copyable && !resized && (quality != .smaller || codec == .proRes422) {
            video = .copy
        } else {
            let toSDR = info.isHDR && codec == .h264
            video = .encode(VideoEncoding(
                codec: codec, width: even(width), height: even(height),
                quality: codec == .proRes422 ? nil : QualityTable.videoQuality(quality),
                keepHDR: info.isHDR && !toSDR, toSDR: toSDR, frameRate: info.frameRate
            ))
            if capped {
                notes.append("Scaled to \(even(width))×\(even(height)), the most H.264 allows. Choose HEVC to keep the full size.")
            }
            if toSDR { notes.append("HDR was converted to standard range.") }
        }

        let audio: AudioPlan
        if !info.hasAudio {
            audio = .none
        } else if codec == .proRes422 {
            audio = .encode(AudioEncoding(format: .pcm(bits: info.bitsPerSample >= 24 ? 24 : 16, bigEndian: false),
                                          sampleRate: pcmRate(info.sampleRate), channels: channels(info)))
        } else {
            audio = aacPlan(info, quality: quality)
        }
        if info.audioTrackCount > 1 && audio != .none {
            notes.append("Its \(info.audioTrackCount) sound tracks were mixed into one.")
        }
        return TranscodePlan(fileType: fileType, fileExtension: ext, video: video, audio: audio, notes: notes,
                             targetTitle: target.title)
    }

    // MARK: Audio

    static func audioPlan(_ info: MediaInfo, target: AudioTarget, quality: Quality, name: String, title: String) throws -> TranscodePlan {
        guard info.hasAudio else { throw ConvertError.noSound(name: name) }
        let audio: AudioPlan
        let bits = info.bitsPerSample >= 24 ? 24 : 16
        switch target {
        case .m4a:
            audio = aacPlan(info, quality: quality)
        case .alac:
            audio = info.audioTrackCount == 1 && info.audioCodec.map(Codecs.alac.contains) == true && info.channels <= 2
                ? .copy
                : .encode(AudioEncoding(format: .alac(bits: bits), sampleRate: pcmRate(info.sampleRate), channels: channels(info)))
        case .wav, .aiff:
            audio = .encode(AudioEncoding(format: .pcm(bits: bits, bigEndian: target == .aiff),
                                          sampleRate: pcmRate(info.sampleRate), channels: channels(info)))
        }
        var notes: [String] = []
        if info.audioTrackCount > 1 { notes.append("Its \(info.audioTrackCount) sound tracks were mixed into one.") }
        return TranscodePlan(fileType: target.fileType, fileExtension: target.fileExtension, video: nil,
                             audio: audio, notes: notes, targetTitle: title)
    }

    static func aacPlan(_ info: MediaInfo, quality: Quality) -> AudioPlan {
        let channels = channels(info)
        let bitRate = QualityTable.aacBitRate(quality, channels: channels)
        let isAAC = info.audioCodec.map(Codecs.aac.contains) ?? false
        // Re-encoding AAC loses a little each time, so copy it unless asked to shrink it.
        let smallEnough = info.audioBitRate > 0 && info.audioBitRate <= Double(bitRate) * 1.25
        if isAAC && info.audioTrackCount == 1 && info.channels <= 2 && (quality != .smaller || smallEnough) {
            return .copy
        }
        return .encode(AudioEncoding(format: .aac(bitRate: bitRate), sampleRate: aacRate(info.sampleRate), channels: channels))
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
