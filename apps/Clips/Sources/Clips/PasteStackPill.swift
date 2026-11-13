import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// The paste stack's floating list in the top-right corner of the screen: what's next, how
/// many are left, and a button to stop. It never takes the keyboard, so you keep typing in
/// the form you're filling. It follows the "hide from screen sharing" setting (it shows clips).
@MainActor
final class PasteStackPill {
    static let width: CGFloat = 280
    private let panel: FloatingPanel
    private let model: AppModel

    init(controller: PasteStackController, model: AppModel) {
        self.model = model
        panel = FloatingPanel(cornerRadius: Radius.xl) {
            PasteStackView(controller: controller, model: model)
        }
        panel.dismissesOnResignKey = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("Paste Stack")
        // Esc in FloatingPanel would close the window without stopping the stack.
        panel.keyHandler = { event in event.keyCode == 53 }
    }

    func show() {
        panel.sharingType = model.windowSharingType
        relayout()
        panel.orderFrontRegardless()
    }

    /// Sizes the window to its content and keeps it in the top-right corner.
    func relayout() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = CGSize(width: Self.width, height: max(64, content.fittingSize.height))
        let mouse = NSEvent.mouseLocation
        let screen = panel.isVisible ? (panel.screen ?? NSScreen.main)
            : NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(PanelPlacement.corner(.topTrailing).frame(size: size, mouse: mouse, visibleFrame: visible), display: true)
    }

    func close() {
        panel.orderOut(nil)
    }
}

private struct PasteStackView: View {
    let controller: PasteStackController
    let model: AppModel
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    /// How many upcoming clips the list shows.
    static let visibleRows = 5

    var body: some View {
        let stack = controller.stack ?? PasteStack()
        let clips = controller.clips()
        let upcoming = clips.filter { $0.index >= stack.position }
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "square.stack.3d.up")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Paste Stack").font(.headline)
                    Text(status(stack))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Spacing.s)
                Button {
                    controller.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop Paste Stack")
                .help("Stop the paste stack (⇧⌘C in Clips)")
            }
            if upcoming.isEmpty {
                Text("Copy things in the order you'll paste them. Each paste takes the next one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(upcoming.prefix(Self.visibleRows)), id: \.index) { entry in
                        row(entry.clip, index: entry.index, isNext: entry.index == stack.position)
                    }
                    if upcoming.count > Self.visibleRows {
                        Text("\(upcoming.count - Self.visibleRows) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, Spacing.s)
                    }
                }
                Text("Copy to add more. ⌘V pastes the next one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .frame(width: PasteStackPill.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func status(_ stack: PasteStack) -> String {
        if stack.items.isEmpty { return "Collecting copies" }
        if stack.remaining == 1 { return "Last one next" }
        return "\(stack.remaining) to paste"
    }

    private func row(_ clip: Clip, index: Int, isNext: Bool) -> some View {
        let rowRadius = Radius.nested(in: panelRadius, padding: Spacing.m, minimum: Radius.s)
        return Button {
            controller.move(to: index)
        } label: {
            HStack(spacing: Spacing.s) {
                Text(ClipText.title(of: clip, limit: 60))
                    .font(.callout.weight(isNext ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isNext {
                    Text("Next").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: 24)
            .background {
                if isNext { RoundedRectangle(cornerRadius: rowRadius, style: .continuous).fill(.quaternary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isNext ? "Next: \(ClipText.title(of: clip, limit: 60))" : ClipText.title(of: clip, limit: 60))
        .help(isNext ? "Pastes next" : "Paste this one next")
    }
}
