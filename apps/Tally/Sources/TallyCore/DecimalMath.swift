import Foundation

/// Exact decimal arithmetic with overflow and divide-by-zero reported as errors instead of
/// NaN. `Double` is used only inside transcendental functions (sin, ln, sqrt...).
enum DecimalMath {
    static let pi = Decimal(string: "3.1415926535897932384626433832795028842", locale: posix)!
    static let e = Decimal(string: "2.7182818284590452353602874713526624978", locale: posix)!
    static let posix = Locale(identifier: "en_US_POSIX")

    static func add(_ a: Decimal, _ b: Decimal) throws(EvalError) -> Decimal {
        var a = a, b = b, r = Decimal()
        try check(NSDecimalAdd(&r, &a, &b, .plain))
        return r
    }

    static func subtract(_ a: Decimal, _ b: Decimal) throws(EvalError) -> Decimal {
        var a = a, b = b, r = Decimal()
        try check(NSDecimalSubtract(&r, &a, &b, .plain))
        return r
    }

    static func multiply(_ a: Decimal, _ b: Decimal) throws(EvalError) -> Decimal {
        var a = a, b = b, r = Decimal()
        try check(NSDecimalMultiply(&r, &a, &b, .plain))
        return r
    }

    static func divide(_ a: Decimal, _ b: Decimal) throws(EvalError) -> Decimal {
        if b.isZero { throw .divisionByZero }
        var a = a, b = b, r = Decimal()
        try check(NSDecimalDivide(&r, &a, &b, .plain))
        return r
    }

    /// Floor modulo: the result has the divisor's sign (`-7 mod 3 = 2`).
    static func modulo(_ a: Decimal, _ b: Decimal) throws(EvalError) -> Decimal {
        if b.isZero { throw .divisionByZero }
        let q = round(try divide(a, b), scale: 0, mode: .down)
        return try subtract(a, try multiply(b, q))
    }

    static func power(_ base: Decimal, _ exponent: Decimal) throws(EvalError) -> Decimal {
        if isInteger(exponent), abs(exponent) <= 100_000 {
            let n = NSDecimalNumber(decimal: exponent).intValue
            if base.isZero {
                if n < 0 { throw .divisionByZero }
                return n == 0 ? 1 : 0
            }
            if base == 1 { return 1 }
            if base == -1 { return n % 2 == 0 ? 1 : -1 }
            var b = base, r = Decimal()
            try check(NSDecimalPower(&r, &b, Swift.abs(n), .plain))
            return n < 0 ? try divide(1, r) : r
        }
        let b = toDouble(base), x = toDouble(exponent)
        if b < 0 { throw .notReal }
        return try fromDouble(Foundation.pow(b, x))
    }

    static func factorial(_ value: Decimal) throws(EvalError) -> Decimal {
        guard isInteger(value), value >= 0 else { throw .wholeNumberNeeded("factorial") }
        guard value <= 200 else { throw .tooLarge }
        var result: Decimal = 1
        var i: Decimal = 2
        while i <= value {
            result = try multiply(result, i)
            i += 1
        }
        return result
    }

    static func round(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var v = value, r = Decimal()
        NSDecimalRound(&r, &v, scale, mode)
        return r
    }

    static func isInteger(_ value: Decimal) -> Bool {
        round(value, scale: 0, mode: .plain) == value
    }

    static func toDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Converts through a 15-significant-digit string so `0.1` stays `0.1` and Double noise
    /// (`0.49999999999999994`) doesn't leak into exact results.
    static func fromDouble(_ value: Double) throws(EvalError) -> Decimal {
        guard value.isFinite else { throw value.isNaN ? .notReal : .tooLarge }
        if Swift.abs(value) > 1e160 { throw .tooLarge }
        if value != 0, Swift.abs(value) < 1e-120 { return 0 }
        guard let d = Decimal(string: String(format: "%.15g", value), locale: posix) else { throw .tooLarge }
        return d
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: posix)!
    }

    private static func check(_ error: NSDecimalNumber.CalculationError) throws(EvalError) {
        switch error {
        case .noError, .lossOfPrecision: return
        case .overflow: throw .tooLarge
        case .underflow: throw .tooSmall
        case .divideByZero: throw .divisionByZero
        @unknown default: throw .tooLarge
        }
    }
}
