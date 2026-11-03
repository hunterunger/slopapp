import Foundation

/// Currency codes, symbols and names. Same-currency math never needs rates; conversions
/// use a `RateTable` (downloaded, opt-in) or rates written in the sheet.
public enum Currencies {
    /// ISO codes Tally recognizes: the ECB reference set plus a few common ones.
    public static let codes: Set<String> = [
        "EUR", "USD", "JPY", "BGN", "CZK", "DKK", "GBP", "HUF", "PLN", "RON", "SEK", "CHF", "ISK",
        "NOK", "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR",
        "NZD", "PHP", "SGD", "THB", "ZAR", "AED", "ARS", "CLP", "COP", "EGP", "NGN", "PKR", "RUB",
        "SAR", "TWD", "UAH", "VND", "KES", "QAR", "MAD", "PEN", "BDT", "HRK",
    ]

    /// Codes whose `$` is the dollar sign. Used for the "$ means" setting.
    public static let dollarCodes = ["USD", "CAD", "AUD", "NZD", "HKD", "SGD", "MXN"]

    static let zeroDecimal: Set<String> = ["JPY", "KRW", "ISK", "CLP", "VND", "HUF", "IDR", "COP"]

    /// Symbols typed or shown in front of a number. `$` is resolved by the "$ means" setting.
    static let symbols: [String: String] = ["€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₺": "TRY", "₽": "RUB"]
    static let displaySymbols: [String: String] = ["EUR": "€", "GBP": "£", "JPY": "¥", "INR": "₹"]

    static let names: [String: CurrencyRef] = [
        "dollar": .dollar, "dollars": .dollar, "bucks": .dollar,
        "euro": .code("EUR"), "euros": .code("EUR"),
        "yen": .code("JPY"), "rupee": .code("INR"), "rupees": .code("INR"),
        "franc": .code("CHF"), "francs": .code("CHF"), "won": .code("KRW"),
        "sterling": .code("GBP"), "quid": .code("GBP"),
    ]

    /// A word naming a currency: an ISO code (all upper or all lower case) or a name.
    static func lookup(_ word: String) -> CurrencyRef? {
        if word.count == 3 {
            let upper = word.uppercased()
            if codes.contains(upper), word == upper || word == word.lowercased() { return .code(upper) }
        }
        return names[word.lowercased()]
    }

    public static func minorUnits(_ code: String) -> Int {
        zeroDecimal.contains(code) ? 0 : 2
    }
}

/// A currency as written: a code, or `$`/"dollars", which depends on the "$ means" setting.
enum CurrencyRef: Hashable, Sendable {
    case code(String)
    case dollar

    func resolve(dollar: String) -> String {
        switch self {
        case .code(let c): c
        case .dollar: dollar
        }
    }
}

/// Exchange rates against one base currency (the ECB publishes EUR-based rates).
public struct RateTable: Equatable, Sendable, Codable {
    /// The publication day, `yyyy-MM-dd`.
    public var date: String
    public var base: String
    public var rates: [String: Decimal]

    public init(date: String, base: String = "EUR", rates: [String: Decimal]) {
        self.date = date
        self.base = base
        self.rates = rates
    }

    /// Units of `code` per one `base`.
    func rate(_ code: String) -> Decimal? {
        code == base ? 1 : rates[code]
    }

    enum CodingKeys: String, CodingKey { case date, base, rates }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        base = try c.decodeIfPresent(String.self, forKey: .base) ?? "EUR"
        // Rates are stored as strings so they stay exact; accept plain numbers too.
        if let strings = try? c.decode([String: String].self, forKey: .rates) {
            var r: [String: Decimal] = [:]
            for (k, v) in strings {
                guard let d = Decimal(string: v, locale: DecimalMath.posix), d > 0 else { throw RatesError.invalid }
                r[k] = d
            }
            rates = r
        } else {
            let numbers = try c.decode([String: Double].self, forKey: .rates)
            rates = try numbers.mapValues { v in
                guard v > 0, let d = Decimal(string: String(v), locale: DecimalMath.posix) else { throw RatesError.invalid }
                return d
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(base, forKey: .base)
        try c.encode(rates.mapValues { NSDecimalNumber(decimal: $0).stringValue }, forKey: .rates)
    }

    /// The publication day as a date (UTC midnight), for staleness checks.
    public var publishedDate: Date? {
        let f = DateFormatter()
        f.locale = DecimalMath.posix
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }

    /// The publication day for people: "3 Nov 2026" (formatted in UTC so it's never off by one).
    public func displayDate(locale: Locale = .current) -> String {
        guard let published = publishedDate else { return date }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: published)
    }

