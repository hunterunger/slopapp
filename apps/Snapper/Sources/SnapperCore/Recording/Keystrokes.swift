import Foundation

/// Modifier keys, in the order macOS shows them (⌃⌥⇧⌘).
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

/// One key press, as the keystroke caption needs it. Never stored or logged.
public struct KeyStroke: Equatable, Sendable {
    public var keyCode: UInt16
    /// The key's character without any modifier ("4" for ⇧⌘4, "a" for ⌥A).
    public var key: String
    /// What the press typed ("$" for ⇧4), for showing typing.
    public var typed: String
    public var modifiers: KeyModifiers
    public var isRepeat: Bool

    public init(keyCode: UInt16, key: String, typed: String? = nil, modifiers: KeyModifiers = [], isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.key = key
        self.typed = typed ?? key
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    /// A key with a name of its own (Return, Esc, arrows, F-keys…), or nil for a character key.
    public var specialName: String? { KeyNames.special[keyCode] }

    /// ⌘, ⌃ or ⌥ held, or a special key: a command, not typing. (Shift alone is typing.)
    public var isShortcut: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || (specialName != nil && keyCode != KeyNames.space)
    }

    /// "⌃⌥⇧⌘4", "⌘Z", "⇧⇥", "Space".
    public var label: String {
        let name = specialName ?? key.uppercased()
        return modifiers.symbols + name
    }
}

public enum KeyNames {
    public static let space: UInt16 = 49

    /// Keys shown by name or symbol instead of their character.
    public static let special: [UInt16: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]
}

/// What the keystroke caption shows.
public enum KeystrokeMode: String, CaseIterable, Identifiable, Sendable {
    /// Shortcuts and special keys only: typed text (a password, a message) never shows up.
    case shortcuts
    /// Typing too.
    case allKeys

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .shortcuts: "Shortcuts Only"
        case .allKeys: "All Keys"
        }
    }
}

/// The on-screen caption of recent keys while recording: the last shortcut ("⌘⇧4", or
/// "⌘Z ×3" when repeated), or, with all keys, a run of what was typed. It clears itself
/// `holdTime` after the last key.
public struct KeystrokeCaption: Equatable, Sendable {
    public var mode: KeystrokeMode
    public var holdTime: TimeInterval
    /// The longest run of typing kept (the oldest characters scroll off).
    public var maxTypingLength = 24
    public private(set) var text: String?
    private var lastLabel: String?
    private var repeats = 0
    private var typing = ""
    private var lastTime: TimeInterval = -.infinity

    public init(mode: KeystrokeMode = .shortcuts, holdTime: TimeInterval = 1.6) {
        self.mode = mode
        self.holdTime = holdTime
    }

    /// Feeds a key press at `time` (seconds). Returns whether the caption changed.
    @discardableResult
    public mutating func feed(_ stroke: KeyStroke, at time: TimeInterval) -> Bool {
        let before = text
        if time - lastTime > holdTime { clear() }
        lastTime = time
        if stroke.isShortcut {
            typing = ""
            let label = stroke.label
            if label == lastLabel {
                repeats += 1
            } else {
                lastLabel = label
                repeats = 1
            }
            text = repeats > 1 ? "\(label) ×\(repeats)" : label
        } else if mode == .allKeys {
            lastLabel = nil
            repeats = 0
            let typed = stroke.keyCode == KeyNames.space ? " " : stroke.typed
            guard !typed.isEmpty, typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return text != before }
            typing += typed
            if typing.count > maxTypingLength { typing = String(typing.suffix(maxTypingLength)) }
            text = typing
        } else {
            // Typing with shortcuts only: nothing shows, and the last shortcut goes away so
            // the caption never seems to belong to what's being typed.
            clear()
        }
        return text != before
    }

    /// Clears the caption once `holdTime` has passed. Returns whether it changed.
    @discardableResult
    public mutating func expire(at time: TimeInterval) -> Bool {
        guard text != nil, time - lastTime >= holdTime else { return false }
        clear()
        return true
    }

    public mutating func clear() {
        text = nil
        lastLabel = nil
        repeats = 0
        typing = ""
    }
}
