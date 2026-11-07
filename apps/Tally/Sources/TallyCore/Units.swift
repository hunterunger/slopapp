import Foundation

public enum Dimension: String, Sendable, Hashable {
    case length, mass, data, time, temperature, area, volume, angle
}

/// A unit: `base = (value + offset) * factor / divisor`. The divisor keeps ratios like
/// 5/9 (°F) and π/180 (degrees) exact in both directions.
public struct PhysicalUnit: Hashable, Sendable, CustomStringConvertible {
    public let id: String
    public let dimension: Dimension
    let factor: Decimal
    let divisor: Decimal
    let offset: Decimal
    /// What results show: "km", "°F", "days".
    let symbol: String
    let singular: String?
    /// For area/volume made from a length unit (`sq ft`): that unit's id.
    let lengthBase: String?
    /// `px` and `em` depend on the sheet's pixel density and em size.
    let css: CSSKind?

    public var description: String { id }

    init(_ id: String, _ dimension: Dimension, _ factor: String, divisor: String = "1", offset: String = "0",
         symbol: String? = nil, singular: String? = nil, lengthBase: String? = nil, css: CSSKind? = nil) {
        self.css = css
        self.id = id
        self.dimension = dimension
        self.factor = DecimalMath.decimal(factor)
        self.divisor = DecimalMath.decimal(divisor)
        self.offset = DecimalMath.decimal(offset)
        self.symbol = symbol ?? id
        self.singular = singular
        self.lengthBase = lengthBase
    }

    init(id: String, dimension: Dimension, factor: Decimal, divisor: Decimal, symbol: String, lengthBase: String?) {
        self.id = id
        self.dimension = dimension
        self.factor = factor
        self.divisor = divisor
        self.offset = 0
        self.symbol = symbol
        self.singular = nil
        self.lengthBase = lengthBase
        self.css = nil
    }

    public static func == (a: PhysicalUnit, b: PhysicalUnit) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func toBase(_ value: Decimal, css metrics: CSSMetrics = .standard) throws(EvalError) -> Decimal {
        if let css { return try DecimalMath.multiply(value, try metrics.metres(per: css)) }
        let shifted = offset.isZero ? value : try DecimalMath.add(value, offset)
        if divisor == 1 { return try DecimalMath.multiply(shifted, factor) }
        return try DecimalMath.divide(try DecimalMath.multiply(shifted, factor), divisor)
    }

    func fromBase(_ base: Decimal, css metrics: CSSMetrics = .standard) throws(EvalError) -> Decimal {
        if let css { return try DecimalMath.divide(base, try metrics.metres(per: css)) }
        let scaled = divisor == 1
            ? try DecimalMath.divide(base, factor)
            : try DecimalMath.divide(try DecimalMath.multiply(base, divisor), factor)
        return offset.isZero ? scaled : try DecimalMath.subtract(scaled, offset)
    }

    /// The text after a number: "1 day", "2 days", "5 km".
    func label(plural: Bool) -> String {
        if let singular, !plural { return singular }
        return symbol
    }
}

/// Screen units whose size depends on settings.
public enum CSSKind: Hashable, Sendable { case px, em }

/// The pixel density and em size `px` and `em` convert with. Defaults are the web's:
/// 96 px per inch, 16 px per em. Settings and sheet lines (`ppi = 326`, `em = 20px`) change them.
public struct CSSMetrics: Hashable, Sendable {
    public var ppi: Decimal
    /// Pixels per em.
    public var em: Decimal

    public init(ppi: Decimal = 96, em: Decimal = 16) {
        self.ppi = ppi
        self.em = em
    }

    public static let standard = CSSMetrics()

    func metres(per kind: CSSKind) throws(EvalError) -> Decimal {
        let px = try DecimalMath.divide(DecimalMath.decimal("0.0254"), ppi)
        return kind == .px ? px : try DecimalMath.multiply(px, em)
    }
}

