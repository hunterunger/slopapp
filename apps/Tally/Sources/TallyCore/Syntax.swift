import Foundation

enum BinaryOp: Sendable { case add, subtract, multiply, divide, modulo, power, bitAnd, bitOr, bitXor, shiftLeft, shiftRight }
enum PercentOp: Sendable { case of, on, off }
enum Aggregate: Sendable { case prev, sum, average }

enum TagRef: Sendable, Equatable {
    case unit(PhysicalUnit)
    case currency(CurrencyRef)
    case rate(RateUnit)
}

enum Target: Sendable, Equatable {
    case unit(PhysicalUnit)
    case currency(CurrencyRef)
    /// `in km/h`, `in $/h`
    case rate(RateRef)
    case percent
    case style(NumberStyle)
    case zone(ZoneRef)
    /// Seconds since 1970.
    case unix
}

/// A compound unit as written; `$` resolves later.
enum RateRef: Sendable, Equatable {
    case unit(RateUnit)
    case currency(CurrencyRef, per: PhysicalUnit)
}

/// The words that start or end a date: `now`, `today`...
enum DateWord: Sendable { case now, today, tomorrow, yesterday }

enum MathFunction: String, Sendable, CaseIterable {
    case sqrt, cbrt, root, abs, round, ceil, floor, ln, log, exp, sin, cos, tan, asin, acos, atan
    case sinh, cosh, tanh, fact, fromunix
}

indirect enum Expr: Sendable, Equatable {
    case number(Decimal)
    case constant(Decimal)
    /// A variable. `strict`: if it isn't defined, the line is an error ("unknown name")
    /// rather than plain text.
    case name(String, strict: Bool)
    case tagged(Expr, TagRef)
    case negate(Expr)
    case binary(BinaryOp, Expr, Expr)
    case percentOp(PercentOp, Expr, Expr)
    /// `a as % of b`, `a as % on b`, `a as % off b`
    case asPercent(PercentOp, Expr, Expr)
    /// `5% of what is 6`: solves for the base.
    case percentBase(PercentOp, Expr, Expr)
    /// Divides by one of a unit: `km / h`, `$25 per hour`.
    case per(Expr, PhysicalUnit)
    case dateWord(DateWord)
    /// A wall-clock time today, in a zone (or the Mac's).
    case timeOfDay(hour: Int, minute: Int, second: Int, zone: ZoneRef?)
    /// A calendar day; the year defaults to this year.
    case calendarDay(year: Int?, month: Int, day: Int)
    /// The time now in a zone: `Tokyo time`, `time in Madrid`.
    case zoneNow(ZoneRef)
    case percent(Expr)
    case factorial(Expr)
    case convert(Expr, Target)
    case call(MathFunction, [Expr])
    case aggregate(Aggregate)
    case mixed([Expr])

    var containsBlockAggregate: Bool {
        switch self {
        case .aggregate(let a): a != .prev
        case .number, .constant, .name, .dateWord, .timeOfDay, .calendarDay, .zoneNow: false
        case .tagged(let e, _), .negate(let e), .percent(let e), .factorial(let e), .convert(let e, _), .per(let e, _):
            e.containsBlockAggregate
        case .binary(_, let a, let b), .percentOp(_, let a, let b), .asPercent(_, let a, let b), .percentBase(_, let a, let b):
            a.containsBlockAggregate || b.containsBlockAggregate
        case .call(_, let args), .mixed(let args): args.contains { $0.containsBlockAggregate }
        }
    }
}

/// Reserved words. Matched case-insensitively.
enum Words {
    static let aggregates: [String: Aggregate] = [
        "prev": .prev, "previous": .prev, "sum": .sum, "total": .sum, "avg": .average, "average": .average,
    ]
    static let scales: [String: Decimal] = [
        "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
    ]
    static let styles: [String: NumberStyle] = [
        "hex": .hex, "hexadecimal": .hex, "bin": .binary, "binary": .binary, "oct": .octal, "octal": .octal,
        "dec": .auto, "decimal": .auto, "sci": .scientific, "scientific": .scientific,
    ]
    static let conversions: Set<String> = ["in", "to", "as", "into"]
    static let operators: Set<String> = [
        "plus", "minus", "times", "mod", "of", "on", "off", "divided", "multiplied", "by", "percent",
        "and", "with", "without", "mul", "divide", "xor", "per", "what", "is",
    ]
    /// Operators that don't make a neighbouring unknown word an error.
    static let softOperators: Set<String> = ["and", "with", "without", "is", "what", "per"]
    static let dateWords: [String: DateWord] = [
        "now": .now, "today": .today, "tomorrow": .tomorrow, "yesterday": .yesterday,
    ]
    static let functions: [String: MathFunction] = Dictionary(uniqueKeysWithValues: MathFunction.allCases.map { ($0.rawValue, $0) })
        .merging(["sqr": .sqrt, "factorial": .fact, "arcsin": .asin, "arccos": .acos, "arctan": .atan],
                 uniquingKeysWith: { a, _ in a })

    static func constant(_ word: String) -> Decimal? {
        switch word {
        case "pi", "π", "PI", "Pi": DecimalMath.pi
        case "e": DecimalMath.e
        default: nil
        }
    }

    /// Why `word` can't be a variable name, or nil if it can.
    static func reservedKind(_ word: String) -> String? {
        let lower = word.lowercased()
        if constant(word) != nil || lower == "pi" { return "a constant" }
        if aggregates[lower] != nil || dateWords[lower] != nil { return "a built-in word" }
        if functions[lower] != nil { return "a function" }
        if Units.lookup(word) != nil || Units.isCompoundPrefix(word) || Units.rateAlias(word) != nil { return "a unit" }
        if Currencies.lookup(word) != nil { return "a currency" }
        if conversions.contains(lower) || operators.contains(lower) || scales[lower] != nil || styles[lower] != nil {
            return "a built-in word"
        }
        return nil
    }
}

/// One parsed line.
enum ParsedLine: Sendable {
    case blank
    case header
    case comment
    /// Not a calculation (unknown words, half-typed): shows nothing.
    case text
    case expression(Expr)
    case assignment(String, Expr)
    case reservedName(String, kind: String)
    /// `1 USD = 1.37 CAD`
    case rate(Expr, Expr)
    /// `em = 20px`, `ppi = 326`: changes how px and em convert for the lines below.
    case cssSetting(CSSSetting, Expr)
}

enum CSSSetting: String, Sendable { case em, ppi }
