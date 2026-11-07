import AppKit
import Observation
import SlopKit
import TallyCore
import UniformTypeIdentifiers

/// What the result column shows for one line.
struct ResultDisplay: Equatable {
    enum Kind: Equatable { case value, error }
    var text: String
    var kind: Kind
    /// Uses downloaded rates older than a week.
    var isStale: Bool = false
    /// Clicking opens Settings ▸ Currency.
    var opensCurrencySettings: Bool = false
    var help: String?
}

/// A sheet in the sidebar.
struct SheetRow: Identifiable, Equatable {
    let id: UUID
    var title: String
    var modified: Date
}

/// The bar under the sheet: the running total, or the total of the selected lines.
struct Footer: Equatable {
    var total: String?
    var isSelection = false
}

/// The library of sheets, the open sheet, its answers, autosave, copying and rates. The
/// editors (NSTextViews in the window and the menu bar panel) share the current sheet's
/// text storage and report every change here.
@MainActor
@Observable
final class SheetModel {
    static let shared = SheetModel()

    private(set) var rows: [SheetRow] = []
    private(set) var currentID: UUID
    private(set) var currentTitle: String = ""
    private(set) var footer = Footer()
    private(set) var theme: Theme = Theme.current
    private(set) var pointSize: CGFloat = TextSize.pointSize(step: TextSize.defaultStep)
    let rates: RatesUpdater
    /// Bumped when rates change, so Settings refreshes.
    private(set) var ratesRevision = 0

    @ObservationIgnored private(set) var current: SheetDocument
    @ObservationIgnored let styler: SheetStyler
    /// Milliseconds the last evaluation took (shown nowhere; logged for perf checks).
    @ObservationIgnored private(set) var lastEvaluationMillis: Double = 0
    @ObservationIgnored var openSettingsAction: (() -> Void)?

    @ObservationIgnored private let library: SheetLibrary
    @ObservationIgnored private var documents: [UUID: SheetDocument] = [:]
    @ObservationIgnored private var titles: [UUID: String] = [:]
    @ObservationIgnored private var editors: [WeakEditor] = []
    @ObservationIgnored private let engine = SheetEngine()
    @ObservationIgnored private let clipboard: Clipboard
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    /// Formatted results, keyed by value; cleared when the format settings or the day change.
    @ObservationIgnored private var formatCache: [Quantity: String] = [:]
    @ObservationIgnored private var formatCacheKey = ""
    @ObservationIgnored private var staleHelp = "Click to copy"
    @ObservationIgnored private var selectedLines: ClosedRange<Int>?

    init(libraryStorage: LibraryStorage = FileLibraryStorage(directory: Platform.dataDirectory),
         ratesStorage: RatesStorage = FileRatesStorage(directory: Platform.dataDirectory),
         fetcher: RatesFetching = ECBFetcher(url: Platform.ratesURL),
         clipboard: Clipboard = SystemClipboard(),
         now: @escaping () -> Date = Date.init,
         timeZone: TimeZone = .current) {
        self.clipboard = clipboard
        self.now = now
        self.timeZone = timeZone
        rates = RatesUpdater(storage: ratesStorage, fetcher: fetcher)
        library = SheetLibrary(storage: libraryStorage, firstText: SheetText.welcome, now: now)
        styler = SheetStyler(pointSize: TextSize.pointSize(step: Pref.defaults.object(forKey: Pref.textSizeStep) as? Int ?? TextSize.defaultStep),
                             theme: Theme.current)
        let id = library.currentID
        let document = SheetDocument(id: id, text: library.text(of: id))
        current = document
        currentID = id
        pointSize = styler.pointSize
        documents[id] = document
        styler.variables = { [weak self] storage in self?.document(for: storage)?.variables ?? [] }
        prepare(document)
        for sheet in library.sheets where sheet.id != id {
            titles[sheet.id] = SheetTitle.title(of: library.text(of: sheet.id))
        }
        rates.onChange = { [weak self] in
            guard let self else { return }
            ratesRevision += 1
            evaluate()
        }
        evaluate()
        refreshRows()
        startRatesSchedule()
    }

    // MARK: Current sheet (also the API tests use)

    var text: String { current.text }
    var lines: [String] { current.lines }
    var outputs: [LineOutput] { current.outputs }
    var displays: [ResultDisplay?] { current.displays }

    var formatter: ResultFormatter {
        ResultFormatter(locale: .current, dollarCode: Pref.dollar, now: minute, timeZone: timeZone)
    }

