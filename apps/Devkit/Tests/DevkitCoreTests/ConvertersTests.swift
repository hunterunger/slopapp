import Foundation
import Testing
@testable import DevkitCore

@Suite struct TimestampTests {
    let utc = TimeZone(identifier: "UTC")!
    let posix = Locale(identifier: "en_US_POSIX")

    @Test func guessesUnits() throws {
        #expect(try Timestamps.parse("1730592000").input == .number(.seconds))
        #expect(try Timestamps.parse("1730592000000").input == .number(.milliseconds))
        #expect(try Timestamps.parse("1730592000000000").input == .number(.microseconds))
        #expect(try Timestamps.parse("1730592000000000000").input == .number(.nanoseconds))
        let all = try ["1730592000", "1730592000000", "1730592000000000", "1730592000000000000"].map { try Timestamps.parse($0).date }
        #expect(Set(all).count == 1)
        #expect(all[0] == Date(timeIntervalSince1970: 1_730_592_000))
    }

    @Test func forcedUnitAndNegative() throws {
        #expect(try Timestamps.parse("1000", unit: .milliseconds).date == Date(timeIntervalSince1970: 1))
        #expect(try Timestamps.parse("-86400").date == Date(timeIntervalSince1970: -86400))
        #expect(try Timestamps.parse("1730592000.5").date == Date(timeIntervalSince1970: 1_730_592_000.5))
    }

    @Test func parsesDates() throws {
        let expected = Date(timeIntervalSince1970: 1_730_592_000) // 2024-11-03T00:00:00Z
        #expect(try Timestamps.parse("2024-11-03T00:00:00Z").date == expected)
        #expect(try Timestamps.parse("2024-11-03T00:00:00.000Z").date == expected)
        #expect(try Timestamps.parse("2024-11-02T20:00:00-04:00").date == expected)
        #expect(try Timestamps.parse("Sun, 03 Nov 2024 00:00:00 +0000").date == expected)
        #expect(try Timestamps.parse("Sun, 3 Nov 2024 00:00:00 GMT").date == expected)
        #expect(try Timestamps.parse("2024-11-03 00:00:00", timeZone: utc).date == expected)
        #expect(try Timestamps.parse("2024-11-03", timeZone: utc).date == expected)
        #expect(throws: Timestamps.ParseError.unrecognized) { try Timestamps.parse("next tuesday") }
        #expect(throws: Timestamps.ParseError.empty) { try Timestamps.parse("") }
    }

    @Test func rows() {
        let date = Date(timeIntervalSince1970: 1_730_592_000)
        let rows = Timestamps.rows(for: date, now: date.addingTimeInterval(3 * 3600), timeZone: utc, locale: posix)
        func value(_ label: String) -> String? { rows.first { $0.label == label }?.value }
        #expect(value("UTC") == "2024-11-03 00:00:00 UTC")
        #expect(value("ISO 8601") == "2024-11-03T00:00:00Z")
        #expect(value("RFC 2822") == "Sun, 03 Nov 2024 00:00:00 +0000")
        #expect(value("Relative") == "3 hours ago")
        #expect(value("Unix seconds") == "1730592000")
        #expect(value("Unix milliseconds") == "1730592000000")
        #expect(value("Day and week") == "Day 308, ISO week 44")
    }

    @Test(arguments: [
        ("1730592000", true), ("631152000", true), ("1730592000123", true), ("1730592000.5", true),
        ("123456789", false), ("99999999999", false), ("4102444801", false), ("12", false), ("17305920001", false),
    ])
    func plausibleTimestamps(text: String, expected: Bool) {
        #expect(Timestamps.isPlausibleTimestamp(text) == expected)
    }
}

@Suite struct ColorTests {
    @Test func parsesHexForms() throws {
        #expect(try ColorConverter.parse("#F80") == RGBAColor(red: 1, green: 0x88 / 255, blue: 0))
        #expect(try ColorConverter.parse("#ff8800") == RGBAColor(red: 1, green: 0x88 / 255, blue: 0))
        #expect(try ColorConverter.parse("ff880080").alpha == 0x80 / 255)
        #expect(try ColorConverter.parse("#F808").alpha == 0x88 / 255)
    }

