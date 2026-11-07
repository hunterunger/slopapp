import Foundation
import Testing
@testable import TallyCore

/// Tue, Nov 3, 2026, 3:42 PM in New York (20:42 UTC; DST ended Nov 1).
let fixedNow = Date(timeIntervalSince1970: 1_793_738_520)
let newYork = TimeZone(identifier: "America/New_York")!

func clockContext(css: CSSMetrics = .standard) -> SheetContext {
    SheetContext(rates: .loaded(fixtureRates, stale: false), css: css, now: fixedNow, timeZone: newYork)
}

/// What each line shows, with the fixed clock and fixture rates.
func clockSheet(_ text: String, css: CSSMetrics = .standard) -> [String] {
    let f = ResultFormatter(locale: usLocale, now: fixedNow, timeZone: newYork)
    return SheetEngine().evaluate(text, context: clockContext(css: css)).map { output in
        switch output.result {
        case .none: return "—"
        case .value(let q): return f.format(q)
        case .error(let e): return "err(\(e.message))"
        }
    }
}

/// Lines for the parity pass (docs/research/tally.md, "Parity pass"), each evaluated alone.
let parityLines: [(String, String)] = [
    // Time zones and dates
    ("now", "3:42 PM"),
    ("now in Tokyo", "Wed 5:42 AM Tokyo"),
    ("time in Madrid", "9:42 PM Madrid"),
    ("PST time", "12:42 PM PST"),
    ("New York time", "3:42 PM New York"),
    ("Tokyo time", "Wed 5:42 AM Tokyo"),
    ("3pm PST in CET", "Wed 12:00 AM CET"),
    ("2:30 pm HKT in Berlin", "Wed 7:30 AM Berlin"),
    ("9:00 in London", "2:00 PM London"),
    ("noon in Tokyo", "Wed 2:00 AM Tokyo"),
    ("15:30", "3:30 PM"),
    ("9am + 3 hours", "12:00 PM"),
    ("5pm - 9am", "8 h"),
    ("6:15pm - 6pm", "15 min"),
    ("now + 90 min", "5:12 PM"),
    ("today", "Tue, Nov 3, 2026"),
    ("tomorrow", "Wed, Nov 4, 2026"),
    ("yesterday", "Mon, Nov 2, 2026"),
    ("today + 3 weeks", "Tue, Nov 24, 2026"),
    ("today - 1 year", "Mon, Nov 3, 2025"),
    ("Dec 25 - today", "52 days"),
    ("(Dec 25 - today) in weeks", "7.428571429 weeks"),
    ("Dec 25 - today in weeks", "7.428571429 weeks"),
    ("Jan 31 + 1 month", "Sat, Feb 28, 2026"),
    ("2026-12-25", "Fri, Dec 25, 2026"),
    ("25 Dec 2027", "Sat, Dec 25, 2027"),
    ("December 25, 2027 - Dec 25", "365 days"),
    ("Feb 30", "err(not a real date)"),
    ("fromunix(1446587186)", "Tue, Nov 3, 2015 at 4:46:26 PM"),
    ("now in unix", "1,793,738,520"),
    ("today + 2", "err(incompatible units)"),
    ("today * 2", "err(incompatible units)"),
    ("Meeting: 3:30pm", "3:30 PM"),
    ("Meeting at 3:30pm", "—"),
    ("today + 36 hours", "Wed, Nov 4, 2026 at 12:00 PM"),
    ("13pm", "—"),
    ("Tokyo", "—"),
    ("5 in Tokyo", "err(incompatible units)"),
    // CSS units
    ("12 pt in px", "16 px"),
    ("1 inch in px", "96 px"),
    ("2 em in px", "32 px"),
    ("1.5 rem in px", "24 px"),
    ("24 px in em", "1.5 em"),
    ("16 px in pt", "12 pt"),
    ("10 px + 1 em", "26 px"),
    // Compound units
    ("60 km/h", "60 km/h"),
    ("60 km/h in m/s", "16.66666667 m/s"),
    ("60 km/h * 3 h", "180 km"),
    ("3 h * 60 km/h", "180 km"),
    ("100 km / 2 h", "50 km/h"),
    ("100 km / 50 km/h", "2 h"),
    ("100 km / (50 km/h)", "2 h"),
    ("30 mph in km/h", "48.28032 km/h"),
    ("30 mph", "30 mph"),
    ("$25/h * 40 h", "$1,000.00"),
    ("$25 per hour * 8 h", "$200.00"),
    ("100 km per 2 hours", "50 km/h"),
    ("$4/kg * 750 g", "$3.00"),
    ("$100 / 4 h", "$25.00/h"),
    ("$25/h in $/day", "$600.00/day"),
    ("1 GB / 100 Mbps", "80 s"),
    ("100 Mbps in MB/s", "12.5 MB/s"),
    ("10 knots in km/h", "18.52 km/h"),
    ("60 km/h + 10 m/s", "96 km/h"),
    ("5 kg / 2 h", "2.5 kg/h"),
    ("120 km/h / 2", "60 km/h"),
    ("6 m² / m", "6 m"),
    ("60 km/h * 2 kg", "err(incompatible units)"),
    ("10 km/h in kg/h", "err(incompatible units)"),
    // Bitwise
    ("12 & 10", "8"),
    ("12 | 3", "15"),
    ("12 xor 10", "6"),
    ("1 << 8", "256"),
    ("256 >> 4", "16"),
    ("1 + 2 << 1", "6"),
    ("(0xF0 | 0x0F) in hex", "0xFF"),
    ("5.5 & 1", "err(bitwise math needs a whole number)"),
    ("R&D 500", "—"),
    ("1 < 2", "—"),
    // Reverse percentages
    ("5% of what is 6", "120"),
    ("5% on what is 6 EUR", "€5.71"),
    ("5% off what is 6", "6.315789474"),
    ("6 is 5% of what", "120"),
    ("20% of what is 30 cm", "150 cm"),
    ("$50 as a % of $100", "50%"),
    ("$70 as a % on $20", "250%"),
    ("$20 as a % off $70", "71.42857143%"),
    ("30 as a percentage of 120", "25%"),
    ("what is 5", "—"),
    // Word operators and function forms
    ("5 and 3", "8"),
    ("$10 with $2", "$12.00"),
    ("10 without 3", "7"),
    ("6 mul 7", "42"),
    ("84 divide by 2", "42"),
    ("square root of 9", "3"),
    ("cube root of 27", "3"),
    ("log 2 (8)", "3"),
    ("root 3 (8)", "2"),
    ("root(27, 3)", "3"),
    ("root 3 (-8)", "-2"),
    ("sinh 0", "0"),
    ("tanh(0)", "0"),
    ("arcsin 1 in deg", "90°"),
    ("rent and utilities", "—"),
    // More units
    ("1 hand in inches", "4 in"),
    ("1 furlong in m", "201.168 m"),
    ("1 carat in g", "0.2 g"),
    ("1 are in sq m", "100 m²"),
    ("6 cbm in litres", "6,000 L"),
    ("20 sqm", "20 m²"),
    ("1 decade in years", "10 years"),
]