/// Every unit Tally knows, and how words map to them. Symbols are case-sensitive
/// (`m` metre, `M` a scale; `b` bit, `B` byte); spelled-out names aren't.
public enum Units {
    // Base units: metre, gram, bit, second, kelvin, square metre, litre, radian.
    static let length: [PhysicalUnit] = [
        .init("mm", .length, "0.001"), .init("cm", .length, "0.01"), .init("dm", .length, "0.1"),
        .init("m", .length, "1"), .init("km", .length, "1000"),
        .init("µm", .length, "0.000001"),
        .init("in", .length, "0.0254"), .init("ft", .length, "0.3048"), .init("yd", .length, "0.9144"),
        .init("mi", .length, "1609.344"), .init("nmi", .length, "1852"),
        .init("pt", .length, "0.0254", divisor: "72"),
        .init("mil", .length, "0.0000254"), .init("hand", .length, "0.1016", symbol: "hands", singular: "hand"),
        .init("rod", .length, "5.0292", symbol: "rods", singular: "rod"),
        .init("chain", .length, "20.1168", symbol: "chains", singular: "chain"),
        .init("furlong", .length, "201.168", symbol: "furlongs", singular: "furlong"),
        .init("cable", .length, "185.2", symbol: "cables", singular: "cable"),
        .init("league", .length, "4828.032", symbol: "leagues", singular: "league"),
    ]
    /// `px` and `em`: lengths whose size comes from `CSSMetrics`. No squares or cubes.
    static let css: [PhysicalUnit] = [
        .init("px", .length, "1", css: .px), .init("em", .length, "1", css: .em),
    ]
    static let mass: [PhysicalUnit] = [
        .init("mg", .mass, "0.001"), .init("g", .mass, "1"), .init("kg", .mass, "1000"),
        .init("t", .mass, "1000000"), .init("oz", .mass, "28.349523125"), .init("lb", .mass, "453.59237"),
        .init("st", .mass, "6350.29318"), .init("ct", .mass, "0.2"),
        .init("centner", .mass, "100000", symbol: "centners", singular: "centner"),
    ]
    static let data: [PhysicalUnit] = [
        .init("bit", .data, "1", symbol: "bits", singular: "bit"), .init("B", .data, "8"),
        .init("kB", .data, "8000"), .init("MB", .data, "8000000"), .init("GB", .data, "8000000000"),
        .init("TB", .data, "8000000000000"), .init("PB", .data, "8000000000000000"),
        .init("KiB", .data, "8192"), .init("MiB", .data, "8388608"), .init("GiB", .data, "8589934592"),
        .init("TiB", .data, "8796093022208"), .init("PiB", .data, "9007199254740992"),
        .init("kb", .data, "1000"), .init("Mb", .data, "1000000"), .init("Gb", .data, "1000000000"),
        .init("Tb", .data, "1000000000000"),
    ]
    static let time: [PhysicalUnit] = [
        .init("ms", .time, "0.001"), .init("s", .time, "1"), .init("min", .time, "60"),
        .init("h", .time, "3600"), .init("day", .time, "86400", symbol: "days", singular: "day"),
        .init("week", .time, "604800", symbol: "weeks", singular: "week"),
        .init("month", .time, "2628000", symbol: "months", singular: "month"),
        .init("year", .time, "31536000", symbol: "years", singular: "year"),
        .init("decade", .time, "315360000", symbol: "decades", singular: "decade"),
        .init("century", .time, "3153600000", symbol: "centuries", singular: "century"),
    ]
    static let temperature: [PhysicalUnit] = [
        .init("°C", .temperature, "1", offset: "273.15"),
        .init("°F", .temperature, "5", divisor: "9", offset: "459.67"),
        .init("K", .temperature, "1"),
    ]
    static let angle: [PhysicalUnit] = [
        PhysicalUnit(id: "°", dimension: .angle, factor: DecimalMath.pi, divisor: 180, symbol: "°", lengthBase: nil),
        .init("rad", .angle, "1"),
    ]
    static let otherArea: [PhysicalUnit] = [
        .init("ha", .area, "10000"), .init("are", .area, "100", symbol: "ares", singular: "are"), .init("acre", .area, "4046.8564224", symbol: "acres", singular: "acre"),
    ]
    static let otherVolume: [PhysicalUnit] = [
        .init("L", .volume, "1"), .init("mL", .volume, "0.001"), .init("cL", .volume, "0.01"),
        .init("tsp", .volume, "0.00492892159375"), .init("tbsp", .volume, "0.01478676478125"),
        .init("cup", .volume, "0.2365882365", symbol: "cups", singular: "cup"),
        .init("pint", .volume, "0.473176473", symbol: "pints", singular: "pint"),
        .init("quart", .volume, "0.946352946", symbol: "quarts", singular: "quart"),
        .init("gal", .volume, "3.785411784"),
    ]

