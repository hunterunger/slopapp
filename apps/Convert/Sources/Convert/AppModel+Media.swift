import AppKit
import AVFoundation
import ConvertCore
import SlopKit

/// Crop, subtitles, surround and file sizes: the card tools and menus for them.
extension AppModel {
    // MARK: Picture (crop, turn, flip)

    /// Videos and photos (not sound, not animated images: those are drawn frame by frame).
    func canCrop(_ entry: CardEntry) -> Bool {
        guard let info = facts(for: entry.input).info else { return false }
        return (info.kind == .image || info.kind == .video && !info.isAnimatedImage) && info.displayWidth > 1
    }

    /// The card's Picture menu: crop first, then turns and flips.
    func pictureEntries(for targets: [CardEntry]) -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = []
        if targets.count == 1, let entry = targets.first, canCrop(entry) {
            entries.append(.action(options(for: entry.input).crop == nil ? "Crop…" : "Change Crop…") { [self] in cropping = entry })
            if options(for: entry.input).crop != nil {
                entries.append(.action("Remove Crop") { [self] in updateOptions(for: [entry]) { $0.crop = nil } })
            }
            entries.append(.separator)
        }
        return entries + turnEntries(for: targets)
    }

    /// "Cropped to 1280×720" for a card.
    func cropTitle(_ crop: CropRect, for url: URL) -> String {
        guard let info = facts(for: url).info else { return "Cropped" }
        let pixels = crop.pixels(width: info.displayWidth, height: info.displayHeight, even: info.kind == .video)
        return "Cropped to \(Int(pixels.width))×\(Int(pixels.height))"
    }

    // MARK: Subtitles

    func hasSubtitles(_ entry: CardEntry) -> Bool {
        !(facts(for: entry.input).info?.subtitleTracks.isEmpty ?? true)
    }

    /// Keep them (as tracks viewers turn on), draw one into the picture, or leave them out.
    func subtitleEntries(for entry: CardEntry) -> [BarMenuEntry] {
        let tracks = facts(for: entry.input).info?.subtitleTracks ?? []
        let current = options(for: entry.input).subtitles
        let target = targetTitle(for: entry.input, kind: .video)
        let holdsTracks = target.hasPrefix("MP4") || target.hasPrefix("MOV")
        var entries: [BarMenuEntry] = [
            .choice(tracks.count > 1 ? "Keep All Subtitles" : "Keep Subtitles",
                    detail: holdsTracks ? "Viewers can turn them on" : "\(CardText.shortTarget(target)) can't hold subtitles",
                    isOn: current == .keep) { [self] in updateOptions(for: [entry]) { $0.subtitles = .keep } },
        ]
        let burnable = tracks.filter(\.canBurn)
        if !burnable.isEmpty {
            entries.append(.separator)
            entries.append(.header("Burn Into the Picture"))
            for track in burnable {
                entries.append(.choice(track.title, detail: nil, isOn: current == .burn(track.index)) { [self] in
                    updateOptions(for: [entry]) { $0.subtitles = .burn(track.index) }
                })
            }
        }
        entries.append(.separator)
        entries.append(.choice("No Subtitles", detail: "Leaves them out", isOn: current == .none) { [self] in
            updateOptions(for: [entry]) { $0.subtitles = .none }
        })
        return entries
    }

    /// For the Edit File menu (works on the whole selection): the first track that can be drawn.
    func burnFirstSubtitles(for entries: [CardEntry]) {
        for entry in entries {
            guard let track = facts(for: entry.input).info?.subtitleTracks.first(where: \.canBurn) else { continue }
            updateOptions(for: [entry]) { $0.subtitles = .burn(track.index) }
        }
    }

    // MARK: Surround

    func isSurround(_ entry: CardEntry) -> Bool {
        (facts(for: entry.input).info?.channels ?? 0) > 2
    }

    // MARK: File size

    /// The Quality menu's size section.
    func fileSizeEntries() -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = [.header("Fit in a Size")]
        for limit in FileSizeLimit.choices {
            entries.append(.choice(limit.title, detail: limit.detail, isOn: settings.fileSize == limit) { [self] in
                settings.fileSize = limit
            })
        }
        let custom = settings.fileSize.flatMap { FileSizeLimit.choices.contains($0) ? nil : $0 }
        entries.append(.choice(custom.map { "\($0.title)…" } ?? "Other Size…", detail: nil, isOn: custom != nil) { [self] in
            askForFileSize()
        })
        entries.append(.note("Each file is made to fit. Lossless formats can't."))
        return entries
    }

    func useQuality(_ quality: Quality) {
        settings.quality = quality
        settings.fileSize = nil
    }

    /// Asks for a size in MB.
    func askForFileSize() {
        let alert = NSAlert()
        alert.messageText = "Fit Each File in a Size"
        alert.informativeText = "Convert picks the bit rate so each video, sound file or photo comes out under this size."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "MB"
        field.stringValue = settings.fileSize.map { FileSizeLimit.number($0.megabytes) } ?? ""
        field.setAccessibilityLabel("Size in megabytes")
        let label = NSTextField(labelWithString: "MB")
        let stack = NSStackView(views: [field, label])
        stack.frame = NSRect(x: 0, y: 0, width: 160, height: 24)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Use Size")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value > 0 else {
            HUD.show("Type a size in MB, like 25", systemImage: "exclamationmark.circle")
            return
        }
        settings.fileSize = FileSizeLimit(megabytes: value)
    }

    /// "Balanced" or "Under 25 MB", for the bar.
    var qualityTitle: String { settings.fileSize?.title ?? settings.quality.title }
}

/// Files AVFoundation can't play (MKV, WebM) copied into an MP4 for the trim and crop
/// sheets and the card picture, kept until Convert quits. In-app, named so it could move.
@MainActor
final class PlayablePreviews {
    static let shared = PlayablePreviews()
    private var made: [URL: URL] = [:]
    private var thumbnails: [URL: URL] = [:]
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Convert Previews", isDirectory: true)

    init() {
        try? FileManager.default.removeItem(at: folder)
    }

    func needsPreview(_ url: URL) -> Bool { MatroskaBridge.handles(url) }

    /// A playable copy of `url` (itself when AVFoundation reads it).
    func playable(_ url: URL) async -> URL? {
        guard needsPreview(url) else { return url }
        if let existing = made[url] { return existing }
        guard let target = await make(url, frames: nil) else { return nil }
        made[url] = target
        return target
    }

    /// The first picture of a file AVFoundation can't open, for its card.
    func thumbnail(_ url: URL, maxSize: CGSize) async -> CGImage? {
        guard needsPreview(url) else { return nil }
        let clip: URL
        if let existing = made[url] ?? thumbnails[url] {
            clip = existing
        } else {
            guard let first = await make(url, frames: 1) else { return nil }
            thumbnails[url] = first
            clip = first
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        return try? await generator.image(at: .zero).image
    }

    private func make(_ url: URL, frames: Int?) async -> URL? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let type = try? MatroskaBridge.outputType(url) else { return nil }
        let target = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(type == .mov ? "mov" : "mp4")
        let result = await Task.detached(priority: .userInitiated) {
            try? await MatroskaBridge.remux(url, to: target, maxVideoFrames: frames)
        }.value
        return result == nil ? nil : target
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}
