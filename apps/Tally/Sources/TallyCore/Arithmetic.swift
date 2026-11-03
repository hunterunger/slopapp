import Foundation

/// Arithmetic on quantities: unit conversion, percent rules, currency.
struct Arithmetic {
    var converter: CurrencyConverter
    var dollar: String
    /// Set when a downloaded rate was used, so the UI can mark stale results.
    var usedTable = false

    typealias D = DecimalMath

    // MARK: Conversion

    func convert(_ q: Quantity, to unit: PhysicalUnit) throws(EvalError) -> Quantity {
        switch q.tag {
        case .none: return Quantity(q.value, .unit(unit))
        case .unit(let u) where u.dimension == unit.dimension:
            if u == unit { return Quantity(q.value, q.tag) }
            return Quantity(try unit.fromBase(try u.toBase(q.value)), .unit(unit))
        default: throw .incompatibleUnits
        }
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
        case (_, .none): return Quantity(try D.divide(a.value, b.value), a.tag)
        case (.percent, .percent): return Quantity(try D.divide(a.value, b.value))
        case (.percent, _), (.none, _): throw .incompatibleUnits
        case (_, .percent): return Quantity(try D.divide(a.value, b.value), a.tag)
        case (.unit(let u1), .unit(let u2)) where u1.dimension != u2.dimension:
            return try divideUnits(a, u1, b, u2)
        default:
            return Quantity(try D.divide(a.value, try align(b, to: a)))
        }
    }

    /// area ÷ length = length, volume ÷ length = area, volume ÷ area = length.
    private func divideUnits(_ a: Quantity, _ u1: PhysicalUnit, _ b: Quantity, _ u2: PhysicalUnit) throws(EvalError) -> Quantity {
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
            throw .incompatibleUnits
        }
    }

    mutating func modulo(_ a: Quantity, _ b: Quantity) throws(EvalError) -> Quantity {
        switch (a.tag, b.tag) {
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
        case .currency:
            guard b.value == 1 else { throw .incompatibleUnits }
            return a
        }
    }

    func percentOf(_ op: PercentOp, _ p: Quantity, _ a: Quantity) throws(EvalError) -> Quantity {
        guard p.isPercent, !a.isPercent else { throw .incompatibleUnits }
        let factor: Decimal
        switch op {
        case .of: factor = p.value
        case .on: factor = try D.add(1, p.value)
        case .off: factor = try D.subtract(1, p.value)
        }
        return Quantity(try D.multiply(a.value, factor), a.tag)
    }

    mutating func asPercent(_ a: Quantity, of b: Quantity) throws(EvalError) -> Quantity {
        let ratio = try divide(a, b)
        guard ratio.isPlain else { throw .incompatibleUnits }
        return Quantity(ratio.value, .percent)
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
        }
    }

    mutating func convert(_ q: Quantity, to target: Target) throws(EvalError) -> Quantity {
        switch target {
        case .unit(let u): return try convert(Quantity(q.value, q.tag), to: u)
        case .currency(let ref): return try convert(Quantity(q.value, q.tag), toCurrency: ref.resolve(dollar: dollar))
        case .percent:
            guard q.isPlain || q.isPercent else { throw .incompatibleUnits }
            return Quantity(q.value, .percent)
        case .style(let style):
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
