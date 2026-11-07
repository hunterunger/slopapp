import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// The panel's navigation: the palette list, or one list opened.
@MainActor
@Observable
final class PanelState {
    var list: ColorListID?
    /// A palette whose name is being edited in place.
    var renaming: UUID?
}

/// Colors side by side in a rounded bar (history and palette previews). Its radius comes
/// from the container it sits in (`Radius.nested`), so it stays concentric with a row's
/// hover or selection shape.
struct ColorStrip: View {
    let colors: [ColorValue]
    let vision: ColorVision
    var height: CGFloat = 34
    var maxCount = 24
    var cornerRadius: CGFloat = Radius.m

    var body: some View {
        let shown = Array(colors.prefix(maxCount))
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        HStack(spacing: 0) {
            if shown.isEmpty {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        shape.strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(vision.simulate(color).swiftUIColor)
                }
            }
        }
        .frame(height: height)
        .clipShape(shape)
        .modifier(SwatchEdge(shape: shape, enabled: !shown.isEmpty))
    }
}

/// The hairline edge every swatch gets, so white swatches show on white and black on black.
struct SwatchEdge<S: Shape>: ViewModifier {
    let shape: S
    var enabled = true

    func body(content: Content) -> some View {
        if enabled {
            content.hairlineBorder(shape, color: Color.primary.opacity(0.18))
        } else {
            content
        }
    }
}

/// A round swatch with a hairline ring, shown as the person's vision setting sees it.
struct RoundSwatch: View {
    let color: ColorValue
    var vision: ColorVision = .normal
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(vision.simulate(color).swiftUIColor)
            .modifier(SwatchEdge(shape: Circle()))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One saved color: swatch, name, value in the copy format. Click copies.
struct ColorRow: View {
    let controller: AppController
    let item: PickedColor
    let list: ColorListID
    var compact = false
    /// In the panel a click copies; in the Library a click selects.
    var copiesOnClick = false
    /// Off in the Library list, which has its own selection-aware context menu.
    var contextMenuEnabled = true
    /// The hover shape's radius: concentric with whatever the row sits in.
    var highlightRadius: CGFloat = Radius.m
    @State private var hovering = false

    private var model: DropperModel { controller.model }

