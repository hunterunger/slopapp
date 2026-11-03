/// Modifier keys held when a link arrives. Our own type so the core doesn't need AppKit.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    /// In Apple's display order: ⌃ ⌥ ⇧ ⌘, then fn.
    public static let all: [Modifiers] = [.control, .option, .shift, .command, .function]

    public var symbol: String {
        Self.all.filter { contains($0) }.map(\.singleSymbol).joined()
    }

    /// Spoken/written name, e.g. "Option" or "Control-Option".
    public var name: String {
        Self.all.filter { contains($0) }.map(\.singleName).joined(separator: "-")
    }

    private var singleSymbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        case .function: "fn"
        default: ""
        }
    }

    private var singleName: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        case .command: "Command"
        case .function: "fn"
        default: ""
        }
    }
}