    var context: SheetContext {
        SheetContext(rates: rates.state, dollarCode: Pref.dollar, css: Pref.css, now: minute, timeZone: timeZone)
    }

    /// The clock, to the minute: answers show minutes and refresh on the minute, and equal
    /// values within a minute reuse their formatted text.
    private var minute: Date {
        let t = now().timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 60).rounded(.down) * 60)
    }

    /// Replaces the current sheet's text (tests, import). Editors normally edit the storage
    /// directly and call `storageDidChange()`.
    func textDidChange(_ newText: String) {
        let storage = current.storage
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: newText)
        storageDidChange()
    }

    /// An editor changed the current sheet's text.
    func storageDidChange() {
        current.dirty = true
        evaluate()
        scheduleSave()
    }

    func evaluate() {
        let start = ContinuousClock.now
        let document = current
        let context = context
        let namesChanged = document.evaluate(engine: engine, context: context)
        let formatter = formatter
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.component(.day, from: context.now)
        let key = Pref.dollar + Locale.current.identifier + "\(day)"
        if key != formatCacheKey || formatCache.count > 20_000 {
            formatCache.removeAll(keepingCapacity: true)
            formatCacheKey = key
        }
        let staleRates: Bool = {
            if case .loaded(_, let stale) = context.rates { return stale }
            return false
        }()
        staleHelp = rates.table.map { "Uses exchange rates from \($0.displayDate()). Click to copy." } ?? "Click to copy"
        document.displays = document.outputs.map { display(for: $0, formatter: formatter, staleRates: staleRates) }
        let elapsed = ContinuousClock.now - start
        lastEvaluationMillis = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        if namesChanged { styler.styleAll(document.storage) }
        updateFooter()
        let title = document.title
        if title != currentTitle {
            currentTitle = title
            titles[document.id] = title
            refreshRows()
        }
        for editor in liveEditors { editor.apply(displays: document.displays) }
        scheduleClockRefresh()
    }

    private func display(for output: LineOutput, formatter: ResultFormatter, staleRates: Bool) -> ResultDisplay? {
        switch output.result {
        case .none:
            return nil
        case .value(let q):
            let stale = staleRates && output.usesDownloadedRates
            let help = stale ? staleHelp : "Click to copy"
            let text: String
            // Dates cache too: how a date shows only depends on today, which is in the key.
            if let cached = formatCache[q] {
                text = cached
            } else {
                text = formatter.format(q)
                formatCache[q] = text
            }
            return ResultDisplay(text: text, kind: .value, isStale: stale, help: help)
        case .error(let e):
            let opens = e == .ratesOff || e == .ratesUnavailable
            return ResultDisplay(text: e.message, kind: .error, opensCurrencySettings: opens,
                                 help: opens ? "Click to open Currency settings" : e.advice)
        }
    }

    /// Answers that read the clock (`now`, `3pm PST in CET`) refresh on the minute.
    private func scheduleClockRefresh() {
        guard current.usesClock else {
            clockTask?.cancel()
            clockTask = nil
            return
        }
        guard clockTask == nil else { return }
        clockTask = Task { @MainActor [weak self] in
            let seconds = 60 - Calendar.current.component(.second, from: Date()) + 1
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            clockTask = nil
            evaluate()
        }
    }

    // MARK: Footer

    /// The lines the selection covers (nil for a plain insertion point on one line).
    func selectionChanged(_ range: NSRange, lineStarts: [Int]) {
        let first = SheetText.lineIndex(containing: range.location, lineStarts: lineStarts)
        let last = SheetText.lineIndex(containing: max(range.location, NSMaxRange(range) - 1), lineStarts: lineStarts)
        let lines: ClosedRange<Int>? = range.length > 0 && last > first ? first...last : nil
        guard lines != selectedLines else { return }
        selectedLines = lines
        updateFooter()
    }

    private func updateFooter() {
        let outputs = current.outputs
        var isSelection = false
        let total: Quantity?
        if let lines = selectedLines, lines.upperBound < outputs.count {
            total = SheetEngine.total(of: outputs[lines], context: context)
            isSelection = true
        } else {
            total = SheetEngine.total(of: outputs, context: context)
        }
        let next = Footer(total: total.map { formatter.format($0) }, isSelection: isSelection)
        if next != footer { footer = next }
    }

    func copyTotal() {
        let outputs = selectedLines.flatMap { $0.upperBound < current.outputs.count ? Array(current.outputs[$0]) : nil } ?? current.outputs
        guard let total = SheetEngine.total(of: outputs, context: context) else {
            NSSound.beep()
            return
        }
        let text = Pref.includesUnit ? formatter.format(total) : formatter.plainNumber(total)
        clipboard.setString(text)
        HUD.show("Copied \(text)", systemImage: "doc.on.doc")
    }

    // MARK: Sheets

    private func document(for storage: NSTextStorage) -> SheetDocument? {
        if current.storage === storage { return current }
        return documents.values.first { $0.storage === storage }
    }

    private func loadDocument(_ id: UUID) -> SheetDocument {
        if let doc = documents[id] { return doc }
        let doc = SheetDocument(id: id, text: library.text(of: id))
        documents[id] = doc
        prepare(doc)
        return doc
    }

    private func prepare(_ document: SheetDocument) {
        document.storage.delegate = styler
        styler.styleAll(document.storage)
        document.styledGeneration = styler.generation
    }

    private func refreshRows() {
        let next = library.sheets.map { info in
            SheetRow(id: info.id, title: info.id == current.id ? current.title : (titles[info.id] ?? SheetTitle.untitled),
                     modified: info.modified)
        }
        if next != rows { rows = next }
    }

    func select(_ id: UUID) {
        guard id != current.id, rows.contains(where: { $0.id == id }) else { return }
        saveNow()
        for editor in liveEditors { current.selection = editor.selectedRange() }
        let document = loadDocument(id)
        if document.styledGeneration != styler.generation {
            styler.styleAll(document.storage)
            document.styledGeneration = styler.generation
        }
        current = document
        currentID = id
        library.select(id)
        selectedLines = nil
        currentTitle = document.title
        evaluate()
        for editor in liveEditors { editor.show(document) }
        refreshRows()
    }

    func newSheet(text: String = "") {
        saveNow()
        let info = library.create(text: text)
        titles[info.id] = SheetTitle.title(of: text)
        selectCreated(info.id)
    }

    private func selectCreated(_ id: UUID) {
        let document = loadDocument(id)
        for editor in liveEditors { current.selection = editor.selectedRange() }
        current = document
        currentID = id
        selectedLines = nil
        currentTitle = document.title
        evaluate()
        for editor in liveEditors { editor.show(document) }
        refreshRows()
        liveEditors.first?.window?.makeFirstResponder(liveEditors.first)
    }

    func selectNeighbour(_ offset: Int) {
        select(library.neighbour(offset))
    }

    /// Deletes a sheet, asking first unless it's empty. Can't be undone.
    func deleteSheet(_ id: UUID, confirm: Bool = true) {
        let text = documents[id]?.text ?? library.text(of: id)
        if confirm, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete “\(documents[id]?.title ?? titles[id] ?? SheetTitle.untitled)”?"
            alert.informativeText = "Its lines and answers go with it. You can’t undo this."
            alert.addButton(withTitle: "Delete").hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let wasCurrent = id == current.id
        let next = library.delete(id)
        documents[id]?.dirty = false
        documents[id] = nil
        titles[id] = nil
        if wasCurrent {
            if titles[next] == nil, documents[next] == nil { titles[next] = SheetTitle.title(of: library.text(of: next)) }
            selectCreated(next)
        }
        refreshRows()
    }

    func title(of id: UUID) -> String {
        id == current.id ? current.title : (titles[id] ?? SheetTitle.untitled)
    }

    // MARK: Editors

    private var liveEditors: [SheetTextView] {
        editors.removeAll { $0.view == nil }
        return editors.compactMap(\.view)
    }

    func register(_ editor: SheetTextView) {
        guard !liveEditors.contains(where: { $0 === editor }) else { return }
        editors.append(WeakEditor(view: editor))
        editor.baseAttributes = styler.baseAttributes
        editor.applyTheme(theme, pointSize: pointSize)
        editor.show(current)
    }

    func unregister(_ editor: SheetTextView) {
        editors.removeAll { $0.view == nil || $0.view === editor }
    }

    /// The editor with keyboard focus, else the window's.
    var editor: SheetTextView? {
        liveEditors.first { $0.window?.isKeyWindow == true } ?? liveEditors.first { $0.window?.isVisible == true } ?? liveEditors.first
    }

    // MARK: Appearance

    func setTheme(_ id: String) {
        let next = Theme.named(id)
        Pref.defaults.set(next.id, forKey: Pref.theme)
        guard next != theme else { return }
        theme = next
        styler.setTheme(next)
        restyleCurrent()
    }

    func setTextSize(step: Int) {
        Pref.defaults.set(TextSize.clamp(step), forKey: Pref.textSizeStep)
        let size = TextSize.pointSize(step: step)
        guard size != pointSize else { return }
        pointSize = size
        styler.setPointSize(size)
        restyleCurrent()
    }

    private func restyleCurrent() {
        styler.styleAll(current.storage)
        current.styledGeneration = styler.generation
        for editor in liveEditors {
            editor.baseAttributes = styler.baseAttributes
            editor.applyTheme(theme, pointSize: pointSize)
            editor.apply(displays: current.displays)
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        var saved = false
        for document in documents.values where document.dirty {
            do {
                try library.save(document.text, id: document.id)
                document.dirty = false
                saved = true
            } catch {
                NSLog("Tally: couldn't save a sheet: \(error.localizedDescription)")
            }
        }
        if saved { refreshRows() }
    }

    // MARK: Copying

    func copyResult(line: Int) {
        guard current.outputs.indices.contains(line),
              let text = SheetText.copyText(current.outputs[line], formatter: formatter, includeUnit: Pref.includesUnit)
        else {
            NSSound.beep()
            return
        }
        clipboard.setString(text)
        HUD.show("Copied \(text)", systemImage: "doc.on.doc")
    }

    /// Copy Result (⇧⌘C): the line with the insertion point.
    func copyCurrentResult() {
        guard let line = editor?.currentLine else { return }
        copyResult(line: line)
    }

    func copyAll() {
        clipboard.setString(SheetText.copyAll(lines: current.lines, outputs: current.outputs, formatter: formatter))
        HUD.show("Copied Sheet", systemImage: "doc.on.doc")
    }

    func clearAll() {
        editor?.replaceAll(with: "", actionName: "Clear All")
    }

    /// Drives the text view's find bar (SwiftUI has no Find menu of its own).
    func find(_ action: NSTextFinder.Action) {
        guard let editor else { return }
        editor.window?.makeFirstResponder(editor)
        let item = NSMenuItem()
        item.tag = action.rawValue
        editor.performTextFinderAction(item)
    }

    func resultClicked(line: Int) {
        guard current.displays.indices.contains(line), let display = current.displays[line] else { return }
        if display.kind == .value {
            copyResult(line: line)
        } else if display.opensCurrencySettings {
            openCurrencySettings()
        }
    }

    func openCurrencySettings() {
        Pref.defaults.set("currency", forKey: Pref.settingsTab)
        openSettingsAction?()
    }

    // MARK: Import / export

    /// Opens a text file as a new sheet.
    func importText() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "Choose a text file. It opens as a new sheet."
        panel.prompt = "Import"
        if let dir = Platform.testFolder { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            newSheet(text: contents.replacingOccurrences(of: "\r\n", with: "\n"))
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t import “\(url.lastPathComponent)”"
            alert.informativeText = "Tally can import plain text files. Check that the file is text, then try again."
            alert.runModal()
        }
    }

    func exportText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let title = current.title == SheetTitle.untitled ? "Tally Sheet" : current.title
        panel.nameFieldStringValue = "\(title.replacingOccurrences(of: "/", with: "-")).txt"
        panel.prompt = "Export"
        if let dir = Platform.testFolder { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(current.text.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t export the sheet"
            alert.informativeText = "\(error.localizedDescription) Choose another folder and try again."
            alert.runModal()
        }
    }

    // MARK: Rates

    /// Called when the "Download exchange rates" toggle changes.
    func downloadRatesChanged(_ enabled: Bool) {
        if enabled {
            Task { await rates.updateIfDue(enabled: true) }
        }
        startRatesSchedule()
    }

    func updateRatesNow() {
        Task { await rates.update() }
    }

    func deleteRates() {
        rates.delete()
    }

    func settingsChanged() {
        evaluate()
    }

    /// While downloading is on: check on launch and every 6 hours; fetch at most daily.
    private func startRatesSchedule() {
        refreshTask?.cancel()
        guard Pref.isDownloadingRates else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.rates.updateIfDue(enabled: Pref.isDownloadingRates)
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }
}

private struct WeakEditor {
    weak var view: SheetTextView?
}
