import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// One capture card, laid out like the quick-access thumbnails people know: the capture
/// fills the card; on hover it dims and shows Copy and Save in the middle, Close and Pin in
/// the top corners, Annotate and Share in the bottom ones. Drag it out, double-click to
/// annotate. The controls are always in the accessibility tree.
struct CardView: View {
    let item: CaptureItem
    let thumbnailSize: CGSize
    let model: AppModel
    let controller: CardController
    @State private var hoveringNow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hovering: Bool {
        hoveringNow || Diagnostics.forceCardHover || item.sourceName == ShowcaseScenes.hoveredCardName
    }

    var body: some View {
        ZStack {
            ThumbnailDragView(item: item, model: model, controller: controller)
            Rectangle()
                .fill(Color(nsColor: OverlayPalette.ink).opacity(hovering ? 0.4 : 0))
                .allowsHitTesting(false)
            if let media = item.media, !hovering {
                MediaBadge(media: media)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(CardController.controlInset)
                    .allowsHitTesting(false)
            }
            controls
                // Not 0: SwiftUI drops fully transparent views from accessibility, and the
                // actions must stay reachable for VoiceOver and keyboard users without hovering.
                .opacity(hovering ? 1 : 0.001)
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: CardController.cornerRadius, style: .continuous))
        // A one-pixel edge so a white or black capture still reads as a card on any backdrop.
        .hairlineBorder(RoundedRectangle(cornerRadius: CardController.cornerRadius, style: .continuous))
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hoveringNow = inside }
            controller.setHovering(item, inside)
        }
        .contextMenu { menu }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                CornerButton("Close", systemImage: "xmark") { controller.close(item) }
                Spacer()
                if !item.isMedia {
                    CornerButton("Pin to Screen", systemImage: "pin.fill") { model.pin(item) }
                }
            }
            Spacer(minLength: 0)
            // Stacked on a normal card; side by side on a short, wide one so they never
            // run into the corner buttons.
            ViewThatFits(in: .vertical) {
                VStack(spacing: Spacing.s) { pills }
                HStack(spacing: Spacing.s) { pills }
            }
            Spacer(minLength: 0)
            HStack {
                if item.isMedia {
                    CornerButton("Open", systemImage: "play.fill") { model.openMedia(item) }
                } else {
                    CornerButton("Annotate", systemImage: "pencil") { model.annotate(item) }
                }
                Spacer()
                CornerButton("Share", systemImage: "square.and.arrow.up") { controller.share(item) }
            }
        }
        .padding(CardController.controlInset)
    }

    @ViewBuilder private var pills: some View {
        PillButton("Copy") { model.copy(item) }
        PillButton("Save") {
            // Only an Option-*click* asks where; the plain button always saves to the
            // folder from Settings. (The click's own event, not the global key state, so a
            // stuck or scripted modifier can't change what Save does.)
            if NSApp.currentEvent?.type == .leftMouseUp, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                model.saveAs(item)
            } else {
                model.save(item)
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if item.isMedia {
            Button("Open") { model.openMedia(item) }
            if item.media?.isGIF == false {
                Button("Export as GIF") { model.exportGIF(item) }
            }
        } else {
            Button("Annotate") { model.annotate(item) }
            Button("Pin to Screen") { model.pin(item) }
        }
        Divider()
        Button("Copy") { model.copy(item) }
        if !item.isMedia {
            Button("Copy Text") { model.copyText(item) }
        }
        Button("Save") { model.save(item) }
        Button("Save As…") { model.saveAs(item) }
        Button("Share…") { controller.share(item) }
        if item.savedURL != nil {
            Button("Show in Finder") { model.showInFinder(item) }
        }
        Divider()
        Button("Close") { controller.close(item) }
        Button("Close All") { controller.closeAll() }
    }
}

/// "▶ 0:07" or "GIF" on a recording's thumbnail.
struct MediaBadge: View {
    let media: MediaFile

    var body: some View {
        Label(media.isGIF ? "GIF" : Elapsed.string(media.duration), systemImage: media.isGIF ? "photo.stack" : "play.fill")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, Spacing.s)
            .frame(height: CardController.controlSide)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel(media.isGIF ? "Animated GIF" : "Video, \(Elapsed.string(media.duration))")
    }
}

/// A small round icon button for the card's corners.
struct CornerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(width: CardController.controlSide, height: CardController.controlSide)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A capsule text button for the card's main actions.
struct PillButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, Spacing.m)
                .frame(minWidth: 64, minHeight: 28)
                .background(.regularMaterial, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title == "Save" ? "Save (Option-click: Save As…)" : title)
        .accessibilityLabel(title)
    }
}

/// The thumbnail as an AppKit view so it can start a real file drag and know how it ended.
struct ThumbnailDragView: NSViewRepresentable {
    let item: CaptureItem
    let model: AppModel
    let controller: CardController

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.configure(item: item, model: model, controller: controller)
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.configure(item: item, model: model, controller: controller)
    }
}

@MainActor
final class DragSourceView: NSView, NSDraggingSource {
    private weak var item: CaptureItem?
    private weak var model: AppModel?
    private weak var controller: CardController?
    private var mouseDownPoint: CGPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(item: CaptureItem, model: AppModel, controller: CardController) {
        self.item = item
        self.model = model
        self.controller = controller
        needsLayout = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(item.isMedia ? "Recording" : "Capture, \(item.pixelSizeDescription) pixels")
        setAccessibilityHelp("Drag it into another app, or double-click to annotate.")
    }

    /// Fills the card: a capture taller than the card shows its top (where a page or a
    /// scrolling capture starts), a wider one its middle.
    override func layout() {
        super.layout()
        guard let image = item?.image, bounds.width > 0, bounds.height > 0 else { return }
        let rows = CGFloat(image.width) * bounds.height / bounds.width
        if rows < CGFloat(image.height), let top = image.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: rows.rounded())) {
            layer?.contents = top
        } else {
            layer?.contents = image
        }
    }

    /// VoiceOver's "press" opens the editor, like a double-click.
    override func accessibilityPerformPress() -> Bool {
        guard let item, let model else { return false }
        model.annotate(item)
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        if event.clickCount == 2, let item, let model {
            if item.isMedia { model.openMedia(item) } else { model.annotate(item) }
            mouseDownPoint = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let item, let model else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        guard let url = item.temporaryFile(format: model.format) else { return }
        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        dragItem.setDraggingFrame(bounds, contents: item.nsImage)
        Diagnostics.record("drag started")
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation != [], let item, let model, let controller else { return }
        Diagnostics.record("dragged out operation=\(operation.rawValue)")
        // Option keeps the card, like Finder's copy-drag convention.
        if model.closeAfterDragging, !NSEvent.modifierFlags.contains(.option) {
            controller.close(item)
        }
    }
}
