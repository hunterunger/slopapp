import IconsmithCore
import SlopKit
import SwiftUI

/// Every template, drawn with your picture, down the right side of the window. Pick by
/// looking, not by name.
struct TemplateGallery: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The last template clicked here.
    @State private var picked: IconShape?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(IconShape.Group.allCases) { group in
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.top, group == .appIcons ? 0 : Spacing.m)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(IconShape.allCases.filter { $0.group == group }) { shape in
                            TemplateCell(model: model, shape: shape) { picked = shape }
                                .id(shape)
                        }
                    }
                }
                .padding(Spacing.m)
            }
            .galleryScrollEdge()
            // macOS 26 lets scroll content run up under the toolbar; the column starts below it.
            .clipped()
            // ⌘1–⌘9 and the Icon menu pick templates too: bring the chosen one into view. Not
            // for clicks in the gallery itself (the cell is already where the pointer is).
            .onChange(of: model.style.shape) { _, shape in
                guard picked != shape else { return }
                if reduceMotion {
                    proxy.scrollTo(shape, anchor: .center)
                } else {
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(shape, anchor: .center) }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Templates")
    }
}

private extension View {
    /// The gallery sits under the toolbar, not beneath it, so macOS 26's soft scroll edge
    /// (which tints the toolbar strip above the column) has nothing to separate.
    @ViewBuilder func galleryScrollEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

/// One template: its live thumbnail with a selection ring that follows the template's own
/// outline, and its name, highlighted like a selected icon in Finder.
struct TemplateCell: View {
    let model: AppModel
    let shape: IconShape
    var onPick: () -> Void = {}
    @State private var hovering = false
    /// Golden Gate greys selections in windows you aren't using.
    @Environment(\.controlActiveState) private var activeState

    /// Gap between the thumbnail's outline and the ring, and the ring's width.
    static let ringGap: CGFloat = 2.5
    static let ringWidth: CGFloat = 2.5
    /// Room around the thumbnail so the ring is never clipped.
    static var ringRoom: CGFloat { ringGap + ringWidth }

    private var selected: Bool { model.style.shape == shape }
    private var number: Int { (IconShape.allCases.firstIndex(of: shape) ?? 0) + 1 }

    var body: some View {
        Button {
            onPick()
            model.setShape(shape)
        } label: {
            VStack(spacing: Spacing.xs) {
                Group {
                    if let image = model.thumbnails[shape] {
                        Image(decorative: image, scale: model.backingScale).resizable().interpolation(.high)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: AppModel.thumbnailPoints, height: AppModel.thumbnailPoints)
                .shapeGuide(shape, model: model, outlineAlways: true)
                .padding(Self.ringRoom)
                .background {
                    if selected || hovering {
                        TemplateRing(shape: shape, inset: Self.ringRoom, gap: Self.ringGap, width: Self.ringWidth)
                            .fill(selected ? AnyShapeStyle(Color.selectionRing(activeState)) : AnyShapeStyle(Color.primary.opacity(0.15)))
                            .accessibilityHidden(true)
                    }
                }
                Text(shape.title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(selected && activeState.isActiveWindow ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
                    .padding(.horizontal, Spacing.xs + 2) // lint:allow optical: Finder's label pill inset
                    .padding(.vertical, 1)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Color.selectionFill(activeState))
                        }
                    }
            }
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(shape.title) (⌘\(number))")
        .accessibilityLabel(shape.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The ring from `TemplateRingGeometry`, for a thumbnail inset `inset` points in this
/// shape's rect.
struct TemplateRing: Shape {
    let shape: IconShape
    let inset: CGFloat
    let gap: CGFloat
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(TemplateRingGeometry.ring(for: shape, in: rect.insetBy(dx: inset, dy: inset), gap: gap, width: width))
    }
}
