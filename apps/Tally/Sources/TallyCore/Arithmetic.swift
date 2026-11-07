import Foundation

/// Arithmetic on quantities: unit conversion, percent rules, currency.
struct Arithmetic {
    var converter: CurrencyConverter
    var dollar: String
    /// How `px` and `em` convert.
    var css: CSSMetrics = .standard
    /// The Mac's zone, for `fromunix`.
    var localZone: TimeZone = .current
    /// Set when a downloaded rate was used, so the UI can mark stale results.
    var usedTable = false

    typealias D = DecimalMath

    // MARK: Conversion

    func convertValue(_ value: Decimal, from u: PhysicalUnit, to unit: PhysicalUnit) throws(EvalError) -> Decimal {
        guard u.dimension == unit.dimension else { throw .incompatibleUnits }
        if u == unit { return value }
        return try unit.fromBase(try u.toBase(value, css: css), css: css)
    }

    func convert(_ q: Quantity, to unit: PhysicalUnit) throws(EvalError) -> Quantity {
        switch q.tag {
        case .none: return Quantity(q.value, .unit(unit))
        case .unit(let u): return Quantity(try convertValue(q.value, from: u, to: unit), .unit(unit))
        default: throw .incompatibleUnits
        }
    }

    /// A rate's value in another rate unit of the same kind: 60 km/h → 16.67 m/s.
    mutating func convertRate(_ value: Decimal, from r: RateUnit, to t: RateUnit) throws(EvalError) -> Decimal {
        guard r.isCompatible(with: t) else { throw .incompatibleUnits }
        let numerator: Decimal
        switch (r.numerator, t.numerator) {
        case (.unit(let a), .unit(let b)): numerator = try convertValue(value, from: a, to: b)
        case (.currency(let a), .currency(let b)): numerator = try convert(Quantity(value, .currency(a)), toCurrency: b).value
        default: throw .incompatibleUnits
        }
        // Per one of the target's denominator: multiply by its size in the source's denominator.
        return try D.multiply(numerator, try convertValue(1, from: t.denominator, to: r.denominator))
    }

    mutating func convert(_ q: Quantity, toCurrency code: String) throws(EvalError) -> Quantity {
        switch q.tag {
        case .none: return Quantity(q.value, .currency(code))
        case .currency(let from):
            if from == code { return Quantity(q.value, q.tag) }
            let (rate, usedTable) = try converter.rate(from: from, to: code)
            if usedTable { self.usedTable = true }
            return Quantity(try D.multiply(q.value, rate), .currency(code))
        default: throw .incompatibleUnits
        }
    }

    /// `b` expressed in `a`'s unit or currency, for + - / mod.
    private mutating func align(_ b: Quantity, to a: Quantity) throws(EvalError) -> Decimal {
        switch (a.tag, b.tag) {
        case (.unit(let u), .unit): return try convert(b, to: u).value
        case (.currency(let c), .currency): return try convert(b, toCurrency: c).value
        case (.rate(let r1), .rate(let r2)): return try convertRate(b.value, from: r2, to: r1)
        case (let x, let y) where x == y: return b.value
        default: throw .incompatibleUnits
        }
    }

    // MARK: Operators

    mutating func add(_ a: Quantity, _ b: Quantity, subtract: Bool = false) throws(EvalError) -> Quantity {
        func op(_ x: Decimal, _ y: Decimal) throws(EvalError) -> Decimal {
            subtract ? try D.subtract(x, y) : try D.add(x, y)
        }
        switch (a.tag, b.tag) {
        case (.date(let d), .unit(let u)) where u.dimension == .time:
            return try shift(a, d, by: b.value, u, negate: subtract)
        case (.unit(let u), .date(let d)) where u.dimension == .time && !subtract:
            return try shift(b, d, by: a.value, u, negate: false)
        case (.date(let d1), .date(let d2)) where subtract:
            return try difference(a, d1, b, d2)
        case (.date, _), (_, .date):
            throw .incompatibleUnits
        case (.percent, .percent):
            return Quantity(try op(a.value, b.value), .percent)
        case (_, .percent):
            // 150 + 20% = 180
            return Quantity(try D.multiply(a.value, try op(1, b.value)), a.tag)
        case (.percent, _):
            throw .incompatibleUnits
        case (.none, _):
            return Quantity(try op(a.value, b.value), b.tag)
        case (_, .none):
            return Quantity(try op(a.value, b.value), a.tag)
        default:
            return Quantity(try op(a.value, try align(b, to: a)), a.tag)
        }
    }