    @Test func parsesFunctions() throws {
        let orange = RGBAColor(red: 1, green: 0.5, blue: 0)
        #expect(try ColorConverter.parse("rgb(255, 127.5, 0)") == orange)
        #expect(try ColorConverter.parse("rgb(100% 50% 0%)") == orange)
        #expect(try ColorConverter.parse("rgba(255,127.5,0,0.5)").alpha == 0.5)
        #expect(try ColorConverter.parse("rgb(255 127.5 0 / 50%)").alpha == 0.5)
        let hsl = try ColorConverter.parse("hsl(30, 100%, 50%)")
        #expect(abs(hsl.red - 1) < 1e-9 && abs(hsl.green - 0.5) < 1e-9 && hsl.blue == 0)
        let hsb = try ColorConverter.parse("hsb(30deg 100% 100%)")
        #expect(abs(hsb.green - 0.5) < 1e-9)
        #expect(throws: ColorConverter.ParseError.unrecognized) { try ColorConverter.parse("cmyk(1,2,3,4)") }
        #expect(throws: ColorConverter.ParseError.unrecognized) { try ColorConverter.parse("#12345") }
    }

    @Test func rows() throws {
        let rows = ColorConverter.rows(for: try ColorConverter.parse("#3366CC"))
        func value(_ label: String) -> String? { rows.first { $0.label == label }?.value }
        #expect(value("Hex") == "#3366CC")
        #expect(value("RGB") == "rgb(51 102 204)")
        #expect(value("HSL") == "hsl(220 60% 50%)")
        #expect(value("HSB") == "hsb(220 75% 80%)")
        #expect(value("SwiftUI") == "Color(red: 0.200, green: 0.400, blue: 0.800)")
        let translucent = ColorConverter.rows(for: try ColorConverter.parse("#3366CC80"))
        #expect(translucent.first?.value == "#3366CC80")
        #expect(translucent[1].value == "rgb(51 102 204 / 0.5)")
    }

    @Test func roundTripsThroughHSLAndHSB() throws {
        for hex in ["#000000", "#FFFFFF", "#123456", "#FEDCBA", "#00FF7F", "#808080"] {
            let color = try ColorConverter.parse(hex)
            let hsl = color.hsl, hsb = color.hsb
            #expect(ColorConverter.rows(for: .fromHSL(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness))[0].value == hex)
            #expect(ColorConverter.rows(for: .fromHSB(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness))[0].value == hex)
        }
    }

    @Test func wcagContrast() {
        let ratio = RGBAColor(red: 0, green: 0, blue: 0).contrast(with: RGBAColor(red: 1, green: 1, blue: 1))
        #expect(abs(ratio - 21) < 1e-9)
    }
}

@Suite struct TextDiffTests {
    @Test func identical() {
        let result = TextDiff.compare("a\nb\n", "a\nb")
        #expect(result.isIdentical)
        #expect(TextDiff.unified(result) == "")
    }

    @Test func sideBySideRows() {
        let result = TextDiff.compare("one\ntwo\nthree\nfour", "one\n2\nthree\nfour\nfive")
        #expect(result.added == 2 && result.removed == 1)
        #expect(result.rows.map(\.kind) == [.same, .changed, .same, .same, .added])
        let changed = result.rows[1]
        #expect(changed.oldText == "two" && changed.newText == "2")
        #expect(changed.oldLine == 2 && changed.newLine == 2)
        #expect(result.rows[4].newLine == 5 && result.rows[4].oldLine == nil)
    }

    @Test func characterHighlights() {
        let row = TextDiff.compare("let value = 10", "let value = 12").rows[0]
        #expect(row.kind == .changed)
        #expect(row.oldHighlights == [NSRange(location: 13, length: 1)])
        #expect(row.newHighlights == [NSRange(location: 13, length: 1)])
    }

    @Test func ignoreOptions() {
        #expect(TextDiff.compare("a  b\nC", "a b\nc", options: .init(ignoreWhitespace: true, ignoreCase: true)).isIdentical)
        #expect(!TextDiff.compare("a  b", "a b").isIdentical)
    }

