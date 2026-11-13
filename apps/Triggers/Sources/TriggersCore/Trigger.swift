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

/// Trackpad gestures Triggers recognizes. Stored as `kind` + `fingers` plus the one detail the
/// kind needs (a direction, a corner or an edge), so files from 0.1 (taps and swipes only)
/// decode unchanged.
public struct Gesture: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case tap, doubleTap, swipe, pinchIn, pinchOut, rotateLeft, rotateRight, cornerTap, edgeSwipe, tipTap
    }
    public enum Direction: String, Codable, Sendable, CaseIterable { case left, right, up, down }
    public enum Corner: String, Codable, Sendable, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    /// Edge swipes start at this edge and move into the pad.
    public enum Edge: String, Codable, Sendable, CaseIterable { case left, right, top, bottom }

    public var kind: Kind
    public var fingers: Int
    /// Swipes (4 directions) and tip-taps (left or right).
    public var direction: Direction?
    /// Corner taps.
    public var corner: Corner?
    /// Edge swipes.
    public var edge: Edge?

    public init(kind: Kind, fingers: Int, direction: Direction? = nil, corner: Corner? = nil, edge: Edge? = nil) {
        self.kind = kind
        self.fingers = fingers
        self.direction = kind == .swipe || kind == .tipTap ? direction : nil
        self.corner = kind == .cornerTap ? corner : nil
        self.edge = kind == .edgeSwipe ? edge : nil
    }

    public static func tap(_ fingers: Int) -> Gesture { Gesture(kind: .tap, fingers: fingers) }
    public static func doubleTap(_ fingers: Int) -> Gesture { Gesture(kind: .doubleTap, fingers: fingers) }
    public static func swipe(_ fingers: Int, _ direction: Direction) -> Gesture {
        Gesture(kind: .swipe, fingers: fingers, direction: direction)
    }
    public static func pinchIn(_ fingers: Int) -> Gesture { Gesture(kind: .pinchIn, fingers: fingers) }
    public static func pinchOut(_ fingers: Int) -> Gesture { Gesture(kind: .pinchOut, fingers: fingers) }
    public static func rotate(_ clockwise: Bool) -> Gesture { Gesture(kind: clockwise ? .rotateRight : .rotateLeft, fingers: 2) }
    public static func cornerTap(_ corner: Corner) -> Gesture { Gesture(kind: .cornerTap, fingers: 1, corner: corner) }
    /// Two fingers from `edge` into the pad.
    public static func edgeSwipe(_ edge: Edge) -> Gesture { Gesture(kind: .edgeSwipe, fingers: 2, edge: edge) }
    /// One finger rests; another taps on its left or right.
    public static func tipTap(_ side: Direction) -> Gesture { Gesture(kind: .tipTap, fingers: 1, direction: side) }

    /// Finger counts each kind supports. Two-finger swipes are scrolling, and one-finger taps
    /// are clicks, so neither is offered.
    public static func fingerRange(_ kind: Kind) -> ClosedRange<Int> {
        switch kind {
        case .tap, .doubleTap, .pinchIn, .pinchOut: 2...5
        case .swipe: 3...5
        case .rotateLeft, .rotateRight, .edgeSwipe: 2...2
        case .cornerTap, .tipTap: 1...1
        }
    }

    /// Whether this is a gesture Triggers can recognize.
    public var isSupported: Bool {
        guard Gesture.fingerRange(kind).contains(fingers) else { return false }
        switch kind {
        case .swipe: return direction != nil
        case .tipTap: return direction == .left || direction == .right
        case .cornerTap: return corner != nil
        case .edgeSwipe: return edge != nil
        default: return true
        }
    }

    /// The picker's groups, in menu order.
    public static let groups: [(title: String, gestures: [Gesture])] = [
        ("Taps", (2...5).map(Gesture.tap)),
        ("Double Taps", (2...5).map(Gesture.doubleTap)),
        ("Three-Finger Swipes", Direction.allCases.map { .swipe(3, $0) }),
        ("Four-Finger Swipes", Direction.allCases.map { .swipe(4, $0) }),
        ("Five-Finger Swipes", Direction.allCases.map { .swipe(5, $0) }),
        ("Pinch and Spread", (2...5).flatMap { [Gesture.pinchIn($0), .pinchOut($0)] }),
        ("Rotate", [.rotate(false), .rotate(true)]),
        ("Corners", Corner.allCases.map(Gesture.cornerTap)),
        ("Edges", Edge.allCases.map(Gesture.edgeSwipe)),
        ("Tip-Taps", [.tipTap(.left), .tipTap(.right)]),
    ]

    /// Every supported gesture, in menu order.
    public static let supported: [Gesture] = groups.flatMap(\.gestures)

    static func count(_ fingers: Int) -> String {
        switch fingers {
        case 1: "One"
        case 2: "Two"
        case 3: "Three"
        case 4: "Four"
        case 5: "Five"
        default: "\(fingers)"
        }
    }

    public var title: String {
        let count = Gesture.count(fingers)
        switch kind {
        case .tap: return "\(count)-finger tap"
        case .doubleTap: return "\(count)-finger double tap"
        case .swipe: return "\(count)-finger swipe \(direction?.rawValue ?? "")"
        case .pinchIn: return "\(count)-finger pinch"
        case .pinchOut: return "\(count)-finger spread"
        case .rotateLeft: return "Two-finger rotate left"
        case .rotateRight: return "Two-finger rotate right"
        case .cornerTap: return "Tap in the \(corner?.title ?? "") corner"
        case .edgeSwipe: return "Two-finger swipe in from the \(edge?.rawValue ?? "") edge"
        case .tipTap: return "Tip-tap \(direction?.rawValue ?? "")"
        }
    }

    public var systemImage: String {
        switch kind {
        case .tap: return "hand.tap"
        case .doubleTap: return "hand.tap.fill"
        case .swipe:
            switch direction ?? .left {
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            }
        case .pinchIn: return "arrow.down.right.and.arrow.up.left"
        case .pinchOut: return "arrow.up.left.and.arrow.down.right"
        case .rotateLeft: return "arrow.counterclockwise"
        case .rotateRight: return "arrow.clockwise"
        case .cornerTap:
            switch corner ?? .topLeft {
            case .topLeft: return "rectangle.inset.topleft.filled"
            case .topRight: return "rectangle.inset.topright.filled"
            case .bottomLeft: return "rectangle.inset.bottomleft.filled"
            case .bottomRight: return "rectangle.inset.bottomright.filled"
            }
        case .edgeSwipe:
            switch edge ?? .left {
            case .left: return "arrow.right.to.line"
            case .right: return "arrow.left.to.line"
            case .top: return "arrow.down.to.line"
            case .bottom: return "arrow.up.to.line"
            }
        case .tipTap: return "hand.point.up.left"
        }
    }
}

