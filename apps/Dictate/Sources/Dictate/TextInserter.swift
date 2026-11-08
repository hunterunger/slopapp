import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictateCore
import SlopKit

/// Gets text into the focused app: paste (clipboard + ⌘V, then the clipboard is put back as
/// it was) or type (keystrokes, clipboard untouched). Reads the selection for Command Mode.
final class TextInserter: TextDelivering {
    /// The system clipboard, or a private one in tests (`DICTATE_PASTEBOARD`).
    let pasteboard: NSPasteboard
    private let isPrivatePasteboard: Bool

    init() {
        if let name = Diagnostics.pasteboardName {
            pasteboard = NSPasteboard(name: .init(name))
            isPrivatePasteboard = true
        } else {
            pasteboard = .general
            isPrivatePasteboard = false
        }
    }

    /// Copies text for the person to paste themselves.
    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func deliver(_ text: String, insert: Bool, method: InsertionMethod) async -> DeliveryOutcome {
        guard insert else {
            copy(text)
            return .copied
        }
        guard AXIsProcessTrusted() else {
            copy(text)
            return .copiedNeedsAccessibility
        }
        if let only = Diagnostics.insertOnlyInto, !Self.frontmostMatches(only) {
            Diagnostics.record("insert skipped: front app is \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"), not \(only)")
            return .skipped
        }
        // A password field blocks synthetic keys; the text would vanish.
        if IsSecureEventInputEnabled() {
            copy(text)
            return .copied
        }
        // A private test pasteboard can't feed ⌘V (it reads the real clipboard): type instead.
        if method == .type || isPrivatePasteboard {
            await Self.type(text)
            Diagnostics.record("insert typed chars=\(text.count)")
        } else {
            paste(text)
            Diagnostics.record("insert pasted chars=\(text.count)")
        }
        return .inserted
    }

    // MARK: Paste

    /// Dictate's keys: the HID stream, and keys still held (Fn, the shortcut) don't suppress ours.
    private static let keyboard = SyntheticKeyboard(destination: .hidEventTap, permitsLocalEventsWhileSuppressed: true)

    private func paste(_ text: String) {
        // Let the write land, then paste; then put the old clipboard back once the app has
        // read it, unless someone copied something else in the meantime (SlopKit).
        ClipboardPaster(pasteboard: pasteboard) { Self.keyboard.paste() }.paste(text)
    }

    // MARK: Command Mode

    func copySelection() async -> SelectionResult {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        let saved = ClipboardSnapshot.capture(pasteboard)
        let before = pasteboard.changeCount
        Self.keyboard.copy()
        var captured: String?
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(25))
            if pasteboard.changeCount != before {
                captured = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before { saved.restore(to: pasteboard) }
        guard let captured, !captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .nothingSelected
        }
        return .text(captured)
    }

    // MARK: Keys

    private static func frontmostMatches(_ name: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return app.bundleIdentifier == name || app.localizedName == name
    }

    /// Types `text` as keystrokes: Unicode in small chunks, Return for new lines.
    static func type(_ text: String) async {
        await keyboard.type(text, interval: .milliseconds(4))
    }
}