@Test(arguments: Array(parityLines.indices))
func parityLine(_ index: Int) {
    let (input, expected) = parityLines[index]
    #expect(clockSheet(input)[0] == expected, "\(input)")
}

@Suite struct ParitySheets {
    @Test func emAndPpiLinesChangeTheLinesBelow() {
        #expect(clockSheet("em = 20px\n2 em in px\n16 px in em\nppi = 326\n1 cm in px\nem = 14\n2 em in px") ==
            ["20 px", "40 px", "0.8 em", "326", "128.3464567 px", "14 px", "28 px"])
    }

    @Test func settingsChangePixelDensityAndEm() {
        let css = CSSMetrics(ppi: 326, em: 10)
        #expect(clockSheet("1 cm in px\n3 em in px", css: css) == ["128.3464567 px", "30 px"])
    }

    @Test func emCanStillBeAUnitAfterBeingSet() {
        #expect(clockSheet("em = 0\nem = 1 inch\n1 em in px") == ["err(not a real number)", "96 px", "96 px"])
    }

    @Test func linesWithTheClockAreMarked() {
        let outputs = SheetEngine().evaluate("now\n2 + 2\nstart = today\nstart + 1 day", context: clockContext())
        #expect(outputs.map(\.usesClock) == [true, false, true, true])
    }

    @Test func totalSkipsPercentagesSumsAndOtherKinds() {
        let outputs = SheetEngine().evaluate("Amount = 3\nPrice = $8 * amount\nDiscount = 5%\n$10 + 2\nsum", context: clockContext())
        let total = SheetEngine.total(of: outputs, context: clockContext())
        #expect(total.map { ResultFormatter(locale: usLocale).format($0) } == "$36.00")
    }

    @Test func totalUsesTheMostCommonKind() {
        func total(_ text: String) -> String? {
            let outputs = SheetEngine().evaluate(text, context: clockContext())
            return SheetEngine.total(of: outputs, context: clockContext()).map { ResultFormatter(locale: usLocale).format($0) }
        }
        #expect(total("$20\n4 cm\n2 kg\n500 g") == "2.5 kg")
        #expect(total("$20\n4 cm\n2 kg") == "$20.00")
        #expect(total("rent = $1200\npeople = 3\nrent / people") == "$1,600.00")
        #expect(total("$10\n€10\n€5") == "$26.28")
        #expect(total("1\n2\n3") == "6")
        #expect(total("now\n50%") == nil)
    }

    @Test func totalOfNothingIsNil() {
        #expect(SheetEngine.total(of: SheetEngine().evaluate("# Notes\nhello", context: clockContext())) == nil)
    }
}