    mutating func multiply(_ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        switch (a.tag, b.tag) {
        case (.date, _), (_, .date): throw .incompatibleUnits
        case (.rate(let r), .unit(let u)): return try rateTimes(a.value, r, b.value, u)
        case (.unit(let u), .rate(let r)): return try rateTimes(b.value, r, a.value, u)
        case (.percent, .percent): return Quantity(try D.multiply(a.value, b.value), .percent)
        case (_, .percent): return Quantity(try D.multiply(a.value, b.value), a.tag)
        case (.percent, _): return Quantity(try D.multiply(a.value, b.value), b.tag)
        case (.none, _): return Quantity(try D.multiply(a.value, b.value), b.tag)
        case (_, .none): return Quantity(try D.multiply(a.value, b.value), a.tag)
        case (.unit(let u1), .unit(let u2)):
            return try multiplyUnits(a, u1, b, u2)
        default: throw .incompatibleUnits
        }
    }

    /// 60 km/h × 3 h = 180 km; $25/h × 40 h = $1,000.
    private func rateTimes(_ rv: Decimal, _ r: RateUnit, _ uv: Decimal, _ u: PhysicalUnit) throws(EvalError) -> Quantity {
        let amount = try convertValue(uv, from: u, to: r.denominator)
        return Quantity(try D.multiply(rv, amount), r.numerator.tag)
    }

    /// length × length = area, area × length = volume (in the left unit's terms).
    private func multiplyUnits(_ a: Quantity, _ u1: PhysicalUnit, _ b: Quantity, _ u2: PhysicalUnit) throws(EvalError) -> Quantity {
        switch (u1.dimension, u2.dimension) {
        case (.length, .length):
            let bv = try convert(b, to: u1).value
            guard let area = Units.power(of: u1, 2) else { throw .incompatibleUnits }
            return Quantity(try D.multiply(a.value, bv), .unit(area))
        case (.area, .length):
            let length = u1.lengthBase.flatMap(Units.unit(id:)) ?? Units.unit(id: "m")!
            let av = try convert(a, to: Units.power(of: length, 2)!).value
            let bv = try convert(b, to: length).value
            return Quantity(try D.multiply(av, bv), .unit(Units.power(of: length, 3)!))
        case (.length, .area):
            let bv = try convert(b, to: Units.power(of: u1, 2)!).value
            return Quantity(try D.multiply(a.value, bv), .unit(Units.power(of: u1, 3)!))
        default:
            throw .incompatibleUnits
        }
    }

    mutating func divide(_ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        if b.value.isZero { throw .divisionByZero }
        switch (a.tag, b.tag) {
        case (.date, _), (_, .date): throw .incompatibleUnits
        case (_, .none): return Quantity(try D.divide(a.value, b.value), a.tag)
        case (.percent, .percent): return Quantity(try D.divide(a.value, b.value))
        case (.percent, _), (.none, _): throw .incompatibleUnits
        case (_, .percent): return Quantity(try D.divide(a.value, b.value), a.tag)
        case (.unit(let u1), .unit(let u2)) where u1.dimension != u2.dimension:
            if let q = try divideUnits(a, u1, b, u2) { return q }
            return Quantity(try D.divide(a.value, b.value), .rate(RateUnit(.unit(u1), per: u2)))
        case (.currency(let c), .unit(let u)):
            return Quantity(try D.divide(a.value, b.value), .rate(RateUnit(.currency(c), per: u)))
        case (.unit, .rate(let r)), (.currency, .rate(let r)):
            // 100 km ÷ 50 km/h = 2 h
            let top = try align(a, to: Quantity(1, r.numerator.tag))
            return Quantity(try D.divide(top, b.value), .unit(r.denominator))
        default:
            return Quantity(try D.divide(a.value, try align(b, to: a)))
        }
    }

    /// area ÷ length = length, volume ÷ length = area, volume ÷ area = length; nil for other
    /// pairs (which make a rate).
    private func divideUnits(_ a: Quantity, _ u1: PhysicalUnit, _ b: Quantity, _ u2: PhysicalUnit) throws(EvalError) -> Quantity? {
        switch (u1.dimension, u2.dimension) {
        case (.area, .length):
            let av = try convert(a, to: Units.power(of: u2, 2)!).value
            return Quantity(try D.divide(av, b.value), .unit(u2))
        case (.volume, .length):
            let av = try convert(a, to: Units.power(of: u2, 3)!).value
            return Quantity(try D.divide(av, b.value), .unit(Units.power(of: u2, 2)!))
        case (.volume, .area):
            let length = u2.lengthBase.flatMap(Units.unit(id:)) ?? Units.unit(id: "m")!
            let av = try convert(a, to: Units.power(of: length, 3)!).value
            let bv = try convert(b, to: Units.power(of: length, 2)!).value
            return Quantity(try D.divide(av, bv), .unit(length))
        default:
            return nil
        }
    }

