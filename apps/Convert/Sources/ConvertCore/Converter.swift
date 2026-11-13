import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// What a finished conversion produced, for the row.
public struct ConversionReport: Equatable, Sendable {
    public var output: URL
    public var bytes: Int64
    /// "MP4 (H.264) · 1920×1080 · 2:14".
    public var summary: String
    /// Only the container changed: nothing was re-encoded, so there's no quality loss.
    public var repackaged: Bool
    /// Anything worth saying ("Scaled to 4096×2304…", "Only the first frame was kept.").
    public var notes: [String]
}

public enum Conversion: Equatable, Sendable {
    case converted(ConversionReport)
    /// Nothing written, with the reason ("Already MP4 (H.264).").
    case unchanged(String)
}

/// Converts one file with the given settings: picks the target for its kind, writes into a
/// scratch file, then moves it to a free name next to the original (or in the chosen
/// folder). Never overwrites anything, never touches the original, and leaves nothing
/// behind when it fails or is cancelled.
public struct Converter: Sendable {
    public var settings: ConvertSettings
    public var files: any FileStore
    public var capabilities: Capabilities

    public init(settings: ConvertSettings, files: any FileStore = SystemFileStore(), capabilities: Capabilities = .system) {
        self.settings = settings
        self.files = files
        self.capabilities = capabilities
    }