extension Gesture.Corner {
    public var title: String {
        switch self {
        case .topLeft: "top-left"
        case .topRight: "top-right"
        case .bottomLeft: "bottom-left"
        case .bottomRight: "bottom-right"
        }
    }
}

/// One press in a key sequence: a key (with the modifiers held for it), or a modifier key
/// pressed and released on its own.
public enum KeyStep: Hashable, Codable, Sendable {
    case key(KeyCombo)
    /// Exactly one of ⌃ ⌥ ⇧ ⌘, tapped alone.
    case modifierTap(Modifiers)

    /// "⌘", "G", "⌃K" (US key names; the app shows the current layout's).
    public func title(keys: (KeyCombo) -> String) -> String {
        switch self {
        case .key(let combo): keys(combo)
        case .modifierTap(let modifier): modifier.symbols
        }
    }
}

/// Keys pressed one after another: ⌘ twice, or G then H. Each press must come within
/// `timeout` seconds of the one before. The keys still reach the app in front: Triggers watches
/// sequences, it never swallows them.
public struct KeySequence: Hashable, Codable, Sendable {
    public var steps: [KeyStep]
    /// Most seconds between one press and the next.
    public var timeout: Double

    public static let defaultTimeout = 0.5
    public static let maxSteps = 4
    /// The choices the editor offers for `timeout`.
    public static let timeouts: [Double] = [0.3, 0.5, 1, 2]

    public init(_ steps: [KeyStep], timeout: Double = KeySequence.defaultTimeout) {
        self.steps = steps
        self.timeout = timeout
    }

