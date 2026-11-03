import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The body of a drop-in utility window (design system §2b): a big `DropZone` when the
/// queue is empty, then one row per file (thumbnail, name, before → after, % saved,
/// progress, and Cancel / Try Again / Show in Finder) with a slim drop strip under it.
/// Drops anywhere on the list add files too; folders are searched.
///
///     FileQueueView(queue: model.queue, selection: $model.selection,
///                   dropTitle: "Drop images here", dropSymbol: "photo")
///
/// - `onFiles`: called with dropped or chosen URLs instead of `queue.add` (to also log,
///   show a HUD, etc.). Call `queue.add` from it.
/// - `onOpen`: double-click / Return on a row. Default: show its output in Finder.
/// - `menuExtras`: extra items for the rows' right-click menu, given the clicked rows.
///
/// Row options are view modifiers (all optional; the defaults suit a compressor):
///
///     FileQueueView(...)
///         .fileQueueSizeStyle(.neutral)          // "4.2 MB → 18 MB", no green "−N%"
///         .fileQueueDetail { item in "→ MP4 · 1920×1080" }   // extra facts per row
///         .fileQueueRetryTitle("Convert Again")  // context menu wording
///         .fileQueueShowsOutputName(false)       // hide "→ output name" in titles
///         .fileQueueOnRemove { rows in model.removeWithUndo(rows) }  // e.g. Undo
public struct FileQueueView<MenuExtras: View>: View {
    @Bindable var queue: FileQueue
    @Binding var selection: Set<FileQueueItem.ID>
    let dropTitle: String
    let dropSymbol: String
    let onFiles: (([URL]) -> Void)?
    let onOpen: (FileQueueItem) -> Void
    let menuExtras: ([FileQueueItem]) -> MenuExtras

    @State private var listTargeted = false
    @Environment(\.fileQueueRemove) private var removeHandler
    @State private var highlighted = Set<FileQueueItem.ID>()
    @FocusState private var listFocused: Bool
    @Environment(\.fileQueueFollowsNewFiles) private var followsNewFiles
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        queue: FileQueue,
        selection: Binding<Set<FileQueueItem.ID>>,
        dropTitle: String,
        dropSymbol: String = "arrow.down.doc",
        onFiles: (([URL]) -> Void)? = nil,
        onOpen: @escaping (FileQueueItem) -> Void = { FileQueueActions.reveal([$0]) },
        @ViewBuilder menuExtras: @escaping ([FileQueueItem]) -> MenuExtras
    ) {
        self.queue = queue
        self._selection = selection
        self.dropTitle = dropTitle
        self.dropSymbol = dropSymbol
        self.onFiles = onFiles
        self.onOpen = onOpen
        self.menuExtras = menuExtras
    }

    private func take(_ urls: [URL]) {
        if let onFiles { onFiles(urls) } else { Task { await queue.add(urls) } }
    }

    /// With `unsupportedReason` set, any file can be dropped: the queue explains the ones it
    /// can't take in their rows.
    private var dropTypes: [UTType] {
        queue.acceptedTypes + [.folder] + (queue.unsupportedReason == nil ? [] : [.item])
    }

    public var body: some View {
        if queue.items.isEmpty {
            DropZone(dropTitle, systemImage: dropSymbol, types: dropTypes) { take($0) }
            .padding(Spacing.windowMargin)
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { scroller in
                List(selection: $selection) {
                    ForEach(queue.items) { item in
                        FileQueueRow(item: item, queue: queue, isSelected: selection.contains(item.id))
                            .listRowBackground(highlighted.contains(item.id)
                                               ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)) : nil)
                            .tag(item.id)
                            .id(item.id)
                    }
                }
                .listStyle(.inset)
                .focused($listFocused)
                .onAppear { if followsNewFiles { listFocused = true } }
                .onChange(of: queue.addedBatches) {
                    guard followsNewFiles, let first = queue.lastAdded.first else { return }
                    let ids = queue.lastAdded
                    listFocused = true
                    highlighted = Set(ids)
                    Task {
                        // Let the list lay out the new rows before scrolling to them.
                        try? await Task.sleep(for: .milliseconds(60))
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            scroller.scrollTo(ids.count > 1 ? first : ids[ids.count - 1], anchor: ids.count > 1 ? .top : .bottom)
                        }
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.easeOut(duration: 0.25)) { highlighted.subtract(ids) }
                    }
                }
                .contextMenu(forSelectionType: FileQueueItem.ID.self) { ids in
                    FileQueueContextMenu(queue: queue, items: items(for: ids))
                    menuExtras(items(for: ids))
                } primaryAction: { ids in
                    items(for: ids).first.map(onOpen)
                }
                .onDeleteCommand { removeRows(items(for: selection)) }
                .overlay {
                    if listTargeted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(2)
                            .allowsHitTesting(false)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    let accepted = DropFilter.accepted(urls, types: dropTypes)
                    guard !accepted.isEmpty else { return false }
                    take(accepted)
                    return true
                } isTargeted: { listTargeted = $0 }
                }

                DropStrip(types: dropTypes) { take($0) }
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
            }
        }
    }

    private func removeRows(_ rows: [FileQueueItem]) {
        if let removeHandler { removeHandler.remove(rows) } else { queue.remove(rows) }
    }

    private func items(for ids: Set<FileQueueItem.ID>) -> [FileQueueItem] {
        queue.items.filter { ids.contains($0.id) }
    }
}

