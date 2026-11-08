import Foundation
import Testing
@testable import ShorthandCore

@Suite("Placeholders")
struct PlaceholderTests {
    // 2026-11-07 14:05 UTC, a Saturday.
    let now = Date(timeIntervalSince1970: 1_794_060_300)
    var resolver: PlaceholderResolver {
        PlaceholderResolver(now: now, locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian),
                            timeZone: TimeZone(identifier: "UTC")!)
    }

    func resolve(_ content: String, clipboard: ClipboardValue = .text("slopapp-test clip"), typedCase: TypedCase = .asWritten) -> Resolved {
        resolver.resolve(content, typedCase: typedCase) { clipboard }
    }

    @Test func parsesTextAndTokens() {
        #expect(PlaceholderParser.parse("Hi {cursor}!") == [.text("Hi "), .placeholder(.cursor, raw: "{cursor}"), .text("!")])
        #expect(PlaceholderParser.parse("{{literal}}") == [.text("{literal}")])
        #expect(PlaceholderParser.parse("{nope}") == [.unknown("{nope}")])
        #expect(PlaceholderParser.parse("open { brace") == [.text("open { brace")])
        #expect(PlaceholderParser.parse("{date:long +1w}") == [.placeholder(.date(DateSpec(kind: .date, style: .long, offset: DateOffset(amount: 1, unit: .week))), raw: "{date:long +1w}")])
        #expect(PlaceholderParser.parse("{date:format=EEE d MMM}") == [.placeholder(.date(DateSpec(kind: .date, format: "EEE d MMM")), raw: "{date:format=EEE d MMM}")])
        #expect(PlaceholderParser.parse("{date:+1d +2d}") == [.unknown("{date:+1d +2d}")])
        #expect(PlaceholderParser.parse("{date:sometime}") == [.unknown("{date:sometime}")])
    }

    @Test func datesInTheLocale() {
        #expect(resolve("{date}").text == "Nov 7, 2026")
        #expect(resolve("{date:iso}").text == "2026-11-07")
        #expect(resolve("{date:long}").text == "November 7, 2026")
        #expect(resolve("{date:full}").text == "Saturday, November 7, 2026")
        #expect(resolve("{time}").text == "2:05\u{202F}PM")
        #expect(resolve("{time:iso}").text == "14:05")
        #expect(resolve("{date:format=EEE d MMM}").text == "Sat 7 Nov")
    }

    @Test func otherLocales() {
        let german = PlaceholderResolver(now: now, locale: Locale(identifier: "de_DE"), calendar: Calendar(identifier: .gregorian),
                                         timeZone: TimeZone(identifier: "UTC")!)
        #expect(german.resolve("{date:long}") { .none }.text == "7. November 2026")
    }

    @Test func offsetsAcrossMonthEnds() {
        #expect(resolve("{date:iso +1d}").text == "2026-11-08")
        #expect(resolve("{date:iso -1w}").text == "2026-10-31")
        #expect(resolve("{date:iso +3M}").text == "2027-02-07")
        #expect(resolve("{date:iso -1y}").text == "2025-11-07")
        #expect(resolve("{time:iso +30m}").text == "14:35")
        let jan31 = PlaceholderResolver(now: Date(timeIntervalSince1970: 1_801_396_800), locale: Locale(identifier: "en_US"),
                                        calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC")!)
        #expect(jan31.resolve("{date:iso +1M}") { .none }.text == "2027-02-28")
    }

    @Test func clipboard() {
        #expect(resolve("[{clipboard}]").text == "[slopapp-test clip]")
        #expect(resolve("[{clipboard}]", clipboard: .none).text == "[]")
        #expect(resolve("[{clipboard}]", clipboard: .concealed).text == "[]")
        let blocked = resolve("[{clipboard}]", clipboard: .notAllowed)
        #expect(blocked.text == "[]")
        #expect(blocked.clipboardBlocked)
        let huge = resolve("{clipboard}", clipboard: .text(String(repeating: "x", count: 200_000)))
        #expect(huge.text.count == PlaceholderResolver.clipboardLimit)
    }

    @Test func clipboardReadOnlyWhenNeeded() {
        var reads = 0
        _ = resolver.resolve("no clipboard here") { reads += 1; return .none }
        #expect(reads == 0)
        _ = resolver.resolve("{clipboard} and {clipboard}") { reads += 1; return .text("a") }
        #expect(reads == 1)
        #expect(PlaceholderResolver.needsClipboard("x {clipboard}"))
        #expect(!PlaceholderResolver.needsClipboard("x {{clipboard}}"))
    }

    @Test func cursor() {
        let r = resolve("Dear {cursor},\nThanks")
        #expect(r.text == "Dear ,\nThanks")
        #expect(r.charactersAfterCursor == 8)
        #expect(r.textBeforeCursor == "Dear ")
        #expect(resolve("{cursor}start").charactersAfterCursor == 5)
        #expect(resolve("end{cursor}").charactersAfterCursor == 0)
        #expect(resolve("none").charactersAfterCursor == 0)
        // Two cursors: the first wins, the second is dropped.
        #expect(resolve("a{cursor}b{cursor}c").charactersAfterCursor == 2)
        // Emoji count as one character (one ← press).
        #expect(resolve("{cursor}👍🏽").charactersAfterCursor == 1)
    }

    @Test func unknownPlaceholdersAreTypedAsWritten() {
        let r = resolve("x {mystery} y")
        #expect(r.text == "x {mystery} y")
        #expect(r.unknownPlaceholders == ["{mystery}"])
    }

    @Test func adaptCase() {
        #expect(resolve("hello there", typedCase: .capitalized).text == "Hello there")
        #expect(resolve("hello {date:iso}", typedCase: .upper).text == "HELLO 2026-11-07")
        #expect(resolve("1 main street", typedCase: .capitalized).text == "1 Main street")
    }

    @Test func tokensRoundTrip() {
        for placeholder: Placeholder in [.cursor, .clipboard, .date(DateSpec(kind: .date)), .date(DateSpec(kind: .time, style: .medium)),
                                         .date(DateSpec(kind: .date, style: .iso, offset: DateOffset(amount: -2, unit: .day))),
                                         .date(DateSpec(kind: .date, format: "d/M"))] {
            let token = PlaceholderParser.token(for: placeholder)
            #expect(PlaceholderParser.parse(token) == [.placeholder(placeholder, raw: token)])
        }
    }
}
