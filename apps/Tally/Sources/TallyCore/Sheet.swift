import Foundation

/// One line's outcome.
public enum LineResult: Equatable, Sendable {
    /// Nothing to show: blank, header, comment, text or a half-typed calculation.
    case none
    case value(Quantity)
    case error(EvalError)

    public var quantity: Quantity? {
        if case .value(let q) = self { return q }
        return nil
    }

    public var error: EvalError? {
        if case .error(let e) = self { return e }
        return nil
    }
}

public struct LineOutput: Equatable, Sendable {
    public var result: LineResult
    /// The value used a downloaded exchange rate (so it can be marked when rates are stale).
    public var usesDownloadedRates: Bool
    /// The line defines a variable (`name = ...`).
    public var assignedName: String?

    public init(result: LineResult, usesDownloadedRates: Bool = false, assignedName: String? = nil) {
        self.result = result
        self.usesDownloadedRates = usesDownloadedRates
        self.assignedName = assignedName
    }
}

/// Settings and data a sheet is evaluated with.
public struct SheetContext: Equatable, Sendable {
    public var rates: RatesState
    /// The currency `$` and "dollars" mean.
    public var dollarCode: String

    public init(rates: RatesState = .off, dollarCode: String = "USD") {
        self.rates = rates
        self.dollarCode = dollarCode
    }
}

/// Evaluates a whole sheet top to bottom. Every edit re-evaluates everything, so a renamed
/// or moved variable can never leave a stale value behind. Parsing is cached per line text,
/// which keeps a 1,000-line sheet well under a frame.
public final class SheetEngine {
    private var cache: [String: ParsedLine] = [:]

    public init() {}

    public func evaluate(_ text: String, context: SheetContext = SheetContext()) -> [LineOutput] {
        evaluate(lines: Self.lines(of: text), context: context)
    }

    public static func lines(of text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public func evaluate(lines: [String], context: SheetContext = SheetContext()) -> [LineOutput] {
        if cache.count > 20_000 { cache.removeAll(keepingCapacity: true) }
        var state = EvalState(context: context)
        var outputs: [LineOutput] = []
        outputs.reserveCapacity(lines.count)
        for line in lines {
            let parsed: ParsedLine
            if let hit = cache[line] {
                parsed = hit
            } else {
                parsed = Parser.parseLine(line)
                cache[line] = parsed
            }
            outputs.append(state.run(parsed))
        }
        return outputs
    }
}

/// Variables, `prev`, the current sum block and sheet-defined rates while walking a sheet.
struct EvalState {
    var variables: [String: Quantity] = [:]
    var prev: Quantity?
    var block: [Quantity] = []
    var manual = ManualRates()
    let context: SheetContext

    init(context: SheetContext) {
        self.context = context
    }

    mutating func run(_ line: ParsedLine) -> LineOutput {
        switch line {
        case .blank, .header:
            block.removeAll()
            return LineOutput(result: .none)
        case .comment, .text:
            return LineOutput(result: .none)
        case .reservedName(let name, let kind):
            return LineOutput(result: .error(.reservedName(name, kind: kind)))
        case .expression(let expr):
            return finish(expr, name: nil)
        case .assignment(let name, let expr):
            return finish(expr, name: name)
        case .rate(let lhs, let rhs):
            return defineRate(lhs, rhs)
        }
    }

    private mutating func finish(_ expr: Expr, name: String?) -> LineOutput {
        var math = makeArithmetic()
        do {
            let q = try eval(expr, &math)
            if let name { variables[name] = q }
            prev = q
            if !expr.containsBlockAggregate { block.append(q) }
            return LineOutput(result: .value(q), usesDownloadedRates: math.usedTable, assignedName: name)
        } catch let error as EvalError {
            if let name { variables[name] = nil }
            return LineOutput(result: .error(error), assignedName: name)
        } catch {
            if let name { variables[name] = nil }
            return LineOutput(result: .none, assignedName: name)
        }
    }

    private mutating func defineRate(_ lhs: Expr, _ rhs: Expr) -> LineOutput {
        var math = makeArithmetic()
        guard let a = try? eval(lhs, &math), let b = try? eval(rhs, &math),
              let from = a.currency, let to = b.currency, from != to, !a.value.isZero, b.value > 0
        else { return LineOutput(result: .none) }
        do {
            try manual.set(from, to, try DecimalMath.divide(b.value, a.value))
            return LineOutput(result: .value(b))
        } catch {
            return LineOutput(result: .error(error))
        }
    }

    private func makeArithmetic() -> Arithmetic {
        Arithmetic(converter: CurrencyConverter(state: context.rates, manual: manual), dollar: context.dollarCode)
    }

    private func eval(_ e: Expr, _ m: inout Arithmetic) throws -> Quantity {
        switch e {
        case .number(let n), .constant(let n):
            return Quantity(n)
        case .name(let name, let strict):
            if let v = variables[name] { return Quantity(v.value, v.tag) }
            if strict { throw EvalError.unknownName(name) }
            throw NotACalculation()
        case .tagged(let inner, let tag):
            return try m.tag(try eval(inner, &m), with: tag)
        case .negate(let inner):
            let q = try eval(inner, &m)
            return Quantity(-q.value, q.tag)
        case .binary(let op, let a, let b):
            let x = try eval(a, &m), y = try eval(b, &m)
            switch op {
            case .add: return try m.add(x, y)
            case .subtract: return try m.add(x, y, subtract: true)
            case .multiply: return try m.multiply(x, y)
            case .divide: return try m.divide(x, y)
            case .modulo: return try m.modulo(x, y)
            case .power: return try m.power(x, y)
            }
        case .percentOp(let op, let p, let a):
            return try m.percentOf(op, try eval(p, &m), try eval(a, &m))
        case .asPercentOf(let a, let b):
            return try m.asPercent(try eval(a, &m), of: try eval(b, &m))
        case .percent(let inner):
            let q = try eval(inner, &m)
            guard q.isPlain else { throw EvalError.incompatibleUnits }
            return Quantity(try DecimalMath.divide(q.value, 100), .percent)
        case .factorial(let inner):
            let q = try eval(inner, &m)
            guard q.isPlain else { throw EvalError.incompatibleUnits }
            return Quantity(try DecimalMath.factorial(q.value))
        case .convert(let inner, let target):
            return try m.convert(try eval(inner, &m), to: target)
        case .call(let fn, let args):
            return try m.call(fn, try args.map { try eval($0, &m) })
        case .aggregate(let agg):
            switch agg {
            case .prev:
                guard let prev else { throw NotACalculation() }
                return Quantity(prev.value, prev.tag)
            case .sum, .average:
                guard var total = block.first else {
                    if agg == .sum { return Quantity(0) }
                    throw NotACalculation()
                }
                total.style = .auto
                for q in block.dropFirst() { total = try m.add(total, q) }
                if agg == .average { total = try m.divide(total, Quantity(Decimal(block.count))) }
                return total
            }
        case .mixed(let parts):
            var total = try eval(parts[0], &m)
            for p in parts.dropFirst() { total = try m.add(total, try eval(p, &m)) }
            return total
        }
    }
}