    var body: some View {
        let value = model.text(for: item.color, name: item.name)
        HStack(spacing: Spacing.m) {
            RoundSwatch(color: item.color, vision: controller.settings.colorVision, size: compact ? 28 : 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .lineLimit(1)
                Text(value)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Menu {
                ColorActions(controller: controller, item: item, list: list)
            } label: {
                Label("Actions for \(item.displayName)", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .accessibilityHidden(!hovering)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, compact ? 2 : Spacing.xs)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: highlightRadius, style: .continuous)
                .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .onHover { hovering = $0 }
        .modifier(TapAction(enabled: copiesOnClick) { controller.copy(item) })
        .modifier(OptionalContextMenu(enabled: contextMenuEnabled) { ColorActions(controller: controller, item: item, list: list) })
        .draggable(value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.displayName), \(value)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Copies the value")
        .accessibilityAction { controller.copy(item) }
    }
}

/// Everything you can do with one saved color (context menus and the ••• button).
struct ColorActions: View {
    let controller: AppController
    let item: PickedColor
    let list: ColorListID

    private var model: DropperModel { controller.model }

    var body: some View {
        Button("Copy \(model.preferences.format.title)") { controller.copy(item) }
        Menu("Copy As") {
            ForEach(ColorFormat.groups) { group in
                Section(group.title) {
                    ForEach(model.preferences.visible(in: group)) { format in
                        Button("\(format.title): \(model.text(for: item.color, as: format, name: item.name))") {
                            controller.copy(item, as: format)
                        }
                    }
                }
            }
        }
        Divider()
        Button("Edit in Library…") { controller.showLibrary(list: list, color: item.id) }
        Menu("Check Contrast") {
            Button("As Text Color") { controller.checkContrast(item.color, as: .text) }
            Button("As Background Color") { controller.checkContrast(item.color, as: .background) }
        }
        Menu("Add to Palette") {
            ForEach(model.palettes.filter { list != .palette($0.id) }) { palette in
                Button(palette.name) { model.add([item], to: palette.id) }
                    .disabled(palette.isLocked || palette.contains(item.color))
            }
            if !model.palettes.isEmpty { Divider() }
            Button("New Palette with This Color") { controller.newPalette(colors: [item]) }
        }
        Divider()
        Button(list == .history ? "Remove from History" : "Remove from Palette", role: .destructive) {
            model.remove([item.id], from: list)
        }
        .disabled(model.isLocked(list))
    }
}

/// Everything you can do with a palette (or the history).
struct ListActions: View {
    let controller: AppController
    let list: ColorListID
    /// Starts renaming where the menu was opened (panel row or Library sidebar).
    var rename: () -> Void

    private var model: DropperModel { controller.model }

    var body: some View {
        switch list {
        case .history:
            Button("Save as New Palette") { controller.newPalette(colors: model.history.items) }
                .disabled(model.history.items.isEmpty)
            Menu("Export") {
                ForEach(PaletteFileFormat.allCases) { format in
                    Button(format.title) { PaletteFiles.export(controller.historyAsPalette, as: format, controller: controller) }
                }
            }
            .disabled(model.history.items.isEmpty)
            Divider()
            Button("Clear History…", role: .destructive) { controller.clearHistory() }
                .disabled(model.history.items.isEmpty)
        case .palette(let id):
            if let palette = model.palette(id) {
                Button(model.activePaletteID == id ? "Stop Adding Picks Here" : "Add New Picks Here") {
                    model.activePaletteID = model.activePaletteID == id ? nil : id
                }
                Button("Rename") { rename() }
                    .disabled(palette.isLocked)
                Menu("Sort By") {
                    ForEach(Palette.SortOrder.allCases) { order in
                        Button(order.title) { model.sortPalette(id, by: order) }
                    }
                }
                .disabled(palette.isLocked || palette.colors.count < 2)
                Button(palette.isLocked ? "Unlock" : "Lock") { model.setLocked(!palette.isLocked, palette: id) }
                Button(palette.inDock ? "Remove from Color Dock" : "Add to Color Dock") {
                    model.setInDock(!palette.inDock, palette: id)
                    if !palette.inDock, !controller.settings.showDock { controller.settings.showDock = true }
                }
                Divider()
                Menu("Export") {
                    ForEach(PaletteFileFormat.allCases) { format in
                        Button(format.title) { controller.exportPalette(id, as: format) }
                    }
                }
                .disabled(palette.colors.isEmpty)
                Button("Duplicate") { model.duplicatePalette(id) }
                Menu("Merge Into") {
                    ForEach(model.palettes.filter { $0.id != id }) { other in
                        Button(other.name) { model.merge([id], into: other.id) }
                            .disabled(other.isLocked)
                    }
                }
                .disabled(model.palettes.count < 2 || palette.isLocked)
                Divider()
                Button("Delete Palette…", role: .destructive) { controller.deletePalette(id) }
                    .disabled(palette.isLocked)
            }
        }
    }
}

/// A gradient track with a round knob (hue, saturation, brightness, contrast sliders).
/// Accessible as an adjustable value.
struct GradientSlider: View {
    let label: String
    @Binding var value: Double
    let colors: [Color]
    var knob: Color
    var onEditingChanged: (Bool) -> Void = { _ in }
    var valueDescription: (Double) -> String = { "\(Int(($0 * 100).rounded())) percent" }

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let knobSize: CGFloat = 16
            let travel = max(geo.size.width - knobSize, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .modifier(SwatchEdge(shape: Capsule()))
                    .frame(height: 10)
                Circle()
                    .fill(knob)
                    // On colour, not chrome: overlay colours, the same in light and dark.
                    .overlay { Circle().strokeBorder(Color(nsColor: OverlayPalette.paper), lineWidth: 2.5) }
                    .shadow(color: Color(nsColor: OverlayPalette.ink).opacity(0.45), radius: 1.5, y: 0.5)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: CGFloat(value.clamped01) * travel)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                if !dragging { dragging = true; onEditingChanged(true) }
                value = Double(((g.location.x - knobSize / 2) / travel).clamped01)
            }.onEnded { _ in
                dragging = false
                onEditingChanged(false)
            })
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.02, 1)
            case .decrement: value = max(value - 0.02, 0)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }
}

extension CGFloat {
    var clamped01: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}

/// Rainbow stops for hue tracks.
let hueStops: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) }

/// A tap action only where it's wanted (so List selection keeps working elsewhere).
struct TapAction: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onTapGesture(perform: action)
        } else {
            content
        }
    }
}

/// A context menu only where wanted (the Library list has its own).
struct OptionalContextMenu<MenuContent: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let menu: () -> MenuContent

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { menu() }
        } else {
            content
        }
    }
}
