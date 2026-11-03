import AppKit
import SlopKit
import SwiftUI

/// Shown when a capture is asked for without Screen Recording permission: why it's needed,
/// a button to the exact Privacy pane (Return), and Restart once it's on (macOS applies it at
/// launch). Esc closes it.
///
/// Built here rather than with SlopKit's `PermissionGate` because the shared prompt has no
/// default button and the window needs Esc; worth moving into SlopKit.
@MainActor
enum PermissionWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView())
            let window = EscapableWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "Snapper Needs Screen Recording"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func close() {
        window?.close()
    }
}

/// A window that closes on Esc (⌘. too), like a sheet.
final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    /// SwiftUI content can swallow Esc before it becomes `cancelOperation`, so catch it here.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            performClose(nil)
            return
        }
        super.sendEvent(event)
    }
}

struct PermissionView: View {
    @State private var isGranted = Permission.screenRecording.isGranted
    @State private var didRequest = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            if isGranted {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Screen Recording is on")
                    .font(.title3.bold())
                Text("Use the Snapper menu or a capture shortcut to take a screenshot.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Done") { PermissionWindow.close() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Image(systemName: Permission.screenRecording.systemImage)
                    .font(.system(size: 40, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Allow Screen Recording")
                    .font(.title3.bold())
                Text("Snapper needs Screen Recording to take screenshots. It only looks at the screen when you capture, and nothing leaves your Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s) {
                    Button("Open System Settings") {
                        Permission.screenRecording.request()
                        didRequest = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    if didRequest {
                        Button("Restart Snapper") { AppRelauncher.relaunch() }
                    }
                }
                .padding(.top, Spacing.xs)
                Text(didRequest ? "After you turn it on, restart Snapper." : "Turn it on in System Settings, then restart Snapper.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 440, height: 330)
        .task {
            // Re-check while the window is open (cheap; stops when granted or closed).
            while !isGranted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                isGranted = Permission.screenRecording.isGranted
            }
        }
    }
}
