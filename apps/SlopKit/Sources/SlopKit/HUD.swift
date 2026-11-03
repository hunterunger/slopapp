import AppKit
import SwiftUI

/// A small system-style confirmation ("Copied") near the bottom of the screen that fades
/// away on its own. Never steals focus or clicks.
///
///     HUD.show("Copied", systemImage: "doc.on.doc")
@MainActor
public enum HUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    public static func show(_ message: String, systemImage: String = "checkmark.circle", duration: Duration = .seconds(1.2)) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: HUDView(message: message, systemImage: systemImage))
        panel.contentView = FloatingPanel.materialView(wrapping: hosting, cornerRadius: 14)
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.12,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = !FloatingPanel.usesGlass
        panel.isReleasedWhenClosed = false
        return panel
    }
}

struct HUDView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.headline)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
    }
}
