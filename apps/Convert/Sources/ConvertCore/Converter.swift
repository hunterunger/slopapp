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
        let info = try await MediaProbe.probe(input)
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
        case .video where settings.video == .gif:
            return try await makeGIF(input, info: info, progress: progress)
        case .video, .audio:
            return try await transcode(input, info: info, progress: progress)
        }
    }

    // MARK: Kinds

    private func convertImage(_ input: URL, info: MediaInfo, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        let target = settings.image
        guard capabilities.canWrite(target) else { throw ConvertError.cantWriteFormat(format: target.title, kind: .image) }
        let turn = options.transform
        if turn.isIdentity,
           ImageConverter.isNoOp(info, inputType: MediaTypes.contentType(of: input), target: target, size: settings.size) {
            return .unchanged("Already \(target.title). Nothing to change.")
        }
        let (quality, size) = (settings.quality, settings.size)
        return try write(input, ext: target.fileExtension) { scratch in
            let result = try ImageConverter.convert(input, to: scratch, target: target, quality: quality, size: size,
                                                    turn: turn, progress: progress)
            return (["\(target.title)", "\(result.width)×\(result.height)"], false, result.notes)
        }
    }

    private func makeGIF(_ input: URL, info: MediaInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        guard capabilities.canWrite(.gif) else { throw ConvertError.cantWriteFormat(format: "GIF", kind: .video) }
        let asset = AVURLAsset(url: input)
        let (quality, size, name, trim, turn) = (settings.quality, settings.size, input.lastPathComponent,
                                                 options.trim, options.transform)
        let shown = info.trimmed(trim)
        return try await writeAsync(input, ext: "gif") { scratch in
            let result = try await GIFMaker.make(asset, info: info, quality: quality, size: size, trim: trim, turn: turn,
                                                 to: scratch, name: name, progress: progress)
            var notes: [String] = []
            if shown.duration > QualityTable.longGIFSeconds { notes.append(GIFText.longClip) }
            if let cap = GIFText.capNote(info, quality: quality, size: size) { notes.append(cap) }
            return (["GIF", "\(result.width)×\(result.height)", Durations.string(shown.duration)], false, notes)
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

    private func transcode(_ input: URL, info: MediaInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> Conversion {
        let name = input.lastPathComponent
        if info.kind == .video, !capabilities.canWrite(settings.video) {
            throw ConvertError.cantWriteFormat(format: settings.video.title, kind: .video)
        }
        let plan = try Planner.plan(info, settings: settings, name: name, options: options)
        if Planner.isNoOp(plan, info: info, inputExtension: input.pathExtension) {
            let hint = plan.video != nil || plan.audio == .copy ? " To make it smaller, choose Smaller under Quality." : ""
            return .unchanged("Already \(plan.targetTitle). Nothing to change.\(hint)")
        }
        let asset = AVURLAsset(url: input, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        return try await writeAsync(input, ext: plan.fileExtension) { scratch in
            let extra = try await Transcoder(asset: asset, plan: plan, output: scratch, name: name).run(progress: progress)
            var parts = [plan.targetTitle]
            let turned = plan.transform.swapsSides
            switch plan.video {
            case .encode(let e)? where e.upright:
                parts.append("\(e.width)×\(e.height)")
            case .encode(let e)?:
                parts.append(info.isRotated != turned ? "\(e.height)×\(e.width)" : "\(e.width)×\(e.height)")
            case .copy?:
                parts.append(turned ? "\(info.displayHeight)×\(info.displayWidth)" : "\(info.displayWidth)×\(info.displayHeight)")
            case nil:
                break
            }
            if case .encode(let a) = plan.audio, case .aac(let bitRate) = a.format {
                parts.append("\(bitRate / 1000) kbps")
            } else if plan.audio == .copy, plan.video == nil, info.audioBitRate > 0,
                      info.audioCodec.map(Codecs.aac.contains) == true {
                parts.append("\(Int((info.audioBitRate / 1000).rounded())) kbps")
            }
            let length = plan.trim?.duration ?? info.duration
            if length > 0 { parts.append(Durations.string(length)) }
            var notes = plan.notes
            if let trim = plan.trim { notes.append("Trimmed to \(trim.title).") }
            if !plan.transform.isIdentity { notes.append(plan.transform.title + ".") }
            return (parts, plan.isRepackage, notes + extra)
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
        return [target, qualityMatters ? quality.rawValue : "", sizeMatters ? size.rawValue : "",
                "\(destination)"].joined(separator: "|")
    }
}