@Suite struct HighlighterTests {
    func kinds(_ line: String, _ vars: Set<String> = []) -> [String] {
        let ns = line as NSString
        return Highlighter.spans(line, variables: vars).map { "\(ns.substring(with: $0.range)):\($0.kind)" }
    }

    @Test func colorsTheWords() {
        #expect(kinds("Fee: 8 CHF in Euro") == ["Fee::label", "8:number", "CHF:unit", "in:keyword", "Euro:unit"])
        #expect(kinds("Price * qty + 1,250.50", ["price", "qty"]) == ["Price:variable", "qty:variable", "1,250.50:number"])
        #expect(kinds("# Header") == ["# Header:header"])
        #expect(kinds("// note") == ["// note:comment"])
        #expect(kinds("3k + 0xFF") == ["3k:number", "0xFF:number"])
        #expect(kinds("20% of what is 30 cm") == ["20:number", "of:keyword", "what:keyword", "is:keyword", "30:number", "cm:unit"])
        #expect(kinds("$5 \"lunch\"") == ["\"lunch\":comment", "$:unit", "5:number"])
        #expect(kinds("3:30pm PST in Tokyo") == ["3:30:number", "pm:keyword", "PST:unit", "in:keyword", "Tokyo:unit"])
        #expect(kinds("hello world") == [])
        #expect(kinds("now in New York") == ["now:keyword", "in:keyword", "New York:unit"])
        #expect(kinds("Tokyo is nice") == [])
    }

    @Test func emojiAndAccentsKeepRangesAligned() {
        let line = "Café 👍: 2 + 2"
        let spans = Highlighter.spans(line, variables: [])
        let ns = line as NSString
        #expect(spans.map { ns.substring(with: $0.range) } == ["Café 👍:", "2", "2"])
    }
}

@Suite struct CompletionTests {
    @Test func variablesComeFirst() {
        let c = Completions.candidates(for: "pr", variables: ["price", "profit", "qty"])
        #expect(Array(c.prefix(2)) == ["price", "profit"])
        #expect(c.contains("previous"))
        #expect(!Completions.candidates(for: "price", variables: ["price"]).contains("price"))
        #expect(Completions.candidates(for: "kilom", variables: []).contains("kilometers"))
        #expect(Completions.candidates(for: "Toky", variables: []).contains("Tokyo"))
    }

    @Test func suggestsOnlyForSheetVariablesAtAWordEnd() {
        #expect(Completions.shouldSuggest(line: "total = pr", cursor: 10, variables: ["price"]) == "pr")
        #expect(Completions.shouldSuggest(line: "p", cursor: 1, variables: ["price"]) == nil)
        #expect(Completions.shouldSuggest(line: "xy", cursor: 2, variables: ["price"]) == nil)
        #expect(Completions.shouldSuggest(line: "price", cursor: 5, variables: ["price"]) == nil)
        #expect(Completions.shouldSuggest(line: "// pr", cursor: 5, variables: ["price"]) == nil)
        #expect(Completions.shouldSuggest(line: "5 \"pr", cursor: 5, variables: ["price"]) == nil)
        #expect(Completions.shouldSuggest(line: "prx", cursor: 2, variables: ["price"]) == nil)
    }
}

final class MemoryLibrary: LibraryStorage {
    var index: LibraryIndex?
    var texts: [UUID: String] = [:]
    var legacy: String?
    func loadIndex() -> LibraryIndex? { index }
    func saveIndex(_ index: LibraryIndex) throws { self.index = index }
    func loadText(_ id: UUID) -> String? { texts[id] }
    func saveText(_ text: String, id: UUID) throws { texts[id] = text }
    func deleteText(_ id: UUID) throws { texts[id] = nil }
    func loadLegacySheet() -> String? { legacy }
}

@Suite struct LibraryTests {
    final class Clock {
        var t = Date(timeIntervalSince1970: 1_000)
        func tick() -> Date { t += 60; return t }
    }