    /// Square and cubic versions of the length units, e.g. `ft²` and `m³`.
    static let squares: [PhysicalUnit] = length.map { unit in
        let f = unit.factor * unit.factor
        return PhysicalUnit(id: "sq \(unit.id)", dimension: .area, factor: f, divisor: 1,
                            symbol: "\(unit.symbol)²", lengthBase: unit.id)
    }
    static let cubes: [PhysicalUnit] = length.map { unit in
        // Base volume unit is the litre: 1 m³ = 1000 L.
        let f = unit.factor * unit.factor * unit.factor * 1000
        return PhysicalUnit(id: "cu \(unit.id)", dimension: .volume, factor: f, divisor: 1,
                            symbol: "\(unit.symbol)³", lengthBase: unit.id)
    }

    static let all: [PhysicalUnit] = length + css + mass + data + time + temperature + angle + otherArea + otherVolume + squares + cubes
    static let byID: [String: PhysicalUnit] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func unit(id: String) -> PhysicalUnit? { byID[id] }

    /// Exact (case-sensitive) symbols and aliases.
    static let symbols: [String: String] = [
        "mm": "mm", "cm": "cm", "dm": "dm", "m": "m", "km": "km", "µm": "µm", "um": "µm",
        "ft": "ft", "yd": "yd", "mi": "mi", "nmi": "nmi",
        "mg": "mg", "g": "g", "kg": "kg", "t": "t", "oz": "oz", "lb": "lb", "lbs": "lb", "st": "st",
        "b": "bit", "B": "B", "kB": "kB", "KB": "kB", "MB": "MB", "GB": "GB", "TB": "TB", "PB": "PB",
        "KiB": "KiB", "MiB": "MiB", "GiB": "GiB", "TiB": "TiB", "PiB": "PiB",
        "kb": "kb", "Kb": "kb", "Mb": "Mb", "Gb": "Gb", "Tb": "Tb",
        "ms": "ms", "s": "s", "sec": "s", "secs": "s", "min": "min", "mins": "min",
        "h": "h", "hr": "h", "hrs": "h", "wk": "week", "wks": "week", "yr": "year", "yrs": "year",
        "°C": "°C", "C": "°C", "°F": "°F", "F": "°F", "K": "K",
        "°": "°", "deg": "°", "rad": "rad",
        "ha": "ha", "L": "L", "l": "L", "mL": "mL", "ml": "mL", "cl": "cL", "cL": "cL",
        "tsp": "tsp", "tbsp": "tbsp", "gal": "gal",
        "m²": "sq m", "cm²": "sq cm", "mm²": "sq mm", "km²": "sq km", "ft²": "sq ft", "in²": "sq in",
        "yd²": "sq yd", "mi²": "sq mi",
        "m³": "cu m", "cm³": "cu cm", "mm³": "cu mm", "ft³": "cu ft", "in³": "cu in", "yd³": "cu yd",
        "cc": "cu cm", "sqm": "sq m", "sqft": "sq ft", "sqkm": "sq km", "cbm": "cu m", "cbft": "cu ft",
        "pt": "pt", "px": "px", "em": "em", "rem": "em", "ct": "ct",
    ]

