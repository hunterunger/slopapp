import Foundation
import Testing
@testable import ClipsCore

@Suite struct FormattingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    @Test func oneLineCollapsesWhitespace() {
        #expect(ClipText.oneLine("\n\n  hello \n\t world  \n") == "hello world")
        #expect(ClipText.oneLine(String(repeating: "a", count: 500), limit: 10).count == 10)
    }

    @Test func ages() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15))!
        #expect(ClipText.age(of: now - 10, now: now, calendar: calendar) == "now")
        #expect(ClipText.age(of: now - 300, now: now, calendar: calendar) == "5 min")
        #expect(ClipText.age(of: now - 7_200, now: now, calendar: calendar) == "2 hr")
        #expect(ClipText.age(of: now - 86_400, now: now, calendar: calendar) == "Yesterday")
        #expect(ClipText.age(of: now - 3 * 86_400, now: now, calendar: calendar) == "Fri")
        #expect(ClipText.age(of: now - 40 * 86_400, now: now, calendar: calendar) == "Sep 23")
        #expect(ClipText.age(of: now - 400 * 86_400, now: now, calendar: calendar) == "Sep 28, 2025")
    }

    @Test func ageSentences() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15))!
        #expect(ClipText.ageSentence(of: now - 10, now: now, calendar: calendar) == "Just now")
        #expect(ClipText.ageSentence(of: now - 300, now: now, calendar: calendar) == "5 min ago")
        #expect(ClipText.ageSentence(of: now - 86_400, now: now, calendar: calendar) == "Yesterday")
    }

    @Test func details() {
        #expect(ClipText.details(of: textClip("one\ntwo")) == "2 lines · 7 characters")
        #expect(ClipText.details(of: textClip("x")) == "1 line · 1 character")
    }

    @Test func ignoredAppsStorage() {
        #expect(IgnoredApp.decode(nil) == IgnoredApp.presets)
        #expect(IgnoredApp.decode(Data("junk".utf8)) == IgnoredApp.presets)
        let custom = [IgnoredApp(bundleID: "com.example.vault", name: "Vault")]
        #expect(IgnoredApp.decode(IgnoredApp.encode(custom)) == custom)
        #expect(IgnoredApp.decode(IgnoredApp.encode([])) == [])
    }

    @Test func shortcutConflicts() {
        let running = ["com.wiheads.paste-setapp", "com.apple.finder"]
        #expect(KnownShortcutOwner.conflicts(for: "⇧⌘V", runningBundleIDs: running).map(\.name) == ["Paste"])
        #expect(KnownShortcutOwner.conflicts(for: "⇧⌥V", runningBundleIDs: running).isEmpty)
        #expect(KnownShortcutOwner.running(in: running).map(\.name) == ["Paste"])
        #expect(ShortcutAdvice.appConflict(for: "⌘V") != nil)
        #expect(ShortcutAdvice.appConflict(for: "⇧⌥V") == nil)
    }
}
