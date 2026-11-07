import AppKit
import ImageIO
import PDFKit
import SlopKit
import SquishCore
import SwiftUI

/// The middle of the window: the drop zone while the list is empty, then the selected
/// file before and after, with what it saved underneath.
struct PreviewPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.queue.items.isEmpty {
                DropZone("Drop images or PDFs here", systemImage: "arrow.down.right.and.arrow.up.left",
                         types: SquishTypes.accepted + [.folder]) { model.add($0) }
                    .padding(Spacing.windowMargin)
            } else if let item = model.focusedItem {
                ItemPreview(model: model, item: item)
                    .id(item.id)
            } else {
                SelectionSummary(model: model)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { SquishTypes.kind(of: $0) != nil || $0.hasDirectoryPath }
            guard !accepted.isEmpty else { return false }
            model.add(accepted)
            return true
        }
    }
}

/// What the preview shows, decoded off the main thread.
struct PreviewImages: @unchecked Sendable {
    var before: CGImage?
    var after: CGImage?
    var pixelSize: CGSize
    var pageCount: Int
    var beforeFacts: FileFacts?
    var afterFacts: FileFacts?
}

enum PreviewLoader {
    /// Previews are capped at this many pixels on the long side (memory); bigger photos are
    /// shown slightly scaled at "actual size".
    static let maxPixels = 4096
    /// PDF pages are rendered this big on the long side.
    static let pdfPixels: CGFloat = 2400

    static func load(before: URL, after: URL?, page: Int) -> PreviewImages {
        let isPDF = SquishTypes.kind(of: before) == .pdf
        let beforeFacts = FileFacts.read(before)
        let afterFacts = after.flatMap(FileFacts.read)
        if isPDF {
            let beforeDoc = PDFDocument(url: before)
            let pages = beforeDoc?.pageCount ?? 0
            let index = min(max(0, page), max(0, pages - 1))
            let b = beforeDoc.flatMap { render($0, page: index) }
            let a = after.flatMap { PDFDocument(url: $0) }.flatMap { render($0, page: index) }
            let size = b.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
            return PreviewImages(before: b, after: a, pixelSize: size, pageCount: pages,
                                 beforeFacts: beforeFacts, afterFacts: afterFacts)
        }
        let b = thumbnail(before)
        let a = after.flatMap(thumbnail)
        let size = b.map { CGSize(width: $0.width, height: $0.height) }
            ?? a.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        return PreviewImages(before: b, after: a, pixelSize: size, pageCount: 1,
                             beforeFacts: beforeFacts, afterFacts: afterFacts)
    }

    static func thumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    static func render(_ document: PDFDocument, page index: Int) -> CGImage? {
        guard let page = document.page(at: index)?.pageRef else { return nil }
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = pdfPixels / max(size.width, size.height)
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        // The page's own transform at 1:1 (it handles rotation and the box origin), scaled up.
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                 rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}

struct ItemPreview: View {
    @Bindable var model: AppModel
    let item: FileQueueItem
    @State private var images: PreviewImages?
    @State private var page = 0
    @State private var split = 0.5

    /// The original, also when Replace Originals moved it to the Trash.
    private var beforeURL: URL {
        if let replaced = model.replacement(for: item), FileManager.default.fileExists(atPath: replaced.trashed.path) {
            return replaced.trashed
        }
        return item.input
    }

    private var afterURL: URL? {
        guard case .finished(.produced(let url, _)) = item.state else { return nil }
        return url
    }

    private var loadKey: String {
        "\(item.runs)|\(afterURL?.path ?? "-")|\(page)"
    }