    /// A modifier tapped twice ("⌘ twice").
    public static func doubleTap(_ modifier: Modifiers) -> KeySequence { KeySequence([.modifierTap(modifier), .modifierTap(modifier)]) }

    /// One modifier tap alone is fine; a single key isn't a sequence (that's a key combination,
    /// or plain typing). At most four presses.
    public var isUsable: Bool {
        guard !steps.isEmpty, steps.count <= KeySequence.maxSteps else { return false }
        if steps.count == 1, case .key = steps[0] { return false }
        return steps.allSatisfy { step in
            if case .modifierTap(let modifier) = step { return modifier.rawValue.nonzeroBitCount == 1 }
            return true
        }
    }

    /// Whether every press is a plain key with no modifier (it types as well as triggers).
    public var typesText: Bool {
        steps.contains { step in
            if case .key(let combo) = step { return combo.modifiers.isEmpty && !KeyNames.isFunctionKey(combo.keyCode) }
            return false
        }
    }

    /// "⌘ twice", "Tap ⌥ alone", "G then H".
    public func title(keys: (KeyCombo) -> String) -> String {
        let names = steps.map { $0.title(keys: keys) }
        if steps.count == 1, case .modifierTap = steps[0] { return "Tap \(names[0]) alone" }
        if steps.count > 1, Set(steps).count == 1 {
            let times = steps.count == 2 ? "twice" : steps.count == 3 ? "three times" : "\(steps.count) times"
            return "\(names[0]) \(times)"
        }
        return names.joined(separator: " then ")
    }

    public var fallbackTitle: String { title(keys: { $0.fallbackDisplay }) }
}

/// What the person does: the input side of a binding.
public enum Trigger: Hashable, Codable, Sendable {
    case gesture(Gesture, modifiers: Modifiers)
    /// CoreGraphics button number: 2 is the middle button, 3 and 4 are "back" and "forward".
    case mouseButton(Int, modifiers: Modifiers)
    case keyCombo(KeyCombo)
    case keySequence(KeySequence)

    public enum Family: String, Sendable { case trackpad, mouse, keyboard }

    public var family: Family {
        switch self {
        case .gesture: .trackpad
        case .mouseButton: .mouse
        case .keyCombo, .keySequence: .keyboard
        }
    }

    public var modifiers: Modifiers {
        switch self {
        case .gesture(_, let modifiers), .mouseButton(_, let modifiers): modifiers
        case .keyCombo(let combo): combo.modifiers
        case .keySequence: []
        }
    }

    /// The same input with other modifiers (sequences carry their own).
    public func with(modifiers: Modifiers) -> Trigger {
        switch self {
        case .gesture(let gesture, _): .gesture(gesture, modifiers: modifiers)
        case .mouseButton(let button, _): .mouseButton(button, modifiers: modifiers)
        case .keyCombo(let combo): .keyCombo(KeyCombo(keyCode: combo.keyCode, modifiers: modifiers))
        case .keySequence: self
        }
    }

    /// Whether held modifiers can be added in the editor (gestures and mouse buttons).
    public var takesModifiers: Bool { family != .keyboard }

    /// "Three-finger tap", "⌥ Button 4", "⌃⌥K" (US key names; the app uses the real layout).
    public var fallbackTitle: String { title(keys: { $0.fallbackDisplay }) }

    public func title(keys: (KeyCombo) -> String) -> String {
        switch self {
        case .gesture(let gesture, let modifiers):
            return modifiers.isEmpty ? gesture.title : "\(modifiers.symbols) \(gesture.title)"
        case .mouseButton(let button, let modifiers):
            let name = Trigger.buttonName(button)
            return modifiers.isEmpty ? name : "\(modifiers.symbols) \(name)"
        case .keyCombo(let combo):
            return keys(combo)
        case .keySequence(let sequence):
            return sequence.title(keys: keys)
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
        case .keySequence: "command"
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
    /// The key Caps Lock becomes while the hyper key is on (`HyperKey`).
    public static let f18 = 79
    /// Modifier keys, left and right (flags-changed events carry these codes).
    public static let modifierKeyCodes: [Int: Modifiers] = [
        55: .command, 54: .command, 58: .option, 61: .option, 56: .shift, 60: .shift, 59: .control, 62: .control,
    ]
    public static let leftBracket = 33
    public static let rightBracket = 30
}
