import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictateCore

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

    private func paste(_ text: String) {
        let saved = ClipboardSnapshot.capture(pasteboard)
        let ours = ClipboardSnapshot.write(text, to: pasteboard, transient: !saved.isEmpty)
        let pasteboard = self.pasteboard
        Task {
            // Let the write land, then paste; then put the old clipboard back once the app
            // has read it, unless someone copied something else in the meantime.
            try? await Task.sleep(for: .milliseconds(60))
            Self.postCommand(key: Self.virtualKey(for: "v") ?? CGKeyCode(kVK_ANSI_V))
            guard !saved.isEmpty else { return }   // nothing to restore: the text stays copied
            try? await Task.sleep(for: .milliseconds(450))
            guard pasteboard.changeCount == ours else { return }
            saved.restore(to: pasteboard)
        }
    }

    // MARK: Command Mode

    func copySelection() async -> SelectionResult {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        let saved = ClipboardSnapshot.capture(pasteboard)
        let before = pasteboard.changeCount
        Self.postCommand(key: Self.virtualKey(for: "c") ?? CGKeyCode(kVK_ANSI_C))
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

    private static func source() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Don't let the keys someone is still holding (Fn, the shortcut) suppress ours.
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        return source
    }

    /// The key that types `character` in the current keyboard layout, so ⌘V is ⌘V on Dvorak
    /// and AZERTY too. Nil if the layout can't be read. (Same approach as Clips' Paster.)
    static func virtualKey(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let target = String(character)
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    /// ⌘ + `key` to the app in front.
    private static func postCommand(key: CGKeyCode) {
        let source = source()
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Types `text` as keystrokes: Unicode in small chunks, Return for new lines.
    static func type(_ text: String) async {
        let source = source()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let units = Array(line.utf16)
            var start = 0
            while start < units.count {
                // Up to 20 UTF-16 units per event; don't split a surrogate pair.
                var end = min(units.count, start + 20)
                if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
                var chunk = Array(units[start..<end])
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                // No modifiers: a key still held (Shift, Fn) mustn't change what's typed.
                down?.flags = []
                up?.flags = []
                down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
                start = end
                try? await Task.sleep(for: .milliseconds(4))
            }
            if index < lines.count - 1 {
                let key = CGKeyCode(kVK_Return)
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(4))
            }
        }
    }
}
