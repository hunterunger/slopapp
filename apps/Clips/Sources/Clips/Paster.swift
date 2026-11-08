import ApplicationServices
import SlopKit

/// Sends ⌘V to the frontmost app. Needs Accessibility; without it Clips only copies.
@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Clips' keys go in after the session taps, from a plain combined-session source.
    private static let keyboard = SyntheticKeyboard(destination: .annotatedSession)

    /// Posts ⌘V on the current layout's V key (Dvorak, AZERTY...) with only Command held (so a
    /// Shift still down from ⇧Return doesn't turn it into "Paste and Match Style").
    static func sendPaste() {
        keyboard.paste()
    }
}
