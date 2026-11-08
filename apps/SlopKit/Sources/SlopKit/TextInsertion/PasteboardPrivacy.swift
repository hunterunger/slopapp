import AppKit

/// Whether macOS lets this app read what other apps copy ("Paste from Other Apps", macOS
/// 15.4+). Reading `changeCount` and writing never ask; reading another app's data does.
public enum PasteboardPrivacy: Equatable, Sendable {
    /// Reads work silently.
    case allowed
    /// macOS shows an alert on each read until the person allows the app in System Settings.
    case asks
    /// macOS blocks every read.
    case denied

    /// Privacy & Security › Paste from Other Apps.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!

    @MainActor
    public static func current(for board: NSPasteboard) -> PasteboardPrivacy {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch board.accessBehavior {
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        case .ask, .default: return .asks
        @unknown default: return .asks
        }
    }

    @MainActor
    public static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
