import Foundation

enum BinaryOp: Sendable { case add, subtract, multiply, divide, modulo, power }
enum PercentOp: Sendable { case of, on, off }
enum Aggregate: Sendable { case prev, sum, average }

enum TagRef: Sendable, Equatable {
    case unit(PhysicalUnit)
    case currency(CurrencyRef)
}

enum Target: Sendable, Equatable {
    case unit(PhysicalUnit)
    case currency(CurrencyRef)
    case percent
    case style(NumberStyle)
}

enum MathFunction: String, Sendable, CaseIterable {
    case sqrt, cbrt, abs, round, ceil, floor, ln, log, exp, sin, cos, tan, asin, acos, atan, fact
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
    case asPercentOf(Expr, Expr)
    case percent(Expr)
    case factorial(Expr)
    case convert(Expr, Target)
    case call(MathFunction, [Expr])
    case aggregate(Aggregate)
    case mixed([Expr])

    var containsBlockAggregate: Bool {
        switch self {
        case .aggregate(let a): a != .prev
        case .number, .constant, .name: false
        case .tagged(let e, _), .negate(let e), .percent(let e), .factorial(let e), .convert(let e, _): e.containsBlockAggregate
        case .binary(_, let a, let b), .percentOp(_, let a, let b), .asPercentOf(let a, let b):
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
    ]
    static let functions: [String: MathFunction] = Dictionary(uniqueKeysWithValues: MathFunction.allCases.map { ($0.rawValue, $0) })
        .merging(["sqr": .sqrt, "root": .sqrt, "factorial": .fact], uniquingKeysWith: { a, _ in a })

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
        if aggregates[lower] != nil { return "a built-in word" }
        if functions[lower] != nil { return "a function" }
        if Units.lookup(word) != nil || Units.isCompoundPrefix(word) { return "a unit" }
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
}
