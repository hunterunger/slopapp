import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

/// macOS privacy permissions Slopapp apps commonly need.
public enum Permission: String, CaseIterable, Sendable, Identifiable {
    case accessibility
    case screenRecording
    case fullDiskAccess

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .fullDiskAccess: "Full Disk Access"
        }
    }

    public var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .fullDiskAccess: "externaldrive"
        }
    }

    /// The exact System Settings pane for this permission.
    public var settingsURL: URL {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        case .fullDiskAccess: "Privacy_AllFiles"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    /// macOS only picks up a Screen Recording grant after the app restarts.
    public var needsRelaunchAfterGrant: Bool { self == .screenRecording }

    @MainActor
    public var isGranted: Bool {
        switch self {
        case .accessibility:
            return AXIsProcessTrusted()
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .fullDiskAccess:
            // The user's TCC database exists for everyone and is only readable with FDA.
            let path = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
            guard let handle = FileHandle(forReadingAtPath: path) else { return false }
            try? handle.close()
            return true
        }
    }

    /// Shows the system prompt where macOS has one, and opens System Settings.
    @MainActor
    public func request() {
        switch self {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .fullDiskAccess:
            break
        }
        NSWorkspace.shared.open(settingsURL)
    }
}

/// Shows `content` once `permission` is granted; until then, a short explanation with a
/// button to the right System Settings pane. Re-checks every second while visible.
///
///     PermissionGate(.accessibility, reason: "Tiles moves and resizes windows for you.") {
///         TilesView()
///     }
public struct PermissionGate<Content: View>: View {
    let permission: Permission
    let reason: String
    let content: Content
    @State private var isGranted: Bool?

    public init(_ permission: Permission, reason: String, @ViewBuilder content: () -> Content) {
        self.permission = permission
        self.reason = reason
        self.content = content()
    }

    public var body: some View {
        Group {
            if isGranted == true {
                content
            } else if isGranted == false {
                PermissionPrompt(permission: permission, reason: reason)
            } else {
                Color.clear
            }
        }
        .task {
            // Poll only while the prompt is on screen; stops when granted or hidden.
            isGranted = permission.isGranted
            while isGranted == false, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                isGranted = permission.isGranted
            }
        }
    }
}

/// The "needs permission" card used by `PermissionGate`. Usable on its own in onboarding.
public struct PermissionPrompt: View {
    let permission: Permission
    let reason: String
    @State private var didRequest = false

    public init(permission: Permission, reason: String) {
        self.permission = permission
        self.reason = reason
    }

    public var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Allow \(permission.title)")
                .font(.title3.bold())
            Text(reason)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s) {
                Button("Open System Settings") {
                    permission.request()
                    didRequest = true
                }
                .buttonStyle(.borderedProminent)
                if permission.needsRelaunchAfterGrant && didRequest {
                    Button("Restart App") { AppRelauncher.relaunch() }
                }
            }
            .padding(.top, Spacing.xs)
            Text(didRequest && permission.needsRelaunchAfterGrant
                 ? "After you turn it on, restart the app."
                 : "Turn it on in System Settings. This screen updates by itself.")
                .font(.caption)
                .foregroundStyle(.secondary) // .tertiary text fails contrast (1.9:1 in light mode)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: 360)
    }
}

/// Restarts the running .app (for permissions macOS only applies at launch).
@MainActor
public enum AppRelauncher {
    public static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
