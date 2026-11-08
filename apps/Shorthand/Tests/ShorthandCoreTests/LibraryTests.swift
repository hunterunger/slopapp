import Foundation
import Testing
@testable import ShorthandCore

/// Test files live in /tmp/shorthand-test only.
func testDirectory() -> URL {
    let url = URL(fileURLWithPath: "/tmp/shorthand-test/unit-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Library")
struct LibraryTests {
    @Test func alwaysHasAGroup() {
        let library = Library()
        #expect(library.groups.count == 1)
        #expect(library.groups[0].name == "Snippets")
        var orphan = Library(snippets: [snippet(";x")])
        orphan.normalize()
        #expect(orphan.snippets[0].groupID == orphan.defaultGroupID)
    }

    @Test func duplicateDeleteAndUndo() {
        var library = Library()
        let a = library.addSnippet(Snippet(groupID: library.defaultGroupID, name: "Address", abbreviation: ";addr", content: "slopapp-test 1"))
        let b = library.addSnippet(Snippet(groupID: library.defaultGroupID, abbreviation: ";b", content: "slopapp-test 2"))
        let copy = library.duplicate(a.id)!
        #expect(library.snippets.map(\.id) == [a.id, copy.id, b.id])
        #expect(copy.abbreviation == "")
        #expect(copy.name == "Address copy")
        let removed = library.removeSnippets([a.id, b.id])
        #expect(library.snippets.map(\.id) == [copy.id])
        library.restore(removed)
        #expect(library.snippets.map(\.id) == [a.id, copy.id, b.id])
    }

    @Test func deleteGroupWithUndo() {
        var library = Library()
        let work = library.addGroup(named: "Work")
        library.addSnippet(Snippet(groupID: work.id, abbreviation: ";w", content: "slopapp-test"))
        let removed = library.removeGroup(work.id)!
        #expect(library.groups.count == 1)
        #expect(library.snippets.isEmpty)
        library.restore(removed)
        #expect(library.groups.map(\.name) == ["Snippets", "Work"])
        #expect(library.snippets.count == 1)
        // The last group stays.
        #expect(library.removeGroup(library.defaultGroupID) != nil)
        #expect(library.removeGroup(library.defaultGroupID) == nil)
    }

    @Test func uniqueGroupNames() {
        var library = Library()
        #expect(library.addGroup(named: "Snippets").name == "Snippets 2")
        #expect(library.addGroup(named: "Snippets").name == "Snippets 3")
    }

    @Test func titleFallsBackToFirstLine() {
        #expect(Snippet(groupID: UUID(), abbreviation: "x", content: "\n  First line\nSecond").title == "First line")
        #expect(Snippet(groupID: UUID(), abbreviation: "x", content: "").title == "Empty snippet")
    }

    @Test func useCounts() {
        var library = Library()
        let s = library.addSnippet(Snippet(groupID: library.defaultGroupID, abbreviation: ";u", content: "slopapp-test"))
        let date = Date(timeIntervalSince1970: 1_000)
        library.recordUse(s.id, at: date)
        library.recordUse(s.id, at: date)
        #expect(library.snippet(s.id)?.useCount == 2)
        #expect(library.snippet(s.id)?.lastUsed == date)
    }
}

@Suite("Store")
struct StoreTests {
    @Test func roundTripsAtomically() throws {
        let store = SnippetStore(directory: testDirectory())
        #expect(store.load() == .fresh(Library()) || store.load().library.snippets.isEmpty)
        var library = Library()
        library.addSnippet(Snippet(groupID: library.defaultGroupID, abbreviation: ";a", content: "slopapp-test é 👍🏽\n{date}"))
        try store.save(library)
        guard case .loaded(let loaded) = store.load() else { Issue.record("not loaded"); return }
        #expect(loaded.snippets.map(\.content) == library.snippets.map(\.content))
    }

    @Test func damagedFileLoadsTheNewestBackup() throws {
        let directory = testDirectory()
        let store = SnippetStore(directory: directory)
        var library = Library()
        library.addSnippet(Snippet(groupID: library.defaultGroupID, abbreviation: ";a", content: "slopapp-test"))
        try store.save(library)
        store.backUpIfNeeded(now: Date(timeIntervalSince1970: 1_800_000_000))
        try Data("{ not json".utf8).write(to: store.fileURL)
        guard case .recovered(let recovered, let name) = store.load() else { Issue.record("not recovered"); return }
        #expect(recovered.snippets.count == 1)
        #expect(name.hasPrefix("Library 2027"))
        let damaged = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("damaged") }
        #expect(damaged.count == 1)
    }

    @Test func damagedWithoutBackupsStartsEmpty() throws {
        let store = SnippetStore(directory: testDirectory())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.fileURL)
        guard case .damaged(let library) = store.load() else { Issue.record("expected damaged"); return }
        #expect(library.snippets.isEmpty)
    }

    @Test func keepsSevenDailyBackups() throws {
        let store = SnippetStore(directory: testDirectory())
        try store.save(Library())
        for day in 0..<10 {
            store.backUpIfNeeded(now: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400))
            store.backUpIfNeeded(now: Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400 + 60))
        }
        #expect(store.backups().count == 7)
    }

    @Test func exportMergesByGroupAndSkipsKnownAbbreviations() throws {
        var source = Library()
        let work = source.addGroup(named: "Work")
        source.addSnippet(Snippet(groupID: work.id, abbreviation: ";w", content: "slopapp-test w"))
        source.addSnippet(Snippet(groupID: work.id, abbreviation: ";dup", content: "slopapp-test d"))
        let data = try LibraryExport.data(source)
        var target = Library()
        target.addSnippet(Snippet(groupID: target.defaultGroupID, abbreviation: ";dup", content: "mine"))
        let added = LibraryExport.merge(try SnippetStore.decode(data), into: &target)
        #expect(added == 1)
        #expect(target.groups.map(\.name) == ["Snippets", "Work"])
    }
}