    private var showsSplit: Bool { model.comparing && images?.after != nil }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let images, images.before != nil || images.after != nil {
                    CompareImageView(before: images.before ?? images.after, after: images.after,
                                     pixelSize: images.pixelSize, split: showsSplit ? split : nil,
                                     controller: model.preview, identity: "\(item.id)|\(page)")
                    if showsSplit {
                        SplitHandle(split: $split, imageRect: model.preview.imageRect)
                    }
                    badges(images)
                } else if images != nil {
                    Label("No preview", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
                if item.isActive {
                    ProgressView()
                        .controlSize(.large)
                        .padding(Spacing.l)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                        .accessibilityLabel("Compressing")
                }
            }
            .overlay(alignment: .bottom) {
                // Nothing to zoom without a picture ("No preview"), so no zoom bar either.
                if let images, images.before != nil || images.after != nil {
                    PreviewControls(model: model, page: $page, pageCount: images.pageCount,
                                    hasResult: images.after != nil)
                        .padding(.bottom, PreviewMetrics.chromeInset)
                }
            }
            .clipped()
            Hairline()
            ResultFooter(model: model, item: item, images: images)
        }
        .task(id: loadKey) {
            let before = beforeURL, after = afterURL, page = page
            let loaded = await Task.detached(priority: .userInitiated) {
                PreviewLoader.load(before: before, after: after, page: page)
            }.value
            guard !Task.isCancelled else { return }
            images = loaded
        }
        .onReceive(NotificationCenter.default.publisher(for: .squishPreviewPage)) { note in
            guard let delta = note.object as? Int, let count = images?.pageCount else { return }
            page = min(max(0, page + delta), count - 1)
        }
    }

    @ViewBuilder private func badges(_ images: PreviewImages) -> some View {
        let before = item.originalBytes.map(FileQueueText.bytes)
        let after = item.outputBytes.map(FileQueueText.bytes)
        VStack {
            HStack {
                if showsSplit || images.after == nil, let before {
                    Badge(text: images.after == nil ? "Original · \(before)" : "Before · \(before)")
                }
                Spacer()
                if images.after != nil, let after {
                    Badge(text: "After · \(after)")
                }
            }
            Spacer()
        }
        .padding(PreviewMetrics.chromeInset)
        .allowsHitTesting(false)
    }
}

/// The bands the badges (top) and the zoom bar (bottom) float in. A fitted image sits
/// between them, so neither ever covers its edges; zoomed in, it scrolls under them.
enum PreviewMetrics {
    /// The badges' and the zoom bar's distance from the preview's edges.
    static let chromeInset = Spacing.m
    static let badgeHeight: CGFloat = 24
    static let controlsHeight: CGFloat = 32
    /// Between a fitted image and the badges or the zoom bar.
    static let gap = Spacing.s
    static var topBand: CGFloat { chromeInset + badgeHeight + gap }
    static var bottomBand: CGFloat { chromeInset + controlsHeight + gap }
    /// Left and right of a fitted image: the badges' inset, so a wide image lines up with them.
    static let sideMargin = chromeInset
}

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, Spacing.s)
            .frame(height: PreviewMetrics.badgeHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
}

/// The line between before and after, dragged sideways. It spans the visible part of the
/// image (not the whole pane), and `split` is measured across that same part.
struct SplitHandle: View {
    @Binding var split: Double
    /// The visible image, in this view's coordinates (from `PreviewController`).
    let imageRect: CGRect

    var body: some View {
        GeometryReader { _ in
            if imageRect.width > 1, imageRect.height > 1 {
                // Chrome over arbitrary pictures: SlopKit's overlay palette (light line, dark
                // shadow), the same in both appearances and never pure white or black.
                ZStack {
                    Rectangle()
                        .fill(Color(cgColor: OverlayPalette.ring))
                        .frame(width: 2, height: imageRect.height)
                        .shadow(color: Color(cgColor: OverlayPalette.ringShadow).opacity(0.6), radius: 1.5)
                    Capsule()
                        .fill(Color(cgColor: OverlayPalette.ring))
                        .frame(width: 10, height: min(44, imageRect.height))
                        .hairlineBorder(Capsule(), color: Color(cgColor: OverlayPalette.ringShadow).opacity(0.35))
                        .shadow(color: Color(cgColor: OverlayPalette.ringShadow).opacity(0.5), radius: 2)
                }
                .frame(width: 24, height: imageRect.height)
                .contentShape(Rectangle())
                .position(x: imageRect.minX + split * imageRect.width, y: imageRect.midY)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("compare"))
                    .onChanged { value in
                        split = min(1, max(0, (value.location.x - imageRect.minX) / imageRect.width))
                    })
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .accessibilityElement()
                .accessibilityLabel("Before and after divider")
                .accessibilityValue("\(Int((split * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: split = min(1, split + 0.1)
                    case .decrement: split = max(0, split - 0.1)
                    @unknown default: break
                    }
                }
            }
        }
        .coordinateSpace(name: "compare")
    }
}

