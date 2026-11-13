import AppKit
import ConvertCore
import QuickLookThumbnailing
import SlopKit
import SwiftUI

/// Cards sit on arbitrary pictures, so their chrome uses SlopKit's `OverlayPalette` (the dark
/// appearance's ink and paper, the same in light and dark mode), never pure black or white.
enum CardInk {
    static var ink: Color { Color(nsColor: OverlayPalette.ink) }
    static var paper: Color { Color(nsColor: OverlayPalette.paper) }
}

/// Card metrics. The bar along the bottom is inset `barInset` on three sides, so its
/// corners are concentric with the card's (`Radius.nested`).
enum CardMetrics {
    static let height: CGFloat = 132
    static let radius = Radius.l
    static let barInset: CGFloat = Spacing.xs + 2 // lint:allow 6 pt: the bar's gap to the card edge
    static let barHeight: CGFloat = 30
    static let barRadius = Radius.nested(in: radius, padding: barInset)
    /// Every tool in the bar (and the remove button) is this tall, so they share a centre line.
    static let control: CGFloat = 22
}

/// One file as a wide card, like a tile: its picture (a video frame, the photo) fills the
/// background under a dark scrim; the name and media facts sit on top; a bar along the bottom
/// shows its state and progress, with per-file tools (format, trim, turn, sound, more).
/// Cards always use dark styling, like photo tiles, so text stays readable on any picture.
struct CardView: View {
    let entry: CardEntry
    let kind: MediaKind?
    @Bindable var model: AppModel
    let isSelected: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var activeState

