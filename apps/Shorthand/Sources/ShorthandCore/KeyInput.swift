import CoreGraphics

/// One key-down as the matcher sees it: what kind of key, and the characters it produced in
/// the active layout (Dvorak, AZERTY and friends work because we read produced characters).
public struct KeyInput: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Produced text (1–4 scalars).
        case characters
        /// Backspace: the newest character goes.
        case backspace
        /// Return, Enter, Tab: counts as a word boundary, then the buffer starts over.
        case boundary
        /// Arrows, Home/End, Page keys, Esc, Forward Delete, ⌥⌫/⌘⌫, ⌘ or ⌃ combinations: the
        /// caret may have moved, so start over.
        case reset
        /// A key that produced no character (a dead key such as ⌥E on US, ^ on French): the
        /// composed letter only exists inside the app, so start over and skip the next one.
        case deadKey
        /// Modifier changes and anything else that doesn't type.
        case ignored
    }

    public enum Origin: Sendable, Equatable {
        /// From the keyboard.
        case hardware
        /// Posted by Shorthand itself (carries our marker).
        case ours
        /// Posted by another app (Dictate typing a transcript, Clips' ⌘V, remote control).
        case synthetic
    }

    public var kind: Kind
    public var origin: Origin
    public var count: Int
    public var s0: UInt32 = 0
    public var s1: UInt32 = 0
    public var s2: UInt32 = 0
    public var s3: UInt32 = 0

    public init(kind: Kind, origin: Origin = .hardware) {
        self.kind = kind
        self.origin = origin
        self.count = 0
    }

    public subscript(_ i: Int) -> UInt32 {
        switch i {
        case 0: s0
        case 1: s1
        case 2: s2
        default: s3
        }
    }

    public mutating func append(_ value: UInt32) {
        switch count {
        case 0: s0 = value
        case 1: s1 = value
        case 2: s2 = value
        case 3: s3 = value
        default: return
        }
        count += 1
    }

    /// Typed text (tests, replays). Control characters become the key they are.
    public static func text(_ string: String, origin: Origin = .hardware) -> [KeyInput] {
        string.unicodeScalars.map { scalar in
            switch scalar {
            case "\n", "\r", "\t": return KeyInput(kind: .boundary, origin: origin)
            default:
                var input = KeyInput(kind: .characters, origin: origin)
                input.append(scalar.value)
                return input
            }
        }
    }
}

/// Turns a `CGEvent` from the tap into a `KeyInput`. Reads only what's needed to decide;
/// no allocation.
public enum KeyDecoder {
    /// Written into `eventSourceUserData` of everything Shorthand posts.
    public static let marker: Int64 = 0x5348_4F52_5448_4E44 // "SHORTHND"

    /// Hardware key events come from the HID system's state table; anything posted by an app
    /// (with a combined-session or private source) carries another state ID.
    static let hidStateID = Int64(CGEventSourceStateID.hidSystemState.rawValue)

    public static func decode(_ event: CGEvent, type: CGEventType) -> KeyInput {
        let origin: KeyInput.Origin
        if event.getIntegerValueField(.eventSourceUserData) == marker {
            origin = .ours
        } else if event.getIntegerValueField(.eventSourceStateID) != hidStateID {
            origin = .synthetic
        } else {
            origin = .hardware
        }
        guard type == .keyDown else { return KeyInput(kind: .ignored, origin: origin) }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if let kind = kind(keyCode: code, flags: flags) { return KeyInput(kind: kind, origin: origin) }

        var length = 0
        var units: (UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0)
        withUnsafeMutableBytes(of: &units) { raw in
            let pointer = raw.baseAddress!.assumingMemoryBound(to: UniChar.self)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: pointer)
        }
        return input(units: units, length: length, origin: origin)
    }

    /// The kind for keys recognised by their code and modifiers alone; nil = look at the
    /// characters it produced.
    public static func kind(keyCode code: Int, flags: CGEventFlags) -> KeyInput.Kind? {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { return .reset }
        switch code {
        case 51: // Delete (Backspace)
            return flags.contains(.maskAlternate) ? .reset : .backspace
        case 36, 76, 48: // Return, keypad Enter, Tab
            return .boundary
        case 117, 123, 124, 125, 126, 115, 119, 116, 121, 53, 114: // fwd delete, arrows, home, end, pg, esc, help
            return .reset
        case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90: // F1–F20
            return .reset
        default:
            return nil
        }
    }

    public static func input(units: (UInt16, UInt16, UInt16, UInt16), length: Int, origin: KeyInput.Origin) -> KeyInput {
        guard length > 0 else { return KeyInput(kind: .deadKey, origin: origin) }
        var input = KeyInput(kind: .characters, origin: origin)
        var i = 0
        let n = min(length, 4)
        while i < n {
            let unit: UInt16 = switch i { case 0: units.0; case 1: units.1; case 2: units.2; default: units.3 }
            if UTF16.isLeadSurrogate(unit), i + 1 < n {
                let trail: UInt16 = switch i + 1 { case 1: units.1; case 2: units.2; default: units.3 }
                input.append(0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(trail) - 0xDC00))
                i += 2
                continue
            }
            if unit < 0x20 || unit == 0x7F {
                // A control character (Return typed as ⌃M etc.): the caret context is unclear.
                return KeyInput(kind: unit == 0x0D || unit == 0x09 || unit == 0x0A ? .boundary : .reset, origin: origin)
            }
            input.append(UInt32(unit))
            i += 1
        }
        return input
    }
}
