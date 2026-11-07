import AppKit
import SlopKit
import SwiftUI

/// The geometry the floating control bars share (recording, scrolling capture): a capsule
/// panel `height` tall whose controls are `controlHeight` capsules or circles, `inset` from
/// every edge, so every inner curve is concentric with the panel's ends.
enum ControlBar {
    static let controlHeight: CGFloat = 28
    static let inset = Spacing.s
    static let height = controlHeight + 2 * inset
    /// A capsule: half the height (44 / 2 = `Radius.xxl`).
    static let panelRadius = height / 2

    /// Places a bar centred under `area` (AppKit global points), or above it / at the bottom
    /// of the screen when there's no room, always inside `visible`.
    static func frame(size: CGSize, under area: CGRect, visible: CGRect) -> CGRect {
        let gap = Spacing.m
        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - gap)
        if origin.y < visible.minY + Spacing.s { origin.y = min(area.maxY + gap, visible.maxY - size.height - Spacing.s) }
        if origin.y < visible.minY + Spacing.s || area.height > visible.height - 2 * size.height { origin.y = visible.minY + Spacing.xxl }
        origin.x = min(max(origin.x, visible.minX + Spacing.s), visible.maxX - size.width - Spacing.s)
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }
}

/// A round icon button for the control bars: a `ControlBar.controlHeight` circle that fills
/// softly on hover and press.
struct BarIconButton: View {
    let title: String
    let systemImage: String
    var tint: Color?
    let action: () -> Void

    init(_ title: String, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .frame(width: ControlBar.controlHeight, height: ControlBar.controlHeight)
        }
        .buttonStyle(TileButtonStyle(radius: ControlBar.controlHeight / 2))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A capsule text button for the control bars, prominent (accent) or plain.
struct BarTextButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, Spacing.m)
            .frame(height: ControlBar.controlHeight)
        }
        .buttonStyle(CapsuleButtonStyle(prominent: prominent))
        .accessibilityLabel(title)
    }
}

/// Accent-filled (prominent) or quietly filled capsule, with pressed and hover states.
struct CapsuleButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, prominent: prominent)
    }

    private struct CapsuleBody: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        /// A prominent button is accent-filled only while its panel is key; in a background
        /// panel it reads as an ordinary quiet button (Golden Gate greys accents there).
        @Environment(\.appearsActive) private var appearsActive

        private var filled: Bool { prominent && appearsActive }

        var body: some View {
            configuration.label
                .foregroundStyle(filled ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
                .background {
                    if filled {
                        Capsule().fill(Color.accentColor)
                            .brightness(configuration.isPressed ? -0.1 : hovering ? 0.04 : 0)
                    } else {
                        Capsule().fill(.primary.opacity(configuration.isPressed ? 0.18 : hovering ? 0.12 : 0.07))
                    }
                }
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
    }
}

/// Reserves the width of the widest of `variants` so a changing label never resizes its bar.
struct FixedWidthText: View {
    let text: String
    let variants: [String]
    var alignment: Alignment = .leading

    var body: some View {
        ZStack(alignment: alignment) {
            ForEach(variants, id: \.self) { Text($0).hidden() }
            Text(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(text)
    }
}
