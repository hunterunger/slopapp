import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

/// Create mode: drop a picture, then the big icon with its buttons. Dropping folders or
/// files on the icon gives them the icon (no timer: the picture stays loaded).
///
/// The empty drop zone and the loaded canvas share one square slot (same frame, same
/// corners), and the controls under it keep their space in both states, so loading a
/// picture never moves anything. (Export results show in the bottom bar.)
struct CreateView: View {
    @Bindable var model: AppModel
    @State private var side: CGFloat = BigPreview.maxSide

    var body: some View {
        VStack(spacing: Spacing.m) {
            Group {
                if model.hasSource {
                    BigPreview(model: model)
                } else {
                    DropZone("Drop pictures here", systemImage: "photo.on.rectangle.angled", types: MainView.sourceTypes,
                             allowsMultiple: true) { model.load($0) }
                        .dropZoneCornerRadius(BigPreview.radius)
                        .overlay {
                            if model.isLoading { ProgressView().controlSize(.large) }
                        }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            // The square itself (the frame below is wider when the height limits the square).
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = max($0, 1) }
            .frame(maxWidth: BigPreview.maxSide, maxHeight: BigPreview.maxSide)

            ZStack(alignment: .top) {
                // Always laid out, so the empty state reserves exactly the loaded layout.
                LoadedControls(model: model, width: side)
                    .opacity(model.hasSource ? 1 : 0)
                    .disabled(!model.hasSource)
                    .accessibilityHidden(!model.hasSource)
                if !model.hasSource {
                    VStack(spacing: Spacing.m) {
                        Text("Drop one picture, or several to make a batch. Apps and folders give their own icon.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: side)
                        Button("New Blank Icon") { model.newBlank() }
                            .controlSize(.large)
                            .help("Start from a folder or tile with no picture, then add a color or text (⌘N)")
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Everything under the icon once a picture is loaded.
private struct LoadedControls: View {
    @Bindable var model: AppModel
    let width: CGFloat

    var body: some View {
        VStack(spacing: Spacing.m) {
            SmallPreviews(model: model)
            HintLine(model: model)
            ActionBar(model: model, width: width)
        }
    }
}

struct BigPreview: View {
    @Bindable var model: AppModel
    @State private var side: CGFloat = 1
    @State private var dragStart: CGPoint?
    @State private var isTargeted = false
    @FocusState private var focused: Bool

    /// The canvas: as big as the window allows, up to this.
    static let maxSide: CGFloat = 440
    static let radius = Radius.xxl
    /// Room around the icon for the corner buttons.
    static let inset: CGFloat = 0.07

    private var canvasShape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }

    var body: some View {
        ZStack {
            canvasShape
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035))
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .shapeGuide(model.style.shape, model: model, lineWidth: 1.5, fillsGuide: false)
                    // Under the guide and the icon: the extent of the exported image.
                    .background { TransparencyGrid().accessibilityHidden(true) }
                    .padding(side * Self.inset)
            } else {
                ProgressView()
            }
            if model.isRemovingBackground {
                Label {
                    Text("Removing Background…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(.callout)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(.regularMaterial, in: Capsule())
                .hairlineBorder(Capsule())
                .transition(.opacity)
            } else if model.isLoading {
                ProgressView().controlSize(.large)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isRemovingBackground)
        .hairlineBorder(canvasShape)
        .overlay {
            if isTargeted {
                canvasShape.strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false)
            } else if focused && NSApp.isFullKeyboardAccessEnabled {
                // The system focus ring, following the canvas's corners (like SlopKit's DropZone).
                // Only with Keyboard navigation on: clicking the canvas focuses it for the arrow
                // keys, and like Preview's image view it doesn't wear a ring for that.
                canvasShape.inset(by: -Spacing.xs / 2)
                    .stroke(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = max($0, 1) }
        .contentShape(canvasShape)
        .gesture(drag)
        .onTapGesture(count: 2) { model.resetPosition() }
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            let step = press.modifiers.contains(.shift) ? 1.0 / 32 : 1.0 / 256
            switch press.key {
            case .upArrow: model.nudge(dx: 0, dy: step)
            case .downArrow: model.nudge(dx: 0, dy: -step)
            case .leftArrow: model.nudge(dx: -step, dy: 0)
            default: model.nudge(dx: step, dy: 0)
            }
            return .handled
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.dropOnCanvas(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .help("Drop files or folders here to give them this icon; drop pictures to use them instead (⌥-drop applies to pictures too). Drag to move the picture, double-click to re-center.")
        .accessibilityElement()
        .accessibilityLabel("Icon preview")
        .accessibilityValue(model.style.isCentered ? "Picture centered" : "Picture moved")
        .accessibilityHint("Drop files or folders to give them this icon. Drag or use the arrow keys to move the picture.")
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "Re-center") { model.resetPosition() }
        .overlay(alignment: .topLeading) {
            RoundButton(title: "Close Image", systemImage: "xmark") { model.closeImage() }
                .help("Close the picture (start over)")
                .padding(RoundButton.inset)
        }
        .overlay(alignment: .topTrailing) {
            RoundButton(title: "Adjust", systemImage: "slider.horizontal.3") { model.showsAdjust.toggle() }
                .help("Size, position, rotation and color (⌥⌘A)")
                .popover(isPresented: $model.showsAdjust, arrowEdge: .trailing) { AdjustPanel(model: model) }
                .padding(RoundButton.inset)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = model.style.offset
                    model.beginContinuousEdit("Move Picture")
                    NSCursor.closedHand.push()
                }
                guard let start = dragStart else { return }
                let canvas = side * (1 - 2 * Self.inset)
                var style = model.style
                style.offset = CGPoint(x: start.x + value.translation.width / canvas,
                                       y: start.y - value.translation.height / canvas)
                model.style = style.clamped()
            }
            .onEnded { _ in
                dragStart = nil
                NSCursor.pop()
                model.endContinuousEdit("Move Picture")
            }
    }
}

/// The usual light/dark checkerboard behind the icon's own square, so transparent parts
/// (the margin around a macOS tile, a cut-out subject, Background None) read as
/// transparent rather than as the canvas colour.
struct TransparencyGrid: View {
    static let cell: CGFloat = Spacing.s

    var body: some View {
        Canvas { context, size in
            // Whole cells only (about 8 pt each), so the pattern meets every edge the same way.
            let columns = max(Int((size.width / Self.cell).rounded()), 1), rows = max(Int((size.height / Self.cell).rounded()), 1)
            let cell = CGSize(width: size.width / CGFloat(columns), height: size.height / CGFloat(rows))
            var path = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height))
                }
            }
            context.fill(path, with: .color(.primary.opacity(0.05)))
        }
    }
}

/// A small round button over a corner of the icon, concentric with the canvas's corner.
struct RoundButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    static let inset = Spacing.s
    /// The circle's radius is the canvas radius minus the inset, so the two curves are parallel.
    static let diameter = 2 * Radius.nested(in: BigPreview.radius, padding: inset)

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: Self.diameter, height: Self.diameter)
        }
        .buttonStyle(RoundButtonStyle())
        .accessibilityLabel(title)
    }
}

