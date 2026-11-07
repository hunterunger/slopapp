import Foundation

/// Modifier keys, as Triggers stores and compares them. Only the four that people hold on
/// purpose; Caps Lock, Fn and the numeric-pad flag never take part in matching.
public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    public static let all: Modifiers = [.control, .option, .shift, .command]

    /// From CoreGraphics event flags (`CGEventFlags.rawValue`).
    public init(cgFlags: UInt64) {
        var result: Modifiers = []
        if cgFlags & 0x0004_0000 != 0 { result.insert(.control) }   // maskControl
        if cgFlags & 0x0008_0000 != 0 { result.insert(.option) }    // maskAlternate
        if cgFlags & 0x0002_0000 != 0 { result.insert(.shift) }     // maskShift
        if cgFlags & 0x0010_0000 != 0 { result.insert(.command) }   // maskCommand
        self = result
    }

    /// CoreGraphics event flags for these modifiers.
    public var cgFlags: UInt64 {
        var flags: UInt64 = 0
        if contains(.control) { flags |= 0x0004_0000 }
        if contains(.option) { flags |= 0x0008_0000 }
        if contains(.shift) { flags |= 0x0002_0000 }
        if contains(.command) { flags |= 0x0010_0000 }
        return flags
    }

    /// Carbon modifier bits (`RegisterEventHotKey`).
    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= 1 << 8 }   // cmdKey
        if contains(.shift) { flags |= 1 << 9 }     // shiftKey
        if contains(.option) { flags |= 1 << 11 }   // optionKey
        if contains(.control) { flags |= 1 << 12 }  // controlKey
        return flags
    }

    /// "⌃⌥⇧⌘" in the order macOS prints them.
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }

    /// "Control-Option" for VoiceOver and prose.
    public var spokenNames: String {
        var names: [String] = []
        if contains(.control) { names.append("Control") }
        if contains(.option) { names.append("Option") }
        if contains(.shift) { names.append("Shift") }
        if contains(.command) { names.append("Command") }
        return names.joined(separator: "-")
    }
}

/// A key and its modifiers, by hardware key code (layout independent, like Carbon hotkeys).
public struct KeyCombo: Hashable, Codable, Sendable {
    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Whether this is safe to take over as a trigger: it needs ⌘, ⌥ or ⌃, unless the key is
    /// a function key (F1–F20), which people don't type.
    public var isUsableAsTrigger: Bool {
        if KeyNames.isFunctionKey(keyCode) { return true }
        return !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    /// "⌃⌥K" with a US-layout key name. The app shows the current layout's name instead.
    public var fallbackDisplay: String { modifiers.symbols + KeyNames.name(for: keyCode) }
}

/// Trackpad gestures Triggers recognizes in v1.
public struct Gesture: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case tap, swipe }
    public enum Direction: String, Codable, Sendable, CaseIterable { case left, right, up, down }

    public var kind: Kind
    public var fingers: Int
    /// Only for swipes.
    public var direction: Direction?

    public init(kind: Kind, fingers: Int, direction: Direction? = nil) {
        self.kind = kind
        self.fingers = fingers
        self.direction = kind == .swipe ? direction : nil
    }

    public static func tap(_ fingers: Int) -> Gesture { Gesture(kind: .tap, fingers: fingers) }
    public static func swipe(_ fingers: Int, _ direction: Direction) -> Gesture {
        Gesture(kind: .swipe, fingers: fingers, direction: direction)
    }

    /// Every gesture v1 supports, in menu order.
    public static let supported: [Gesture] = [3, 4].flatMap { fingers in
        [Gesture.tap(fingers)] + Direction.allCases.map { Gesture.swipe(fingers, $0) }
    }

    public var title: String {
        let count = fingers == 3 ? "Three" : fingers == 4 ? "Four" : "\(fingers)"
        switch kind {
        case .tap: return "\(count)-finger tap"
        case .swipe: return "\(count)-finger swipe \(direction?.rawValue ?? "")"
        }
    }

    public var systemImage: String {
        switch kind {
        case .tap: return "hand.tap"
        case .swipe:
            switch direction ?? .left {
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            }
        }
    }
}

/// What the person does: the input side of a binding.
public enum Trigger: Hashable, Codable, Sendable {
    case gesture(Gesture, modifiers: Modifiers)
    /// CoreGraphics button number: 2 is the middle button, 3 and 4 are "back" and "forward".
    case mouseButton(Int, modifiers: Modifiers)
    case keyCombo(KeyCombo)

    public enum Family: String, Sendable { case trackpad, mouse, keyboard }

    public var family: Family {
        switch self {
        case .gesture: .trackpad
        case .mouseButton: .mouse
        case .keyCombo: .keyboard
        }
    }

    public var modifiers: Modifiers {
        switch self {
        case .gesture(_, let modifiers), .mouseButton(_, let modifiers): modifiers
        case .keyCombo(let combo): combo.modifiers
        }
    }

    /// The same input with other modifiers.
    public func with(modifiers: Modifiers) -> Trigger {
        switch self {
        case .gesture(let gesture, _): .gesture(gesture, modifiers: modifiers)
        case .mouseButton(let button, _): .mouseButton(button, modifiers: modifiers)
        case .keyCombo(let combo): .keyCombo(KeyCombo(keyCode: combo.keyCode, modifiers: modifiers))
        }
    }

    /// "Three-finger tap", "⌥ Button 4", "⌃⌥K" (US key names; the app uses the real layout).
    public var fallbackTitle: String {
        switch self {
        case .gesture(let gesture, let modifiers):
            return modifiers.isEmpty ? gesture.title : "\(modifiers.symbols) \(gesture.title)"
        case .mouseButton(let button, let modifiers):
            let name = Trigger.buttonName(button)
            return modifiers.isEmpty ? name : "\(modifiers.symbols) \(name)"
        case .keyCombo(let combo):
            return combo.fallbackDisplay
        }
    }

    public static func buttonName(_ button: Int) -> String {
        switch button {
        case 2: "Middle button"
        case 3: "Button 4 (back)"
        case 4: "Button 5 (forward)"
        default: "Button \(button + 1)"
        }
    }

    public var systemImage: String {
        switch self {
        case .gesture(let gesture, _): gesture.systemImage
        case .mouseButton: "computermouse"
        case .keyCombo: "keyboard"
        }
    }
}

/// US-layout key names, used for storage-independent fallbacks and tests.
public enum KeyNames {
    private static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
        51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let functionKeys: Set<Int> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                                 105, 107, 113, 106, 64, 79, 80, 90]

    public static func name(for keyCode: Int) -> String { names[keyCode] ?? "Key \(keyCode)" }
    public static func isFunctionKey(_ keyCode: Int) -> Bool { functionKeys.contains(keyCode) }
    public static let escape = 53
    public static let leftBracket = 33
    public static let rightBracket = 30
}