extension FileQueueView where MenuExtras == EmptyView {
    public init(
        queue: FileQueue,
        selection: Binding<Set<FileQueueItem.ID>>,
        dropTitle: String,
        dropSymbol: String = "arrow.down.doc",
        onFiles: (([URL]) -> Void)? = nil,
        onOpen: @escaping (FileQueueItem) -> Void = { FileQueueActions.reveal([$0]) }
    ) {
        self.init(queue: queue, selection: selection, dropTitle: dropTitle, dropSymbol: dropSymbol,
                  onFiles: onFiles, onOpen: onOpen) { _ in EmptyView() }
    }
}

/// The slim "drop more here" target under a non-empty queue. Click to choose files.
struct DropStrip: View {
    let types: [UTType]
    let onFiles: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        Button {
            FileQueueActions.chooseFiles(types: types, then: onFiles)
        } label: {
            Label("Drop more files here, or click to choose", systemImage: "plus")
                .font(.callout)
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1, dash: isTargeted ? [] : [5, 4]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Files")
        .accessibilityHint("Opens a file chooser")
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = DropFilter.accepted(urls, types: types)
            guard !accepted.isEmpty else { return false }
            onFiles(accepted)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// One row: thumbnail, name, before → after, progress, and the one action that fits.
struct FileQueueRow: View {
    let item: FileQueueItem
    let queue: FileQueue
    var isSelected = false
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.fileQueueSizeStyle) private var sizeStyle
    @Environment(\.fileQueueDetail) private var detailProvider
    @Environment(\.fileQueueShowsOutputName) private var showsOutputName

    /// The app's extra facts for this row, if any.
    private var extra: String? {
        detailProvider?(item).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func withExtra(_ text: String) -> String {
        extra.map { text + " · " + $0 } ?? text
    }

    /// The input, unless it's gone (replaced by its output, e.g. a converted original).
    private var thumbnailURL: URL {
        if let output = item.output, !FileManager.default.fileExists(atPath: item.input.path) { return output }
        return item.input
    }

    /// "Photo.webp", or "Photo.webp → Photo-small.jpg" when the output has another name.
    private var title: some View {
        HStack(spacing: Spacing.xs) {
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if showsOutputName, let outputName = item.outputName {
                Text("→ " + outputName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                FileThumbnail(url: thumbnailURL)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    title
                    detail
                }
                Spacer(minLength: Spacing.s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FileQueueText.accessibilityLabel(for: item, sizeStyle: sizeStyle, detail: extra))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityActions { accessibilityActions }
            trailing
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var detail: some View {
        switch item.state {
        case .waiting:
            Text(withExtra(sizeText(item.originalBytes) + " · Waiting"))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1)
        case .working(let fraction):
            HStack(spacing: Spacing.s) {
                ProgressView(value: fraction ?? 0.05)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Progress")
                if let extra {
                    Text(extra)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
        case .finished(.produced(_, let bytes)):
            Text(withExtra("\(sizeText(item.originalBytes)) → \(FileQueueText.bytes(bytes))"))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(2)
        case .finished(.unchanged(let reason)), .finished(.skipped(let reason)):
            Text(sizeText(item.originalBytes) + " · " + reason)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                // On a selected (accent-filled) row, orange is hard to read.
                .foregroundStyle(isSelected && activeState == .key ? AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor)) : AnyShapeStyle(.orange))
                .lineLimit(3)
                .help(message)
        case .cancelled:
            Text("Canceled").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: Spacing.s) {
            if sizeStyle == .savings, let fraction = item.savedFraction {
                Text(FileQueueText.percent(saved: fraction))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            switch item.state {
            case .waiting, .working:
                iconButton("Cancel", symbol: "xmark.circle.fill") { queue.cancel(item) }
            case .failed, .cancelled:
                if item.canRetry {
                    iconButton("Try Again", symbol: "arrow.clockwise.circle.fill") { queue.retry(item) }
                }
            case .finished:
                iconButton("Show in Finder", symbol: "magnifyingglass.circle.fill") {
                    FileQueueActions.reveal([item])
                }
            }
        }
    }

    private func iconButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var accessibilityActions: some View {
        if item.isActive {
            Button("Cancel") { queue.cancel(item) }
        } else {
            Button("Show in Finder") { FileQueueActions.reveal([item]) }
            if item.canRetry { Button("Try Again") { queue.retry(item) } }
        }
    }

    private func sizeText(_ bytes: Int64?) -> String {
        bytes.map(FileQueueText.bytes) ?? "—"
    }
}

/// Right-click menu for the selected rows.
struct FileQueueContextMenu: View {
    let queue: FileQueue
    let items: [FileQueueItem]
    @Environment(\.fileQueueRetryTitle) private var retryTitle
    @Environment(\.fileQueueRemove) private var removeHandler

    var body: some View {
        Button("Show in Finder") { FileQueueActions.reveal(items) }
        Button("Show Original in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(items.map(\.input))
        }
        Divider()
        if items.contains(where: \.isActive) {
            Button("Cancel") { items.forEach(queue.cancel) }
        }
        if items.contains(where: \.canRetry) {
            Button(retryTitle) { items.forEach(queue.retry) }
        }
        Button("Remove from List") {
            if let removeHandler { removeHandler.remove(items) } else { queue.remove(items) }
        }
    }
}

/// Small helpers views and apps share.
@MainActor
public enum FileQueueActions {
    public static func reveal(_ items: [FileQueueItem]) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.revealURL))
    }

    /// Opens a file chooser that also allows folders.
    public static func chooseFiles(types: [UTType], then onFiles: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.begin { response in
            if response == .OK, !panel.urls.isEmpty { onFiles(panel.urls) }
        }
    }
}

/// Wording shared by the row, the status line and VoiceOver.
public enum FileQueueText {
    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "−67%" (with a real minus sign). Rounds down so 99.6% never shows as "−100%".
    public static func percent(saved fraction: Double) -> String {
        let value = Int((fraction * 100).rounded(.down))
        return value <= 0 ? "0%" : "\u{2212}\(value)%"
    }

    @MainActor
    public static func accessibilityLabel(for item: FileQueueItem) -> String {
        accessibilityLabel(for: item, sizeStyle: .savings, detail: nil)
    }

    /// The row's VoiceOver label. `detail` is the app's extra facts (`fileQueueDetail`).
    @MainActor
    public static func accessibilityLabel(for item: FileQueueItem, sizeStyle: FileQueueSizeStyle, detail: String?) -> String {
        let label = baseAccessibilityLabel(for: item, sizeStyle: sizeStyle)
        guard let detail, !detail.isEmpty, !item.state.isFailedOrCancelled else { return label }
        return label + ", " + detail
    }

    @MainActor
    private static func baseAccessibilityLabel(for item: FileQueueItem, sizeStyle: FileQueueSizeStyle) -> String {
        let before = item.originalBytes.map(bytes) ?? ""
        switch item.state {
        case .waiting: return "\(item.name), \(before), waiting"
        case .working(let fraction):
            let percent = fraction.map { " \(Int($0 * 100)) percent" } ?? ""
            return "\(item.name), working\(percent)"
        case .finished(.produced(_, let after)):
            let saved = sizeStyle == .savings
                ? item.savedFraction.map { ", saved \(Int(($0 * 100).rounded(.down))) percent" } ?? "" : ""
            let savedAs = item.outputName.map { ", written as \($0)" } ?? ""
            return "\(item.name), \(before) to \(bytes(after))\(saved)\(savedAs)"
        case .finished(.unchanged(let reason)), .finished(.skipped(let reason)):
            return "\(item.name), \(reason)"
        case .failed(let message): return "\(item.name), failed: \(message)"
        case .cancelled: return "\(item.name), canceled"
        }
    }
}

/// A Quick Look thumbnail, generated lazily when the row appears and cached.
struct FileThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = await ThumbnailCache.shared.thumbnail(for: url, side: 36, scale: scale)
        }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 400
    }

    func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

