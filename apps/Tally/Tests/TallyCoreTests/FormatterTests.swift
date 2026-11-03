import Foundation
import Testing
@testable import TallyCore

@Suite struct Formatting {
    let f = ResultFormatter(locale: usLocale)

    @Test func significantDigitsAndTrimming() {
        #expect(f.number(Decimal(string: "3.10685596118667")!) == "3.106855961")
        #expect(f.number(Decimal(string: "2.500")!) == "2.5")
        #expect(f.number(Decimal(string: "-0.00000001")!) == "-0.00000001")
        #expect(f.number(Decimal(string: "0.0000000001234")!) == "1.234e-10")
        #expect(f.number(Decimal(string: "999999999999999")!) == "999,999,999,999,999")
        #expect(f.number(Decimal(string: "1000000000000000")!) == "1e15")
        #expect(f.number(Decimal(string: "9.9999999999")!) == "10")
        #expect(f.number(0) == "0")
    }

    @Test func groupingFollowsTheLocale() {
        let swiss = ResultFormatter(locale: Locale(identifier: "de_CH"))
        let sep = Locale(identifier: "de_CH").groupingSeparator!
        #expect(swiss.number(1_234_567) == "1\(sep)234\(sep)567")
        let german = ResultFormatter(locale: Locale(identifier: "de_DE"))
        // Decimal-comma locales keep "." as the decimal point (it's what input accepts)
        // and group with a narrow space.
        #expect(german.number(Decimal(string: "1234.5")!) == "1\u{202F}234.5")
    }

    @Test func percentCurrencyAndUnits() {
        #expect(f.format(Quantity(Decimal(string: "0.25")!, .percent)) == "25%")
        #expect(f.format(Quantity(Decimal(string: "1234.5")!, .currency("USD"))) == "$1,234.50")
        #expect(f.format(Quantity(Decimal(string: "-3")!, .currency("EUR"))) == "-€3.00")
        #expect(f.format(Quantity(5, .currency("CHF"))) == "5.00 CHF")
        #expect(f.format(Quantity(1, .unit(Units.unit(id: "day")!))) == "1 day")
        #expect(f.format(Quantity(2, .unit(Units.unit(id: "day")!))) == "2 days")
    }

    @Test func plainNumberForCopying() {
        #expect(f.plainNumber(Quantity(Decimal(string: "1234.5")!, .currency("USD"))) == "1234.50")
        #expect(f.plainNumber(Quantity(2000, .unit(Units.unit(id: "g")!))) == "2000")
        #expect(f.plainNumber(Quantity(Decimal(string: "0.25")!, .percent)) == "25")
    }

    @Test func styles() {
        #expect(f.format(Quantity(-255, .none, style: .hex)) == "-0xFF")
        #expect(f.format(Quantity(5, .none, style: .binary)) == "0b101")
        #expect(f.format(Quantity(1234, .unit(Units.unit(id: "m")!), style: .scientific)) == "1.234e3 m")
    }
}

@Suite struct Lines {
    @Test func classifiesNoteParts() {
        #expect(LineSyntax.parse("   ").kind == .blank)
        #expect(LineSyntax.parse("  # Header").kind == .header)
        #expect(LineSyntax.parse("// c").kind == .comment)
        let line = LineSyntax.parse("Rent: \"May\" 1200 // due")
        #expect(line.kind == .content)
        #expect(line.label == NSRange(location: 0, length: 5))
        #expect(line.quotes == [NSRange(location: 6, length: 5)])
        #expect(line.comment == NSRange(location: 17, length: 6))
        #expect(line.expression.trimmingCharacters(in: .whitespaces) == "1200")
    }

    @Test func colonsInsideQuotesOrWithoutLettersArentLabels() {
        #expect(LineSyntax.parse("\"a: b\" 5").label == nil)
        #expect(LineSyntax.parse("12:30").label == nil)
    }

    @Test func curlyQuotesAndUnclosedQuotes() {
        #expect(calc("“lunch” 12 + 3") == "15")
        #expect(calc("12 + 3 \"unfinished") == "15")
    }

    @Test func emojiAndRTLTextDontBreakRanges() {
        let line = LineSyntax.parse("🍕 Pizza: 12 * 2")
        #expect(line.label == NSRange(location: 0, length: 9))
        #expect(calc("🍕 Pizza: 12 * 2") == "24")
        #expect(calc("سعر: 5 + 5") == "10")
    }
}