    mutating func modulo(_ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        switch (a.tag, b.tag) {
        case (.date, _), (_, .date): throw .incompatibleUnits
        case (_, .none): return Quantity(try D.modulo(a.value, b.value), a.tag)
        case (.none, _): throw .incompatibleUnits
        default: return Quantity(try D.modulo(a.value, try align(b, to: a)), a.tag)
        }
    }

    func power(_ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        guard b.isPlain else { throw .incompatibleUnits }
        switch a.tag {
        case .none, .percent:
            return Quantity(try D.power(a.value, b.value), a.tag)
        case .unit(let u):
            if b.value == 1 { return a }
            guard u.dimension == .length, b.value == 2 || b.value == 3,
                  let target = Units.power(of: u, b.value == 2 ? 2 : 3) else { throw .incompatibleUnits }
            return Quantity(try D.power(a.value, b.value), .unit(target))
        case .currency, .rate, .date:
            guard b.value == 1 else { throw .incompatibleUnits }
            return a
        }
    }

    // MARK: Bitwise

    func bitwise(_ op: BinaryOp, _ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        guard a.isPlain, b.isPlain else { throw .incompatibleUnits }
        guard D.isInteger(a.value), D.isInteger(b.value) else { throw .wholeNumberNeeded("bitwise math") }
        let limit = Decimal(Int64.max)
        guard Swift.abs(a.value) <= limit, Swift.abs(b.value) <= limit else { throw .tooLarge }
        let x = NSDecimalNumber(decimal: a.value).int64Value, y = NSDecimalNumber(decimal: b.value).int64Value
        let style = a.style != .auto ? a.style : b.style
        let result: Decimal
        switch op {
        case .bitAnd: result = Decimal(x & y)
        case .bitOr: result = Decimal(x | y)
        case .bitXor: result = Decimal(x ^ y)
        case .shiftLeft, .shiftRight:
            guard (0...63).contains(y) else { throw .wholeNumberNeeded("a shift between 0 and 63") }
            if op == .shiftRight {
                result = Decimal(x >> y)
            } else {
                let (shifted, overflow) = x.multipliedReportingOverflow(by: Int64(1) << y)
                guard !overflow, y < 63 || x == 0 else { throw .tooLarge }
                result = Decimal(shifted)
            }
        default: throw .incompatibleUnits
        }
        return Quantity(result, .none, style: style)
    }

    // MARK: Dates

    /// A date moved by a duration. Days, weeks, months and years move by the calendar (so
    /// `Jan 31 + 1 month` is Feb 28 and DST changes don't shift the time of day).
    func shift(_ q: Quantity, _ tag: DateTag, by amount: Decimal, _ unit: PhysicalUnit, negate: Bool) throws(EvalError) -> Quantity {
        let n = negate ? -amount : amount
        let date = DateMath.date(q.value)
        if D.isInteger(n), Swift.abs(n) < 100_000 {
            let k = NSDecimalNumber(decimal: n).intValue
            let step: (Calendar.Component, Int)? = switch unit.id {
            case "day": (.day, k)
            case "week": (.day, 7 * k)
            case "month": (.month, k)
            case "year": (.year, k)
            case "decade": (.year, 10 * k)
            case "century": (.year, 100 * k)
            default: nil
            }
            if let (component, value) = step,
               let moved = DateMath.calendar(tag.timeZone).date(byAdding: component, value: value, to: date) {
                return Quantity(DateMath.seconds(moved), q.tag)
            }
        }
        let seconds = try unit.toBase(n)
        let result = try D.add(q.value, seconds)
        guard Swift.abs(result) < 1e13 else { throw .tooLarge }
        var newTag = tag
        if tag.style == .date, !D.isInteger(try D.divide(seconds, 86400)) { newTag.style = .dateTime }
        return Quantity(result, .date(newTag))
    }

    /// `a - b` for two dates: whole days between calendar days, otherwise minutes, hours or days.
    func difference(_ a: Quantity, _ da: DateTag, _ b: Quantity, _ db: DateTag) throws(EvalError) -> Quantity {
        if da.style == .date, db.style == .date,
           let days = DateMath.dayDifference(from: DateMath.date(b.value), to: DateMath.date(a.value), zone: da.timeZone) {
            return Quantity(Decimal(days), .unit(Units.unit(id: "day")!))
        }
        let seconds = D.round(try D.subtract(a.value, b.value), scale: 0, mode: .plain)
        let size = Swift.abs(seconds)
        let id = size < 60 ? "s" : size < 3600 ? "min" : size < 86400 ? "h" : "day"
        let unit = Units.unit(id: id)!
        return Quantity(try unit.fromBase(seconds), .unit(unit))
    }

