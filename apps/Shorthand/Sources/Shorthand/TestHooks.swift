import AppKit
import ShorthandCore
import SlopKit

/// `SHORTHAND_TEST_HOOKS=1`: distributed notifications `app.slopapp.shorthand.test.<name>`,
/// for scripted walkthroughs. They only touch Shorthand's own state and windows.
///
/// - `library` / `library-passive` (open it, without activating), `settings` (object: tab
///   title), `new`, `import`, `import-file` (object: a fixture under /tmp/shorthand-test/)
/// - `replay` (object: timeline path): see `AppModel.replay`
/// - `seed` (object: path to a Shorthand JSON export): replace the library (test data only)
/// - `pause`, `resume`, `exclude`/`include` (object: bundle id), `insertmode` (object: mode),
///   `wordstart` (object: 0/1)
/// - `stats`: logs the tap's latency histogram and `CGGetEventTapList` entry
/// - `benchmark` (object: key count): engine + callback benchmark, logged
/// - `select` (object: abbreviation)
/// - `editor-select-all`: select all of the open editor's text
/// - `search` (toggle the search panel), `search-query` (object: text), `search-pick` (object:
///   row number from 1; inserts or opens the form), `search-copy`
/// - `insert` (object: abbreviation): insert that snippet as if picked in the search panel
/// - `fill` (object: `name=value;name=value`): set the open form's fields, `fill-insert`, `fill-cancel`
@MainActor
enum TestHooks {
    static let prefix = "app.slopapp.shorthand.test."

    static func install() {
        let center = DistributedNotificationCenter.default()
        func on(_ name: String, _ body: @escaping @MainActor (String?) -> Void) {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { note in
                let object = note.object as? String
                MainActor.assumeIsolated { body(object) }
            }
        }
        on("library") { _ in LibraryOpener.open() }
        on("library-passive") { _ in LibraryOpener.open(activate: false) }
        on("new") { _ in LibraryOpener.open(activate: false, request: .newSnippet) }
        on("import") { _ in LibraryOpener.open(activate: false, request: .importReplacements) }
        on("import-file") { path in
            guard let path, path.hasPrefix("/tmp/shorthand-test/") || path.hasPrefix("/private/tmp/shorthand-test/") else { return }
            LibraryOpener.open(activate: false, request: .importFile(URL(fileURLWithPath: path)))
        }
        on("settings") { _ in SettingsWindow.open() }
        on("replay") { path in
            guard let path else { return }
            Task { await AppModel.shared.replay(URL(fileURLWithPath: path)) }
        }
        on("seed") { path in
            guard Diagnostics.isTestMode, let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let library = try? SnippetStore.decode(data) else { return }
            AppModel.shared.edit { $0 = library }
            Diagnostics.record("seeded snippets=\(library.snippets.count)")
        }
        on("exclude") { id in
            guard let id else { return }
            AppModel.shared.excludedApps.append(.init(bundleID: id, name: "Test Pad"))
        }
        on("include") { id in AppModel.shared.excludedApps.removeAll { $0.bundleID == id } }
        on("insertmode") { mode in AppModel.shared.insertMode = InsertMode(rawValue: mode ?? "") ?? .automatic }
        on("wordstart") { value in AppModel.shared.wordStartOnly = value == "1" }
        on("pause") { _ in AppModel.shared.isEnabled = false }
        on("resume") { _ in AppModel.shared.isEnabled = true }
        on("stats") { _ in
            Diagnostics.record("stats " + AppModel.shared.latencySummary() + " " + EventTapStats.summary()
                               + " status=\(AppModel.shared.status.line)")
        }
        on("benchmark") { object in benchmark(keys: Int(object ?? "") ?? 1_000_000) }
        on("select") { abbreviation in LibraryOpener.open(activate: false, request: .select(abbreviation ?? "")) }
        on("editor-select-all") { _ in
            guard let view = TextViewHandle.current?.textView else { return }
            view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        }
        on("search") { _ in AppModel.shared.toggleSearch() }
        on("search-query") { text in AppModel.shared.search.state.query = text ?? "" }
        on("search-pick") { number in
            let state = AppModel.shared.search.state
            let index = (Int(number ?? "1") ?? 1) - 1
            guard state.results.indices.contains(index) else { return }
            let id = state.results[index].id
            AppModel.shared.search.dismiss()
            Task { await AppModel.shared.insertFromSearch(id) }
        }
        on("search-copy") { _ in
            guard let snippet = AppModel.shared.search.state.selected else { return }
            AppModel.shared.search.dismiss()
            AppModel.shared.copySnippet(snippet.id)
        }
        on("insert") { abbreviation in
            guard let snippet = AppModel.shared.library.snippet(abbreviation: abbreviation ?? "") else { return }
            Task { await AppModel.shared.insertFromSearch(snippet.id) }
        }
        on("fill") { pairs in
            guard let state = AppModel.shared.fillIn.state else { return }
            for pair in (pairs ?? "").split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                if parts[1] == "on" || parts[1] == "off" { state.values[parts[0]] = .flag(parts[1] == "on") } else { state.values[parts[0]] = .text(parts[1]) }
            }
        }
        on("fill-insert") { _ in AppModel.shared.fillIn.state?.insert() }
        on("fill-cancel") { _ in AppModel.shared.fillIn.state?.onCancel() }
    }

    /// The matcher with 5,000 abbreviations, and the full callback path (decode a real
    /// `CGEvent`, lock, engine, histogram) over constructed events. Nothing is posted.
    static func benchmark(keys: Int) {
        let index = AbbreviationIndex(snippets: Benchmark.library(count: 5_000))
        let engine = Benchmark.run(index: index, keys: keys)
        Diagnostics.record("benchmark matcher 5000 abbreviations " + engine.summary)

        let shared = TapShared()
        shared.update { $0.index = index }
        let source = CGEventSource(stateID: .hidSystemState)
        let text = Array("the quick brown fox jumps over the lazy dog; ;k12 then more words. ".utf16)
        let events: [CGEvent] = text.compactMap { unit in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return nil }
            var units = [unit]
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &units)
            return event
        }
        var expansions = 0
        for i in 0..<keys {
            let start = MonotonicClock.now()
            let decision = shared.handle(KeyDecoder.decode(events[i % events.count], type: .keyDown), start: start)
            if case .expand(let match) = decision {
                expansions += 1
                shared.cancel(match.id)
            }
        }
        Diagnostics.record("benchmark callback path " + shared.latency.summary + " expansions=\(expansions)")
    }
}
