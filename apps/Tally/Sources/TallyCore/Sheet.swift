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
    /// The line reads the clock (`now`, `today`, `3pm`), so its answer changes over time.
    public var usesClock: Bool
    /// The line adds up other lines (`sum`, `avg`), so totals skip it.
    public var isAggregate: Bool

    public init(result: LineResult, usesDownloadedRates: Bool = false, assignedName: String? = nil,
                usesClock: Bool = false, isAggregate: Bool = false) {
        self.result = result
        self.usesDownloadedRates = usesDownloadedRates
        self.assignedName = assignedName
        self.usesClock = usesClock
        self.isAggregate = isAggregate
    }
}

/// Settings and data a sheet is evaluated with.
public struct SheetContext: Equatable, Sendable {
    public var rates: RatesState
    /// The currency `$` and "dollars" mean.
    public var dollarCode: String
    /// Pixel density and em size for `px` and `em` (Settings; sheet lines can change them).
    public var css: CSSMetrics
    /// What `now` and `today` mean.
    public var now: Date
    /// The Mac's time zone.
    public var timeZone: TimeZone

    public init(rates: RatesState = .off, dollarCode: String = "USD", css: CSSMetrics = .standard,
                now: Date = Date(), timeZone: TimeZone = .current) {
        self.rates = rates
        self.dollarCode = dollarCode
        self.css = css
        self.now = now
        self.timeZone = timeZone
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

extension SheetEngine {
    /// The total shown under the sheet: the answers of the most common kind (money, length,
    /// plain numbers...) added up in the first such answer's unit or currency. Percentages,
    /// dates and `sum`/`avg` lines are skipped, as are answers that can't be converted, so
    /// a budget with a few unit conversions still totals its money.
    public static func total(of outputs: some Sequence<LineOutput>, context: SheetContext = SheetContext()) -> Quantity? {
        var math = Arithmetic(converter: CurrencyConverter(state: context.rates, manual: ManualRates()),
                              dollar: context.dollarCode, css: context.css, localZone: context.timeZone)
        var groups: [String: [Quantity]] = [:]
        var order: [String] = []
        for output in outputs where !output.isAggregate {
            guard var q = output.result.quantity, let kind = Self.kind(of: q) else { continue }
            q.style = .auto
            if groups[kind] == nil { order.append(kind) }
            groups[kind, default: []].append(q)
        }
        // Most answers wins; ties go to the kind that appears first.
        let most = order.map { groups[$0]!.count }.max() ?? 0
        guard let kind = order.first(where: { groups[$0]!.count == most }),
              let values = groups[kind], var total = values.first else { return nil }
        for q in values.dropFirst() {
            if let sum = try? math.add(total, q) { total = sum }
        }
        return total
    }

    /// What can be added together: plain numbers, a currency (any, converted), a dimension, a
    /// kind of rate. Nil for things a total skips.
    private static func kind(of q: Quantity) -> String? {
        switch q.tag {
        case .none: "number"
        case .percent, .date: nil
        case .currency: "currency"
        case .unit(let u): u.dimension.rawValue
        case .rate(let r): "rate:\(r.numerator.dimensionKey)/\(r.denominator.dimension.rawValue)"
        }
    }
}

/// Variables, `prev`, the current sum block and sheet-defined rates while walking a sheet.
struct EvalState {
    /// Keyed by lower-cased name.
    var variables: [String: Quantity] = [:]
    var prev: Quantity?
    var block: [Quantity] = []
    var manual = ManualRates()
    var css: CSSMetrics
    let context: SheetContext

    init(context: SheetContext) {
        self.context = context
        css = context.css
    }

    /// The variables defined so far, for autocomplete and highlighting.
    var variableNames: Set<String> { Set(variables.keys) }

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
        case .cssSetting(let setting, let expr):
            return setCSS(setting, expr)
        }
    }

