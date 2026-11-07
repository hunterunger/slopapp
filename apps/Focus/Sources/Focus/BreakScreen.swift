import AppKit
import FocusCore
import SlopKit
import SwiftUI

/// The optional break screen: during a break, every display is covered with a calm full-screen
/// view showing the time left. Esc, "Back to Work" or "Hide" dismiss it straight away; it
/// never blocks. Off by default (Settings ▸ Timer).
@MainActor
final class BreakScreen {
    private let controller: FocusController
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?

    init(controller: FocusController) {
        self.controller = controller
    }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.observe() } }
        }
    }

    private func update() {
        let wanted = controller.showsBreakScreen
        if wanted, windows.isEmpty {
            show()
        } else if !wanted, !windows.isEmpty {
            hide()
        }
    }

    private func show() {
        TestHooks.log("break screen shown")
        let windowed = TestHooks.breakScreenWindowed
        let screens = windowed ? Array(NSScreen.main.map { [$0] } ?? []) : NSScreen.screens
        for screen in screens {
            let primary = screen == NSScreen.main || NSScreen.screens.count == 1
            let view = BreakScreenView(controller: AppModel.controller, reflection: AppModel.reflection, primary: primary)
            // Test hook: one opaque, normal-level window, so a screenshot holds nothing else.
            let frame = windowed ? Self.testFrame(on: screen) : screen.frame
            let window = KeyableWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.setFrame(frame, display: false)
            window.level = windowed ? .normal : .statusBar
            window.title = "Break"
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            let effect = NSVisualEffectView()
            effect.material = windowed ? .windowBackground : .fullScreenUI
            effect.blendingMode = windowed ? .withinWindow : .behindWindow
            effect.state = .active
            let hosting = NSHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: effect.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            window.contentView = effect
            window.alphaValue = 0
            window.orderFrontRegardless()
            if primary { window.makeKey() }
            windows.append(window)
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.35
            for window in windows { window.animator().alphaValue = 1 }
        }
        AppActivation.activate()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc hides it, wherever the focus is.
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.controller.dismissBreakScreen() }
            return nil
        }
    }

    private func hide() {
        TestHooks.log("break screen hidden")
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    private static func testFrame(on screen: NSScreen) -> NSRect {
        let size = NSSize(width: 1100, height: 760)
        let visible = screen.visibleFrame
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Borderless windows can't take the keyboard unless they say so.
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }
}

/// What the break screen shows: the time left, a nudge to rest, and ways out. The main
/// display also offers the reflection for the session that just ended.
struct BreakScreenView: View {
    let controller: FocusController
    let reflection: ReflectionDraft
    var primary = true
    var snapshotNow: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: min(1, max(0.05, controller.unit / 60)))) { context in
            content(now: snapshotNow ?? context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if primary {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(controller.runningPhase == .longBreak ? "Time for a long break" : "Time for a break")
                    .font(.largeTitle.weight(.semibold))
                if let run = controller.state.run {
                    Text(TimeText.menuBar(run.remaining(at: now), showSeconds: true, unit: controller.unit))
                        .font(.system(size: 88, weight: .thin).monospacedDigit())
                        .contentTransition(.numericText())
                        .accessibilityLabel("Time left")
                        .accessibilityValue(TimeText.left(run.remaining(at: now), unit: controller.unit))
                }
                Text("Stand up, stretch, drink some water, look at something far away.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if let record = controller.pendingReflection {
                    ReflectionCard(controller: controller, record: record, draft: reflection, compact: true)
                        .padding(Spacing.l)
                        .frame(width: 380)
                        // A system material, not a see-through fill: stays readable at the
                        // clearest glass setting.
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }
                HStack(spacing: Spacing.m) {
                    Button("Hide") { controller.dismissBreakScreen() }
                        .controlSize(.large)
                    // One prominent button per screen: Save, while a reflection waits.
                    if controller.pendingReflection == nil {
                        Button("Back to Work") { controller.skipBreak() }
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Back to Work") { controller.skipBreak() }
                            .controlSize(.large)
                    }
                }
                Text("Press Esc to hide this screen. The break keeps running in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.xxl)
        } else {
            Button("Hide") { controller.dismissBreakScreen() }
                .controlSize(.large)
        }
    }
}
