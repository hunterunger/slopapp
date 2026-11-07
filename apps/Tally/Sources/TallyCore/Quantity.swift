import Foundation

/// What a number measures.
public enum Tag: Hashable, Sendable {
    case none
    /// Stored as a fraction: 20% is 0.2.
    case percent
    case unit(PhysicalUnit)
    case currency(String)
    /// A compound unit: `km/h`, `$/h`, `Mb/s`.
    case rate(RateUnit)
    /// A point in time. The value is seconds since 1970 (UTC).
    case date(DateTag)
}

/// `numerator / denominator`, where the numerator is a unit or a currency.
public struct RateUnit: Hashable, Sendable {
    public enum Numerator: Hashable, Sendable {
        case unit(PhysicalUnit)
        case currency(String)

        var tag: Tag {
            switch self {
            case .unit(let u): .unit(u)
            case .currency(let c): .currency(c)
            }
        }

        var dimensionKey: String {
            switch self {
            case .unit(let u): u.dimension.rawValue
            case .currency: "currency"
            }
        }
    }

    public var numerator: Numerator
    public var denominator: PhysicalUnit
    /// A name to show instead of `num/den` (`mph`, `knots`, `Mbps`).
    public var alias: String?

    public init(_ numerator: Numerator, per denominator: PhysicalUnit, alias: String? = nil) {
        self.numerator = numerator
        self.denominator = denominator
        self.alias = alias
    }

    /// Same kind of rate (length per time, currency per mass...).
    func isCompatible(with other: RateUnit) -> Bool {
        numerator.dimensionKey == other.numerator.dimensionKey && denominator.dimension == other.denominator.dimension
    }
}

/// How a date is shown and which zone it's in.
public struct DateTag: Hashable, Sendable {
    public enum Style: Hashable, Sendable {
        /// A time of day ("3:00 PM"), with the weekday or date only when it isn't today.
        case time
        /// A calendar day ("Tue, Nov 24, 2026").
        case date
        /// Both.
        case dateTime
    }

    /// A `TimeZone` identifier.
    public var zone: String
    /// What the user called the zone ("Tokyo", "PST"); nil for the Mac's own zone.
    public var label: String?
    public var style: Style

    public init(zone: String, label: String? = nil, style: Style) {
        self.zone = zone
        self.label = label
        self.style = style
    }

    var timeZone: TimeZone { DateMath.zone(zone) ?? .current }
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

    public var rate: RateUnit? {
        if case .rate(let r) = tag { return r }
        return nil
    }

    public var date: DateTag? {
        if case .date(let d) = tag { return d }
        return nil
    }

    var isPercent: Bool { tag == .percent }
    var isPlain: Bool { tag == .none }
}
