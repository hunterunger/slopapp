import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// One capture card: the thumbnail (drag it out, double-click to annotate) with its actions.
/// The action bar fades in on hover; it's always there for VoiceOver and the keyboard.
struct CardView: View {
    let item: CaptureItem
    let thumbnailSize: CGSize
    let model: AppModel
    let controller: CardController
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ThumbnailDragView(item: item, model: model, controller: controller)
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack {
                HStack {
                    CardButton("Close", systemImage: "xmark") { controller.close(item) }
                    Spacer()
                    CardButton("Pin to Screen", systemImage: "pin") { model.pin(item) }
                }
                Spacer()
                HStack(spacing: Spacing.s) {
                    CardButton("Copy", systemImage: "doc.on.doc") { model.copy(item) }
                    CardButton("Save", systemImage: "square.and.arrow.down") {
                        // Only an Option-*click* asks where; the plain button always saves to
                        // the folder from Settings. (The click's own event, not the global key
                        // state, so a stuck or scripted modifier can't change what Save does.)
                        if NSApp.currentEvent?.type == .leftMouseUp, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                            model.saveAs(item)
                        } else {
                            model.save(item)
                        }
                    }
                    CardButton("Annotate", systemImage: "pencil") { model.annotate(item) }
                }
            }
            .padding(Spacing.s)
            // Not 0: SwiftUI drops fully transparent views from accessibility, and the
            // actions must stay reachable for VoiceOver and keyboard users without hovering.
            .opacity(hovering ? 1 : 0.001)
        }
        .padding(6)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovering = inside }
            controller.setHovering(item, inside)
        }
        .contextMenu {
            Button("Copy") { model.copy(item) }
            Button("Save") { model.save(item) }
            Button("Save As…") { model.saveAs(item) }
            Divider()
            Button("Annotate") { model.annotate(item) }
            Button("Pin to Screen") { model.pin(item) }
            if item.savedURL != nil {
                Button("Show in Finder") { model.showInFinder(item) }
            }
            Divider()
            Button("Close") { controller.close(item) }
        }
    }
}

/// A round icon button on a material backing, readable over any screenshot.
struct CardButton: View {
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
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
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
        layer?.contents = item.image
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Capture, \(item.pixelSizeDescription) pixels")
        setAccessibilityHelp("Drag it into another app, or double-click to annotate.")
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
            model.annotate(item)
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
