import AppKit
import SlopKit
import SwiftUI

/// What a recording extra needs and doesn't have yet.
enum RecordingPermission: Equatable {
    case media(MediaKind)
    /// Keystroke display: watching keys pressed in other apps.
    case accessibility

    var title: String {
        switch self {
        case .media(let kind): "Allow \(kind.title)"
        case .accessibility: "Allow Accessibility"
        }
    }

    var reason: String {
        switch self {
        case .media(.microphone):
            "To record your voice, turn on Snapper under Privacy & Security → Microphone. Snapper listens only while a recording is set up or running. Without it, recordings have no voice."
        case .media(.camera):
            "To show your camera in a bubble in the recording, turn on Snapper under Privacy & Security → Camera. The camera is on only while a recording is set up or running."
        case .accessibility:
            "To show the keys you press, turn on Snapper under Privacy & Security → Accessibility. Keys are shown while you record and never kept."
        }
    }

    var systemImage: String {
        switch self {
        case .media(.microphone): "mic.slash"
        case .media(.camera): "video.slash"
        case .accessibility: "keyboard"
        }
    }

    var settingsURL: URL {
        switch self {
        case .media(let kind): kind.settingsURL
        case .accessibility: Permission.accessibility.settingsURL
        }
    }

    @MainActor var isGranted: Bool {
        switch self {
        case .media(let kind): MediaEnvironment.authorizer.status(kind) == .authorized
        case .accessibility: KeyAccess.isGranted
        }
    }
}

/// Whether global key events can be watched (Accessibility), or what
/// `SNAPPER_FAKE_ACCESSIBILITY` says.
@MainActor
enum KeyAccess {
    static var isGranted: Bool {
        if let fake = Diagnostics.fakeAccessibility { return fake == "granted" }
        return Permission.accessibility.isGranted
    }
}

/// Explains a missing camera, microphone or Accessibility permission, with the exact System
/// Settings pane. Updates by itself when it's turned on (and runs `onGranted`). Esc closes.
///
/// Built like SlopKit's `PermissionPrompt` (whose `Permission` has no camera or microphone);
/// worth moving there with `MediaKind`.
@MainActor
enum MediaPermissionWindow {
    private static var window: NSWindow?
    private static var onGranted: (() -> Void)?

    static func show(_ permission: RecordingPermission, onGranted: (() -> Void)? = nil) {
        window?.close()
        self.onGranted = onGranted
        let hosting = NSHostingController(rootView: MediaPermissionView(permission: permission) {
            MediaPermissionWindow.granted()
        })
        let window = EscapableWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = permission.title
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Diagnostics.record("permission window shown")
    }

    static var isShown: Bool { window?.isVisible == true }

    static func close() {
        window?.close()
        window = nil
    }

    private static func granted() {
        let action = onGranted
        onGranted = nil
        action?()
    }
}

struct MediaPermissionView: View {
    let permission: RecordingPermission
    let onGranted: () -> Void
    @State private var isGranted = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: isGranted ? "checkmark.circle" : permission.systemImage)
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isGranted ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(isGranted ? "It's on" : permission.title)
                .font(.title3.bold())
            Text(isGranted ? "You can close this window." : permission.reason)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            HStack(spacing: Spacing.s) {
                if isGranted {
                    Button("Done") { MediaPermissionWindow.close() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { MediaPermissionWindow.close() }
                        .keyboardShortcut(.cancelAction)
                    Button("Open System Settings") {
                        if permission == .accessibility { Permission.accessibility.request() } else { NSWorkspace.shared.open(permission.settingsURL) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.xxl)
        .frame(width: 440)
        .task {
            // Re-check while the window is open (cheap; stops when granted or closed).
            isGranted = permission.isGranted
            while !isGranted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if permission.isGranted {
                    isGranted = true
                    onGranted()
                }
            }
        }
    }
}
