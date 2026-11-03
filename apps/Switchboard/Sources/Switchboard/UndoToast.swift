import AppKit
import SlopKit
import SwiftUI

/// A small confirmation with an Undo button, bottom center of the screen, for a few seconds.
/// Unlike `HUD` it takes clicks, but it never becomes the key window, so typing keeps going
/// to the app you're in (usually the browser the link just opened in).
@MainActor
enum UndoToast {
    private static var panel: ToastPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, duration: Duration = .seconds(6), undo: @escaping @MainActor () -> Void) {
        let panel = self.panel ?? ToastPanel()
        self.panel = panel
        let content = ToastView(message: message) {
            undo()
            hide()
        }
        let hosting = NSHostingView(rootView: content)
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.12,
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
        panel?.orderOut(nil)
    }
}

private final class ToastPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Only become key if a control needs typing; buttons don't, so focus stays put.
        becomesKeyOnlyIfNeeded = true
        setAccessibilityLabel("Rule added")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ToastView: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
            Button("Undo", action: undo)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}
