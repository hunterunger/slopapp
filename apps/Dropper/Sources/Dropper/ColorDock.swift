import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// The Color Dock: a slim strip on a screen edge with a bar per palette marked "Show in
/// Color Dock". Hover or click a bar to see its colors (click one to copy it, drag it into
/// another app); drag the grip to move the dock, it snaps to the nearest edge. Floats over
/// other windows on every Space and never takes focus.
@MainActor
final class ColorDockController {
    private unowned let controller: AppController
    private var panel: NSPanel?
    private var flyout: NSPanel?
    private var hosting: NSHostingView<DockStripView>?
    private(set) var flyoutPalette: UUID?
    private var hoveringBar = false
    private var hoveringFlyout = false
    private var hideTask: Task<Void, Never>?
    private var dragOffset: CGPoint?

    /// Bars are 12 pt wide with `DockLayout.padding` on each side, and the dock's ends are
    /// round: half the thickness, so they're concentric with the bars' capsule ends.
    static let thickness: CGFloat = DockLayout.barWidth + 2 * DockLayout.padding
    static var cornerRadius: CGFloat { thickness / 2 }

    init(controller: AppController) {
        self.controller = controller
    }

    func start() {
        update()
    }

    /// Shows, hides or resizes the dock to match the settings and palettes.
    private func update() {
        let state = withObservationTracking {
            (controller.settings.showDock, controller.model.dockPalettes.map { ($0.id, $0.colors.count) }.count,
             controller.model.dockPalettes.map(\.colors.count), controller.settings.dockPlacement)
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        let palettes = controller.model.dockPalettes
        guard state.0, !palettes.isEmpty else {
            panel?.orderOut(nil)
            hideFlyout()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame(for: palettes), display: true)
        panel.orderFrontRegardless()
        if let id = flyoutPalette, !palettes.contains(where: { $0.id == id }) { hideFlyout() }
    }

    func toggle() {
        controller.settings.showDock.toggle()
        if controller.settings.showDock, controller.model.dockPalettes.isEmpty {
            HUD.show("Add a palette to the Color Dock from its ••• menu", systemImage: "sidebar.left")
        }
    }

    private var screen: NSScreen? { panel?.screen ?? NSScreen.main ?? NSScreen.screens.first }

    private func frame(for palettes: [Palette]) -> CGRect {
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return controller.settings.dockPlacement.frame(length: DockLayout.length(palettes), thickness: Self.thickness, in: visible)
    }

    private func makePanel() -> NSPanel {
        let panel = DockPanel(contentRect: CGRect(x: 0, y: 0, width: Self.thickness, height: 100),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.title = "Color Dock"
        panel.setAccessibilityLabel("Color Dock")
        let hosting = NSHostingView(rootView: DockStripView(controller: controller, dock: self))
        self.hosting = hosting
        panel.contentView = Material.view(wrapping: hosting, cornerRadius: Self.cornerRadius)
        return panel
    }

    // MARK: Moving

    func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragOffset == nil {
            dragOffset = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
            hideFlyout()
        }
        guard let offset = dragOffset else { return }
        panel.setFrameOrigin(CGPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
    }

    func dragEnded() {
        dragOffset = nil
        guard let panel else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let target = NSScreen.screens.first { $0.frame.contains(center) } ?? screen
        let visible = target?.visibleFrame ?? panel.frame
        controller.settings.dockPlacement = DockPlacement.snapped(center: center, in: visible)
        let frame = controller.settings.dockPlacement.frame(length: DockLayout.length(controller.model.dockPalettes),
                                                            thickness: Self.thickness, in: visible)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: Flyout

    func hoverBar(_ id: UUID, inside: Bool) {
        hoveringBar = inside
        if inside { showFlyout(for: id) } else { scheduleHide() }
    }

    func hoverFlyout(_ inside: Bool) {
        hoveringFlyout = inside
        if !inside { scheduleHide() }
    }

    func showFlyout(for id: UUID) {
        guard let panel, dragOffset == nil, let palette = controller.model.palette(id),
              let index = controller.model.dockPalettes.firstIndex(where: { $0.id == id }) else { return }
        hideTask?.cancel()
        flyoutPalette = id
        let flyout = self.flyout ?? makeFlyout()
        self.flyout = flyout
        let view = NSHostingView(rootView: DockFlyoutView(controller: controller, dock: self, palette: palette))
        flyout.contentView = Material.view(wrapping: view, cornerRadius: DockFlyoutView.cornerRadius)
        let size = view.fittingSize
        let bar = DockLayout.barRect(index: index, palettes: controller.model.dockPalettes, in: panel.frame,
                                     vertical: controller.settings.dockPlacement.edge.isVertical)
        let gap = Spacing.s
        var origin: CGPoint
        switch controller.settings.dockPlacement.edge {
        case .left: origin = CGPoint(x: panel.frame.maxX + gap, y: bar.midY - size.height / 2)
        case .right: origin = CGPoint(x: panel.frame.minX - gap - size.width, y: bar.midY - size.height / 2)
        case .bottom: origin = CGPoint(x: bar.midX - size.width / 2, y: panel.frame.maxY + gap)
        case .top: origin = CGPoint(x: bar.midX - size.width / 2, y: panel.frame.minY - gap - size.height)
        }
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        flyout.setFrame(CGRect(origin: origin, size: size), display: true)
        flyout.orderFrontRegardless()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !hoveringBar, !hoveringFlyout else { return }
            hideFlyout()
        }
    }

    func hideFlyout() {
        flyout?.orderOut(nil)
        flyoutPalette = nil
    }

    private func makeFlyout() -> NSPanel {
        let flyout = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        flyout.level = .floating
        flyout.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        flyout.isReleasedWhenClosed = false
        flyout.hidesOnDeactivate = false
        flyout.backgroundColor = .clear
        flyout.isOpaque = false
        flyout.hasShadow = true
        flyout.title = "Color Dock palette"
        return flyout
    }
}

/// Non-activating, can be key for its menus, never becomes main.
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Bar sizes, shared by the strip view and the flyout placement.
enum DockLayout {
    static let padding = Spacing.s
    static let barWidth: CGFloat = 12
    static let grip: CGFloat = 16
    static let gap = Spacing.s

    static func barLength(_ palette: Palette) -> CGFloat {
        palette.colors.isEmpty ? 18 : 12 + CGFloat(min(palette.colors.count, 10)) * 6
    }

    static func length(_ palettes: [Palette]) -> CGFloat {
        padding * 2 + grip + palettes.reduce(0) { $0 + gap + barLength($1) }
    }

    /// A bar's rect in screen coordinates, from the dock's frame. Vertical docks list from
    /// the top.
    static func barRect(index: Int, palettes: [Palette], in frame: CGRect, vertical: Bool) -> CGRect {
        var offset = padding + grip
        for i in 0..<index { offset += gap + barLength(palettes[i]) }
        offset += gap
        let length = barLength(palettes[index])
        if vertical {
            return CGRect(x: frame.minX, y: frame.maxY - offset - length, width: frame.width, height: length)
        }
        return CGRect(x: frame.minX + offset, y: frame.minY, width: length, height: frame.height)
    }
}

struct DockStripView: View {
    let controller: AppController
    let dock: ColorDockController

    var body: some View {
        let vertical = controller.settings.dockPlacement.edge.isVertical
        let layout = vertical ? AnyLayout(VStackLayout(spacing: DockLayout.gap)) : AnyLayout(HStackLayout(spacing: DockLayout.gap))
        layout {
            Image(systemName: "line.3.horizontal")
                .rotationEffect(vertical ? .zero : .degrees(90))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                // A fixed slot as wide as a bar: the glyph's own width (13 pt) made the dock
                // a point wider than its frame.
                .frame(width: vertical ? DockLayout.barWidth : DockLayout.grip, height: vertical ? DockLayout.grip : DockLayout.barWidth)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { _ in dock.dragChanged() }
                    .onEnded { _ in dock.dragEnded() })
                .help("Drag to move the Color Dock")
                .accessibilityLabel("Move Color Dock")
            ForEach(controller.model.dockPalettes) { palette in
                DockBar(palette: palette, vertical: vertical, vision: controller.settings.colorVision)
                    .frame(width: vertical ? DockLayout.barWidth : DockLayout.barLength(palette),
                           height: vertical ? DockLayout.barLength(palette) : DockLayout.barWidth)
                    .onHover { dock.hoverBar(palette.id, inside: $0) }
                    .onTapGesture { dock.showFlyout(for: palette.id) }
                    .accessibilityElement()
                    .accessibilityLabel("\(palette.name), \(palette.colors.count) colors")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { dock.showFlyout(for: palette.id) }
            }
        }
        .padding(DockLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .top : .leading)
    }
}

private struct DockBar: View {
    let palette: Palette
    let vertical: Bool
    let vision: ColorVision

