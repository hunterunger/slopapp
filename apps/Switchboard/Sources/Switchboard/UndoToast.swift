import AppKit
import SlopKit
import SwiftUI

/// A small confirmation with an Undo button, bottom center of the screen, for a few seconds.
/// Unlike `HUD` it takes clicks, but it never becomes the key window, so typing keeps going
/// to the app you're in (usually the browser the link just opened in).
@MainActor
enum UndoToast {
    private static var panel: FloatingPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, duration: Duration = .seconds(6), undo: @escaping @MainActor () -> Void) {
        panel?.orderOut(nil)
        let content = ToastView(message: message) {
            undo()
            hide()
        }
        // A capsule like SlopKit's HUD: measure first, since the radius is half the height.
        let size = NSHostingView(rootView: content).fittingSize
        let panel = FloatingPanel(cornerRadius: (size.height / 2).rounded(.down)) { content }
        panel.level = .statusBar
        panel.dismissesOnResignKey = false
        // Only become key if a control needs typing; buttons don't, so focus stays put.
        panel.becomesKeyOnlyIfNeeded = true
        panel.setAccessibilityLabel("Rule added")
        self.panel = panel

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(CGRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.minY + visible.height * 0.12).rounded(),
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    static func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        // Fade like the HUD (a fade is fine under Reduce Motion: nothing moves).
        hideTask = Task { @MainActor in
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
        }
    }
}

private struct ToastView: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Label(message, systemImage: "checkmark.circle")
                .symbolRenderingMode(.hierarchical)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
            Button("Undo", action: undo)
                .buttonBorderShape(.capsule)
        }
        // HUD-like: more room on the leading side so the text clears the round end; the
        // button sits as far from the trailing end as from the top and bottom, so its
        // capsule follows the panel's.
        .padding(.leading, Spacing.xl)
        .padding(.trailing, Spacing.m)
        .padding(.vertical, Spacing.m)
    }
}
