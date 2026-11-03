import AppKit
import IconsmithCore
import SlopKit
import SwiftUI

/// The icon large (drag to move the picture, double-click to re-center, arrows to nudge),
/// and at the small sizes Finder and the Dock really use.
struct PreviewPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: Spacing.l) {
            BigPreview(model: model)
                .frame(maxWidth: 460, maxHeight: 460)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)
            SmallPreviews(model: model)
            if let warning = model.smallSourceWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xl)
            }
            Spacer(minLength: Spacing.m)
        }
    }
}

struct BigPreview: View {
    @Bindable var model: AppModel
    @State private var side: CGFloat = 1
    @State private var dragStart: CGPoint?
    @State private var isTargeted = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : (focused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08)),
                              lineWidth: isTargeted ? 2 : 1)
            if let preview = model.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
                    .shapeGuide(model.style.shape, model: model, lineWidth: 1.5)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { side = max($0, 1) }
        .contentShape(Rectangle())
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
            let accepted = DropFilter.accepted(urls, types: MainView.sourceTypes)
            guard !accepted.isEmpty else { return false }
            model.load(accepted)
            return true
        } isTargeted: { isTargeted = $0 }
        .help("Drag to move the picture. Double-click to re-center. Drop another picture to use it instead.")
        .accessibilityElement()
        .accessibilityLabel("Icon preview")
        .accessibilityValue(model.style.isCentered ? "Picture centered" : "Picture moved")
        .accessibilityHint("Drag or use the arrow keys to move the picture")
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: "Re-center") { model.resetPosition() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = model.style.offset
                    model.beginContinuousEdit()
                    NSCursor.closedHand.push()
                }
                guard let start = dragStart else { return }
                var style = model.style
                style.offset = CGPoint(x: start.x + value.translation.width / side,
                                       y: start.y - value.translation.height / side)
                model.style = style.clamped()
            }
            .onEnded { _ in
                dragStart = nil
                NSCursor.pop()
                model.endContinuousEdit("Move Picture")
            }
    }
}

struct SmallPreviews: View {
    let model: AppModel

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview at \(points) points")
            }
        }
    }
}