/// Material circle with a hairline; a touch darker on hover, darker still while pressed.
struct RoundButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .hairlineBorder(Circle())
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// The sizes Finder and the Dock really use. Drag one to Finder to save the icon.
struct SmallPreviews: View {
    let model: AppModel
    @State private var hovered: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xxl) {
            ForEach(AppModel.smallSizes, id: \.self) { points in
                VStack(spacing: Spacing.xs) {
                    Group {
                        if let image = model.smallPreviews[points] {
                            Image(decorative: image, scale: model.backingScale)
                                .interpolation(.high)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: CGFloat(points), height: CGFloat(points))
                    Text("\(points) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                // Hovering shows that these can be picked up (they're the drag-out handles). The
                // highlight reaches past the item without taking layout space.
                .background {
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        .fill(Color.primary.opacity(hovered == points ? 0.06 : 0))
                        .padding(-Spacing.xs)
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).inset(by: -Spacing.xs))
                .onHover { inside in
                    hovered = inside ? points : (hovered == points ? nil : hovered)
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .onDrag { model.dragItem() }
                .help("Drag to Finder to save an .icns file (hold ⌥ for PNG)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview at \(points) points")
                .accessibilityHint("Drag to Finder to save the icon")
            }
        }
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

/// What to do next, in one or two short lines.
struct HintLine: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Text("Drop files or folders on the icon to give them this icon.")
                Button("Choose…") { model.chooseTargets(remove: false) }
                    .buttonStyle(.link)
                    .help("Choose files, folders, disks or apps to give this icon (⌘J)")
            }
            Text("Drag a small icon to Finder to save it as .icns.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Text, background removal and Export, under the icon, as wide as the icon.
struct ActionBar: View {
    @Bindable var model: AppModel
    let width: CGFloat

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button { model.showsText.toggle() } label: {
                ActionLabel("Text", systemImage: "textformat")
            }
            .help("Add text or emoji: a label, a word or a badge (⌘T)")
            .popover(isPresented: $model.showsText, arrowEdge: .bottom) { TextPanel(model: model) }
            if model.canRestoreBackground {
                Button { model.restoreBackground() } label: {
                    ActionLabel("Restore Background", systemImage: "photo")
                }
                .help("Put the picture’s background back")
            } else {
                Button { model.removeBackground() } label: {
                    ActionLabel("Remove Background", systemImage: "person.and.background.dotted")
                }
                .disabled(model.isRemovingBackground || model.source?.isBlank == true)
                .help("Keep only the subject (a person, pet or object). Works on this Mac; nothing is uploaded.")
            }
            Spacer(minLength: Spacing.s)
            // In the spacer's room, so Export doesn't move when it appears.
            if model.isExporting {
                ProgressView().controlSize(.small).accessibilityLabel("Exporting")
            }
            Button { model.showsExport.toggle() } label: {
                ActionLabel("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isExporting)
            .help("Choose a format and export (⌘E exports \(model.prefs.format.title) straight away)")
            .popover(isPresented: $model.showsExport, arrowEdge: .bottom) { ExportPanel(model: model) }
        }
        .controlSize(.large)
        .frame(width: width)
    }
}

/// A button label of one fixed height. Labels align their symbol to the text baseline, so
/// symbols of different shapes (Aa, the share arrow, the person) otherwise make buttons
/// 28 or 29 pt tall in the same row.
struct ActionLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
        // Never truncated: if the icon is narrower than the buttons, the row overhangs it evenly.
        .fixedSize()
        .frame(height: ActionLabel.height)
    }

    static let height: CGFloat = 17
}