    public func isStale(now: Date, maxAge: TimeInterval = 7 * 86_400) -> Bool {
        guard let published = publishedDate else { return true }
        return now.timeIntervalSince(published) > maxAge
    }
}

public enum RatesError: Error, Equatable {
    case invalid
}

/// Parses the ECB's daily reference-rate XML (`eurofxref-daily.xml`).
public enum ECBRatesParser {
    public static func parse(_ data: Data) throws -> RateTable {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let date = delegate.date, !delegate.rates.isEmpty else { throw RatesError.invalid }
        return RateTable(date: date, base: "EUR", rates: delegate.rates)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var date: String?
        var rates: [String: Decimal] = [:]

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            guard elementName == "Cube" || elementName.hasSuffix(":Cube") else { return }
            if let time = attributes["time"] { date = time }
            if let code = attributes["currency"], let raw = attributes["rate"],
               code.count == 3, let rate = Decimal(string: raw, locale: DecimalMath.posix), rate > 0 {
                rates[code.uppercased()] = rate
            }
        }
    }
}

/// Rates written in the sheet (`1 USD = 1.37 CAD`): direct pairs that win over the file.
struct ManualRates {
    /// `pairs[from][to]` = how many `to` per one `from`.
    private(set) var pairs: [String: [String: Decimal]] = [:]

    var isEmpty: Bool { pairs.isEmpty }

    mutating func set(_ from: String, _ to: String, _ rate: Decimal) throws(EvalError) {
        pairs[from, default: [:]][to] = rate
        pairs[to, default: [:]][from] = try DecimalMath.divide(1, rate)
    }

    func rate(_ from: String, _ to: String) -> Decimal? { pairs[from]?[to] }

    func neighbors(_ code: String) -> [String: Decimal] { pairs[code] ?? [:] }
}

/// The rates a sheet evaluates with.
public enum RatesState: Equatable, Sendable {
    /// Downloading is off and no rates file exists.
    case off
    case loaded(RateTable, stale: Bool)
    /// A rates file exists but couldn't be read.
    case unavailable

    var table: RateTable? {
        if case .loaded(let t, _) = self { return t }
        return nil
    }
}

struct CurrencyConverter {
    var state: RatesState
    var manual: ManualRates

    /// How many `to` per one `from`. Returns whether the downloaded table was used.
    func rate(from: String, to: String) throws(EvalError) -> (Decimal, usedTable: Bool) {
        if from == to { return (1, false) }
        if let direct = manual.rate(from, to) { return (direct, false) }
        if let table = state.table {
            // A rate written in the sheet wins: go through it when it involves either side,
            // so the sheet's rates stay consistent with each other.
            for (x, r) in manual.neighbors(from) {
                if let fx = table.rate(x), let ft = table.rate(to) {
                    return (try DecimalMath.multiply(r, try DecimalMath.divide(ft, fx)), true)
                }
            }
            for (x, r) in manual.neighbors(to) {
                if let fx = table.rate(x), let ff = table.rate(from) {
                    // from → x via table, x → to via manual (r is x per to, so divide).
                    let fromToX = try DecimalMath.divide(fx, ff)
                    return (try DecimalMath.divide(fromToX, r), true)
                }
            }
            if let f = table.rate(from), let t = table.rate(to) {
                return (try DecimalMath.divide(t, f), true)
            }
            throw .noRate(table.rate(from) == nil ? from : to)
        }
        // Manual only: one hop through a shared currency.
        for (x, r1) in manual.neighbors(from) {
            if let r2 = manual.rate(x, to) { return (try DecimalMath.multiply(r1, r2), false) }
        }
        if !manual.isEmpty, manual.neighbors(from).isEmpty || manual.neighbors(to).isEmpty {
            throw .noRate(manual.neighbors(from).isEmpty ? from : to)
        }
        switch state {
        case .unavailable: throw .ratesUnavailable
        default: throw manual.isEmpty ? .ratesOff : .noRate(to)
        }
    }
}