    @Test func firstRunStartsWithTheWelcomeSheet() {
        let store = MemoryLibrary()
        let lib = SheetLibrary(storage: store, firstText: "# Hi")
        #expect(lib.sheets.count == 1)
        #expect(lib.text(of: lib.currentID) == "# Hi")
        #expect(store.index == nil && store.texts.isEmpty) // nothing written until an edit
        try? lib.save("# Hi!", id: lib.currentID)
        #expect(store.index?.current == lib.currentID)
        #expect(store.texts[lib.currentID] == "# Hi!")
    }

    @Test func theOldSingleSheetMovesIn() {
        let store = MemoryLibrary()
        store.legacy = "rent = 1450"
        let lib = SheetLibrary(storage: store, firstText: "# Hi")
        #expect(lib.text(of: lib.currentID) == "rent = 1450")
        #expect(store.legacy == "rent = 1450") // left in place for older versions
        let second = lib.create(text: "b")
        #expect(store.texts[lib.sheets.last!.id] == "rent = 1450") // the first sheet is written with the second
        // A second launch reads the index, not the welcome text.
        let again = SheetLibrary(storage: store, firstText: "# Hi")
        #expect(again.currentID == second.id)
        #expect(again.sheets.count == 2)
    }

    @Test func newestEditFirstAndDeletingPicksTheNextOne() throws {
        let clock = Clock()
        let store = MemoryLibrary()
        let lib = SheetLibrary(storage: store, firstText: "a", now: clock.tick)
        let first = lib.currentID
        let second = lib.create(text: "b").id
        let third = lib.create(text: "c").id
        #expect(lib.sheets.map(\.id) == [third, second, first])
        try lib.save("a2", id: first)
        #expect(lib.sheets.map(\.id) == [first, third, second])
        lib.select(third)
        #expect(lib.neighbour(1) == second)
        #expect(lib.neighbour(-1) == first)
        #expect(lib.neighbour(2) == first)
        #expect(lib.delete(third) == second)
        #expect(store.texts[third] == nil)
        lib.delete(second)
        #expect(lib.delete(first) != first)
        #expect(lib.sheets.count == 1)
        #expect(lib.text(of: lib.currentID) == "")
    }

    @Test func titlesComeFromTheFirstLine() {
        #expect(SheetTitle.title(of: "\n\n# Groceries\n2 + 2") == "Groceries")
        #expect(SheetTitle.title(of: "// trip\n") == "trip")
        #expect(SheetTitle.title(of: "  \n") == SheetTitle.untitled)
        #expect(SheetTitle.title(of: "rent / 3") == "rent / 3")
    }

    @Test func filesRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tally-lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "old sheet".write(to: dir.appendingPathComponent("sheet.txt"), atomically: true, encoding: .utf8)
        let store = FileLibraryStorage(directory: dir)
        let lib = SheetLibrary(storage: store, firstText: "welcome")
        #expect(lib.text(of: lib.currentID) == "old sheet")
        let made = lib.create(text: "second")
        let reopened = SheetLibrary(storage: FileLibraryStorage(directory: dir), firstText: "welcome")
        #expect(reopened.sheets.count == 2)
        #expect(reopened.currentID == made.id)
        #expect(reopened.text(of: made.id) == "second")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sheet.txt").path))
    }
}

@Suite struct InlineSuggestionTests {
    @Test func variablesThenUnitsAfterNumbers() {
        #expect(Completions.inline(line: "total = pr", cursor: 10, variables: ["price"]) == "ice")
        #expect(Completions.inline(line: "Pr", cursor: 2, variables: ["price"]) == "ice")
        #expect(Completions.inline(line: "price", cursor: 5, variables: ["price"]) == nil)
        #expect(Completions.inline(line: "5 kilom", cursor: 7, variables: []) == "eter")
        #expect(Completions.inline(line: "5 km in fee", cursor: 11, variables: []) == "t")
        #expect(Completions.inline(line: "now in Tok", cursor: 10, variables: []) == "yo")
        #expect(Completions.inline(line: "Groceries for the wee", cursor: 21, variables: []) == nil)
        #expect(Completions.inline(line: "// pr", cursor: 5, variables: ["price"]) == nil)
        #expect(Completions.inline(line: "# pr", cursor: 4, variables: ["price"]) == nil)
        #expect(Completions.inline(line: "Pri: 5", cursor: 3, variables: ["price"]) == nil)
        #expect(Completions.inline(line: "prx", cursor: 2, variables: ["price"]) == nil)
        #expect(Completions.inline(line: "5 kg", cursor: 4, variables: []) == nil)
    }
}
