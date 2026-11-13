import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a media file is: the facts rows show ("HEVC · 1920×1080 · 2:14") and the facts the
/// planner needs to decide between copying and re-encoding.
public struct MediaInfo: Equatable, Sendable {
    public var kind: MediaKind
    /// Encoded (stored) size, before rotation.
    public var width = 0
    public var height = 0
    /// True when the picture is shown rotated by 90° (portrait phone videos, EXIF 5–8).
    public var isRotated = false
    public var duration: Double = 0
    public var frameRate: Double = 0
    /// FourCC of the first video track ("avc1", "hvc1", "apcn"…), or nil.
    public var videoCodec: String?
    public var isHDR = false
    /// FourCC of the first audio track ("aac ", "lpcm", ".mp3"…), or nil.
    public var audioCodec: String?
    public var audioTrackCount = 0
    public var channels = 0
    public var sampleRate: Double = 0
    /// Bits per sample for PCM and lossless sources (0 when unknown or lossy).
    public var bitsPerSample = 0
    /// Bits per second of the first audio track (0 when unknown).
    public var audioBitRate: Double = 0
    /// Images: the format name ("HEIC") and frame count.
    public var imageFormat: String?
    public var frameCount = 1
    /// Every audio track, in file order (for choosing one).
    public var audioTracks: [AudioTrackInfo] = []
    /// Subtitle and caption tracks, in file order.
    public var subtitleTracks: [SubtitleTrackInfo] = []
    /// "MKV" or "WebM" for files read by `MatroskaBridge`; nil for what AVFoundation reads.
    public var container: String?
    /// Things worth saying about the file itself ("Its DTS sound can't be read…").
    public var sourceNotes: [String] = []
    /// The file's size in bytes (0 when unknown).
    public var fileBytes: Int64 = 0
    /// Bits per second of the picture (0 when unknown).
    public var videoBitRate: Double = 0

    public init(kind: MediaKind) {
        self.kind = kind
    }

    public var hasVideo: Bool { videoCodec != nil }
    /// An animated GIF, PNG, WebP or HEIC: treated as a (silent) video.
    public var isAnimatedImage: Bool { kind == .video && imageFormat != nil }
    public var hasAudio: Bool { audioCodec != nil }

    /// Size as shown (after rotation).
    public var displayWidth: Int { isRotated ? height : width }
    public var displayHeight: Int { isRotated ? width : height }

    /// "HEVC · 1920×1080 · 2:14", "AAC · 3:20", "HEIC · 4032×3024".
    public var summary: String {
        var parts: [String] = []
        switch kind {
        case .video:
            if let imageFormat { parts.append("Animated \(imageFormat)") }
            if let videoCodec { parts.append(Codecs.videoName(videoCodec)) }
            if isHDR { parts.append("HDR") }
            if width > 0 { parts.append("\(displayWidth)×\(displayHeight)") }
            if duration > 0 { parts.append(Durations.string(duration)) }
        case .audio:
            if let audioCodec { parts.append(Codecs.audioName(audioCodec)) }
            if duration > 0 { parts.append(Durations.string(duration)) }
        case .image:
            if let imageFormat { parts.append(imageFormat) }
            if width > 0 { parts.append("\(displayWidth)×\(displayHeight)") }
            if frameCount > 1 { parts.append("\(frameCount) frames") }
        }
        return parts.joined(separator: " · ")
    }
}