    private var row: RowFacts { model.facts(for: entry.input) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.leading, Spacing.l)
                .padding(.trailing, Spacing.m)
                .padding(.top, Spacing.m)
            Spacer(minLength: Spacing.s)
            CardStatusBar(entry: entry, kind: kind, model: model)
                .padding(CardMetrics.barInset)
        }
        .frame(height: CardMetrics.height)
        .background { CardBackground(url: thumbnailURL, kind: kind, showsSymbol: resultLine == nil) }
        .clipShape(shape)
        .hairlineBorder(shape, color: CardInk.paper.opacity(0.2))
        .overlay {
            if isSelected {
                // Grey in a window you aren't using, like Finder's selection.
                shape.strokeBorder(Color.selectionRing(activeState), lineWidth: 3)
            }
        }
        .environment(\.colorScheme, .dark)
        .contentShape(shape)
    }

    /// The input, unless it's gone (moved to the Trash after converting).
    private var thumbnailURL: URL {
        if let output = entry.item?.output, !FileManager.default.fileExists(atPath: entry.input.path) { return output }
        return entry.input
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.input.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(infoLine)
                    .font(.caption)
                    // Not .secondary: over a bright photo the vibrant grey drops to about 3:1.
                    .foregroundStyle(.primary.opacity(0.9))
                    .monospacedDigit()
                    .lineLimit(2)
                if let result = resultLine {
                    Text(result.text)
                        .font(.caption)
                        .foregroundStyle(result.isProblem ? AnyShapeStyle(.textOrange) : AnyShapeStyle(.primary.opacity(0.85)))
                        .lineLimit(2)
                        .help(result.text)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                model.remove([entry])
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    // A white cross on a darkened disc: readable on any picture.
                    .foregroundStyle(CardInk.paper, CardInk.ink.opacity(0.6))
                    .frame(width: CardMetrics.control, height: CardMetrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // The button's box overhangs the top of the text a little so the disc sits on
            // the name's centre line.
            .padding(.top, -Spacing.xs / 2)
            .help("Remove from the list. The file isn't touched.")
            .accessibilityLabel("Remove \(entry.input.lastPathComponent) from List")
        }
    }

    /// "33.9 MB · 1280×720 · H.264 · 30 fps · AAC · Stereo · 0:41".
    private var infoLine: String {
        let bytes: Int64? = switch entry {
        case .staged(let file): file.bytes
        case .item(let item): item.originalBytes
        }
        let parts = [bytes.map(FileQueueText.bytes), row.info?.cardLine].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Reading…" : parts.joined(separator: " · ")
    }

    /// What it became, why it failed, or what's set for it.
    private var resultLine: (text: String, isProblem: Bool)? {
        switch entry.item?.state {
        case .finished(.produced)?:
            guard let report = row.report else { return nil }
            var parts = [report.summary]
            if report.repackaged { parts.append("No quality loss") }
            parts += report.notes
            if row.trashedOriginal { parts.append("Original moved to the Trash") }
            return (parts.joined(separator: " · "), false)
        case .finished(.unchanged(let reason))?, .finished(.skipped(let reason))?:
            return (reason, false)
        case .failed(let message)?:
            return (message, true)
        default:
            if case .staged = entry, let problem = row.readError { return (problem, true) }
            var edits = CardText.edits(row.options, kind: kind)
            if let crop = row.options.crop {
                edits = [model.cropTitle(crop, for: entry.input), edits].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return edits.isEmpty ? nil : (edits, false)
        }
    }
}

/// The bar along a card's bottom: state and progress on the left, tools on the right.
struct CardStatusBar: View {
    let entry: CardEntry
    let kind: MediaKind?
    @Bindable var model: AppModel

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardMetrics.barRadius, style: .continuous)
        HStack(spacing: Spacing.s) {
            primaryButton
            Text(statusText)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .accessibilityLabel("Status")
                .accessibilityValue(statusText)
            Spacer(minLength: Spacing.xs)
            if !isUnreadable { tools }
        }
        // Less on the trailing side: the format pop-up has its own margin, and this puts its
        // chevron on the same right edge as the remove button above it.
        .padding(.leading, Spacing.xs)
        .padding(.trailing, Spacing.xs / 2)
        .frame(height: CardMetrics.barHeight)
        .background {
            ZStack(alignment: .leading) {
                shape.fill(reduceTransparency ? AnyShapeStyle(CardInk.ink.opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial))
                if let fraction = progress {
                    // A straight leading edge, clipped to the bar's corners.
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.windowAccent(activeState).opacity(0.45))
                            .frame(width: proxy.size.width * fraction)
                    }
                    .clipShape(shape)
                }
            }
        }
    }

    /// Read and found unconvertible (damaged, MKV…), or failed in a way trying again won't
    /// fix: nothing to start or set, so no tools.
    private var isUnreadable: Bool {
        switch entry {
        case .staged: model.facts(for: entry.input).readError != nil
        case .item(let item): item.state.isFailure && !item.canRetry
        }
    }

    private var progress: Double? {
        if case .working(let fraction)? = entry.item?.state { return fraction ?? 0.03 }
        return nil
    }

    private var targetTitle: String? {
        kind.map { model.targetTitle(for: entry.input, kind: $0) }
    }

    /// The state only: the target sits right there in the format pop-up. While converting,
    /// the target it was started with shows if the pop-up has changed since.
    private var statusText: String {
        switch entry {
        case .staged:
            if isUnreadable { return "Can't convert" }
            return "Ready"
        case .item(let item):
            switch item.state {
            case .waiting: return "Waiting…"
            case .working(let fraction):
                let running = model.facts(for: item).runningTarget.flatMap { $0 == targetTitle ? nil : " → \($0)" } ?? ""
                return fraction.map { "Converting \(Int($0 * 100))%" + running } ?? "Converting…" + running
            case .finished(.produced(_, let bytes)):
                if model.isOutdated(item) { return "Settings changed" }
                return "Done · " + (item.originalBytes.map(FileQueueText.bytes).map { $0 + " → " } ?? "") + FileQueueText.bytes(bytes)
            case .finished: return "Nothing to change"
            case .failed: return "Couldn't convert"
            case .cancelled: return "Stopped"
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch entry {
        case .staged:
            if isUnreadable {
                problemSymbol
            } else {
                iconButton("Start", symbol: "play.fill", help: "Convert this file now") { model.start([entry]) }
            }
        case .item(let item):
            switch item.state {
            case .waiting, .working:
                iconButton("Stop", symbol: "stop.fill", help: "Stop converting this file") { model.queue.cancel(item) }
            case .finished(.produced):
                if model.isOutdated(item) {
                    iconButton("Convert Again", symbol: "arrow.clockwise", help: "Convert again with the new settings") { model.queue.retry(item) }
                } else {
                    iconButton("Show in Finder", symbol: "magnifyingglass", help: "Show the new file in Finder") { FileQueueActions.reveal([item]) }
                }
            case .finished:
                iconButton("Show in Finder", symbol: "magnifyingglass", help: "Show the file in Finder") { FileQueueActions.reveal([item]) }
            case .failed, .cancelled:
                if item.canRetry {
                    iconButton("Try Again", symbol: "arrow.clockwise", help: "Try converting it again") { model.queue.retry(item) }
                } else {
                    problemSymbol
                }
            }
        }
    }

    private var problemSymbol: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(CardTools.symbolFont)
            .foregroundStyle(.orange)
            .frame(width: CardMetrics.control, height: CardMetrics.control)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var tools: some View {
        let targets = model.targets(for: entry)
        HStack(spacing: Spacing.xs) {
            if let kind {
                let row = model.facts(for: entry.input)
                if model.canTrim(entry) {
                    iconButton("Trim", symbol: "timeline.selection",
                               help: row.options.trim.map { "Trimmed to \($0.title). Click to change." } ?? "Trim: keep only part of it",
                               highlighted: row.options.trim != nil) { model.trimming = entry }
                }
                if model.canTurn(entry) {
                    // Crop, rotate and flip: one tool for the picture's shape.
                    let edited = !row.options.transform.isIdentity || row.options.crop != nil
                    let help = [row.options.crop.map { model.cropTitle($0, for: entry.input) },
                                row.options.transform.isIdentity ? nil : row.options.transform.title]
                        .compactMap { $0 }.joined(separator: ", ")
                    BarMenuButton(name: "Picture", value: "", symbol: "crop.rotate",
                                  help: help.isEmpty ? "Crop, rotate or flip" : help,
                                  dark: true, highlighted: edited, active: activeState.isActiveWindow,
                                  size: CGSize(width: CardMetrics.control, height: CardMetrics.control)) {
                        model.pictureEntries(for: targets)
                    }
                }
                if kind == .video, let info = row.info, info.hasAudio, !info.isAnimatedImage {
                    BarMenuButton(name: "Sound", value: "", symbol: row.options.sound == .none ? "speaker.slash" : "speaker.wave.2",
                                  help: CardText.sound(row.options.sound, info: info), dark: true,
                                  highlighted: row.options.sound != .all, active: activeState.isActiveWindow,
                                  size: CGSize(width: CardMetrics.control, height: CardMetrics.control)) {
                        model.soundEntries(for: entry)
                    }
                }
                if kind == .audio, model.isSurround(entry), let info = row.info {
                    BarMenuButton(name: "Sound", value: "", symbol: "hifispeaker.2",
                                  help: row.options.stereo ? "Sound: mixed to stereo" : "Sound: \(Channels.name(info.channels) ?? "surround") kept",
                                  dark: true, highlighted: row.options.stereo, active: activeState.isActiveWindow,
                                  size: CGSize(width: CardMetrics.control, height: CardMetrics.control)) {
                        model.surroundEntries(for: entry)
                    }
                }
                if kind == .video, model.hasSubtitles(entry) {
                    BarMenuButton(name: "Subtitles", value: "",
                                  symbol: row.options.subtitles == .none ? "captions.bubble.fill" : "captions.bubble",
                                  help: CardText.subtitles(row.options.subtitles, info: row.info), dark: true,
                                  highlighted: row.options.subtitles != .keep, active: activeState.isActiveWindow,
                                  size: CGSize(width: CardMetrics.control, height: CardMetrics.control)) {
                        model.subtitleEntries(for: entry)
                    }
                }
                BarMenuButton(name: "Format", value: CardText.shortTarget(model.targetTitle(for: entry.input, kind: kind)),
                              symbol: "", help: "This file becomes \(model.targetTitle(for: entry.input, kind: kind))",
                              dark: true, highlighted: row.options.hasOwnFormat(for: kind), active: activeState.isActiveWindow,
                              size: CGSize(width: 0, height: CardMetrics.control)) {
                    model.formatEntries(for: targets, kind: kind)
                }
            }
        }
    }

    private func iconButton(_ title: String, symbol: String, help: String, highlighted: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(CardTools.symbolFont)
                .frame(width: CardMetrics.control, height: CardMetrics.control)
                .foregroundStyle(highlighted ? Color.windowAccent(activeState) : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// How the card's tools draw their symbols, shared by the SwiftUI buttons and the AppKit
/// pop-ups so they match in size and weight.
enum CardTools {
    static let symbolPointSize: CGFloat = 12
    static var symbolFont: Font { .system(size: symbolPointSize, weight: .semibold) }
    static var symbolConfiguration: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
    }
}

/// Short wording for cards.
enum CardText {
    /// "MP4 (H.264)" stays; "Audio Only (M4A)" becomes "M4A"; "Apple Lossless (M4A)" stays.
    static func shortTarget(_ title: String) -> String {
        title.hasPrefix("Audio Only (") ? String(title.dropFirst("Audio Only (".count).dropLast()) + " (sound)" : title
    }

    /// "Trimmed to 0:02.0 – 0:10.0 · Turned right · No sound".
    static func edits(_ options: FileOptions, kind: MediaKind?) -> String {
        var parts: [String] = []
        if let trim = options.trim { parts.append("Trimmed to \(trim.title)") }
        if !options.transform.isIdentity { parts.append(options.transform.title) }
        switch options.sound {
        case .all: break
        case .none: parts.append("No sound")
        case .track(let index): parts.append("Sound track \(index + 1)")
        }
        switch options.subtitles {
        case .keep: break
        case .burn: parts.append("Subtitles burned in")
        case .none: parts.append("No subtitles")
        }
        if options.stereo { parts.append("Mixed to stereo") }
        return parts.joined(separator: " · ")
    }

    static func subtitles(_ choice: SubtitleChoice, info: MediaInfo?) -> String {
        let tracks = info?.subtitleTracks ?? []
        switch choice {
        case .keep: return tracks.count > 1 ? "Subtitles: all \(tracks.count) kept" : "Subtitles: kept"
        case .none: return "Subtitles: removed"
        case .burn(let index):
            return "Subtitles: \(tracks.first { $0.index == index }?.title ?? "track \(index + 1)") burned into the picture"
        }
    }

    static func sound(_ choice: SoundChoice, info: MediaInfo) -> String {
        switch choice {
        case .all: info.audioTrackCount > 1 ? "Sound: all \(info.audioTrackCount) tracks, mixed" : "Sound: kept"
        case .none: "Sound: removed"
        case .track(let index): "Sound: track \(index + 1) only"
        }
    }
}

/// The card's picture: a Quick Look thumbnail filling the card under a dark scrim. Sound
/// files (no picture) get the accent colour with a large symbol.
struct CardBackground: View {
    let url: URL
    let kind: MediaKind?
    /// The large kind symbol; off when the card has a third line of text it would sit under.
    var showsSymbol = true
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            // Black under everything, so transparent pictures (a PNG logo) don't show the
            // window through and wash out the text.
            CardInk.ink
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if showsSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(CardInk.paper.opacity(0.2))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Spacing.xxl + Spacing.xs)
                }
            }
            // Darkest behind the name and facts (they must read on any picture), lightest
            // in the middle, darker again behind the bar.
            LinearGradient(stops: [.init(color: CardInk.ink.opacity(0.8), location: 0),
                                   .init(color: CardInk.ink.opacity(0.65), location: 0.35),
                                   .init(color: CardInk.ink.opacity(0.4), location: 0.6),
                                   .init(color: CardInk.ink.opacity(0.6), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = await CardThumbnails.shared.thumbnail(for: url, scale: scale)
        }
    }

    private var symbol: String {
        switch kind {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case nil: "doc"
        }
    }
}

/// Large thumbnails for cards (a frame for videos, the picture for images), generated lazily
/// and cached. Sound files get none (Quick Look would only give the file icon).
@MainActor
final class CardThumbnails {
    static let shared = CardThumbnails()
    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 200
    }

    func thumbnail(for url: URL, scale: CGFloat) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let kind = MediaTypes.kind(of: url), kind != .audio, MediaTypes.unreadableFormatName(for: url) == nil else { return nil }
        if PlayablePreviews.shared.needsPreview(url) {
            // Quick Look has no picture for MKV or WebM: take the first frame ourselves.
            guard let frame = await PlayablePreviews.shared.thumbnail(url, maxSize: CGSize(width: 420 * scale, height: 240 * scale))
            else { return nil }
            let image = NSImage(cgImage: frame, size: NSSize(width: CGFloat(frame.width) / scale, height: CGFloat(frame.height) / scale))
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 420, height: 240), scale: scale,
                                                   representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