    var body: some View {
        let colors = Array(palette.colors.prefix(10))
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            if colors.isEmpty {
                Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                ForEach(colors) { item in
                    Rectangle().fill(vision.simulate(item.color).swiftUIColor)
                }
            }
        }
        .clipShape(Capsule())
        .modifier(SwatchEdge(shape: Capsule(), enabled: !colors.isEmpty))
    }
}

/// One palette's colors next to the dock. Click copies; drag drops the value elsewhere.
struct DockFlyoutView: View {
    static let cornerRadius = Radius.xl
    static let padding = Spacing.m
    static let swatch: CGFloat = 28
    /// Concentric with the flyout's corners (the first swatch sits in the corner).
    static let swatchRadius = Radius.nested(in: cornerRadius, padding: padding)

    let controller: AppController
    let dock: ColorDockController
    let palette: Palette
    @State private var hovered: PickedColor?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                if palette.isLocked {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Locked")
                }
                Text(hovered.map { "\(palette.name) / \($0.displayName)" } ?? palette.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: Spacing.l)
                Menu {
                    Button("Edit in Library…") { dock.hideFlyout(); controller.showLibrary(list: .palette(palette.id)) }
                    Button("Remove from Color Dock") { dock.hideFlyout(); controller.model.setInDock(false, palette: palette.id) }
                    Button(palette.isLocked ? "Unlock" : "Lock") { controller.model.setLocked(!palette.isLocked, palette: palette.id) }
                    Divider()
                    Button("Delete Palette…", role: .destructive) { dock.hideFlyout(); controller.deletePalette(palette.id) }
                        .disabled(palette.isLocked)
                } label: {
                    Label("Actions for \(palette.name)", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if palette.colors.isEmpty {
                Text("Empty palette").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.swatch), spacing: Spacing.xs), count: min(palette.colors.count, 10)),
                          spacing: Spacing.xs) {
                    ForEach(palette.colors) { item in
                        let value = controller.model.text(for: item.color, name: item.name)
                        let shape = RoundedRectangle(cornerRadius: Self.swatchRadius, style: .continuous)
                        shape
                            .fill(controller.settings.colorVision.simulate(item.color).swiftUIColor)
                            .modifier(SwatchEdge(shape: shape))
                            .frame(width: Self.swatch, height: Self.swatch)
                            .onHover { hovered = $0 ? item : (hovered?.id == item.id ? nil : hovered) }
                            .onTapGesture { controller.copy(item) }
                            .draggable(value)
                            .help(value)
                            .accessibilityElement()
                            .accessibilityLabel("\(item.displayName), \(value)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Copies the value")
                            .accessibilityAction { controller.copy(item) }
                    }
                }
            }
        }
        .padding(Self.padding)
        .frame(minWidth: 160)
        .onHover { dock.hoverFlyout($0) }
    }
}