extension MediaInfo {
    /// The fuller line a file's card shows: "1920×1080 · HEVC · HDR · 30 fps · AAC · 160 kbps ·
    /// Stereo · 2:14" for videos, "AAC · 256 kbps · 44.1 kHz · Stereo · 3:20" for sound,
    /// "HEIC · 4032×3024" for images.
    public var cardLine: String {
        var parts: [String] = []
        func sound() {
            guard let audioCodec else { return }
            parts.append(Codecs.audioName(audioCodec))
            if audioBitRate > 0, !["PCM"].contains(Codecs.audioName(audioCodec)) {
                parts.append("\(Int((audioBitRate / 1000).rounded())) kbps")
            }
            if kind == .audio, sampleRate > 0 {
                let khz = sampleRate / 1000
                parts.append(khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz))
            }
            if kind == .audio, bitsPerSample > 0, ["PCM", "FLAC", "Apple Lossless"].contains(Codecs.audioName(audioCodec)) {
                parts.append("\(bitsPerSample)-bit")
            }
            if let name = Channels.name(channels) { parts.append(name) }
            if audioTrackCount > 1 { parts.append("\(audioTrackCount) sound tracks") }
        }
        switch kind {
        case .video:
            if width > 0 { parts.append("\(displayWidth)×\(displayHeight)") }
            if let imageFormat { parts.append("Animated \(imageFormat)") }
            if let videoCodec { parts.append(Codecs.videoName(videoCodec)) }
            if isHDR { parts.append("HDR") }
            if frameRate > 0 {
                parts.append(frameRate == frameRate.rounded() ? "\(Int(frameRate)) fps" : String(format: "%.2f fps", frameRate))
            }
            sound()
            switch subtitleTracks.count {
            case 0: break
            case 1: parts.append("Subtitles")
            default: parts.append("\(subtitleTracks.count) subtitles")
            }
            if duration > 0 { parts.append(Durations.string(duration)) }
        case .audio:
            sound()
            if duration > 0 { parts.append(Durations.string(duration)) }
        case .image:
            if let imageFormat { parts.append(imageFormat) }
            if width > 0 { parts.append("\(displayWidth)×\(displayHeight)") }
            if frameCount > 1 { parts.append("\(frameCount) frames") }
        }
        return parts.joined(separator: " · ")
    }
}

/// One audio track: enough to name it in a menu and to plan copying it.
public struct AudioTrackInfo: Equatable, Sendable {
    public var index: Int
    public var codec: String?
    public var channels = 0
    public var sampleRate: Double = 0
    public var bitsPerSample = 0
    public var bitRate: Double = 0
    /// "English", from the track's language tag, when it has one.
    public var language: String?
    public var isEnabled = true

    public init(index: Int, codec: String? = nil, channels: Int = 0, language: String? = nil) {
        self.index = index
        self.codec = codec
        self.channels = channels
        self.language = language
    }

    /// "Track 2 · English · AAC · Stereo".
    public var title: String {
        var parts = ["Track \(index + 1)"]
        if let language { parts.append(language) }
        if let codec { parts.append(Codecs.audioName(codec)) }
        if let name = Channels.name(channels) { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    static func read(_ track: AVAssetTrack, index: Int) async -> AudioTrackInfo {
        var info = AudioTrackInfo(index: index)
        if let (formats, rate, enabled, language) = try? await track.load(.formatDescriptions, .estimatedDataRate, .isEnabled, .languageCode) {
            info.bitRate = Double(rate)
            info.isEnabled = enabled
            if let language, language != "und" {
                info.language = Locale.current.localizedString(forLanguageCode: language) ?? language
            }
            if let format = formats.first {
                info.codec = Codecs.fourCC(CMFormatDescriptionGetMediaSubType(format))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    info.channels = Int(asbd.mChannelsPerFrame)
                    info.sampleRate = asbd.mSampleRate
                    info.bitsPerSample = Int(asbd.mBitsPerChannel)
                    if info.codec == "alac" || info.codec == "flac" {
                        info.bitsPerSample = [1: 16, 2: 20, 3: 24, 4: 32][Int(asbd.mFormatFlags)] ?? 16
                    }
                }
            }
        }
        return info
    }
}

extension MediaInfo {
    /// The file as the planner should see it once a sound choice is made: one chosen track,
    /// or none.
    public func choosingSound(_ choice: SoundChoice) -> MediaInfo {
        var info = self
        switch choice {
        case .all:
            break
        case .none:
            info.audioCodec = nil
            info.audioTrackCount = 0
        case .track(let index):
            guard let track = audioTracks.first(where: { $0.index == index }) else { break }
            info.audioCodec = track.codec
            info.audioTrackCount = 1
            info.channels = track.channels
            info.sampleRate = track.sampleRate
            info.bitsPerSample = track.bitsPerSample
            info.audioBitRate = track.bitRate
        }
        return info
    }

