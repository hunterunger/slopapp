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

/// The one sheet: its text, its results, autosave, copying, rates. The editor (an
/// NSTextView) owns the text while editing and reports every change here.
@MainActor
@Observable
final class SheetModel {
    static let shared = SheetModel()

    @ObservationIgnored private(set) var lines: [String] = []
    @ObservationIgnored private(set) var outputs: [LineOutput] = []
    @ObservationIgnored private(set) var displays: [ResultDisplay?] = []
    /// Milliseconds the last evaluation took (shown nowhere; logged for perf checks).
    @ObservationIgnored private(set) var lastEvaluationMillis: Double = 0

    /// Called after results change, so the editor can redraw.
    @ObservationIgnored var onResultsChange: (() -> Void)?
    @ObservationIgnored weak var editor: SheetTextView?
    @ObservationIgnored var openSettingsAction: (() -> Void)?

    private(set) var text: String
    let rates: RatesUpdater
    /// Bumped when rates change, so Settings refreshes.
    private(set) var ratesRevision = 0

    @ObservationIgnored private let engine = SheetEngine()
    @ObservationIgnored private let storage: SheetStorage
    @ObservationIgnored private let clipboard: Clipboard
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    /// Formatted results, keyed by value; cleared when the format settings change.
    @ObservationIgnored private var formatCache: [Quantity: String] = [:]
    @ObservationIgnored private var formatCacheKey = ""
    @ObservationIgnored private var staleHelp = "Click to copy"

    init(storage: SheetStorage = FileSheetStorage(directory: Platform.dataDirectory),
         ratesStorage: RatesStorage = FileRatesStorage(directory: Platform.dataDirectory),
         fetcher: RatesFetching = ECBFetcher(url: Platform.ratesURL),
         clipboard: Clipboard = SystemClipboard()) {
        self.storage = storage
        self.clipboard = clipboard
        rates = RatesUpdater(storage: ratesStorage, fetcher: fetcher)
        text = storage.load() ?? SheetText.welcome
        rates.onChange = { [weak self] in
            guard let self else { return }
            ratesRevision += 1
            evaluate()
        }
        evaluate()
        startRatesSchedule()
    }

    var formatter: ResultFormatter {
        ResultFormatter(locale: .current, dollarCode: Pref.dollar)
    }

    // MARK: Editing

    func textDidChange(_ newText: String) {
        text = newText
        dirty = true
        evaluate()
        scheduleSave()
    }

    func evaluate() {
        let start = ContinuousClock.now
        lines = SheetEngine.lines(of: text)
        let context = SheetContext(rates: rates.state, dollarCode: Pref.dollar)
        outputs = engine.evaluate(lines: lines, context: context)
        let formatter = formatter
        let key = Pref.dollar + Locale.current.identifier
        if key != formatCacheKey || formatCache.count > 20_000 {
            formatCache.removeAll(keepingCapacity: true)
            formatCacheKey = key
        }
        let staleRates: Bool = {
            if case .loaded(_, let stale) = context.rates { return stale }
            return false
        }()
        staleHelp = rates.table.map { "Uses exchange rates from \($0.displayDate()). Click to copy." } ?? "Click to copy"
        displays = outputs.map { display(for: $0, formatter: formatter, staleRates: staleRates) }
        let elapsed = ContinuousClock.now - start
        lastEvaluationMillis = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        onResultsChange?()
    }

    private func display(for output: LineOutput, formatter: ResultFormatter, staleRates: Bool) -> ResultDisplay? {
        switch output.result {
        case .none:
            return nil
        case .value(let q):
            let stale = staleRates && output.usesDownloadedRates
            let help = stale ? staleHelp : "Click to copy"
            let text: String
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
        guard dirty else { return }
        do {
            try storage.save(text)
            dirty = false
        } catch {
            NSLog("Tally: couldn't save the sheet: \(error.localizedDescription)")
        }
    }

    // MARK: Copying

    func copyResult(line: Int) {
        guard outputs.indices.contains(line),
              let text = SheetText.copyText(outputs[line], formatter: formatter, includeUnit: Pref.includesUnit)
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
        clipboard.setString(SheetText.copyAll(lines: lines, outputs: outputs, formatter: formatter))
        HUD.show("Copied Sheet", systemImage: "doc.on.doc")
    }

    var hasText: Bool { !text.isEmpty }

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
        guard displays.indices.contains(line), let display = displays[line] else { return }
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

    func importText() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "Choose a text file. It replaces the sheet; you can undo this."
        panel.prompt = "Import"
        if let dir = Platform.testFolder { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            editor?.replaceAll(with: contents.replacingOccurrences(of: "\r\n", with: "\n"), actionName: "Import")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't import “\(url.lastPathComponent)”"
            alert.informativeText = "Tally can import plain text files. Check that the file is text, then try again."
            alert.runModal()
        }
    }

    func exportText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Tally Sheet.txt"
        panel.prompt = "Export"
        if let dir = Platform.testFolder { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't export the sheet"
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
