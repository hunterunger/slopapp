import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// The three kinds of file Convert takes. Each kind has its own target format.
public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case video, audio, image

    public var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Image"
        }
    }
}

/// Where a video goes. The audio-only targets extract the sound.
public enum VideoTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case mp4H264, mp4HEVC, movProRes, gif, audioM4A, audioWAV
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mp4H264: "MP4 (H.264)"
        case .mp4HEVC: "MP4 (HEVC)"
        case .movProRes: "MOV (ProRes 422)"
        case .gif: "GIF"
        case .audioM4A: "Audio Only (M4A)"
        case .audioWAV: "Audio Only (WAV)"
        }
    }

    /// One line for menus: who it's for.
    public var detail: String {
        switch self {
        case .mp4H264: "Plays everywhere"
        case .mp4HEVC: "About half the size, plays on recent devices"
        case .movProRes: "Big files for video editors"
        case .gif: "Silent loop for chats and docs"
        case .audioM4A: "Just the sound, compressed"
        case .audioWAV: "Just the sound, uncompressed"
        }
    }

    /// The short name rows show after "→".
    public var shortName: String {
        switch self {
        case .mp4H264, .mp4HEVC: "MP4"
        case .movProRes: "MOV"
        case .gif: "GIF"
        case .audioM4A: "M4A"
        case .audioWAV: "WAV"
        }
    }

    public var audioTarget: AudioTarget? {
        switch self {
        case .audioM4A: .m4a
        case .audioWAV: .wav
        default: nil
        }
    }
}

public enum AudioTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    // An MP3 target would slot in here, written through `AudioFileWriter` like FLAC, once
    // there's an encoder (macOS has none; see the README).
    case m4a, alac, flac, wav, aiff
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .m4a: "M4A (AAC)"
        case .alac: "Apple Lossless (M4A)"
        case .flac: "FLAC"
        case .wav: "WAV"
        case .aiff: "AIFF"
        }
    }

    public var detail: String {
        switch self {
        case .m4a: "Small, plays everywhere"
        case .alac: "Lossless, about half the size of WAV"
        case .flac: "Lossless, plays in most apps and players"
        case .wav: "Uncompressed, for editors"
        case .aiff: "Uncompressed, for Mac audio apps"
        }
    }

    public var shortName: String {
        switch self {
        case .m4a, .alac: "M4A"
        case .flac: "FLAC"
        case .wav: "WAV"
        case .aiff: "AIFF"
        }
    }

    /// The container AVFoundation writes. FLAC files are written by `AudioFileWriter`.
    public var fileType: AVFileType {
        switch self {
        case .m4a, .alac: .m4a
        case .flac: AVFileType(rawValue: "org.xiph.flac")
        case .wav: .wav
        case .aiff: .aiff
        }
    }

    /// Written as an audio file (decoded sound in, a `.flac` out) rather than by AVAssetWriter.
    public var usesAudioFile: Bool { self == .flac }

    public var fileExtension: String {
        switch self {
        case .m4a, .alac: "m4a"
        case .flac: "flac"
        case .wav: "wav"
        case .aiff: "aiff"
        }
    }

    /// Lossless and uncompressed targets ignore Quality.
    public var usesQuality: Bool { self == .m4a }
}

public enum ImageTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    // WebP is offered only where ImageIO can write it (no macOS can yet, so menus don't show
    // it); a bundled encoder would make `Capabilities.canWrite(.webp)` true.
    case jpeg, png, heic, avif, webp, tiff
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .avif: "AVIF"
        case .webp: "WebP"
        case .tiff: "TIFF"
        }
    }

    public var detail: String {
        switch self {
        case .jpeg: "Opens everywhere"
        case .png: "Lossless, keeps transparency"
        case .heic: "Smaller than JPEG, Apple devices"
        case .avif: "Smallest, recent browsers"
        case .webp: "Small, for websites"
        case .tiff: "Lossless, for print and editing"
        }
    }

    public var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .avif: UTType("public.avif") ?? .image
        case .webp: .webP
        case .tiff: .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .avif: "avif"
        case .webp: "webp"
        case .tiff: "tiff"
        }
    }

    public var isLossy: Bool { self == .jpeg || self == .heic || self == .avif || self == .webp }
}

/// Quality as intent. Each target maps it to its own numbers (see `QualityTable`).
public enum Quality: String, Codable, Sendable, CaseIterable, Identifiable {
    case smaller, balanced, best
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smaller: "Smaller"
        case .balanced: "Balanced"
        case .best: "Best"
        }
    }

    public var detail: String {
        switch self {
        case .smaller: "Smallest files, always re-encodes"
        case .balanced: "Looks the same, much smaller"
        case .best: "Hard to tell from the original"
        }
    }
}

/// An upper bound on picture size. Never enlarges. "1080p" means "fits in 1920×1080",
/// either way round, so portrait videos and photos are handled the same way.
public enum SizeLimit: String, Codable, Sendable, CaseIterable, Identifiable {
    case original, p2160, p1080, p720, p480
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: "Original Size"
        case .p2160: "Up to 4K (2160p)"
        case .p1080: "Up to 1080p"
        case .p720: "Up to 720p"
        case .p480: "Up to 480p"
        }
    }

    public var shortTitle: String {
        switch self {
        case .original: "Original Size"
        case .p2160: "Up to 4K"
        case .p1080: "Up to 1080p"
        case .p720: "Up to 720p"
        case .p480: "Up to 480p"
        }
    }

    /// The box (long edge, short edge) a picture must fit in, or nil for no limit.
    public var box: (long: Int, short: Int)? {
        switch self {
        case .original: nil
        case .p2160: (3840, 2160)
        case .p1080: (1920, 1080)
        case .p720: (1280, 720)
        case .p480: (854, 480)
        }
    }
}

