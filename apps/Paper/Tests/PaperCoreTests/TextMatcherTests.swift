import Foundation
import Testing
@testable import PaperCore

@Suite struct TextMatcherTests {
    @Test func findsEveryOccurrenceIgnoringCase() {
        let ranges = TextMatcher.ranges(of: "secret", in: "Secret, SECRET and secretive")
        #expect(ranges.count == 3)
        #expect(ranges.first == NSRange(location: 0, length: 6))
    }

    @Test func caseSensitiveOption() {
        let ranges = TextMatcher.ranges(of: "Secret", in: "Secret, SECRET", options: .init(caseSensitive: true))
        #expect(ranges == [NSRange(location: 0, length: 6)])
    }

    @Test func wholeWordSkipsPartsOfWords() {
        let text = "cat catalog concat cat."
        let ranges = TextMatcher.ranges(of: "cat", in: text, options: .init(wholeWord: true))
        #expect(ranges.map(\.location) == [0, 19])
    }

    @Test func wholeWordStillMatchesInScriptsWithoutSpaces() {
        let text = "口座番号は東京支店です。"
        #expect(TextMatcher.ranges(of: "東京", in: text, options: .init(wholeWord: true)).count == 1)
    }

    @Test func emptyOrWhitespaceQueryFindsNothing() {
        #expect(TextMatcher.ranges(of: "  ", in: "anything").isEmpty)
        #expect(TextMatcher.ranges(of: "x", in: "").isEmpty)
    }

    @Test func queryIsTrimmed() {
        #expect(TextMatcher.ranges(of: " fox ", in: "the fox").count == 1)
    }

    @Test func accentedTextMatches() {
        #expect(TextMatcher.ranges(of: "déjà", in: "Café déjà vu").count == 1)
    }

    @Test func contextCollapsesWhitespaceAndAddsEllipses() {
        let text = String(repeating: "a ", count: 40) + "needle\nin   the haystack" + String(repeating: " b", count: 40)
        let range = (text as NSString).range(of: "needle")
        let context = TextMatcher.context(for: range, in: text, radius: 10)
        #expect(context.hasPrefix("…"))
        #expect(context.hasSuffix("…"))
        #expect(context.contains("needle in the"))
        #expect(!context.contains("\n"))
    }

    @Test func contextAtStartHasNoLeadingEllipsis() {
        let context = TextMatcher.context(for: NSRange(location: 0, length: 3), in: "abc def", radius: 10)
        #expect(context == "abc def")
    }

    @Test func countIsExact() {
        #expect(TextMatcher.count(of: "ab", in: "ab abab AB") == 3)
        #expect(TextMatcher.count(of: "", in: "ab") == 0)
    }
}
