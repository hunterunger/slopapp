import AppKit
import Observation
import SlopKit
import SquishCore
import SwiftUI

/// Naming a preset.
enum PresetSheet: Identifiable {
    case saveNew
    case rename(CompressionPreset)

    var id: String {
        switch self {
        case .saveNew: "new"
        case .rename(let preset): preset.id
        }
    }
}

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
            if case .subfolder(let name) = settings.destination, name != subfolderName {
                subfolderName = name
                UserDefaults.standard.set(name, forKey: Self.subfolderKey)
            }
        }
    }
    /// The settings each file was last compressed with, by input path.
    private var settingsUsed: [String: SquishSettings] = [:]
    /// Folders picked under Save To, most recent first.
    private(set) var recentFolders: [URL]
    /// The last subfolder name used, so switching Save To away and back keeps it.
    private(set) var subfolderName: String
    /// Shown once, the first time the user turns on Replace Originals.
    var confirmingReplace = false

    /// Built-in and saved presets.
    private(set) var presets: PresetLibrary {
        didSet { savePresets() }
    }
    /// The Save Preset / Rename Preset sheet.
    var presetSheet: PresetSheet?

    /// The file list (sidebar) and the options column (inspector).
    var columns: NavigationSplitViewVisibility = .detailOnly
    var showsOptions: Bool {
        didSet { UserDefaults.standard.set(showsOptions, forKey: Self.showsOptionsKey) }
    }
    /// Before/after split in the preview (off: the result alone).
    var comparing: Bool {
        didSet { UserDefaults.standard.set(comparing, forKey: Self.comparingKey) }
    }
    /// Zoom and scrolling of the preview.
    let preview = PreviewController()

    private static let settingsKey = "settings"
    private static let presetsKey = "presets"
    private static let recentFoldersKey = "recentFolders"
    private static let subfolderKey = "subfolderName"
    private static let replaceConfirmedKey = "replaceConfirmed"
    private static let showsOptionsKey = "showsOptions"
    private static let comparingKey = "comparing"

    private init() {
        let defaults = UserDefaults.standard
        let loaded = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(SquishSettings.self, from: $0) } ?? SquishSettings()
        settings = loaded
        presets = defaults.data(forKey: Self.presetsKey)
            .flatMap { try? JSONDecoder().decode(PresetLibrary.self, from: $0) } ?? PresetLibrary()
        recentFolders = (defaults.stringArray(forKey: Self.recentFoldersKey) ?? []).map { URL(fileURLWithPath: $0) }
        subfolderName = defaults.string(forKey: Self.subfolderKey) ?? SquishSettings.defaultSubfolder
        showsOptions = defaults.object(forKey: Self.showsOptionsKey) as? Bool ?? true
        comparing = defaults.object(forKey: Self.comparingKey) as? Bool ?? true
        queue = FileQueue(processor: SquishProcessor.placeholder, acceptedTypes: SquishTypes.accepted)
        queue.processor = processor(for: loaded)
        queue.onIdle = { [weak self] in self?.batchFinished() }
    }

    // MARK: Presets

    /// The preset the current options came from, if it still exists.
    var currentPreset: CompressionPreset? {
        presets.preset(id: settings.presetID)
    }

    /// Options changed since the preset was picked.
    var presetIsEdited: Bool {
        currentPreset.map { $0.options != settings.options } ?? true
    }

    /// "Balanced", "Web (Edited)", "Custom".
    var presetTitle: String {
        guard let preset = currentPreset else { return "Custom" }
        return presetIsEdited ? "\(preset.name) (Edited)" : preset.name
    }

    func apply(_ preset: CompressionPreset) {
        settings.apply(preset)
    }

    func saveNewPreset(named name: String) {
        let preset = presets.add(name: name, options: settings.options)
        settings.presetID = preset.id
        HUD.show("Saved “\(preset.name)”", systemImage: "checkmark")
    }

    /// Saves the current options into the selected (user) preset.
    func updateCurrentPreset() {
        guard let preset = currentPreset, !preset.isBuiltIn else { return }
        presets.update(id: preset.id, options: settings.options)
        HUD.show("Updated “\(preset.name)”", systemImage: "checkmark")
    }

    func renamePreset(id: String, to name: String) {
        presets.rename(id: id, to: name)
    }

    func deletePreset(id: String) {
        guard let preset = presets.preset(id: id), !preset.isBuiltIn else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the preset “\(preset.name)”?"
        alert.informativeText = "Files you already compressed with it aren't affected."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        Self.ask(alert) { [weak self] confirmed in
            if confirmed { self?.presets.delete(id: id) }
        }
    }

    /// Shows `alert` as a sheet on the main window (or on its own without one) and reports
    /// whether the first button was chosen.
    static func ask(_ alert: NSAlert, then done: @escaping @MainActor (Bool) -> Void) {
        guard let window = MainWindow.window, window.isVisible, window.attachedSheet == nil else {
            done(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { done(response == .alertFirstButtonReturn) }
        }
    }

    func movePresets(fromOffsets source: IndexSet, toOffset destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
    }

    // MARK: Preview

    /// The row the preview shows: the selected one, or the first.
    var focusedItem: FileQueueItem? {
        if selection.count > 1 { return nil }
        if let id = selection.first, let item = queue.items.first(where: { $0.id == id }) { return item }
        return selection.isEmpty ? queue.items.first : nil
    }

    /// File ▸ Copy Compressed File: puts the selected outputs on the pasteboard.
    /// `SQUISH_PASTEBOARD` names a private pasteboard for scripted tests.
    func copyCompressed() {
        let urls = targetItems.compactMap(\.output)
        guard !urls.isEmpty else { NSSound.beep(); return }
        let board = ProcessInfo.processInfo.environment["SQUISH_PASTEBOARD"].map { NSPasteboard(name: .init($0)) } ?? .general
        board.clearContents()
        board.writeObjects(urls as [NSURL])
        HUD.show(urls.count == 1 ? "Copied" : "Copied \(urls.count) files", systemImage: "doc.on.doc")
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
        Self.ask(alert) { [weak self] confirmed in
            if confirmed { self?.putBack(replacements: all) }
        }
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
            if !queue.items.isEmpty, columns == .detailOnly { columns = .all }
            // Show the first new file in the preview, like opening a document.
            if selection.isEmpty || !queue.items.contains(where: { selection.contains($0.id) }), let first = added.first {
                selection = [first.id]
            }
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

    /// ⌘R: the selected rows, or all of them.
    func processAgain() {
        targetItems.forEach(queue.retry)
    }

    func clearList() {
        removeRows(queue.items, actionName: "Clear List")
        selection = []
        columns = .detailOnly
    }

    /// Removes rows (never files), with Undo.
    func removeRows(_ rows: [FileQueueItem], actionName: String = "Remove from List") {
        guard !rows.isEmpty else { return }
        let offsets = rows.compactMap { row in queue.items.firstIndex { $0.id == row.id } }
        queue.remove(rows)
        if queue.items.isEmpty { columns = .detailOnly }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.queue.restore(rows, at: offsets)
                if model.columns == .detailOnly { model.columns = .all }
            }
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

    func useSubfolder() {
        settings.destination = .subfolder(subfolderName)
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

    /// The compressed files Share sends: the selected rows', or the one shown.
    var shareURLs: [URL] {
        let rows = selectedItems.isEmpty ? (focusedItem.map { [$0] } ?? []) : selectedItems
        return rows.compactMap(\.output)
    }

    /// The options column's footer: the batch total.
    var footerText: String {
        let s = queue.summary
        guard s.total > 0 else { return "New files use these settings." }
        if s.remaining > 0 { return "Compressing \(min(s.done + 1, s.total)) of \(s.total)…" }
        let files = s.total == 1 ? "1 file" : "\(s.total) files"
        guard s.savedBytes > 0, let fraction = s.savedFraction else { return files }
        return "\(files) · saved \(FileQueueText.bytes(s.savedBytes)) (\(FileQueueText.percent(saved: fraction)))"
    }

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
        // Short enough for the title bar at the smallest window width. The file count and
        // the percentage are in the options column's footer.
        var parts: [String] = []
        if s.savedBytes > 0 {
            parts.append("Saved \(FileQueueText.bytes(s.savedBytes))")
        } else {
            parts.append(s.total == 1 ? "1 file" : "\(s.total) files")
        }
        if s.failed > 0 { parts.append("\(s.failed) failed") }
        return parts.joined(separator: " · ")
    }
}
