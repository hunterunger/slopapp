import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// A region the user picked with the crosshair overlay, in every coordinate space the
/// capture flows need.
@MainActor
struct PickedRegion {
    let screen: NSScreen
    /// Screen-local AppKit points (origin bottom-left of the screen).
    let local: CGRect
    /// The pixels as frozen when picked (area picks only).
    let frozen: CGImage?
    /// The picked window, for window picks.
    let window: WindowInfo?

    var displayID: CGDirectDisplayID { screen.displayID }
    /// AppKit global points.
    var global: CGRect { local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) }
    /// Quartz global points (origin top-left of the primary screen).
    var quartz: CGRect { ScreenCoordinates.flip(global, primaryHeight: NSScreen.primaryHeight) }

    /// Shows the overlay and waits. Window picks become the window's frame (clipped to its
    /// screen); Return in area mode is the whole screen. Nil if cancelled or failed (errors
    /// are reported by `report`).
    static func pick(_ mode: RegionOverlay.Mode, capturer: ScreenCapturing, options: RegionOverlay.Options,
                     started: TimeInterval, report: (Error) -> Void) async -> PickedRegion? {
        let overlay = RegionOverlay(capturer: capturer, mode: mode, options: options)
        switch await overlay.run(started: started) {
        case .area(let displayID, let rect, let image):
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
            return PickedRegion(screen: screen, local: rect, frozen: image, window: nil)
        case .window(let window):
            let appKit = ScreenCoordinates.flip(window.frame, primaryHeight: NSScreen.primaryHeight)
            let center = CGPoint(x: appKit.midX, y: appKit.midY)
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) ?? NSScreen.main else { return nil }
            let local = appKit.intersection(screen.frame).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            guard !local.isNull, !local.isEmpty else { return nil }
            return PickedRegion(screen: screen, local: local, frozen: nil, window: window)
        case .cancelled:
            Diagnostics.record("capture cancelled")
            return nil
        case .failed(let error):
            report(error)
            return nil
        }
    }
}

/// A thin frame around a region on screen (recording, scrolling capture, self-timer), with
/// the rest of the screen optionally dimmed. Click-through, and it's our own window, so it
/// never shows up in captures or recordings.
@MainActor
final class RegionFrame {
    private var panels: [NSPanel] = []

    /// `rect` in AppKit global points.
    init(rect: CGRect, dimOutside: Bool, color: NSColor = .controlAccentColor) {
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            let local = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            panel.contentView = FrameView(hole: local, dim: dimOutside, color: color)
            panel.setAccessibilityElement(false)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    var windowNumbers: Set<CGWindowID> { Set(panels.map { CGWindowID($0.windowNumber) }) }

    func close() {
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels = []
    }

    private final class FrameView: NSView {
        let hole: CGRect
        let dim: Bool
        let color: NSColor

        init(hole: CGRect, dim: Bool, color: NSColor) {
            self.hole = hole
            self.dim = dim
            self.color = color
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func draw(_ dirtyRect: NSRect) {
            let outline = hole.insetBy(dx: -2, dy: -2)
            if dim {
                let path = NSBezierPath(rect: bounds)
                path.append(NSBezierPath(rect: outline))
                path.windingRule = .evenOdd
                NSColor(cgColor: OverlayPalette.scrim)?.setFill()
                path.fill()
            }
            guard bounds.intersects(outline) else { return }
            // Drawn just outside the region so it's never part of what's recorded. It sits on
            // any screen content: a solid overlay-ink line under the coloured dashes keeps it
            // visible over a page of the same colour, in light and dark alike.
            let border = NSBezierPath(rect: outline.insetBy(dx: 0.75, dy: 0.75))
            border.lineWidth = 1.5
            OverlayPalette.ink.withAlphaComponent(0.6).setStroke()
            border.stroke()
            color.setStroke()
            border.setLineDash([6, 4], count: 2, phase: 0)
            border.stroke()
        }
    }
}

/// The self-timer and recording countdown: a big number in the middle of the region.
@MainActor
enum Countdown {
    /// Counts down `seconds`; false if cancelled (Esc, or `cancel()`).
    static func run(_ seconds: Int, centeredIn rect: CGRect, label: String) async -> Bool {
        guard seconds > 0 else { return true }
        let state = CountdownState(remaining: seconds, label: label)
        let panel = FloatingPanel(cornerRadius: Radius.xxl) { CountdownView(state: state) }
        panel.dismissesOnResignKey = false
        panel.level = .statusBar
        panel.setAccessibilityLabel("Countdown")
        var cancelled = false
        panel.onDismiss = { cancelled = true }
        let size = CGSize(width: CountdownView.side, height: CountdownView.side)
        panel.setFrame(CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        current = panel
        defer {
            panel.onDismiss = nil
            panel.orderOut(nil)
            panel.close()
            if current === panel { current = nil }
        }
        while state.remaining > 0 {
            Diagnostics.record("countdown \(state.remaining)")
            try? await Task.sleep(for: .seconds(1))
            if cancelled { return false }
            // The digit rolls over (a fade under Reduce Motion).
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.25)) {
                state.remaining -= 1
            }
        }
        // Let the panel leave the screen before anything is captured.
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(80))
        return !cancelled
    }

    private static weak var current: FloatingPanel?

    static func cancel() { current?.dismiss() }
}

@MainActor
@Observable
final class CountdownState {
    var remaining: Int
    let label: String
    init(remaining: Int, label: String) {
        self.remaining = remaining
        self.label = label
    }
}

struct CountdownView: View {
    static let side: CGFloat = 152
    let state: CountdownState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The digit sits on the square's centre line; the labels hang below it, so the
        // number doesn't drift when the second line wraps or changes.
        Text("\(state.remaining)")
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
            .frame(width: Self.side, height: Self.side)
            // Optical centring, measured: the digit's line box has empty descender space, so
            // the digit + labels block sits 32 pt from the top and 30 pt from the bottom.
            .offset(y: -Spacing.xxl)
            .overlay(alignment: .bottom) {
                VStack(spacing: 2) {
                    Text(state.label)
                        .font(.callout.weight(.medium))
                    Text("Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, Spacing.xxl + Spacing.xs)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(state.label) in \(state.remaining)")
    }
}
