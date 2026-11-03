import AppKit
import SlopKit

// Shared-component candidate: SlopKit's `Permission` has no case for macOS's pasteboard
// privacy ("Paste from Other Apps", macOS 15.4+). Kept here until it moves to SlopKit.

/// Whether macOS lets Clips read what other apps copy.
enum ClipboardAccess: Equatable {
    /// Reads work silently.
    case allowed
    /// macOS shows an alert on each read until the user allows Clips in System Settings.
    case asks
    /// macOS blocks every read.
    case denied

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!

    @MainActor
    static func current(for board: NSPasteboard) -> ClipboardAccess {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch board.accessBehavior {
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        case .ask, .default: return .asks
        @unknown default: return .asks
        }
    }

    @MainActor
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
