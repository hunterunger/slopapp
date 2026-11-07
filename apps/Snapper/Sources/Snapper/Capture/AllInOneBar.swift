import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// All-in-One: one shortcut brings up a bar of every capture kind near the bottom of the
/// screen; click one (or press its number) to start it. Esc closes the bar.
@MainActor
enum AllInOneBar {
    private static var panel: FloatingPanel?

    static var isShown: Bool { panel?.isVisible == true }

    static func toggle(model: AppModel) {
        if isShown { close() } else { show(model: model) }
    }

    static func show(model: AppModel) {
        close()
        let modes = CaptureMode.allInOneModes
        let panel = FloatingPanel(cornerRadius: AllInOneView.panelRadius) {
            AllInOneView(modes: modes) { choose($0, model: model) }
        }
        panel.level = .statusBar
        panel.title = "All-in-One"
        panel.setAccessibilityLabel("Capture modes")
        panel.keyHandler = { event in
            if let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...modes.count).contains(digit) {
                choose(modes[digit - 1], model: model)
                return true
            }
            return false
        }
        panel.onDismiss = { if Self.panel === panel { Self.panel = nil } }
        // Computed from the same constants the view uses (the hosting view's fitting size
        // isn't reliable before the first layout).
        let size = AllInOneView.size(for: modes)
        let screen = NSScreen.underPointer ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = CGRect(x: visible.midX - size.width / 2, y: visible.minY + Spacing.xxl * 2, width: size.width, height: size.height)
        if let scene = TestScene.recordingTarget {
            // Test mode: over the test scene, so screenshots of the (translucent) bar never
            // show anything else on screen through it.
            let appKit = ScreenCoordinates.flip(scene.frame, primaryHeight: NSScreen.primaryHeight)
            frame.origin = CGPoint(x: appKit.midX - size.width / 2, y: appKit.minY + Spacing.xxl * 2)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKey()
        self.panel = panel
        Diagnostics.record("all-in-one shown")
    }

    static func close() {
        guard let panel else { return }
        self.panel = nil
        panel.onDismiss = nil
        panel.orderOut(nil)
        panel.close()
    }

    private static func choose(_ mode: CaptureMode, model: AppModel) {
        close()
        Diagnostics.record("all-in-one chose mode=\(mode.rawValue)")
        // Let the bar leave the screen before it freezes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { model.capture(mode) }
    }
}

struct AllInOneView: View {
    let modes: [CaptureMode]
    let choose: (CaptureMode) -> Void

    /// Each mode is a fixed tile, so the bar never changes size; the tiles' hover shape is
    /// concentric with the panel's corners at the bar's even `inset`.
    static let tile = CGSize(width: 80, height: 60)
    static let inset = Spacing.s
    static let gap = Spacing.xs
    static let panelRadius = Radius.xl
    static let tileRadius = Radius.nested(in: panelRadius, padding: inset)

    /// Groups: screenshots, then text, then recording, with a hairline between groups.
    static func startsGroup(_ mode: CaptureMode) -> Bool { mode == .text || mode == .recording }

    static func size(for modes: [CaptureMode]) -> CGSize {
        let separators = CGFloat(modes.dropFirst().filter(startsGroup).count)
        let tiles = CGFloat(modes.count)
        // Between neighbours: one gap, or gap + hairline + gap where a group starts.
        let width = tiles * tile.width + (tiles - 1) * gap + separators * (gap + 1) + 2 * inset
        return CGSize(width: width, height: tile.height + 2 * inset)
    }

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                if index > 0, Self.startsGroup(mode) {
                    Hairline(axis: .vertical)
                        .frame(width: 1, height: Self.tile.height - 2 * Spacing.m)
                }
                Button { choose(mode) } label: {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: mode.systemImage)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .frame(height: 26)
                        Text(mode.shortTitle)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .frame(width: Self.tile.width, height: Self.tile.height)
                }
                .buttonStyle(TileButtonStyle(radius: Self.tileRadius))
                .help("\(mode.title) (\(index + 1))")
                .accessibilityLabel(mode.title)
            }
        }
        .padding(Self.inset)
        .fixedSize()
    }
}

/// A borderless tile that shows a soft rounded fill on hover and a deeper one while pressed
/// (the panel's glass stays visible around it).
struct TileButtonStyle: ButtonStyle {
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, radius: radius)
    }

    private struct TileBody: View {
        let configuration: Configuration
        let radius: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
    }
}
