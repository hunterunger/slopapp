import AppKit
import SlopKit
import SwiftUI

/// Shown when measuring is asked for without Screen Recording: one sentence on why, a
/// button to the exact Privacy pane (Return), and Restart once it's on (macOS applies it at
/// launch). Esc closes it.
///
/// Same shape as Snapper's PermissionWindow (SlopKit's `PermissionPrompt` has no default
/// button and its window doesn't close on Esc); both are worth moving into SlopKit.
@MainActor
enum PermissionWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView())
            let window = EscapableWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "Ruler Needs Screen Recording"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func close() {
        window?.close()
    }
}

/// A window that closes on Esc, like a sheet.
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
                Text("Press the Measure shortcut or choose Measure from the Ruler menu.")
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
                Text("Ruler reads the pixels on screen to find edges, so it needs Screen Recording. It only looks while you measure, and nothing is saved or leaves your Mac.")
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
                        Button("Restart Ruler") { AppRelauncher.relaunch() }
                    }
                }
                .padding(.top, Spacing.xs)
                Text(didRequest ? "After you turn it on, restart Ruler." : "Turn it on in System Settings, then restart Ruler.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 440, height: 330)
        .task {
            while !isGranted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                isGranted = Permission.screenRecording.isGranted
            }
            AppModel.shared.refreshPermission()
        }
    }
}