    func percentOf(_ op: PercentOp, _ p: Quantity, _ a: Quantity) throws(EvalError) -> Quantity {
        guard p.isPercent, !a.isPercent, a.date == nil else { throw .incompatibleUnits }
        let factor: Decimal
        switch op {
        case .of: factor = p.value
        case .on: factor = try D.add(1, p.value)
        case .off: factor = try D.subtract(1, p.value)
        }
        return Quantity(try D.multiply(a.value, factor), a.tag)
    }

    /// `a as % of b` = a/b; `a as % on b` = how much a is above b; `a as % off b` = below.
    mutating func asPercent(_ op: PercentOp, _ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        let ratio = try divide(a, b)
        guard ratio.isPlain else { throw .incompatibleUnits }
        switch op {
        case .of: return Quantity(ratio.value, .percent)
        case .on: return Quantity(try D.subtract(ratio.value, 1), .percent)
        case .off: return Quantity(try D.subtract(1, ratio.value), .percent)
        }
    }

    /// `5% of what is 6` = 120; `5% on what is 6` = 6 / 1.05; `5% off what is 6` = 6 / 0.95.
    func percentBase(_ op: PercentOp, _ p: Quantity, _ y: Quantity) throws(EvalError) -> Quantity {
        guard p.isPercent, !y.isPercent, y.date == nil else { throw .incompatibleUnits }
        let factor: Decimal
        switch op {
        case .of: factor = p.value
        case .on: factor = try D.add(1, p.value)
        case .off: factor = try D.subtract(1, p.value)
        }
        return Quantity(try D.divide(y.value, factor), y.tag)
    }

    mutating func tag(_ q: Quantity, with tag: TagRef) throws(EvalError) -> Quantity {
        switch tag {
        case .unit(let u):
            if q.isPlain { return Quantity(q.value, .unit(u)) }
            if q.unit == u { return q }
            throw .incompatibleUnits
        case .currency(let ref):
            let code = ref.resolve(dollar: dollar)
            if q.isPlain || q.currency == code { return Quantity(q.value, .currency(code)) }
            throw .incompatibleUnits
        case .rate(let r):
            if q.isPlain || q.rate == r { return Quantity(q.value, .rate(r)) }
            throw .incompatibleUnits
        }
    }

    mutating func convert(_ q: Quantity, to target: Target) throws(EvalError) -> Quantity {
        switch target {
        case .unit(let u): return try convert(Quantity(q.value, q.tag), to: u)
        case .rate(let ref):
            let unit: RateUnit = switch ref {
            case .unit(let r): r
            case .currency(let c, let per): RateUnit(.currency(c.resolve(dollar: dollar)), per: per)
            }
            switch q.tag {
            case .none: return Quantity(q.value, .rate(unit))
            case .rate(let r): return Quantity(try convertRate(q.value, from: r, to: unit), .rate(unit))
            default: throw .incompatibleUnits
            }
        case .zone(let zone):
            guard var tag = q.date else { throw .incompatibleUnits }
            tag.zone = zone.id
            tag.label = zone.label
            if tag.style == .date { tag.style = .dateTime }
            return Quantity(q.value, .date(tag))
        case .unix:
            guard q.date != nil else { throw .incompatibleUnits }
            return Quantity(D.round(q.value, scale: 0, mode: .down))
        case .currency(let ref): return try convert(Quantity(q.value, q.tag), toCurrency: ref.resolve(dollar: dollar))
        case .percent:
            guard q.isPlain || q.isPercent else { throw .incompatibleUnits }
            return Quantity(q.value, .percent)
        case .style(let style):
            guard q.date == nil else { throw .incompatibleUnits }
            if style == .hex || style == .binary || style == .octal {
                guard D.isInteger(q.value) else {
                    throw .wholeNumberNeeded(style == .hex ? "hex" : style == .binary ? "binary" : "octal")
                }
                guard abs(q.value) <= Decimal(Int64.max) else { throw .tooLarge }
            }
            return Quantity(q.value, q.tag, style: style)
        }
    }

    // MARK: Functions

