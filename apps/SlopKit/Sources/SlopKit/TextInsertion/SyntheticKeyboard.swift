import AppKit
import Carbon.HIToolbox

/// Posts synthetic key events: Unicode text in small chunks, single keys (Backspace, ←) and
/// command shortcuts on the current layout's key. One implementation for every app that
/// types or pastes for the person (Dictate, Clips, Shorthand).
///
/// Posting needs Accessibility. Each app keeps its own destination and source settings, so
/// moving here changed nobody's behaviour:
///
///     SyntheticKeyboard(destination: .hidEventTap, permitsLocalEventsWhileSuppressed: true) // Dictate
///     SyntheticKeyboard(destination: .annotatedSession)                                     // Clips
public struct SyntheticKeyboard: Sendable {
    public enum Destination: Sendable, Equatable {
        /// The HID stream: as if typed on the keyboard. Event taps see it.
        case hidEventTap
        /// After the session taps.
        case annotatedSession
        /// Straight to one process (tests and walkthroughs: never reaches another app).
        case process(pid_t)
    }

    /// One posted key press (down and up).
    public enum Stroke: Sendable, Equatable {
        /// Unicode text, at most `maxChunk` UTF-16 units, no modifiers.
        case text([UInt16])
        /// A virtual key with flags (nil: whatever the event source reports, as a typed
        /// Return always had in Dictate).
        case key(CGKeyCode, flags: UInt64?)
    }

    /// Most apps read at most 20 UTF-16 units from one Unicode key event.
    public static let maxChunk = 20

    public var destination: Destination
    /// Don't let keys someone is still holding (Fn, a shortcut) suppress ours (Dictate).
    public var permitsLocalEventsWhileSuppressed: Bool
    /// Written to `eventSourceUserData` on every event, so an event tap can recognise and
    /// skip its own app's events. 0 = unmarked.
    public var marker: Int64

    public init(destination: Destination = .hidEventTap, permitsLocalEventsWhileSuppressed: Bool = false, marker: Int64 = 0) {
        self.destination = destination
        self.permitsLocalEventsWhileSuppressed = permitsLocalEventsWhileSuppressed
        self.marker = marker
    }

    // MARK: Plans (pure, tested)

    /// The strokes that type `text`: Unicode chunks per line, Return between lines. Chunks
    /// never split a surrogate pair.
    public static func strokes(typing text: String) -> [Stroke] {
        var strokes: [Stroke] = []
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let units = Array(line.utf16)
            var start = 0
            while start < units.count {
                var end = min(units.count, start + maxChunk)
                if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
                strokes.append(.text(Array(units[start..<end])))
                start = end
            }
            if index < lines.count - 1 {
                strokes.append(.key(CGKeyCode(kVK_Return), flags: nil))
            }
        }
        return strokes
    }

    // MARK: Posting

    /// Types `text` as keystrokes, waiting `interval` after each one (the clipboard is never
    /// touched). Dictate uses 4 ms.
    @MainActor
    public func type(_ text: String, interval: Duration = .milliseconds(4)) async {
        let source = makeSource()
        for stroke in Self.strokes(typing: text) {
            post(stroke, source: source)
            if interval > .zero { try? await Task.sleep(for: interval) }
        }
    }

    /// Types `text` without pausing between chunks (short text, where speed matters).
    @MainActor
    public func typeNow(_ text: String) {
        let source = makeSource()
        for stroke in Self.strokes(typing: text) { post(stroke, source: source) }
    }

    /// Presses `key` `count` times (Backspace, arrows).
    @MainActor
    public func press(_ key: CGKeyCode, count: Int = 1, flags: CGEventFlags = []) {
        guard count > 0 else { return }
        let source = makeSource()
        for _ in 0..<count { post(.key(key, flags: flags.rawValue), source: source) }
    }

    /// ⌘ + the key that types `character` in the current layout (⌘V on Dvorak is ⌘V), with
    /// only Command held, so a Shift still down doesn't turn it into another command.
    @MainActor
    public func command(_ character: Character, fallback: Int) {
        let key = KeyboardLayout.commandKey(character, fallback: fallback)
        post(.key(key, flags: CGEventFlags.maskCommand.rawValue), source: makeSource())
    }

    /// ⌘V on the current layout.
    @MainActor
    public func paste() { command("v", fallback: kVK_ANSI_V) }

    /// ⌘C on the current layout.
    @MainActor
    public func copy() { command("c", fallback: kVK_ANSI_C) }

    private func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        if permitsLocalEventsWhileSuppressed {
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                               state: .eventSuppressionStateSuppressionInterval)
        }
        return source
    }

    private func post(_ stroke: Stroke, source: CGEventSource?) {
        let code: CGKeyCode
        let flags: CGEventFlags?
        var units: [UInt16] = []
        switch stroke {
        case .text(let chunk):
            code = 0
            flags = [] // a key still held (Shift, Fn) mustn't change what's typed
            units = chunk
        case .key(let key, let raw):
            code = key
            flags = raw.map { CGEventFlags(rawValue: $0) }
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        if let flags {
            down.flags = flags
            up.flags = flags
        }
        if !units.isEmpty {
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        }
        if marker != 0 {
            down.setIntegerValueField(.eventSourceUserData, value: marker)
            up.setIntegerValueField(.eventSourceUserData, value: marker)
        }
        switch destination {
        case .hidEventTap:
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        case .annotatedSession:
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        case .process(let pid):
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }
}
