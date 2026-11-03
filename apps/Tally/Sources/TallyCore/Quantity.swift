import Foundation

/// What a number measures.
public enum Tag: Hashable, Sendable {
    case none
    /// Stored as a fraction: 20% is 0.2.
    case percent
    case unit(PhysicalUnit)
    case currency(String)
}

/// How a plain number is written out (`in hex`, `in sci`).
public enum NumberStyle: Hashable, Sendable {
    case auto, hex, binary, octal, scientific
}

/// A value with what it measures.
public struct Quantity: Hashable, Sendable {
    public var value: Decimal
    public var tag: Tag
    public var style: NumberStyle

    public init(_ value: Decimal, _ tag: Tag = .none, style: NumberStyle = .auto) {
        self.value = value
        self.tag = tag
        self.style = style
    }

    public var unit: PhysicalUnit? {
        if case .unit(let u) = tag { return u }
        return nil
    }

    public var currency: String? {
        if case .currency(let c) = tag { return c }
        return nil
    }

    var isPercent: Bool { tag == .percent }
    var isPlain: Bool { tag == .none }
}