    /// `started` is told what kind the file turned out to be once it has been read (an
    /// animated GIF is a video, a picture-less .mp4 is audio).
    ///
    /// `replacing` is this row's own output from an earlier run: if the new file has the same
    /// name and folder, it takes that file's place instead of becoming "name 2.ext". Nothing
    /// else is ever overwritten.
    ///
    /// `options` are the file's own choices: its format (instead of the default for its
    /// kind), a trim, a turn or mirror, and which sound to keep.
    public func run(_ input: URL, options: FileOptions = FileOptions(), replacing previous: URL? = nil,
                    started: @Sendable (MediaKind) -> Void = { _ in },
                    progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Conversion {
        let info = try await MediaProbe.probe(input, decoders: capabilities.decoders)
        try Task.checkCancellation()
        started(info.kind)
        progress(0.01)
        var me = self
        me.previous = previous.flatMap { $0.standardizedFileURL == input.standardizedFileURL ? nil : $0 }
        me.options = options
        me.settings = settings.applying(options)
        return try await me.convert(input, info: info, progress: progress)
    }

    /// This row's earlier output (see `run`).
    var previous: URL?
    /// The file's own options (its format is already folded into `settings`).
    private var options = FileOptions()

    private func convert(_ input: URL, info: MediaInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {

        let folder = OutputPlanner.folder(for: input, destination: settings.destination)
        if case .folder = settings.destination, !files.isDirectory(folder) {
            throw ConvertError.noFolder(folder: folder.lastPathComponent)
        }
        guard files.isWritableDirectory(folder) else { throw ConvertError.cantWrite(folder: folder.lastPathComponent) }

        switch info.kind {
        case .image:
            return try await convertImage(input, info: info, folder: folder, progress: progress)
        case .video where info.isAnimatedImage:
            return try await convertAnimation(input, info: info, progress: progress)
        case _ where info.container != nil:
            return try await convertMatroska(input, info: info, folder: folder, progress: progress)
        case .video where settings.video == .gif:
            return try await makeGIF(input, media: input, info: info, progress: progress)
        case .video, .audio:
            return try await transcode(input, media: input, info: info, progress: progress)
        }
    }

    /// MKV and WebM: copied into an MP4 first (macOS reads that), then converted like any
    /// other video. When that copy is already the result (H.264 or HEVC with AAC to MP4), it
    /// goes straight to its place: one pass, no quality loss.
    private func convertMatroska(_ input: URL, info: MediaInfo, folder: URL,
                                 progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        let name = input.lastPathComponent
        let decoders = capabilities.decoders
        let bridgeType = try MatroskaBridge.outputType(input, capabilities: decoders)
        if info.kind == .video, settings.video != .gif, settings.video.audioTarget == nil, bridgeType == .mp4,
           let plan = try? Planner.plan(info, settings: settings, name: name, options: options),
           plan.isRepackage, plan.fileType == .mp4, plan.trim == nil, plan.transform.isIdentity, plan.sound == .all,
           plan.subtitles == .copy(info.subtitleTracks.map(\.index)) || info.subtitleTracks.isEmpty {
            let title = plan.targetTitle
            return try await writeAsync(input, ext: "mp4") { scratch in
                _ = try await MatroskaBridge.remux(input, to: scratch, capabilities: decoders, progress: progress)
                var parts = [title, "\(info.displayWidth)×\(info.displayHeight)"]
                if let channels = Channels.name(info.channels), info.channels > 2 { parts.append(channels) }
                if info.duration > 0 { parts.append(Durations.string(info.duration)) }
                return (parts, true, plan.notes)
            }
        }
        let base = input.deletingPathExtension().lastPathComponent
        let bridge: (url: URL, cleanup: @Sendable () -> Void)
        do {
            bridge = try files.scratch(for: base + (bridgeType == .mov ? ".mov" : ".mp4"), near: folder)
        } catch {
            throw ConvertError.cantWrite(folder: folder.lastPathComponent)
        }
        defer { bridge.cleanup() }
        _ = try await MatroskaBridge.remux(input, to: bridge.url, capabilities: decoders) { progress(0.02 + $0 * 0.28) }
        try Task.checkCancellation()
        var media: MediaInfo
        do {
            media = try await MediaProbe.probeAsset(AVURLAsset(url: bridge.url), name: name, kind: info.kind, decoders: decoders)
        } catch {
            throw ConvertError.damaged(name: name)
        }
        media.sourceNotes = info.sourceNotes
        media.fileBytes = info.fileBytes
        let rest: @Sendable (Double) -> Void = { progress(0.3 + $0 * 0.7) }
        if media.kind == .video, settings.video == .gif {
            return try await makeGIF(input, media: bridge.url, info: media, progress: rest)
        }
        return try await transcode(input, media: bridge.url, info: media, progress: rest)
    }

    // MARK: Kinds

    private func convertImage(_ input: URL, info: MediaInfo, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        let target = settings.image
        guard capabilities.canWrite(target) else { throw ConvertError.cantWriteFormat(format: target.title, kind: .image) }
        let turn = options.transform
        let crop = options.crop.flatMap { $0.isWhole ? nil : $0 }
        if turn.isIdentity, crop == nil,
           ImageConverter.isNoOp(info, inputType: MediaTypes.contentType(of: input), target: target, size: settings.size,
                                 fileSize: settings.fileSize) {
            return .unchanged("Already \(target.title). Nothing to change.")
        }
        let (quality, size, fileSize) = (settings.quality, settings.size, settings.fileSize)
        return try write(input, ext: target.fileExtension) { scratch in
            var result = try ImageConverter.convert(input, to: scratch, target: target, quality: quality, size: size,
                                                    turn: turn, crop: crop, fileSize: fileSize, progress: progress)
            if crop != nil { result.notes.append("Cropped.") }
            return (["\(target.title)", "\(result.width)×\(result.height)"], false, result.notes)
        }
    }

    private func makeGIF(_ input: URL, media: URL, info: MediaInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        guard capabilities.canWrite(.gif) else { throw ConvertError.cantWriteFormat(format: "GIF", kind: .video) }
        let asset = AVURLAsset(url: media)
        let (quality, size, name, trim, turn) = (settings.quality, settings.size, input.lastPathComponent,
                                                 options.trim, options.transform)
        let crop = options.crop.flatMap { $0.isWhole ? nil : $0 }
        var burn: Int?
        if case .burn(let index) = options.subtitles, info.subtitleTracks.contains(where: { $0.index == index && $0.canBurn }) {
            burn = index
        }
        let limit = settings.fileSize
        let files = files
        let shown = info.trimmed(trim)
        let (burnIndex, cropRect) = (burn, crop)
        return try await writeAsync(input, ext: "gif") { scratch in
            var overlay: SubtitleOverlay?
            if let burnIndex { overlay = SubtitleOverlay(cues: try await SubtitleReader.cues(asset, trackIndex: burnIndex)) }
            var shape = GIFMaker.shape(info, quality: quality, size: size, turn: turn, crop: cropRect)
            var result = try await GIFMaker.make(asset, info: info, quality: quality, size: size, trim: trim, turn: turn,
                                                 crop: cropRect, subtitles: overlay, shape: shape, to: scratch, name: name,
                                                 progress: progress)
            var notes: [String] = []
            // Too big for the size asked for: smaller frames (and fewer of them), up to three times.
            if let limit {
                var attempts = 0
                while let bytes = files.size(of: scratch), bytes > limit.bytes, attempts < 3 {
                    attempts += 1
                    let scale = (Double(limit.bytes) * 0.92 / Double(bytes)).squareRoot()
                    let long = max(80, Int(Double(max(shape.width, shape.height)) * scale))
                    let (w, h) = Planner.fit(shape.width, shape.height, in: (long, long))
                    shape = (w, h, scale < 0.6 ? max(6, shape.fps * 0.75) : shape.fps)
                    try? FileManager.default.removeItem(at: scratch)
                    result = try await GIFMaker.make(asset, info: info, quality: quality, size: size, trim: trim, turn: turn,
                                                     crop: cropRect, subtitles: overlay, shape: shape, to: scratch, name: name,
                                                     progress: { progress(0.5 + $0 / 2) })
                }
                if attempts > 0 { notes.append("Made \(result.width)×\(result.height) to fit in \(FileSizeLimit.number(limit.megabytes)) MB.") }
                if let bytes = files.size(of: scratch), bytes > limit.bytes {
                    notes.append("It's still over \(FileSizeLimit.number(limit.megabytes)) MB. Trim it to make it smaller.")
                }
            }
            if shown.duration > QualityTable.longGIFSeconds { notes.append(GIFText.longClip) }
            if limit == nil, let cap = GIFText.capNote(info, quality: quality, size: size) { notes.append(cap) }
            if burnIndex != nil { notes.append("Subtitles are part of the picture.") }
            return (["GIF", "\(result.width)×\(result.height)", Durations.string(shown.duration)], false, info.sourceNotes + notes)
        }
    }

    /// Animated GIF / PNG / WebP / HEICS: frames to a video (or to a GIF).
    private func convertAnimation(_ input: URL, info: MediaInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        let name = input.lastPathComponent
        let target = settings.video
        if target.audioTarget != nil { throw ConvertError.noSound(name: name) }
        guard capabilities.canWrite(target) else { throw ConvertError.cantWriteFormat(format: target.title, kind: .video) }
        let (quality, size) = (settings.quality, settings.size)
        if target == .gif {
            if info.imageFormat == "GIF" { return .unchanged("Already GIF. Nothing to change.") }
            return try await writeAsync(input, ext: "gif") { scratch in
                let result = try await AnimationConverter.toGIF(input, info: info, quality: quality, size: size,
                                                                to: scratch, name: name, progress: progress)
                return (["GIF", "\(result.width)×\(result.height)", Durations.string(info.duration)], false, [])
            }
        }
        let (fileType, ext): (AVFileType, String) = target == .movProRes ? (.mov, "mov") : (.mp4, "mp4")
        return try await writeAsync(input, ext: ext) { scratch in
            let result = try await AnimationConverter.toVideo(input, info: info, target: target, fileType: fileType,
                                                              quality: quality, size: size, to: scratch, name: name,
                                                              progress: progress)
            return ([target.title, "\(result.width)×\(result.height)", Durations.string(info.duration)], false, [])
        }
    }

    private func transcode(_ input: URL, media: URL, info: MediaInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        let name = input.lastPathComponent
        if info.kind == .video, !capabilities.canWrite(settings.video) {
            throw ConvertError.cantWriteFormat(format: settings.video.title, kind: .video)
        }
        if info.kind == .audio || settings.video.audioTarget != nil {
            let target = info.kind == .audio ? settings.audio : settings.video.audioTarget!
            if !capabilities.canWrite(target) { throw ConvertError.cantWriteFormat(format: target.title, kind: info.kind) }
        }
        let plan = try Planner.plan(info, settings: settings, name: name, options: options)
        if Planner.isNoOp(plan, info: info, inputExtension: input.pathExtension) {
            let hint = plan.video != nil || plan.audio == .copy ? " To make it smaller, choose Smaller under Quality." : ""
            return .unchanged("Already \(plan.targetTitle). Nothing to change.\(hint)")
        }
        let asset = AVURLAsset(url: media, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let files = files
        return try await writeAsync(input, ext: plan.fileExtension) { scratch in
            func write(_ plan: TranscodePlan, progress: @escaping @Sendable (Double) -> Void) async throws -> [String] {
                if plan.usesAudioFile {
                    return try await AudioFileTranscoder(asset: asset, plan: plan, output: scratch, name: name).run(progress: progress)
                }
                return try await Transcoder(asset: asset, plan: plan, output: scratch, name: name).run(progress: progress)
            }
            var used = plan
            var extra = try await write(plan, progress: progress)
            // Over the size asked for (encoders overshoot a little on busy footage): once
            // more, a little lower.
            if let limit = plan.sizeLimit, let bytes = files.size(of: scratch), bytes > limit.bytes,
               let lower = plan.lowered(actual: bytes, limit: limit) {
                try? FileManager.default.removeItem(at: scratch)
                used = lower
                extra = try await write(lower, progress: { progress(0.5 + $0 / 2) })
            }
            var parts = [used.targetTitle]
            let turned = used.transform.swapsSides
            switch used.video {
            case .encode(let e)? where e.upright:
                parts.append("\(e.width)×\(e.height)")
            case .encode(let e)?:
                parts.append(info.isRotated != turned ? "\(e.height)×\(e.width)" : "\(e.width)×\(e.height)")
            case .copy?:
                parts.append(turned ? "\(info.displayHeight)×\(info.displayWidth)" : "\(info.displayWidth)×\(info.displayHeight)")
            case nil:
                break
            }
            if case .encode(let a) = used.audio, case .aac(let bitRate) = a.format {
                parts.append("\(bitRate / 1000) kbps")
            } else if used.audio == .copy, used.video == nil, info.audioBitRate > 0,
                      info.audioCodec.map(Codecs.aac.contains) == true {
                parts.append("\(Int((info.audioBitRate / 1000).rounded())) kbps")
            }
            switch used.audio {
            case .encode(let a) where a.channels > 2: parts.append(Channels.name(a.channels) ?? "")
            case .copy where info.channels > 2: parts.append(Channels.name(info.channels) ?? "")
            default: break
            }
            let length = used.trim?.duration ?? info.duration
            if length > 0 { parts.append(Durations.string(length)) }
            var notes = used.notes
            if let trim = used.trim { notes.append("Trimmed to \(trim.title).") }
            if !used.transform.isIdentity { notes.append(used.transform.title + ".") }
            if case .encode(let e)? = used.video, let crop = e.crop { notes.append("Cropped to \(Int(crop.width))×\(Int(crop.height)).") }
            if case .copy(let kept) = used.subtitles, !kept.isEmpty, info.container != nil {
                notes.append(kept.count == 1 ? "Subtitles kept." : "\(kept.count) subtitle tracks kept.")
            }
            if let limit = used.sizeLimit, let bytes = files.size(of: scratch), bytes > limit.bytes {
                notes.append("It came out a little over \(FileSizeLimit.number(limit.megabytes)) MB. Trim it or choose a smaller size.")
            }
            return (parts, used.isRepackage, notes + extra)
        }
    }

    // MARK: Writing

    typealias Made = (summary: [String], repackaged: Bool, notes: [String])

    private func write(_ input: URL, ext: String, make: (URL) throws -> Made) throws -> Conversion {
        let (preferred, scratch, cleanup) = try prepare(input, ext: ext)
        defer { cleanup() }
        let made = try make(scratch)
        try Task.checkCancellation()
        return try finish(input, scratch: scratch, preferred: preferred, made: made)
    }

    func writeAsync(_ input: URL, ext: String, make: (URL) async throws -> Made) async throws -> Conversion {
        let (preferred, scratch, cleanup) = try prepare(input, ext: ext)
        defer { cleanup() }
        let made = try await make(scratch)
        try Task.checkCancellation()
        return try finish(input, scratch: scratch, preferred: preferred, made: made)
    }

    private func prepare(_ input: URL, ext: String) throws -> (URL, URL, @Sendable () -> Void) {
        let preferred = OutputPlanner.preferredURL(for: input, ext: ext, destination: settings.destination)
        let folder = preferred.deletingLastPathComponent()
        do {
            let scratch = try files.scratch(for: preferred.lastPathComponent, near: folder)
            return (preferred, scratch.url, scratch.cleanup)
        } catch {
            throw ConvertError.cantWrite(folder: folder.lastPathComponent)
        }
    }

    private func finish(_ input: URL, scratch: URL, preferred: URL, made: Made) throws -> Conversion {
        guard let bytes = files.size(of: scratch), bytes > 0 else {
            throw ConvertError.encodeFailed(name: input.lastPathComponent)
        }
        let output: URL
        if let previous, files.fileExists(previous),
           previous.deletingLastPathComponent().standardizedFileURL == preferred.deletingLastPathComponent().standardizedFileURL,
           previous.pathExtension.lowercased() == preferred.pathExtension.lowercased() {
            // Converting the same row again replaces what it made last time.
            try files.replace(previous, with: scratch)
            output = previous
        } else {
            output = try OutputPlanner.claim(scratch, as: preferred, files: files)
        }
        if settings.keepDates { files.copyDates(from: input, to: output) }
        return .converted(ConversionReport(output: output, bytes: bytes, summary: made.summary.joined(separator: " · "),
                                           repackaged: made.repackaged, notes: made.notes))
    }
}

extension ConvertSettings {
    /// "MP4 (H.264)" for videos, "M4A (AAC)" for audio, "JPEG" for images.
    public func targetTitle(for kind: MediaKind) -> String {
        switch kind {
        case .video: video.title
        case .audio: audio.title
        case .image: image.title
        }
    }
}

public enum GIFText {
    public static let longClip = "Long clips make big GIFs."

    /// The Size menu's note: "GIFs are capped at 640 px (800 px with Best)".
    public static func menuNote(_ quality: Quality) -> String {
        "GIFs are capped at \(QualityTable.gif(quality).longEdge) px (\(QualityTable.gif(.best).longEdge) px with Best)"
    }

    /// "GIFs are capped at 640 px. Best makes them 800 px." when the clip was bigger.
    public static func capNote(_ info: MediaInfo, quality: Quality, size: SizeLimit) -> String? {
        let cap = QualityTable.gif(quality).longEdge
        guard max(info.displayWidth, info.displayHeight) > cap, size.box.map({ $0.long > cap }) ?? true else { return nil }
        let best = QualityTable.gif(.best).longEdge
        return quality == .best ? "GIFs are capped at \(cap) px." : "GIFs are capped at \(cap) px. Best makes them \(best) px."
    }
}

extension ConvertSettings {
    /// Everything that decides how a file of this kind turns out. When it changes, files
    /// converted before are out of date.
    public func signature(for kind: MediaKind) -> String {
        let target: String = switch kind {
        case .video: video.rawValue
        case .audio: audio.rawValue
        case .image: image.rawValue
        }
        let sizeMatters = kind != .audio && !(kind == .video && video.audioTarget != nil)
        let qualityMatters: Bool = switch kind {
        case .video: video != .movProRes && video != .audioWAV
        case .audio: audio.usesQuality
        case .image: image.isLossy
        }
        let fileSizeMatters: Bool = switch kind {
        case .video: video != .movProRes && !(video.audioTarget.map { $0 != .m4a } ?? false)
        case .audio: audio == .m4a
        case .image: true
        }
        return [target, qualityMatters ? quality.rawValue : "", sizeMatters ? size.rawValue : "",
                "\(destination)", fileSizeMatters ? fileSize.map { "\($0.megabytes)" } ?? "" : ""].joined(separator: "|")
    }
}
