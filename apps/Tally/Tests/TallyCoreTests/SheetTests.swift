import Foundation
import Testing
@testable import TallyCore

@Suite struct SheetBehavior {
    @Test func sumAndAverageCoverTheBlockAboveUpToABlankLine() {
        let r = sheet("5\n\n10\n20\n30\nsum\navg\ntotal\naverage")
        #expect(r == ["5", "—", "10", "20", "30", "60", "20", "60", "20"])
    }

    @Test func headersStartANewBlock() {
        let r = sheet("100\n# Food\n12\n8\nsum")
        #expect(r.last == "20")
    }

    @Test func sumWithNothingAboveIsZeroAndAverageIsNothing() {
        #expect(sheet("sum\navg") == ["0", "—"])
    }

    @Test func sumConvertsUnitsToTheFirstLinesUnit() {
        #expect(sheet("1 km\n500 m\nsum").last == "1.5 km")
        #expect(sheet("$10\n$5.50\nsum").last == "$15.50")
        #expect(sheet("1 kg\n2 m\nsum").last == "err(incompatible units)")
    }

    @Test func sumIncludesAssignmentsAndSkipsTextAndErrors() {
        let r = sheet("rent = 1200\nfood = 300\nnotes here\n5 / 0\n// c\nsum")
        #expect(r.last == "1,500")
    }

    @Test func prevSkipsLinesWithoutValuesAndCrossesBlankLines() {
        let r = sheet("10\n// note\n\nprev * 2\nhello\nprev + 1")
        #expect(r == ["10", "—", "—", "20", "—", "21"])
        #expect(sheet("prev") == ["—"])
    }

    @Test func variablesCanBeReassignedAndUseUnitsAndPercent() {
        let r = sheet("a = 2\nb2 = a * 3\na = 10\nb2 + a\ntip = 18%\ndinner = $186.40\ndinner + tip\nprev / 4")
        #expect(r == ["2", "6", "10", "16", "18%", "$186.40", "$219.95", "$54.99"])
    }

    @Test func reservedNamesExplainThemselves() {
        #expect(calc("km = 5") == "err(“km” is a unit)")
        #expect(calc("sum = 5") == "err(“sum” is a built-in word)")
        #expect(calc("pi = 3") == "err(“pi” is a constant)")
        #expect(calc("sqrt = 3") == "err(“sqrt” is a function)")
        #expect(calc("usd = 3") == "err(“usd” is a currency)")
    }

    @Test func aFailedAssignmentRemovesTheOldValue() {
        let r = sheet("a = 5\na = 5 / 0\na + 1")
        #expect(r == ["5", "err(division by zero)", "err(unknown name “a”)"])
    }

    @Test func variablesAreCaseSensitiveAndMayContainDigitsAndUnderscores() {
        let r = sheet("Rate_2 = 3\nrate_2 + 1\nRate_2 + 1")
        #expect(r == ["3", "err(unknown name “rate_2”)", "4"])
    }

    @Test func sumLinesDontCountTowardsLaterSums() {
        let r = sheet("10\n20\nsum\nsum")
        #expect(r == ["10", "20", "30", "30"])
    }

    @Test func assignmentOutputNamesTheVariable() {
        let out = SheetEngine().evaluate("price = 4\n4")
        #expect(out[0].assignedName == "price")
        #expect(out[1].assignedName == nil)
    }

    @Test func dollarSettingChangesWhatDollarMeans() {
        #expect(calc("$5 + 2", dollar: "CAD") == "$7.00")
        #expect(calc("5 USD", dollar: "CAD") == "5.00 USD")
        #expect(calc("5 CAD", dollar: "CAD") == "$5.00")
        #expect(calc("10 dollars", dollar: "AUD") == "$10.00")
    }

    @Test func reEvaluationIsDeterministicWithTheParseCache() {
        let engine = SheetEngine()
        let text = corpusText
        let first = engine.evaluate(text, context: SheetContext(rates: .loaded(fixtureRates, stale: false)))
        let second = engine.evaluate(text, context: SheetContext(rates: .loaded(fixtureRates, stale: false)))
        #expect(first == second)
        // The cache holds parses only: changing the context changes the results.
        let third = engine.evaluate(text, context: SheetContext(rates: .off))
        #expect(third[49].result == .error(.ratesOff))
    }

    @Test func crlfAndTrailingNewlineKeepLineCount() {
        #expect(SheetEngine.lines(of: "1\n2\n").count == 3)
        #expect(sheet("1 + 1\r").first == "2")
    }
}

@Suite struct Currency {
    let loaded = RatesState.loaded(fixtureRates, stale: false)

