import Foundation
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

func textClip(_ text: String, at date: Date = now, source: String? = nil) -> Clip {
    try! ClipBuilder.build(PasteboardSnapshot(text: text), sourceBundleID: source, sourceName: source, now: date).get().0
}

@Suite struct HistoryTests {
    @Test func newestFirst() {
        var history = History()
        history.record(textClip("one", at: now))
        history.record(textClip("two", at: now + 1))
        #expect(history.clips.map(\.text) == ["two", "one"])
    }

    @Test func copyingAgainMovesToTopInsteadOfDuplicating() {
        var history = History()
        let first = textClip("one", at: now)
        history.record(first)
        history.record(textClip("two", at: now + 1))
        let result = history.record(textClip("one", at: now + 2, source: "com.apple.Notes"))
        guard case .bumped(let bumped) = result else { Issue.record("expected bump"); return }
        #expect(bumped.id == first.id)
        #expect(bumped.useCount == 2)
        #expect(bumped.lastUsed == now + 2)
        #expect(bumped.created == now)
        #expect(bumped.sourceBundleID == "com.apple.Notes")
        #expect(history.clips.map(\.text) == ["one", "two"])
    }

    @Test func touchMovesToTop() {
        var history = History()
        let a = textClip("a", at: now)
        history.record(a)
        history.record(textClip("b", at: now + 1))
        history.touch(id: a.id, now: now + 5)
        #expect(history.clips.first?.id == a.id)
        #expect(history.clips.first?.useCount == 2)
    }

    @Test func pinAndRemoveAndRestore() {
        var history = History()
        let a = textClip("a", at: now), b = textClip("b", at: now + 1), c = textClip("c", at: now + 2)
        [a, b, c].forEach { history.record($0) }
        history.setPinned(true, id: a.id)
        #expect(history.clip(id: a.id)?.isPinned == true)
        let removed = history.remove(ids: [b.id])
        #expect(history.clips.map(\.text) == ["c", "a"])
        history.restore(removed)
        #expect(history.clips.map(\.text) == ["c", "b", "a"])
        history.restore(removed) // no duplicates
        #expect(history.clips.count == 3)
    }

    @Test func clearKeepsPinned() {
        var history = History()
        let a = textClip("a"), b = textClip("b", at: now + 1)
        history.record(a); history.record(b)
        history.setPinned(true, id: a.id)
        let removed = history.clear()
        #expect(removed.map(\.text) == ["b"])
        #expect(history.clips.map(\.text) == ["a"])
        history.clear(keepPinned: false)
        #expect(history.clips.isEmpty)
    }

    @Test func pruneByAgeSparesPinned() {
        var history = History()
        let old = textClip("old", at: now - 10 * 86_400)
        let oldPinned = textClip("old pinned", at: now - 400 * 86_400)
        let fresh = textClip("fresh", at: now - 3_600)
        [oldPinned, old, fresh].forEach { history.record($0) }
        history.setPinned(true, id: oldPinned.id)
        let removed = history.prune(retention: .week, now: now)
        #expect(removed == [old.id])
        #expect(Set(history.clips.map(\.text)) == ["fresh", "old pinned"])
        #expect(history.prune(retention: .forever, now: now + 1_000 * 86_400).isEmpty)
    }

    @Test func pruneByCount() {
        var history = History(itemLimit: 3)
        for i in 0..<5 { history.record(textClip("item \(i)", at: now + Double(i))) }
        let pinned = history.clips.last!
        history.setPinned(true, id: pinned.id)
        history.prune(retention: .forever, now: now)
        #expect(history.clips.map(\.text) == ["item 4", "item 3", "item 2", "item 0"])
    }

    @Test func retentionAges() {
        #expect(HistoryRetention.day.maxAge == 86_400)
        #expect(HistoryRetention.forever.maxAge == nil)
        #expect(HistoryRetention.allCases.count == 6)
    }
}