    func call(_ fn: MathFunction, _ args: [Quantity]) throws -> Quantity {
        func one() throws -> Quantity {
            guard args.count == 1 else { throw NotACalculation() }
            return args[0]
        }
        func plain(_ q: Quantity) throws(EvalError) -> Double {
            guard q.isPlain else { throw .incompatibleUnits }
            return D.toDouble(q.value)
        }
        switch fn {
        case .sqrt:
            let q = try one()
            if case .unit(let u) = q.tag, u.dimension == .area, let lb = u.lengthBase, let l = Units.unit(id: lb) {
                guard q.value >= 0 else { throw EvalError.notReal }
                return Quantity(try D.fromDouble(Foundation.sqrt(D.toDouble(q.value))), .unit(l))
            }
            let x = try plain(q)
            guard x >= 0 else { throw EvalError.notReal }
            return Quantity(try D.fromDouble(Foundation.sqrt(x)))
        case .cbrt:
            return Quantity(try D.fromDouble(Foundation.cbrt(try plain(try one()))))
        case .root:
            guard (1...2).contains(args.count) else { throw NotACalculation() }
            if args.count == 1 { return try call(.sqrt, args) }
            let x = try plain(args[0]), n = try plain(args[1])
            guard n != 0 else { throw EvalError.divisionByZero }
            if x < 0 {
                // Odd roots of negatives are real: root 3 (-8) = -2.
                guard n == n.rounded(), Int(n) % 2 != 0 else { throw EvalError.notReal }
                return Quantity(try D.fromDouble(-Foundation.pow(-x, 1 / n)))
            }
            return Quantity(try D.fromDouble(Foundation.pow(x, 1 / n)))
        case .sinh, .cosh, .tanh:
            let x = try plain(try one())
            return Quantity(try D.fromDouble(fn == .sinh ? Foundation.sinh(x) : fn == .cosh ? Foundation.cosh(x) : Foundation.tanh(x)))
        case .fromunix:
            let x = try plain(try one())
            guard Swift.abs(x) < 1e13 else { throw EvalError.tooLarge }
            return Quantity(args[0].value, .date(DateTag(zone: localZone.identifier, style: .dateTime)))
        case .abs:
            let q = try one()
            return Quantity(Swift.abs(q.value), q.tag)
        case .round, .ceil, .floor:
            guard (1...2).contains(args.count) else { throw NotACalculation() }
            let q = args[0]
            var digits = 0
            if args.count == 2 {
                guard args[1].isPlain, D.isInteger(args[1].value), Swift.abs(args[1].value) <= 30 else {
                    throw EvalError.wholeNumberNeeded(fn.rawValue)
                }
                digits = NSDecimalNumber(decimal: args[1].value).intValue
            }
            let mode: NSDecimalNumber.RoundingMode = fn == .round ? .plain : (fn == .ceil ? .up : .down)
            if q.isPercent {
                let pct = try D.multiply(q.value, 100)
                return Quantity(try D.divide(D.round(pct, scale: digits, mode: mode), 100), .percent)
            }
            return Quantity(D.round(q.value, scale: digits, mode: mode), q.tag)
        case .ln, .log:
            if fn == .log, args.count == 2 {
                let x = try plain(args[0]), base = try plain(args[1])
                guard x > 0, base > 0, base != 1 else { throw EvalError.notReal }
                return Quantity(try D.fromDouble(Foundation.log(x) / Foundation.log(base)))
            }
            let x = try plain(try one())
            guard x > 0 else { throw EvalError.notReal }
            return Quantity(try D.fromDouble(fn == .ln ? Foundation.log(x) : Foundation.log10(x)))
        case .exp:
            return Quantity(try D.fromDouble(Foundation.exp(try plain(try one()))))
        case .sin, .cos, .tan:
            let q = try one()
            let radians: Double
            switch q.tag {
            case .none: radians = D.toDouble(q.value)
            case .unit(let u) where u.dimension == .angle: radians = D.toDouble(try u.toBase(q.value))
            default: throw EvalError.incompatibleUnits
            }
            var r = fn == .sin ? Foundation.sin(radians) : (fn == .cos ? Foundation.cos(radians) : Foundation.tan(radians))
            if Swift.abs(r) < 1e-14 { r = 0 }
            if fn == .tan, Swift.abs(r) > 1e14 { throw EvalError.notReal }
            return Quantity(try D.fromDouble(r))
        case .asin, .acos, .atan:
            let x = try plain(try one())
            if fn != .atan, Swift.abs(x) > 1 { throw EvalError.notReal }
            let r = fn == .asin ? Foundation.asin(x) : (fn == .acos ? Foundation.acos(x) : Foundation.atan(x))
            return Quantity(try D.fromDouble(r), .unit(Units.unit(id: "rad")!))
        case .fact:
            let q = try one()
            guard q.isPlain else { throw EvalError.incompatibleUnits }
            return Quantity(try D.factorial(q.value))
        }
    }
}