// MARK: Row options

/// How a finished row shows its sizes.
public enum FileQueueSizeStyle: Sendable {
    /// "4.2 MB → 1.1 MB" plus a green "−74%" (compressors).
    case savings
    /// "4.2 MB → 18 MB" only, in neutral colours (converters, where outputs may grow).
    case neutral
}

/// Wraps the detail closure so rows don't redraw every time the parent view does
/// (closures can't be compared). The closure should capture the app's model object, not
/// copies of its values: rows update through Observation when what it reads changes.
struct FileQueueDetailProvider: Equatable, Sendable {
    let detail: @MainActor @Sendable (FileQueueItem) -> String?

    @MainActor func callAsFunction(_ item: FileQueueItem) -> String? { detail(item) }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension FileQueueItem.State {
    var isFailedOrCancelled: Bool {
        switch self {
        case .failed, .cancelled: true
        default: false
        }
    }
}

extension EnvironmentValues {
    @Entry var fileQueueSizeStyle: FileQueueSizeStyle = .savings
    @Entry var fileQueueDetail: FileQueueDetailProvider? = nil
    @Entry var fileQueueRetryTitle: String = "Process Again"
    @Entry var fileQueueFollowsNewFiles = false
    @Entry var fileQueueShowsOutputName = true
    @Entry var fileQueueRemove: FileQueueRemoveHandler? = nil
}

/// The app's own "remove rows" (e.g. to register Undo). Equatable like the detail provider.
struct FileQueueRemoveHandler: Equatable, Sendable {
    let remove: @MainActor @Sendable ([FileQueueItem]) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension View {
    /// How finished rows show their sizes. Default `.savings`.
    public func fileQueueSizeStyle(_ style: FileQueueSizeStyle) -> some View {
        environment(\.fileQueueSizeStyle, style)
    }

    /// Extra facts for each row (e.g. "→ MP4 · 1920×1080 · 2:14"), shown after the size
    /// while waiting, next to the progress bar while working, and after before → after when
    /// done. Return nil for nothing. Read observable state inside it and rows update.
    public func fileQueueDetail(_ detail: @escaping @MainActor @Sendable (FileQueueItem) -> String?) -> some View {
        environment(\.fileQueueDetail, FileQueueDetailProvider(detail: detail))
    }

    /// Scroll to rows as they're added (and re-run), tint them for a moment, and give the
    /// list keyboard focus, so arrows, Space and Delete work without clicking first.
    public func fileQueueFollowsNewFiles(_ follows: Bool = true) -> some View {
        environment(\.fileQueueFollowsNewFiles, follows)
    }

    /// The context menu's "run it again" item. Default "Process Again".
    /// Whether a row whose output has another name shows it ("Photo.webp → Photo-small.jpg").
    /// Default true.
    public func fileQueueShowsOutputName(_ shows: Bool) -> some View {
        environment(\.fileQueueShowsOutputName, shows)
    }

    /// Handles Remove from List (Delete key and the row menu) instead of `queue.remove`,
    /// e.g. to register Undo with `queue.restore(_:at:)`. Call `queue.remove` from it.
    public func fileQueueOnRemove(_ remove: @escaping @MainActor @Sendable ([FileQueueItem]) -> Void) -> some View {
        environment(\.fileQueueRemove, FileQueueRemoveHandler(remove: remove))
    }

    public func fileQueueRetryTitle(_ title: String) -> some View {
        environment(\.fileQueueRetryTitle, title)
    }
}