@Suite struct SearchTests {
    let clips: [Clip] = [
        textClip("Café meeting notes", at: now + 3, source: "Notes"),
        textClip("https://example.com/report", at: now + 2, source: "Safari"),
        textClip("Invoice 2026 draft", at: now + 1, source: "Mail"),
        textClip("#336699", at: now),
    ]

    @Test func emptyQueryReturnsEverything() {
        #expect(ClipSearch.run(clips, query: "  ").count == 4)
    }

    @Test func caseAndAccentInsensitive() {
        #expect(ClipSearch.run(clips, query: "CAFE").map(\.text) == ["Café meeting notes"])
        #expect(ClipSearch.run(clips, query: "café").count == 1)
    }

    @Test func everyWordMustMatchInAnyOrder() {
        #expect(ClipSearch.run(clips, query: "draft invoice").map(\.text) == ["Invoice 2026 draft"])
        #expect(ClipSearch.run(clips, query: "draft meeting").isEmpty)
    }

    @Test func matchesSourceApp() {
        #expect(ClipSearch.run(clips, query: "safari").map(\.kind) == [.link])
    }

    @Test func filters() {
        #expect(ClipSearch.run(clips, query: "", filter: .links).count == 1)
        #expect(ClipSearch.run(clips, query: "", filter: .text).count == 3) // colors count as text
        #expect(ClipSearch.run(clips, query: "", filter: .images).isEmpty)
        var pinned = clips
        pinned[2].isPinned = true
        #expect(ClipSearch.run(pinned, query: "", filter: .pinned).map(\.text) == ["Invoice 2026 draft"])
    }

    @Test func highlightsEveryWordIgnoringCaseAndAccents() {
        let text = "Café meeting notes, cafe again"
        let ranges = SearchText.highlights(in: text, query: "CAFE note")
        let words = ranges.map { (text as NSString).substring(with: $0) }
        #expect(words == ["Café", "note", "cafe"])
        #expect(SearchText.highlights(in: text, query: "  ").isEmpty)
        #expect(SearchText.highlights(in: "aaaa", query: "aa a").count == 1) // merged
    }

    @Test func findsWordsDeepInLongClips() {
        let long = String(repeating: "slopapp-test filler words ", count: 8_400) + "ENDMARK" // ~218k chars
        let clip = textClip(long)
        #expect(clip.text.count == Clip.textLimit)
        #expect(clip.longText?.count == long.count)
        #expect(!clip.isSearchTruncated)
        #expect(ClipSearch.run([clip], query: "endmark").count == 1)
        let huge = textClip(String(repeating: "x", count: Clip.searchLimit + 10) + " LATE")
        #expect(huge.isSearchTruncated)
        #expect(ClipSearch.run([huge], query: "late").isEmpty)
    }

    @Test func snippetsShowDeepMatches() {
        let text = "Meeting notes for the quarterly planning session with the whole team, and then the invoice number 4471 for March"
        let snippet = ClipText.snippet(in: text, query: "invoice")
        #expect(snippet?.hasPrefix("…") == true)
        #expect(snippet?.contains("invoice number 4471") == true)
        #expect(ClipText.snippet(in: text, query: "meeting") == nil) // visible in the title
        #expect(ClipText.snippet(in: text, query: "absent") == nil)
        #expect(ClipText.snippet(in: text, query: " ") == nil)
    }

    @Test func fiveThousandItemsFilterFast() {
        let synthetic = SyntheticHistory.make(count: 5_000, now: now).map(\.0)
        #expect(synthetic.count == 5_000)
        let clock = ContinuousClock()
        var hits = 0
        // Simulate typing a query one letter at a time.
        let elapsed = clock.measure {
            for query in ["s", "sy", "syn", "synthetic 49", "synthetic 499", "zulu del", "café"] {
                hits = ClipSearch.run(synthetic, query: query).count
            }
        }
        #expect(hits > 0)
        // Seven searches; each must fit well inside a frame. Generous for slow CI machines.
        #expect(elapsed < .milliseconds(150), "7 searches over 5,000 clips took \(elapsed)")
    }
}