    /// The file as the planner should see it after a trim: shorter.
    public func trimmed(_ trim: TrimRange?) -> MediaInfo {
        guard let trim, !trim.isWhole(of: duration) else { return self }
        var info = self
        info.duration = min(duration, trim.end) - trim.start
        return info
    }
}

/// "Mono", "Stereo", "5.1", "7.1".
public enum Channels {
    public static func name(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 7: "6.1"
        case 8: "7.1"
        default: "\(count) channels"
        }
    }
}

/// Human names for codec FourCCs.
public enum Codecs {
    public static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
    }

    public static func videoName(_ fourCC: String) -> String {
        switch fourCC {
        case "avc1", "avc3": "H.264"
        case "hvc1", "hev1": "HEVC"
        case "dvh1", "dvhe": "Dolby Vision"
        case "apcn", "apch", "apcs", "apco": "ProRes 422"
        case "ap4h", "ap4x": "ProRes 4444"
        case "aprn", "aprh": "ProRes RAW"
        case "jpeg", "mjpa", "mjpb": "Motion JPEG"
        case "mp4v": "MPEG-4"
        case "mp2v", "mp1v": "MPEG-2"
        case "av01": "AV1"
        case "vp09": "VP9"
        case "dvc ", "dvcp", "dv5n", "dv5p", "dvhp": "DV"
        default: fourCC.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    public static func audioName(_ fourCC: String) -> String {
        switch fourCC {
        case "aac ", "aach", "aacp", "aacl": "AAC"
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64": "PCM"
        case "alac": "Apple Lossless"
        case ".mp3", ".mp2", ".mp1": "MP3"
        case "flac": "FLAC"
        case "opus": "Opus"
        case "ac-3": "AC-3"
        case "ec-3": "E-AC-3"
        case "samr": "AMR"
        case "vorb": "Vorbis"
        default: fourCC.trimmingCharacters(in: CharacterSet(charactersIn: " .")).uppercased()
        }
    }

    static let h264: Set<String> = ["avc1"]
    static let hevc: Set<String> = ["hvc1"]
    static let proRes422: Set<String> = ["apcn", "apch", "apcs", "apco"]
    static let aac: Set<String> = ["aac "]
    static let alac: Set<String> = ["alac"]
}

public enum Durations {
    /// "0:07", "2:14", "1:02:03".
    public static func string(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Reads `MediaInfo` from files.
public enum MediaProbe {
    /// Images by ImageIO; audio and video by AVFoundation. Throws `ConvertError` with a
    /// plain reason when the file can't be read.
    public static func probe(_ url: URL, decoders: DecoderCapabilities = .system) async throws -> MediaInfo {
        let name = url.lastPathComponent
        if MatroskaBridge.handles(url) { return try MatroskaBridge.probe(url, capabilities: decoders) }
        guard let kind = MediaTypes.kind(of: url) else { throw ConvertError.unsupported(name: name) }
        if kind == .image {
            var info = try probeImage(url)
            if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { info.fileBytes = Int64(bytes) }
            return info
        }
        do {
            var info = try await probeAsset(AVURLAsset(url: url), name: name, kind: kind, decoders: decoders)
            if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { info.fileBytes = Int64(bytes) }
            return info
        } catch ConvertError.damaged(let damaged) {
            // Tried and failed: a format macOS has no reader for says so by name.
            if let format = MediaTypes.unreadableFormatName(for: url) {
                throw ConvertError.unreadableFormat(name: name, format: format)
            }
            throw ConvertError.damaged(name: damaged)
        }
    }

    static func probeImage(_ url: URL) throws -> MediaInfo {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw ConvertError.damaged(name: name) }
        var info = MediaInfo(kind: .image)
        info.width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        info.height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        info.isRotated = orientation >= 5 && orientation <= 8
        info.frameCount = CGImageSourceGetCount(source)
        if let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }) {
            info.imageFormat = imageFormatName(type)
        }
        // Several frames with timing: an animation, converted like a silent video.
        let delays = AnimationConverter.delays(source)
        if info.frameCount > 1, !delays.isEmpty {
            info.kind = .video
            info.duration = delays.reduce(0, +)
            info.frameRate = info.duration > 0 ? Double(info.frameCount) / info.duration : 0
        }
        return info
    }

    static func imageFormatName(_ type: UTType) -> String {
        if type.conforms(to: .jpeg) { return "JPEG" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIC" }
        if type.conforms(to: .png) { return "PNG" }
        if type.conforms(to: .tiff) { return "TIFF" }
        if type.conforms(to: .gif) { return "GIF" }
        if type.conforms(to: .webP) { return "WebP" }
        if type.conforms(to: .rawImage) { return "RAW" }
        return type.preferredFilenameExtension?.uppercased() ?? "Image"
    }

    static func probeAsset(_ asset: AVURLAsset, name: String, kind: MediaKind,
                           decoders: DecoderCapabilities = .system) async throws -> MediaInfo {
        let tracks: [AVAssetTrack]
        let duration: CMTime
        do {
            (tracks, duration) = try await asset.load(.tracks, .duration)
        } catch {
            throw ConvertError.damaged(name: name)
        }
        if (try? await asset.load(.hasProtectedContent)) == true { throw ConvertError.protected(name: name) }
        var info = MediaInfo(kind: kind)
        info.duration = duration.isNumeric ? duration.seconds : 0

        let videos = tracks.filter { $0.mediaType == .video }
        let audios = tracks.filter { $0.mediaType == .audio }
        if let video = try await firstEnabled(videos) {
            let (size, transform, rate, formats) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
            info.width = Int(abs(size.width).rounded())
            info.height = Int(abs(size.height).rounded())
            info.isRotated = abs(transform.b) == 1 && abs(transform.c) == 1
            info.frameRate = Double(rate)
            if let format = formats.first {
                info.videoCodec = Codecs.fourCC(CMFormatDescriptionGetMediaSubType(format))
            }
            if let codec = info.videoCodec, !decoders.canDecode(codec) {
                throw ConvertError.unreadableCodec(name: name, codec: "\(Codecs.videoName(codec)) video")
            }
            info.isHDR = (try? await video.load(.mediaCharacteristics))?.contains(.containsHDRVideo) ?? false
            info.videoBitRate = Double((try? await video.load(.estimatedDataRate)) ?? 0)
        } else {
            // A "movie" with no picture (e.g. an .mp4 of a podcast) is audio.
            info.kind = .audio
        }
        info.audioTrackCount = audios.count
        for (index, track) in audios.enumerated() {
            info.audioTracks.append(await AudioTrackInfo.read(track, index: index))
        }
        if let audio = try await firstEnabled(audios) {
            let (formats, rate) = try await audio.load(.formatDescriptions, .estimatedDataRate)
            info.audioBitRate = Double(rate)
            if let format = formats.first {
                info.audioCodec = Codecs.fourCC(CMFormatDescriptionGetMediaSubType(format))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    info.channels = Int(asbd.mChannelsPerFrame)
                    info.sampleRate = asbd.mSampleRate
                    info.bitsPerSample = Int(asbd.mBitsPerChannel)
                    if info.audioCodec == "alac" || info.audioCodec == "flac" {
                        // Apple Lossless and FLAC keep the source bit depth in their flags.
                        info.bitsPerSample = [1: 16, 2: 20, 3: 24, 4: 32][Int(asbd.mFormatFlags)] ?? 16
                    }
                }
            }
        }
        for (index, track) in tracks.filter({ $0.mediaType == .subtitle || $0.mediaType == .closedCaption }).enumerated() {
            let (formats, language, characteristics) = (try? await track.load(.formatDescriptions, .languageCode, .mediaCharacteristics))
                ?? ([], nil, [])
            let code = formats.first.map { Codecs.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "tx3g"
            let languageName = language.flatMap { $0 == "und" ? nil : (Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
            info.subtitleTracks.append(SubtitleTrackInfo(index: index, format: code, language: languageName,
                                                         isForced: characteristics.contains(.containsOnlyForcedSubtitles)))
        }
        if !info.hasVideo && !info.hasAudio {
            // No usable tracks: either damaged or not a real media file.
            throw tracks.isEmpty ? ConvertError.damaged(name: name) : ConvertError.empty(name: name)
        }
        return info
    }

    static func firstEnabled(_ tracks: [AVAssetTrack]) async throws -> AVAssetTrack? {
        for track in tracks where (try? await track.load(.isEnabled)) ?? true {
            return track
        }
        return tracks.first
    }
}