public enum Destination: Codable, Equatable, Sendable, Hashable {
    /// Next to the original.
    case alongside
    /// Into this folder.
    case folder(URL)
}

/// Everything the user can choose. Codable so the app keeps it in UserDefaults.
public struct ConvertSettings: Codable, Equatable, Sendable {
    public var video: VideoTarget = .mp4H264
    public var audio: AudioTarget = .m4a
    public var image: ImageTarget = .jpeg
    public var quality: Quality = .balanced
    public var size: SizeLimit = .original
    public var destination: Destination = .alongside
    /// Copy the original's creation and modification dates to the new file.
    public var keepDates = false
    /// Make each file fit in this size (Convert picks the bit rate). Replaces Quality where
    /// a size can be aimed at.
    public var fileSize: FileSizeLimit?

    public init() {}

    /// The short "→ MP4" name for a file of this kind.
    public func targetName(for kind: MediaKind) -> String {
        switch kind {
        case .video: video.shortName
        case .audio: audio.shortName
        case .image: image.title
        }
    }

    // Lenient decoding: a stored value from an older version (or with a target this
    // version dropped) still loads, with defaults for whatever is missing.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ConvertSettings()
        video = (try? c.decode(VideoTarget.self, forKey: .video)) ?? d.video
        audio = (try? c.decode(AudioTarget.self, forKey: .audio)) ?? d.audio
        image = (try? c.decode(ImageTarget.self, forKey: .image)) ?? d.image
        quality = (try? c.decode(Quality.self, forKey: .quality)) ?? d.quality
        size = (try? c.decode(SizeLimit.self, forKey: .size)) ?? d.size
        destination = (try? c.decode(Destination.self, forKey: .destination)) ?? d.destination
        keepDates = (try? c.decode(Bool.self, forKey: .keepDates)) ?? d.keepDates
        fileSize = try? c.decodeIfPresent(FileSizeLimit.self, forKey: .fileSize)
    }
}

/// The numbers behind Quality. Documented in the README; tests pin them.
public enum QualityTable {
    /// `AVVideoQualityKey` for H.264 / HEVC.
    public static func videoQuality(_ quality: Quality) -> Double {
        switch quality {
        case .smaller: 0.40
        case .balanced: 0.55
        case .best: 0.75
        }
    }

    /// AAC bit rate in bits per second for this many channels: mono, stereo, 5.1 or 7.1.
    public static func aacBitRate(_ quality: Quality, channels: Int) -> Int {
        switch (quality, channels) {
        case (_, ...1): aacBitRate(quality, channels: 2) / 2
        case (.smaller, 2): 96_000
        case (.balanced, 2): 160_000
        case (.best, 2): 256_000
        case (.smaller, 3...6): 256_000
        case (.balanced, 3...6): 384_000
        case (.best, 3...6): 512_000
        case (.smaller, _): 320_000
        case (.balanced, _): 448_000
        case (.best, _): 640_000
        }
    }

    /// Lossy image quality (0...1) for JPEG, HEIC and AVIF.
    public static func imageQuality(_ quality: Quality, target: ImageTarget) -> Double {
        switch (quality, target) {
        case (.smaller, .jpeg): 0.70
        case (.balanced, .jpeg): 0.85
        case (.best, .jpeg): 0.95
        case (.smaller, _): 0.60
        case (.balanced, _): 0.78
        case (.best, _): 0.92
        }
    }

    /// GIF size and frame rate. The long edge is capped (640 px for Balanced: 640 wide for
    /// landscape clips, 640 tall for portrait ones).
    public static func gif(_ quality: Quality) -> (longEdge: Int, fps: Int) {
        switch quality {
        case .smaller: (480, 10)
        case .balanced: (640, 12)
        case .best: (800, 15)
        }
    }

    /// GIFs longer than this still convert, with a warning on the row.
    public static let longGIFSeconds: Double = 30
}

/// What a file is, from its type. Cheap (no decoding), so the queue can use it to pick a
/// concurrency lane. `Converter` refines it (a "movie" with no picture is audio).
public enum MediaTypes {
    /// What the drop zone and the file chooser accept.
    public static let accepted: [UTType] = [.audiovisualContent, .image]

    public static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
    }

    public static func kind(of url: URL) -> MediaKind? {
        guard let type = contentType(of: url) else { return nil }
        return kind(of: type)
    }

    public static func kind(of type: UTType) -> MediaKind? {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) { return .video }
        return nil
    }

    /// Containers macOS often can't open, with the name people know them by. Used to explain
    /// a file AVFoundation couldn't read (it's always tried first: newer macOS versions read
    /// more, Ogg for one). MKV and WebM have their own reader (`MatroskaBridge`).
    public static func unreadableFormatName(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "avi": "AVI"
        case "wmv", "asf": "WMV"
        case "wma": "WMA"
        case "flv", "f4v": "FLV"
        case "ogv": "Ogg video"
        case "ogg", "oga": "Ogg"
        case "rm", "rmvb": "RealMedia"
        case "divx", "xvid": "DivX"
        case "ape": "Monkey's Audio"
        case "wv": "WavPack"
        default: nil
        }
    }
}