    /// `em = 20px` (or a plain number of pixels), `ppi = 326`.
    private mutating func setCSS(_ setting: CSSSetting, _ expr: Expr) -> LineOutput {
        var math = makeArithmetic()
        do {
            let q = try eval(expr, &math)
            let px = Units.unit(id: "px")!
            let shown: Quantity
            switch setting {
            case .em:
                let value = q.isPlain ? q.value : try math.convert(q, to: px).value
                guard value > 0 else { throw EvalError.notReal }
                css.em = value
                shown = Quantity(value, .unit(px))
            case .ppi:
                guard q.isPlain || q.unit == px, q.value > 0 else { throw EvalError.incompatibleUnits }
                css.ppi = q.value
                shown = q
            }
            prev = shown
            block.append(shown)
            return LineOutput(result: .value(shown))
        } catch let error as EvalError {
            return LineOutput(result: .error(error))
        } catch {
            return LineOutput(result: .none)
        }
    }

    private mutating func finish(_ expr: Expr, name: String?) -> LineOutput {
        var math = makeArithmetic()
        do {
            let q = try eval(expr, &math)
            if let name { variables[name.lowercased()] = q }
            prev = q
            if !expr.containsBlockAggregate { block.append(q) }
            return LineOutput(result: .value(q), usesDownloadedRates: math.usedTable, assignedName: name,
                              usesClock: q.date != nil, isAggregate: expr.containsBlockAggregate)
        } catch let error as EvalError {
            if let name { variables[name.lowercased()] = nil }
            return LineOutput(result: .error(error), assignedName: name)
        } catch {
            if let name { variables[name.lowercased()] = nil }
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
        Arithmetic(converter: CurrencyConverter(state: context.rates, manual: manual), dollar: context.dollarCode,
                   css: css, localZone: context.timeZone)
    }

    private func eval(_ e: Expr, _ m: inout Arithmetic) throws -> Quantity {
        switch e {
        case .number(let n), .constant(let n):
            return Quantity(n)
        case .name(let name, let strict):
            // Names match in any case: "Rent = 1200" then "rent / 3".
            if let v = variables[name.lowercased()] { return Quantity(v.value, v.tag) }
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
            case .bitAnd, .bitOr, .bitXor, .shiftLeft, .shiftRight: return try m.bitwise(op, x, y)
            }
        case .percentOp(let op, let p, let a):
            return try m.percentOf(op, try eval(p, &m), try eval(a, &m))
        case .asPercent(let op, let a, let b):
            return try m.asPercent(op, try eval(a, &m), try eval(b, &m))
        case .percentBase(let op, let p, let y):
            return try m.percentBase(op, try eval(p, &m), try eval(y, &m))
        case .per(let inner, let unit):
            return try m.divide(try eval(inner, &m), Quantity(1, .unit(unit)))
        case .dateWord(let word):
            let zone = context.timeZone
            let tag = { (style: DateTag.Style) in Tag.date(DateTag(zone: zone.identifier, style: style)) }
            switch word {
            case .now: return Quantity(DateMath.seconds(context.now), tag(.time))
            case .today, .tomorrow, .yesterday:
                let offset = word == .today ? 0 : (word == .tomorrow ? 1 : -1)
                return Quantity(DateMath.seconds(DateMath.startOfDay(context.now, zone: zone, addingDays: offset)), tag(.date))
            }
        case .timeOfDay(let hour, let minute, let second, let zoneRef):
            let zone = zoneRef.flatMap { DateMath.zone($0.id) } ?? context.timeZone
            guard let date = DateMath.timeToday(hour: hour, minute: minute, second: second, zone: zone, now: context.now) else {
                throw EvalError.invalidDate
            }
            return Quantity(DateMath.seconds(date), .date(DateTag(zone: zone.identifier, label: zoneRef?.label, style: .time)))
        case .calendarDay(let year, let month, let day):
            let zone = context.timeZone
            let y = year ?? DateMath.year(of: context.now, zone: zone)
            guard let date = DateMath.day(year: y, month: month, day: day, zone: zone) else { throw EvalError.invalidDate }
            return Quantity(DateMath.seconds(date), .date(DateTag(zone: zone.identifier, style: .date)))
        case .zoneNow(let zone):
            return Quantity(DateMath.seconds(context.now), .date(DateTag(zone: zone.id, label: zone.label, style: .time)))
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