    @Test func unifiedOutput() {
        let old = (1...10).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "5", with: "five")
        let unified = TextDiff.unified(TextDiff.compare(old, new))
        #expect(unified == """
        --- Original
        +++ Changed
        @@ -2,7 +2,7 @@
         2
         3
         4
        -5
        +five
         6
         7
         8
        """)
    }

    @Test func unifiedFromEmpty() {
        #expect(TextDiff.unified(TextDiff.compare("", "a\nb")) == "--- Original\n+++ Changed\n@@ -0,0 +1,2 @@\n+a\n+b")
    }

    @Test func crlfLinesMatchLF() {
        #expect(TextDiff.compare("a\r\nb", "a\nb").isIdentical)
    }
}

@Suite struct RegexTesterTests {
    @Test func findsMatchesAndGroups() {
        let outcome = RegexTester.evaluate(pattern: #"(?<user>\w+)@(\w+)\.com"#, flags: [], in: "ada@example.com, bob@test.com")
        guard case let .matches(matches, truncated) = outcome else { Issue.record("\(outcome)"); return }
        #expect(!truncated)
        #expect(matches.map(\.text) == ["ada@example.com", "bob@test.com"])
        #expect(matches[0].groups.map(\.text) == ["ada", "example"])
        #expect(matches[0].groups[0].name == "user")
        #expect(matches[0].groups[1].name == nil)
        #expect(matches[1].range == NSRange(location: 17, length: 12))
    }

    @Test func flags() {
        func count(_ pattern: String, _ flags: RegexTester.Flags, _ text: String) -> Int {
            if case let .matches(matches, _) = RegexTester.evaluate(pattern: pattern, flags: flags, in: text) { return matches.count }
            return -1
        }
        #expect(count("abc", [], "ABC abc") == 1)
        #expect(count("abc", .caseInsensitive, "ABC abc") == 2)
        #expect(count("^x", [], "x\nx") == 1)
        #expect(count("^x", .multiline, "x\nx") == 2)
        #expect(count("a.b", [], "a\nb") == 0)
        #expect(count("a.b", .dotAll, "a\nb") == 1)
        #expect(count("a b # comment", .extended, "ab") == 1)
    }

    @Test func unmatchedOptionalGroup() {
        guard case let .matches(matches, _) = RegexTester.evaluate(pattern: "a(b)?", flags: [], in: "a") else { Issue.record(); return }
        #expect(matches[0].groups[0].range == nil)
    }

    @Test func catastrophicBacktrackingTimesOut() {
        let clock = ContinuousClock()
        var outcome: RegexTester.Outcome?
        let elapsed = clock.measure {
            outcome = RegexTester.evaluate(pattern: "(a+)+$", flags: [], in: String(repeating: "a", count: 40) + "b",
                                           timeout: .milliseconds(200))
        }
        #expect(outcome == .timedOut(partial: []))
        #expect(elapsed < .seconds(2))
    }

    @Test func invalidPatterns() {
        #expect(RegexTester.evaluate(pattern: "(abc", flags: [], in: "") == .invalidPattern("A ( group isn't closed. Add a ), or escape it as \\(."))
        #expect(RegexTester.evaluate(pattern: "abc)", flags: [], in: "") == .invalidPattern("There's a ) without a matching (. Escape it as \\) to match a parenthesis."))
        #expect(RegexTester.evaluate(pattern: "[a-", flags: [], in: "") == .invalidPattern("A [ character class isn't closed. Add a ], or escape it as \\[."))
        #expect(RegexTester.evaluate(pattern: "*a", flags: [], in: "") == .invalidPattern("The pattern starts with a quantifier (*) that has nothing to repeat. Escape it with a backslash."))
        #expect(RegexTester.evaluate(pattern: "", flags: [], in: "x") == .emptyPattern)
    }

    @Test func limitsMatches() {
        guard case let .matches(matches, truncated) = RegexTester.evaluate(pattern: ".", flags: [], in: String(repeating: "x", count: 100), limit: 10) else { Issue.record(); return }
        #expect(matches.count == 10 && truncated)
    }

    @Test func replaces() {
        #expect(RegexTester.replace(pattern: #"(\w+)@(\w+)"#, flags: [], in: "ada@home bob@work", template: "$2:$1")
                == .replaced("home:ada work:bob", count: 2))
        #expect(RegexTester.replace(pattern: #"(?<first>\w)(\w*)"#, flags: [], in: "hello world", template: "${first}.")
                == .replaced("h. w.", count: 2))
        #expect(RegexTester.replace(pattern: "(a+)+$", flags: [], in: String(repeating: "a", count: 40) + "b", template: "", timeout: .milliseconds(100)) == .timedOut)
    }

    @Test func groupNamesSkipLookbehindAndClasses() {
        #expect(RegexTester.groupNames(in: #"(?<=x)(?<a>y)[(](?:z)(?P<b>w)\((q)"#) == [1: "a", 2: "b"])
    }
}

@Suite struct HighlighterTests {
    @Test func classifiesTokens() {
        let spans = JSONHighlighter.spans(in: #"{"a": "b", "n": -1.5e3, "t": true, "z": null}"#)
        #expect(spans.map(\.kind) == [.key, .string, .key, .number, .key, .keyword, .key, .keyword])
        #expect(spans[0].range == NSRange(location: 1, length: 3))
        #expect(spans[3].range == NSRange(location: 16, length: 6))
    }

    @Test func respectsLimit() {
        #expect(JSONHighlighter.spans(in: "[1,2]", limit: 3).isEmpty)
    }
}
