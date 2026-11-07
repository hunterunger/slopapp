import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// "Copied" confirmation with the color's swatch. Same placement and timing as SlopKit's
/// `HUD`, which only takes a symbol. Candidate for SlopKit: a HUD with custom SwiftUI content.
@MainActor
enum ColorHUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(color: ColorValue, text: String, note: String?, hint: String?) {
        let view = ColorHUDView(color: color, text: text, note: note, hint: hint)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: view)
        panel.contentView = materialView(wrapping: hosting)
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.12,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let spoken = ["Copied \(text)", note].compactMap { $0 }.joined(separator: ". ")
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: spoken, .priority: NSAccessibilityPriorityLevel.medium.rawValue])

        hideTask?.cancel()
        let duration: Duration = hint == nil ? .seconds(1.4) : .seconds(4)
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
        panel.hasShadow = !usesGlass
        panel.isReleasedWhenClosed = false
        return panel
    }

    private static var usesGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    private static func materialView(wrapping content: NSView) -> NSView {
        Material.view(wrapping: content, cornerRadius: ColorHUDView.cornerRadius)
    }
}

struct ColorHUDView: View {
    static let cornerRadius = Radius.xl
    /// Even on every side, so the swatch in the top-leading corner is concentric with it.
    static let padding = Spacing.m

    let color: ColorValue
    let text: String
    let note: String?
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                SwatchView(color: color, size: 28, cornerRadius: Radius.nested(in: Self.cornerRadius, padding: Self.padding))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                }
            }
            if let note {
                Label(note, systemImage: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280, alignment: .leading)
            }
        }
        .padding(Self.padding)
    }
}