/// Zoom, compare and page buttons floating over the preview.
struct PreviewControls: View {
    @Bindable var model: AppModel
    @Binding var page: Int
    let pageCount: Int
    let hasResult: Bool
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        HStack(spacing: Spacing.s) {
            button("Zoom Out", "minus.magnifyingglass") { model.preview.zoomOut() }
            button(model.preview.isFitted ? "Actual Size" : "Zoom to Fit",
                   model.preview.isFitted ? "1.magnifyingglass" : "arrow.down.right.and.arrow.up.left") {
                model.preview.isFitted ? model.preview.actualSize() : model.preview.zoomToFit()
            }
            button("Zoom In", "plus.magnifyingglass") { model.preview.zoomIn() }
            Hairline(axis: .vertical).frame(height: 16)
            Toggle(isOn: $model.comparing) {
                // On: the accent, grey in a background window (Golden Gate), like the
                // toolbar's own toggles.
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(model.comparing && hasResult ? Color.windowAccent(activeState) : Color.primary)
                    .frame(width: 18, height: 18)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .disabled(!hasResult)
            .help("Compare before and after (⌘K)")
            .accessibilityLabel("Compare Before and After")
            if pageCount > 1 {
                Hairline(axis: .vertical).frame(height: 16)
                button("Previous Page", "chevron.left") { page = max(0, page - 1) }
                    .disabled(page == 0)
                Text("\(page + 1) of \(pageCount)")
                    .monospacedDigit()
                    .font(.callout)
                    .accessibilityLabel("Page \(page + 1) of \(pageCount)")
                button("Next Page", "chevron.right") { page = min(pageCount - 1, page + 1) }
                    .disabled(page >= pageCount - 1)
            }
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: PreviewMetrics.controlsHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Under the preview: "3.1 MB → 880 KB", "Size reduced by 72%", and the file facts.
/// Always the same height and the same leading edge, whatever the row's state, so the
/// preview above it never moves when the selection changes.
struct ResultFooter: View {
    @Bindable var model: AppModel
    let item: FileQueueItem
    let images: PreviewImages?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            FileProxy(item: item)
            ZStack(alignment: .leading) {
                // The tallest layout (a two-line message), invisible: it holds the height.
                lines(name: " ", sizes: " ", detail: " \n ", caption: " ", savedAs: nil)
                    .hidden()
                    .accessibilityHidden(true)
                lines(name: item.name, sizes: sizes, detail: detail, caption: factsLine, savedAs: item.outputName)
                    .accessibilityElement(children: .combine)
            }
            Spacer(minLength: Spacing.s)
            HStack(spacing: Spacing.s) {
                if item.canRetry, stoppedShort {
                    Button("Try Again") { model.queue.retry(item) }
                }
                if let output = item.output {
                    ShareLink(item: output) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Share")
                    .accessibilityLabel("Share")
                }
                Button {
                    FileQueueActions.reveal([item])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder (⇧⌘R)")
                .accessibilityLabel("Show in Finder")
            }
            .font(.title3)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    private func lines(name: String, sizes: String, detail: String, caption: String?, savedAs: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(sizes)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .foregroundStyle(detailIsWarning ? AnyShapeStyle(.textOrange) : AnyShapeStyle(.secondary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // "JPEG · 3840 × 2160 · Saved as photo-small.jpg": the facts never truncate;
            // a long output name gives way in the middle.
            HStack(spacing: 0) {
                if let caption { Text(caption).layoutPriority(1) }
                if let savedAs {
                    Text((caption == nil ? "" : " · ") + "Saved as \(savedAs)")
                        .truncationMode(.middle)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    private var sizes: String {
        let before = item.originalBytes.map(FileQueueText.bytes) ?? "—"
        if let after = item.outputBytes { return "\(before) → \(FileQueueText.bytes(after))" }
        return before
    }

    private var detail: String {
        switch item.state {
        case .waiting: return "Waiting"
        case .working: return "Compressing…"
        case .finished(.produced):
            guard let fraction = item.savedFraction else { return "" }
            return "Size reduced by \(Int((fraction * 100).rounded(.down)))%"
        case .finished(.unchanged(let reason)), .finished(.skipped(let reason)): return reason
        case .failed(let message): return message
        case .cancelled: return "Canceled"
        }
    }

    /// Failed or canceled: the cases a Try Again button can help.
    private var stoppedShort: Bool {
        switch item.state {
        case .failed, .cancelled: true
        default: false
        }
    }

    private var detailIsWarning: Bool {
        if case .failed = item.state { return true }
        return false
    }

    /// "JPEG · 3840 × 2160 → JPEG · 1920 × 1080" or "PDF · 12 pages · 9 images".
    private var factsLine: String? {
        guard let before = images?.beforeFacts else { return nil }
        guard let after = images?.afterFacts, after.summary != before.summary else { return before.summary }
        if before.pageCount != nil { return before.summary }
        return "\(before.summary) → \(after.summary)"
    }
}

/// The file's icon, always in the same slot. With a result (a compressed copy, or the
/// original Squish kept) it can be dragged into Mail, a browser upload, Finder…; otherwise
/// it's dimmed.
struct FileProxy: View {
    let item: FileQueueItem
    static let side: CGFloat = 40

    /// The file to hand over when dragged, if there's one to use.
    private var result: URL? {
        switch item.state {
        case .finished(.produced(let url, _)): url
        case .finished(.unchanged): item.input
        default: nil
        }
    }

    var body: some View {
        let icon = Image(nsImage: NSWorkspace.shared.icon(forFile: (result ?? item.input).path))
            .resizable()
            .frame(width: Self.side, height: Self.side)
        if let result {
            icon
                .onDrag { NSItemProvider(contentsOf: result) ?? NSItemProvider() }
                .help(item.output == nil ? "Drag the file anywhere" : "Drag the compressed file anywhere")
                .accessibilityLabel(item.output == nil ? "File" : "Compressed file")
                .accessibilityHint("Drag to use it elsewhere")
        } else {
            icon
                .opacity(0.5)
                .accessibilityHidden(true)
        }
    }
}

/// Several rows selected: their total.
struct SelectionSummary: View {
    @Bindable var model: AppModel

    var body: some View {
        let items = model.selectedItems
        let before = items.compactMap(\.originalBytes).reduce(0, +)
        let after = items.reduce(Int64(0)) { $0 + ($1.outputBytes ?? $1.originalBytes ?? 0) }
        VStack(spacing: Spacing.s) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("\(items.count) files selected")
                .font(.title3.weight(.semibold))
            Text("\(FileQueueText.bytes(before)) → \(FileQueueText.bytes(after))")
                .font(.title3)
                .monospacedDigit()
            if before > after {
                Text("Size reduced by \(Int((Double(before - after) / Double(before) * 100).rounded(.down)))%")
                    .foregroundStyle(.secondary)
            }
            Button("Show in Finder") { model.revealTargets() }
                .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

extension Notification.Name {
    /// Next (+1) / previous (−1) page in the preview, from the View menu.
    static let squishPreviewPage = Notification.Name("squishPreviewPage")
}
