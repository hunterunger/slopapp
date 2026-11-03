import Foundation
import Testing
@testable import TallyCore

/// The 68-line v1 corpus from docs/research/tally.md, evaluated as one sheet top to bottom.
/// `—` = nothing shown, `err(…)` = an error reason.
let corpus: [(input: String, expected: String)] = [
    ("2 + 3", "5"),
    ("2 + 3 * 4", "14"),
    ("(2 + 3) * 4", "20"),
    ("2 ^ 10", "1,024"),
    ("-2 ^ 2", "-4"),
    ("2 ^ 3 ^ 2", "512"),
    ("10 / 4", "2.5"),
    ("1 / 3", "0.3333333333"),
    ("0.1 + 0.2", "0.3"),
    ("7 mod 3", "1"),
    ("8 times 9", "72"),
    ("100 divided by 8", "12.5"),
    ("1,250 + 750", "2,000"),
    ("1.5e3", "1,500"),
    ("0xff + 1", "256"),
    ("3k + 2.5M", "2,503,000"),
    ("1.2 billion / 1000", "1,200,000"),
    ("2(3 + 1)", "8"),
    ("", "—"),
    ("20% of 150", "30"),
    ("150 + 20%", "180"),
    ("150 - 20%", "120"),
    ("5% on 200", "210"),
    ("6% off 50", "47"),
    ("30 as % of 120", "25%"),
    ("12.5% of 80", "10"),
    ("", "—"),
    ("price = 40", "40"),
    ("qty = 3", "3"),
    ("price * qty", "120"),
    ("prev + 10%", "132"),
    ("Rent: 1200 + 85", "1,285"),
    ("// a comment", "—"),
    ("# Groceries", "—"),
    ("hello world", "—"),
    ("", "—"),
    ("10", "10"),
    ("20", "20"),
    ("30", "30"),
    ("sum", "60"),
    ("", "—"),
    ("1 m + 20 cm", "1.2 m"),
    ("5 km in miles", "3.106855961 mi"),
    ("6 ft to cm", "182.88 cm"),
    ("3 lb in kg", "1.36077711 kg"),
    ("250 g + 1 kg", "1,250 g"),
    ("1 GB in MB", "1,000 MB"),
    ("1 GiB in MiB", "1,024 MiB"),
    ("100 Mb in MB", "12.5 MB"),
    ("100 USD in EUR", "€92.17"),
    ("50 EUR in GBP", "£42.15"),
    ("$20 + $5", "$25.00"),
    ("90 min in hours", "1.5 h"),
    ("2 days in hours", "48 h"),
    ("1 TB in GiB", "931.3225746 GiB"),
    ("10 km / 2", "5 km"),
    ("1 GB / 1 MB", "1,000"),
    ("5 kg + 3 m", "err(incompatible units)"),
    ("5 / 0", "err(division by zero)"),
    ("sqrt 16 + 2", "6"),
    ("pi * 2", "6.283185307"),
    ("sin(30°)", "0.5"),
    ("round(2.5)", "3"),
    ("x = 5", "5"),
    ("x ^ 2 + 1", "26"),
    ("20 °C in °F", "68 °F"),
    ("0 K in C", "-273.15 °C"),
    ("1 h 30 min in min", "90 min"),
]

let corpusText = corpus.map(\.input).joined(separator: "\n")

@Test func corpusHas68Lines() {
    #expect(corpus.count == 68)
}

@Test(arguments: Array(corpus.indices))
func corpusLine(_ index: Int) {
    let results = sheet(corpusText, rates: .loaded(fixtureRates, stale: false))
    #expect(results.count == corpus.count)
    let (input, expected) = corpus[index]
    #expect(results[index] == expected, "line \(index + 1): \(input)")
}

@Test func corpusWithoutRatesFileMarksConversionsRatesOff() {
    let results = sheet(corpusText, rates: .off)
    #expect(results[49] == "err(rates off)")
    #expect(results[50] == "err(rates off)")
    // Same-currency math never needs rates.
    #expect(results[51] == "$25.00")
    // Everything else is unaffected.
    for i in corpus.indices where i != 49 && i != 50 {
        #expect(results[i] == corpus[i].expected, "line \(i + 1): \(corpus[i].input)")
    }
}

@Test func renamingAVariableBreaksDependentLinesImmediately() {
    var lines = corpus.map(\.input)
    lines[27] = "cost = 40"
    let results = sheet(lines.joined(separator: "\n"))
    #expect(results[27] == "40")
    #expect(results[29] == "err(unknown name “price”)")
    // prev now points at "qty = 3" (the nearest line above with a value): no stale 120.
    #expect(results[30] == "3.3")
    #expect(results[31] == "1,285")
}

@Test func movingADefinitionBelowItsUseMakesTheUseAnError() {
    var lines = corpus.map(\.input)
    lines.swapAt(28, 29) // "price * qty" now comes before "qty = 3"
    let results = sheet(lines.joined(separator: "\n"))
    #expect(results[28] == "err(unknown name “qty”)")
    #expect(results[29] == "3")
}
