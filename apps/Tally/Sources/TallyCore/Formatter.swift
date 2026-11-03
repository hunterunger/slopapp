import Foundation

/// Turns results into the text shown in the result column (and copied).
///
/// At most 10 significant digits, trailing zeros trimmed, locale grouping on the integer
/// part. Currency rounds to its minor units. Very large or small numbers use `1.5e20`.
public struct ResultFormatter: Sendable {
    public var locale: Locale
    /// Which currency `$` shows for.
    public var dollarCode: String
    public static let significantDigits = 10

    private let groupingSeparator: String
    private let decimalSeparator: String

    public init(locale: Locale = .current, dollarCode: String = "USD") {
        self.locale = locale
        self.dollarCode = dollarCode
        // Input only accepts "." as the decimal point, so results use it too; locales whose
        // decimal mark is "," get a thin space for grouping instead of a confusing ".".
        let localeDecimal = locale.decimalSeparator ?? "."
        let localeGrouping = locale.groupingSeparator ?? ","
        decimalSeparator = "."
        if localeDecimal == "." {
            groupingSeparator = localeGrouping == "." ? "," : localeGrouping
        } else {
            groupingSeparator = "\u{202F}"
        }
    }

    /// The full result text: "1.2 m", "$25.00", "25%", "0xFF".
    public func format(_ q: Quantity) -> String {
        switch q.style {
        case .hex: return integerString(q.value, radix: 16, prefix: "0x") ?? number(q.value)
        case .binary: return integerString(q.value, radix: 2, prefix: "0b") ?? number(q.value)
        case .octal: return integerString(q.value, radix: 8, prefix: "0o") ?? number(q.value)
        case .scientific: return withTag(scientific(q.value), q)
        case .auto: break
        }
        switch q.tag {
        case .none: return number(q.value)
        case .percent: return number(q.value * 100) + "%"
        case .unit(let u):
            let plural = q.value != 1 && q.value != -1
            let label = u.label(plural: plural)
            return u.id == "°" ? number(q.value) + label : "\(number(q.value)) \(label)"
        case .currency(let code): return currency(q.value, code: code)
        }
    }

    /// Just the number, without unit or grouping, for "Copy number only".
    public func plainNumber(_ q: Quantity) -> String {
        let v = q.isPercent ? q.value * 100 : q.value
        if let code = q.currency {
            return trimmed(DecimalMath.round(v, scale: Currencies.minorUnits(code), mode: .plain), fixedScale: Currencies.minorUnits(code), grouping: false)
        }
        return number(v, grouping: false)
    }

    private func withTag(_ text: String, _ q: Quantity) -> String {
        switch q.tag {
        case .none: return text
        case .percent: return text + "%"
        case .unit(let u): return "\(text) \(u.label(plural: true))"
        case .currency(let code): return "\(text) \(code)"
        }
    }

    func currency(_ value: Decimal, code: String) -> String {
        let minor = Currencies.minorUnits(code)
        if magnitude(value).map({ $0 >= 15 }) == true {
            return "\(number(value)) \(code)"
        }
        let rounded = DecimalMath.round(value, scale: minor, mode: .plain)
        let negative = rounded < 0
        let digits = trimmed(abs(rounded), fixedScale: minor, grouping: true)
        let symbol = code == dollarCode ? "$" : Currencies.displaySymbols[code]
        if let symbol {
            return (negative ? "-" : "") + symbol + digits
        }
        return (negative ? "-" : "") + digits + " " + code
    }

    /// A plain number with up to 10 significant digits.
    public func number(_ value: Decimal, grouping: Bool = true) -> String {
        guard let mag = magnitude(value) else { return "0" }
        if mag >= 15 || mag < -9 { return scientific(value) }
        let scale = max(0, Self.significantDigits - 1 - mag)
        let rounded = DecimalMath.round(value, scale: scale, mode: .plain)
        if rounded.isZero { return "0" }
        return trimmed(rounded, fixedScale: nil, grouping: grouping)
    }

    func scientific(_ value: Decimal) -> String {
        guard var mag = magnitude(value) else { return "0" }
        var mantissa = value
        var m = mantissa
        NSDecimalMultiplyByPowerOf10(&mantissa, &m, Int16(-mag), .plain)
        mantissa = DecimalMath.round(mantissa, scale: Self.significantDigits - 1, mode: .plain)
        if abs(mantissa) >= 10 {
            mantissa /= 10
            mag += 1
        }
        return trimmed(mantissa, fixedScale: nil, grouping: false) + "e\(mag)"
    }

    /// Position of the leading digit: 0 for 1–9.99, 3 for 1,000, -2 for 0.01.
    func magnitude(_ value: Decimal) -> Int? {
        if value.isZero { return nil }
        let digits = abs(value).description
        if let dot = digits.firstIndex(of: ".") {
            let intPart = digits[..<dot]
            if intPart != "0" { return intPart.count - 1 }
            let frac = digits[digits.index(after: dot)...]
            let zeros = frac.prefix { $0 == "0" }.count
            return -(zeros + 1)
        }
        return digits.count - 1
    }

    /// Plain notation with optional fixed decimals and grouping.
    private func trimmed(_ value: Decimal, fixedScale: Int?, grouping: Bool) -> String {
        var text = value.description
        var negative = false
        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
        }
        var intPart = text
        var frac = ""
        if let dot = text.firstIndex(of: ".") {
            intPart = String(text[..<dot])
            frac = String(text[text.index(after: dot)...])
        }
        if let fixedScale {
            if frac.count < fixedScale { frac += String(repeating: "0", count: fixedScale - frac.count) }
            if frac.count > fixedScale { frac = String(frac.prefix(fixedScale)) }
        } else {
            while frac.hasSuffix("0") { frac.removeLast() }
        }
        if grouping, intPart.count > 3 {
            var groups: [Substring] = []
            var end = intPart.endIndex
            while end > intPart.startIndex {
                let start = intPart.index(end, offsetBy: -3, limitedBy: intPart.startIndex) ?? intPart.startIndex
                groups.insert(intPart[start..<end], at: 0)
                end = start
            }
            intPart = groups.joined(separator: groupingSeparator)
        }
        let body = frac.isEmpty ? intPart : intPart + decimalSeparator + frac
        if negative, body.contains(where: { $0 != "0" && $0 != "." && $0 != "," }) { return "-" + body }
        return body
    }

    private func integerString(_ value: Decimal, radix: Int, prefix: String) -> String? {
        guard DecimalMath.isInteger(value), abs(value) <= Decimal(Int64.max) else { return nil }
        let n = NSDecimalNumber(decimal: value).int64Value
        let digits = String(n.magnitude, radix: radix, uppercase: true)
        return (n < 0 ? "-" : "") + prefix + digits
    }
}