    /// Spelled-out names, matched case-insensitively.
    static let names: [String: String] = {
        var n: [String: String] = [:]
        func add(_ id: String, _ words: String...) { for w in words { n[w] = id } }
        add("mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add("cm", "centimeter", "centimeters", "centimetre", "centimetres")
        add("dm", "decimeter", "decimeters", "decimetre", "decimetres")
        add("m", "meter", "meters", "metre", "metres")
        add("km", "kilometer", "kilometers", "kilometre", "kilometres")
        add("µm", "micrometer", "micrometers", "micron", "microns")
        add("in", "inch", "inches")
        add("ft", "foot", "feet")
        add("yd", "yard", "yards")
        add("mi", "mile", "miles")
        add("nmi", "nautical mile", "nautical miles")
        add("pt", "point", "points")
        add("px", "pixel", "pixels")
        add("mil", "mil", "mils", "thou")
        add("hand", "hand", "hands")
        add("rod", "rod", "rods")
        add("chain", "chain", "chains")
        add("furlong", "furlong", "furlongs")
        add("cable", "cable", "cables")
        add("league", "league", "leagues")
        add("ct", "carat", "carats")
        add("centner", "centner", "centners")
        add("are", "are", "ares")
        add("decade", "decade", "decades")
        add("century", "century", "centuries")
        add("mg", "milligram", "milligrams")
        add("g", "gram", "grams", "gramme", "grammes")
        add("kg", "kilogram", "kilograms", "kilo", "kilos")
        add("t", "tonne", "tonnes", "metric ton", "metric tons")
        add("oz", "ounce", "ounces")
        add("lb", "pound", "pounds")
        add("st", "stone", "stones")
        add("bit", "bit", "bits")
        add("B", "byte", "bytes")
        add("kB", "kilobyte", "kilobytes")
        add("MB", "megabyte", "megabytes")
        add("GB", "gigabyte", "gigabytes")
        add("TB", "terabyte", "terabytes")
        add("PB", "petabyte", "petabytes")
        add("KiB", "kibibyte", "kibibytes")
        add("MiB", "mebibyte", "mebibytes")
        add("GiB", "gibibyte", "gibibytes")
        add("TiB", "tebibyte", "tebibytes")
        add("kb", "kilobit", "kilobits")
        add("Mb", "megabit", "megabits")
        add("Gb", "gigabit", "gigabits")
        add("ms", "millisecond", "milliseconds")
        add("s", "second", "seconds")
        add("min", "minute", "minutes")
        add("h", "hour", "hours")
        add("day", "day", "days")
        add("week", "week", "weeks")
        add("month", "month", "months")
        add("year", "year", "years")
        add("°C", "celsius", "centigrade")
        add("°F", "fahrenheit")
        add("K", "kelvin", "kelvins")
        add("°", "degree", "degrees")
        add("rad", "radian", "radians")
        add("ha", "hectare", "hectares")
        add("acre", "acre", "acres")
        add("L", "liter", "liters", "litre", "litres")
        add("mL", "milliliter", "milliliters", "millilitre", "millilitres")
        add("cL", "centiliter", "centiliters", "centilitre", "centilitres")
        add("tsp", "teaspoon", "teaspoons")
        add("tbsp", "tablespoon", "tablespoons")
        add("cup", "cup", "cups")
        add("pint", "pint", "pints")
        add("quart", "quart", "quarts")
        add("gal", "gallon", "gallons")
        return n
    }()

    /// The unit a single word names, if any.
    public static func lookup(_ word: String) -> PhysicalUnit? {
        if let id = symbols[word] { return byID[id] }
        if let id = names[word.lowercased()] { return byID[id] }
        return nil
    }

    /// `sq ft`, `square feet`, `cubic meters`.
    static func compound(prefix: String, length word: String) -> PhysicalUnit? {
        let p = prefix.lowercased()
        guard let unit = lookup(word), unit.dimension == .length else { return nil }
        switch p {
        case "sq", "square": return byID["sq \(unit.id)"]
        case "cu", "cubic": return byID["cu \(unit.id)"]
        default: return nil
        }
    }

    static func isCompoundPrefix(_ word: String) -> Bool {
        ["sq", "square", "cu", "cubic"].contains(word.lowercased())
    }

    /// The area or volume unit made from a length unit (`ft` → `ft²`).
    static func power(of length: PhysicalUnit, _ n: Int) -> PhysicalUnit? {
        guard length.dimension == .length else { return nil }
        switch n {
        case 2: return byID["sq \(length.id)"]
        case 3: return byID["cu \(length.id)"]
        default: return nil
        }
    }

    /// Compound units written as one word: `mph`, `kph`, `knots`, `Mbps`.
    static let rateAliases: [String: RateUnit] = {
        func rate(_ num: String, _ den: String, _ alias: String?) -> RateUnit {
            RateUnit(.unit(byID[num]!), per: byID[den]!, alias: alias)
        }
        let mph = rate("mi", "h", "mph"), kph = rate("km", "h", nil), knots = rate("nmi", "h", "knots")
        return [
            "mph": mph, "kph": kph, "kmh": kph, "kmph": kph, "knot": knots, "knots": knots, "kn": knots,
            "kbps": rate("kb", "s", nil), "Mbps": rate("Mb", "s", nil), "Gbps": rate("Gb", "s", nil),
            "mps": rate("m", "s", nil),
        ]
    }()

    /// A one-word compound unit.
    static func rateAlias(_ word: String) -> RateUnit? {
        rateAliases[word]
    }
}
