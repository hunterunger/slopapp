import AppKit
import Observation
import SlopKit
import SquishCore

/// App state: the settings (persisted) and the queue that uses them.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let queue: FileQueue
    var selection: Set<FileQueueItem.ID> = []
    /// Space bar Quick Look.
    var previewURL: URL?
    let capabilities = EncoderCapabilities.system

    var settings: SquishSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            queue.processor = processor(for: settings)
            if settings.preset == .custom, oldValue.preset != .custom { editingQuality = true }
        }
    }
    /// The settings each file was last compressed with, by input path.
    private var settingsUsed: [String: SquishSettings] = [:]
    /// Folders picked under Save To, most recent first.
    private(set) var recentFolders: [URL]
    /// The custom quality and size popovers in the options bar.
    var editingQuality = false
    var editingSize = false
    /// Shown once, the first time the user turns on Replace Originals.
    var confirmingReplace = false

    private static let settingsKey = "settings"
    private static let recentFoldersKey = "recentFolders"
    private static let replaceConfirmedKey = "replaceConfirmed"

    private init() {
        let defaults = UserDefaults.standard
        let loaded = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(SquishSettings.self, from: $0) } ?? SquishSettings()
        settings = loaded
        recentFolders = (defaults.stringArray(forKey: Self.recentFoldersKey) ?? []).map { URL(fileURLWithPath: $0) }
        queue = FileQueue(processor: SquishProcessor.placeholder, acceptedTypes: SquishTypes.accepted)
        queue.processor = processor(for: loaded)
        queue.onIdle = { [weak self] in self?.batchFinished() }
    }

    private func processor(for settings: SquishSettings) -> SquishProcessor {
        let squisher = Squisher(settings: settings, files: SystemFileStore.app, replacements: registry, onReplace: { replacement in
            Task { @MainActor in AppModel.shared.record(replacement) }
        })
        return SquishProcessor(squisher: squisher) { input in
            Task { @MainActor in AppModel.shared.settingsUsed[Self.key(input)] = settings }
        }
    }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    // MARK: Outdated rows (Redo All)

    /// Finished rows made with settings other than the current ones.
    var outdatedItems: [FileQueueItem] {
        queue.items.filter { item in
            guard item.canRetry, let used = settingsUsed[Self.key(item.input)] else { return false }
            return used != settings
        }
    }

    /// Compresses every outdated row again with the current settings.
    func redoOutdated() {
        outdatedItems.forEach(queue.retry)
    }

    // MARK: Replaced originals (Put Back / Undo)

    /// Originals moved to the Trash by Replace Originals (shared with the compressor, which
    /// re-encodes from them when a replaced file is compressed again). Saved in Application
    /// Support, so Put Back still works after a relaunch while the originals are in the Trash.
    @ObservationIgnored let registry = ReplacementRegistry(
        storage: (try? AppPaths.applicationSupport)?.appendingPathComponent("replaced-originals.json"))
    /// Bumped whenever the registry changes, so menus and labels re-check.
    private var replacementsVersion = 0
    private var replacedThisBatch: [Replacement] = []
    /// The main window's undo manager (what Edit ▸ Undo uses).
    var undoManager: UndoManager? { MainWindow.window?.undoManager }

    private func record(_ replacement: Replacement) {
        replacementsVersion += 1
        replacedThisBatch.append(replacement)
    }

    func replacement(for item: FileQueueItem) -> Replacement? {
        _ = replacementsVersion
        return item.output.flatMap { registry.replacement(outputAt: $0) }
    }

    /// Originals that can still be put back, including ones from earlier sessions.
    var replacedCount: Int {
        _ = replacementsVersion
        return registry.all.count
    }

    var canPutBack: Bool { replacedCount > 0 }

    /// File ▸ Put Back Originals: the selected rows' originals, or, with no such rows, every
    /// original Squish replaced (also from earlier sessions), after asking.
    func putBackFromMenu() {
        let rows = targetItems.filter { replacement(for: $0) != nil }
        if !rows.isEmpty { putBack(rows); return }
        let all = registry.all
        guard !all.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = all.count == 1 ? "Put back 1 original?" : "Put back \(all.count) originals?"
        alert.informativeText = "Squish replaced these earlier. Each original goes back where it was, and its compressed copy goes to the Trash."
        alert.addButton(withTitle: "Put Back")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        putBack(replacements: all)
    }

    /// Puts originals back where they were (the compressed files go to the Trash).
    func putBack(_ items: [FileQueueItem]) {
        putBack(replacements: items.compactMap { replacement(for: $0) })
    }

    private func putBack(replacements: [Replacement]) {
        var failures: [String] = []
        var restored = 0
        let store = SystemFileStore.app
        for replacement in replacements {
            do {
                do {
                    try replacement.putBack(files: store)
                } catch OutputError.outputEdited(let name) {
                    // The user changed the compressed file since: ask before trashing it.
                    guard confirmPutBackOverEdits(name) else { continue }
                    try replacement.putBack(files: store, evenIfEdited: true)
                }
                registry.remove(replacement)
                replacementsVersion += 1
                if let item = queue.items.first(where: { $0.output.map(Self.key) == Self.key(replacement.output) }) {
                    queue.setOutcome(.unchanged(reason: "Original put back. The compressed copy is in the Trash."), for: item)
                }
                restored += 1
            } catch {
                let e = error as? any LocalizedError
                failures.append([e?.errorDescription, e?.recoverySuggestion].compactMap { $0 }.joined(separator: " "))
            }
        }
        if restored > 0 {
            HUD.show(restored == 1 ? "Original put back" : "\(restored) originals put back", systemImage: "arrow.uturn.backward")
        }
        if let first = failures.first {
            let alert = NSAlert()
            alert.messageText = failures.count == 1 ? "An original couldn't be put back" : "\(failures.count) originals couldn't be put back"
            alert.informativeText = first
            alert.runModal()
        }
    }

    private func confirmPutBackOverEdits(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(name) was changed after Squish compressed it"
        alert.informativeText = "Putting the original back moves your changed version to the Trash."
        alert.addButton(withTitle: "Keep My Changes")
        let put = alert.addButton(withTitle: "Put Back Original")
        put.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Undo for a batch: the originals it replaced, wherever their stand-ins are now.
    private func putBack(_ batch: [Replacement]) {
        let originals = Set(batch.map { Self.key($0.original) })
        putBack(replacements: registry.all.filter { originals.contains(Self.key($0.original)) })
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Files

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Diagnostics.batchStarted()
        Task {
            // Expand folders here so Squish's own earlier outputs (tagged) can be left out.
            let (files, skipped, unsupported) = await Task.detached(priority: .userInitiated) {
                let found = FileIntake.expand(urls, types: SquishTypes.accepted).map(\.url)
                let split = OutputFilter.split(found)
                return (split.keep, split.skipped, Unsupported.files(in: urls))
            }.value
            let added = files.isEmpty ? [] : await queue.add(files)
            if let message = Unsupported.message(unsupported), added.isEmpty {
                HUD.show(message, systemImage: "nosign")
            } else if skipped > 0 {
                HUD.show(skipped == 1 ? "1 file Squish already compressed was skipped"
                                      : "\(skipped) files Squish already compressed were skipped",
                         systemImage: "doc.on.doc")
            } else if added.isEmpty, !files.isEmpty {
                HUD.show("Already in the list", systemImage: "doc.on.doc")
            } else if let message = Unsupported.message(unsupported) {
                HUD.show(message, systemImage: "nosign")
            }
        }
    }

    func chooseFiles() {
        FileQueueActions.chooseFiles(types: SquishTypes.accepted + [.folder]) { [weak self] in self?.add($0) }
    }

    var selectedItems: [FileQueueItem] {
        queue.items.filter { selection.contains($0.id) }
    }

    /// The selection, or everything when nothing is selected.
    var targetItems: [FileQueueItem] {
        selectedItems.isEmpty ? queue.items : selectedItems
    }

    func revealTargets() {
        let items = targetItems.filter { $0.output != nil }
        FileQueueActions.reveal(items.isEmpty ? targetItems : items)
    }

    /// Custom… starts from the current preset's values, so nothing jumps.
    func editCustomQuality() {
        if settings.preset != .custom {
            var custom = settings
            custom.customQuality = settings.imageQuality
            custom.customPDFResolution = settings.pdf.resolution
            custom.preset = .custom
            settings = custom
        }
        editingQuality = true
    }

    /// ⌘R: the selected rows, or all of them.
    func processAgain() {
        targetItems.forEach(queue.retry)
    }

    func clearList() {
        removeRows(queue.items, actionName: "Clear List")
        selection = []
    }

    /// Removes rows (never files), with Undo.
    func removeRows(_ rows: [FileQueueItem], actionName: String = "Remove from List") {
        guard !rows.isEmpty else { return }
        let offsets = rows.compactMap { row in queue.items.firstIndex { $0.id == row.id } }
        queue.remove(rows)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.queue.restore(rows, at: offsets) }
        }
        undoManager?.setActionName(actionName)
    }

    func toggleQuickLook() {
        if previewURL != nil {
            previewURL = nil
        } else if let item = selectedItems.first ?? queue.items.first {
            previewURL = item.revealURL
        }
    }

    private func batchFinished() {
        Diagnostics.batchFinished(files: queue.items.count)
        if AppDelegate.quitAlertOpen { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
        if !replacedThisBatch.isEmpty, let undoManager {
            let batch = replacedThisBatch
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.putBack(batch) }
            }
            undoManager.setActionName("Replace Originals")
        }
        replacedThisBatch = []
        malloc_zone_pressure_relief(nil, 0)
        // A gentle Dock bounce if the user went elsewhere while a long batch ran.
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    // MARK: Destination

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = "Choose where compressed files go."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.useFolder(url) }
        }
    }

    func useFolder(_ url: URL) {
        settings.destination = .folder(url)
        recentFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFolders.insert(url, at: 0)
        recentFolders = Array(recentFolders.prefix(4))
        UserDefaults.standard.set(recentFolders.map(\.path), forKey: Self.recentFoldersKey)
    }

    func requestReplaceOriginals() {
        if UserDefaults.standard.bool(forKey: Self.replaceConfirmedKey) {
            settings.destination = .replaceOriginal
        } else {
            confirmingReplace = true
        }
    }

    func confirmReplaceOriginals() {
        UserDefaults.standard.set(true, forKey: Self.replaceConfirmedKey)
        settings.destination = .replaceOriginal
    }

    // MARK: Labels

    var summaryText: String {
        let s = queue.summary
        guard s.total > 0 else {
            // A quiet reminder when starting in Replace mode, or with originals to put back.
            var parts: [String] = []
            if settings.destination == .replaceOriginal { parts.append("Replace Originals is on") }
            if replacedCount > 0 { parts.append(replacedCount == 1 ? "1 original can be put back" : "\(replacedCount) originals can be put back") }
            return parts.joined(separator: " · ")
        }
        if s.remaining > 0 {
            return "Compressing \(s.done + 1 > s.total ? s.total : s.done + 1) of \(s.total)…"
        }
        var parts: [String] = []
        if s.savedBytes > 0, let fraction = s.savedFraction {
            parts.append("Saved \(FileQueueText.bytes(s.savedBytes)) (\(FileQueueText.percent(saved: fraction)))")
        }
        parts.append(s.total == 1 ? "1 file" : "\(s.total) files")
        if s.failed > 0 { parts.append("\(s.failed) failed") }
        return parts.joined(separator: " · ")
    }
}