    @Test func conversionsUseTheDownloadedTable() {
        #expect(calc("100 USD in EUR", rates: loaded) == "€92.17")
        #expect(calc("100 USD in GBP", rates: loaded) == "£77.70")
        #expect(calc("$10 + €10", rates: loaded) == "$20.85")
        #expect(calc("€10 / $10", rates: loaded) == "1.085")
        #expect(calc("100 USD in CHF", rates: loaded) == "err(no rate for CHF)")
    }

    @Test func outputsSayWhenTheTableWasUsed() {
        let out = SheetEngine().evaluate("100 USD in EUR\n$5 + $5", context: SheetContext(rates: loaded))
        #expect(out[0].usesDownloadedRates)
        #expect(!out[1].usesDownloadedRates)
    }

    @Test func rateLinesWorkOfflineAndOverrideTheTable() {
        let r = sheet("1 USD = 1.37 CAD\n100 USD in CAD\n137 CAD in USD\n50 CAD in EUR")
        #expect(r == ["1.37 CAD", "137.00 CAD", "$100.00", "err(no rate for EUR)"])
        let withTable = sheet("1 EUR = 1.10 USD\n100 EUR in USD\n100 USD in GBP", rates: loaded)
        #expect(withTable[1] == "$110.00")
        // GBP goes through the table: 100 USD → EUR (manual, 1/1.10) → GBP (table).
        #expect(withTable[2] == "£76.64")
    }

    @Test func rateLinesCanChainThroughAThirdCurrency() {
        let r = sheet("1 EUR = 1.1 USD\n1 USD = 1.4 CAD\n10 EUR in CAD")
        #expect(r.last == "15.40 CAD")
    }

    @Test func aRateLineAboveDoesntAffectLinesBeforeIt() {
        let r = sheet("10 USD in CAD\n1 USD = 1.37 CAD")
        #expect(r.first == "err(rates off)")
    }

    @Test func nonCurrencyEquationsShowNothing() {
        #expect(calc("2 + 2 = 4") == "—")
        #expect(calc("1 USD = 1 USD") == "—")
    }

    @Test func unreadableRatesFileSaysSo() {
        #expect(calc("1 USD in EUR", rates: .unavailable) == "err(rates unavailable)")
    }

    @Test func zeroDecimalCurrencies() {
        #expect(calc("1000 JPY in EUR", rates: .loaded(RateTable(date: "2026-11-03", rates: ["JPY": 160]), stale: false)) == "€6.25")
        #expect(calc("10 EUR in JPY", rates: .loaded(RateTable(date: "2026-11-03", rates: ["JPY": 160]), stale: false)) == "¥1,600")
    }

    @Test func parsesTheECBDailyXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
            <gesmes:subject>Reference rates</gesmes:subject>
            <Cube>
                <Cube time='2026-11-03'>
                    <Cube currency='USD' rate='1.0850'/>
                    <Cube currency='JPY' rate='162.31'/>
                    <Cube currency='GBP' rate='0.84300'/>
                </Cube>
            </Cube>
        </gesmes:Envelope>
        """
        let table = try ECBRatesParser.parse(Data(xml.utf8))
        #expect(table.date == "2026-11-03")
        #expect(table.base == "EUR")
        #expect(table.rates["USD"] == Decimal(string: "1.085"))
        #expect(table.rates["GBP"] == Decimal(string: "0.843"))
        #expect(table.rates.count == 3)
    }

    @Test func rejectsGarbageXML() {
        #expect(throws: (any Error).self) { try ECBRatesParser.parse(Data("<html>nope</html>".utf8)) }
        #expect(throws: (any Error).self) { try ECBRatesParser.parse(Data("not xml".utf8)) }
    }

    @Test func rateTableRoundTripsExactlyThroughJSON() throws {
        let data = try JSONEncoder().encode(fixtureRates)
        let back = try JSONDecoder().decode(RateTable.self, from: data)
        #expect(back == fixtureRates)
        let numeric = #"{"date":"2026-11-01","base":"EUR","rates":{"USD":1.085}}"#
        let decoded = try JSONDecoder().decode(RateTable.self, from: Data(numeric.utf8))
        #expect(decoded.rates["USD"] == Decimal(string: "1.085"))
        let bad = #"{"date":"2026-11-01","rates":{"USD":"-1"}}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RateTable.self, from: Data(bad.utf8)) }
    }

    @Test func displayDateIsThePublicationDayInEveryTimeZone() {
        #expect(fixtureRates.displayDate(locale: usLocale) == "Nov 3, 2026")
        #expect(RateTable(date: "junk", rates: [:]).displayDate(locale: usLocale) == "junk")
    }

    @Test func staleness() {
        let table = RateTable(date: "2026-11-03", rates: ["USD": 1])
        let day: TimeInterval = 86_400
        let published = table.publishedDate!
        #expect(!table.isStale(now: published.addingTimeInterval(3 * day)))
        #expect(table.isStale(now: published.addingTimeInterval(8 * day)))
        #expect(RateTable(date: "garbage", rates: [:]).isStale(now: published))
    }
}
