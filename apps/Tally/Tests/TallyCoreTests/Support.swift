import Foundation
@testable import TallyCore

let usLocale = Locale(identifier: "en_US")
let fixtureRates = RateTable(date: "2026-11-03", base: "EUR", rates: ["USD": Decimal(string: "1.0850")!, "GBP": Decimal(string: "0.8430")!])

/// What a line shows: the result text, "—" for nothing, or "err(reason)".
func shown(_ output: LineOutput, dollar: String = "USD") -> String {
    let f = ResultFormatter(locale: usLocale, dollarCode: dollar)
    switch output.result {
    case .none: return "—"
    case .value(let q): return f.format(q)
    case .error(let e): return "err(\(e.message))"
    }
}

/// Evaluates `text` as one sheet and returns what each line shows.
func sheet(_ text: String, rates: RatesState = .off, dollar: String = "USD") -> [String] {
    SheetEngine().evaluate(text, context: SheetContext(rates: rates, dollarCode: dollar)).map { shown($0, dollar: dollar) }
}

/// What a single line shows on its own.
func calc(_ line: String, rates: RatesState = .off, dollar: String = "USD") -> String {
    sheet(line, rates: rates, dollar: dollar)[0]
}