@Suite("Text Replacements import")
struct ImportTests {
    /// What System Settings writes when Text Replacements rows are dragged out (fixture, not
    /// anyone's real list).
    let exported = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <array>
        <dict><key>phrase</key><string>slopapp-test on my way</string><key>shortcut</key><string>omw</string></dict>
        <dict><key>phrase</key><string>slopapp-test line one\r\nline two</string><key>shortcut</key><string>;two</string></dict>
        <dict><key>phrase</key><string>slopapp-test spaced</string><key>shortcut</key><string>has space</string></dict>
        <dict><key>phrase</key><string>slopapp-test again</string><key>shortcut</key><string>omw</string></dict>
        <dict><key>phrase</key><string>slopapp-test {braces}</string><key>shortcut</key><string>;br</string></dict>
        <dict><key>phrase</key><string>slopapp-test exists</string><key>shortcut</key><string>;have</string></dict>
        <dict><key>phrase</key><string>スロップ</string><key>shortcut</key><string>すろ</string></dict>
    </array>
    </plist>
    """

    @Test func readsTheExportAndFlagsProblems() throws {
        var library = Library()
        library.addSnippet(Snippet(groupID: library.defaultGroupID, abbreviation: ";have", content: "mine"))
        let entries = try TextReplacementsImport.entries(fromPlist: Data(exported.utf8))
        #expect(entries.count == 7)
        let rows = TextReplacementsImport.candidates(entries, library: library)
        #expect(rows.map(\.isSelected) == [true, true, false, false, true, false, true])
        #expect(rows[1].phrase == "slopapp-test line one\nline two")
        #expect(rows[2].issue == .invalid(.whitespace))
        #expect(rows[3].issue == .repeated)
        #expect(rows[5].issue == .alreadyInLibrary)
        #expect(!rows[2].canSelect)
        #expect(rows[5].canSelect)

        let added = TextReplacementsImport.apply(rows, to: &library)
        #expect(added == 4)
        let group = library.groups.first { $0.name == "Text Replacements" }
        #expect(group != nil)
        // Braces stay literal.
        let braces = library.snippets.first { $0.abbreviation == ";br" }!
        #expect(PlaceholderResolver(now: Date()).resolve(braces.content) { .none }.text == "slopapp-test {braces}")
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: TextReplacementsImport.ReadError.notAPropertyList) {
            try TextReplacementsImport.entries(fromPlist: Data([0xFF, 0x00, 0x13, 0x7B]))
        }
        let dict = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>a</key><string>b</string></dict></plist>"
        #expect(throws: TextReplacementsImport.ReadError.notTextReplacements) {
            try TextReplacementsImport.entries(fromPlist: Data(dict.utf8))
        }
    }

    @Test func fromTheSpellCheckerDictionary() {
        let entries = TextReplacementsImport.entries(fromDictionary: ["omw": "slopapp-test a", "brb": "slopapp-test b"])
        #expect(entries.map(\.shortcut) == ["brb", "omw"])
        #expect(TextReplacementsImport.candidates([], library: Library()).isEmpty)
    }

    @Test func tenThousandEntries() {
        let entries = (0..<10_000).map { (shortcut: ";s\($0)", phrase: "slopapp-test \($0)") }
        var library = Library()
        let rows = TextReplacementsImport.candidates(entries, library: library)
        #expect(TextReplacementsImport.apply(rows, to: &library) == 10_000)
        let index = AbbreviationIndex(snippets: library.expandable)
        #expect(index.entries.count == 10_000)
    }
}

@Suite("Search")
struct SearchTests {
    @Test func caseAndAccentInsensitive() {
        let group = UUID()
        let a = Snippet(groupID: group, name: "Café address", abbreviation: ";cafe", content: "slopapp-test Rue")
        let b = Snippet(groupID: group, abbreviation: ";sig", content: "Best regards, Zoë", useCount: 5)
        #expect(SnippetSearch.search([a, b], query: "CAFE").map(\.id) == [a.id])
        #expect(SnippetSearch.search([a, b], query: "zoe").map(\.id) == [b.id])
        #expect(SnippetSearch.search([a, b], query: "rue cafe").map(\.id) == [a.id])
        #expect(SnippetSearch.search([a, b], query: "").count == 2)
        #expect(SnippetSearch.search([a, b], query: "nothing").isEmpty)
    }

    @Test func abbreviationHitsFirstThenMostUsed() {
        let group = UUID()
        let content = Snippet(groupID: group, abbreviation: ";zz", content: "sig is here", useCount: 9)
        let abbreviation = Snippet(groupID: group, abbreviation: "sig", content: "slopapp-test")
        #expect(SnippetSearch.search([content, abbreviation], query: "sig").map(\.id) == [abbreviation.id, content.id])
    }

    @Test func fiveThousandSnippetsSearchFast() {
        let snippets = Benchmark.library(count: 5_000)
        let start = MonotonicClock.now()
        _ = SnippetSearch.search(snippets, query: "expansion 4999")
        let ms = Double(MonotonicClock.now() - start) / 1_000_000
        #expect(ms < 160) // budget 16 ms per keystroke in release; ×10 for debug builds
    }
}
