import AppKit
import Observation
import SlopKit
import SnapperCore

/// Capture History in the app: keeps the index in step with `HistoryStore` (which does all
/// file work off the main thread), records every capture after its card is up, follows
/// edits and saves, prunes by the retention setting, and restores entries as captures.
@MainActor
@Observable
final class HistoryController {
    /// Newest first.
    private(set) var entries: [HistoryEntry] = []
    private(set) var isLoaded = false
    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.byteSize } }

    var retention: HistoryRetention {
        didSet {
            guard retention != oldValue else { return }
            UserDefaults.standard.set(retention.rawValue, forKey: Self.retentionKey)
            prune()
        }
    }

    @ObservationIgnored let store: HistoryStore
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var timer: Timer?
    /// The capture whose card closed last ("Reopen Last Capture"), kept across launches.
    @ObservationIgnored private var lastClosedID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.lastClosedKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.lastClosedKey) }
    }

    static let retentionKey = "historyRetention"
    private static let lastClosedKey = "historyLastClosed"

    /// `~/Library/Application Support/app.slopapp.snapper/History`, or `SNAPPER_HISTORY_DIR`.
    static var rootURL: URL {
        if let override = Diagnostics.historyDirectory { return URL(fileURLWithPath: override, isDirectory: true) }
        let base = (try? AppPaths.applicationSupport) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("History", isDirectory: true)
    }

    init(model: AppModel) {
        self.model = model
        store = HistoryStore(root: Self.rootURL)
        retention = UserDefaults.standard.string(forKey: Self.retentionKey).flatMap(HistoryRetention.init) ?? .default
    }

    var isOn: Bool { retention.keepsCaptures }

    /// Loads the index, erases what was deleted last session and what's expired, then
    /// prunes every hour.
    func start() {
        let started = Diagnostics.now()
        Task {
            await store.purgeDeleted()
            let index = await store.load()
            entries = index.entries
            isLoaded = true
            Diagnostics.record("history index read ms=\(Diagnostics.milliseconds(since: started))")
            prune()
            Diagnostics.record("history loaded entries=\(entries.count) bytes=\(totalBytes)")
        }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func entry(_ id: UUID?) -> HistoryEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    // MARK: Recording captures

    /// Writes a fresh capture to history in the background (after its card is on screen).
    func record(_ item: CaptureItem, kind: HistoryKind, source: SourceApp?) {
        guard isOn, item.historyID == nil else { return }
        let id = UUID()
        item.historyID = id
        let capture = HistoryCapture(id: id, createdAt: item.createdAt, kind: kind, scale: item.scale, image: item.image,
                                     original: item.isMedia ? nil : item.original, document: item.document,
                                     media: item.media?.url, duration: item.media?.duration, format: model.format,
                                     baseName: item.fileBaseName, source: source)
        let started = Diagnostics.now()
        Task {
            do {
                let entry = try await store.add(capture)
                insert(entry)
                item.historyFile = store.fileURL(for: entry)
                if let media = item.media {
                    // The recording now lives in history; the temporary copy goes at quit.
                    item.media = MediaFile(url: store.fileURL(for: entry), duration: media.duration)
                }
                Diagnostics.record("history saved kind=\(kind.rawValue) ms=\(Diagnostics.milliseconds(since: started)) bytes=\(entry.byteSize)")
            } catch {
                item.historyID = nil
                Diagnostics.record("history write failed error=\(error)")
            }
        }
    }

    /// After the editor applies edits: the entry gets the new version and the edits.
    func edited(_ item: CaptureItem) {
        guard let id = item.historyID, !item.isMedia else { return }
        item.historyFile = nil
        let image = item.image, document = item.document, format = model.format, name = item.fileBaseName
        Task {
            guard let entry = try? await store.update(id, image: image, document: document, format: format, baseName: name) else { return }
            replace(entry)
            if item.image === image { item.historyFile = store.fileURL(for: entry) }
        }
    }

    func saved(_ item: CaptureItem, to url: URL) {
        guard let id = item.historyID else { return }
        Task {
            await store.setSavedPath(id, url.path(percentEncoded: false))
            if let entry = await store.entry(id) { replace(entry) }
        }
    }

    /// A card closed: it's what "Reopen Last Capture" brings back.
    func closed(_ item: CaptureItem) {
        guard let id = item.historyID else { return }
        lastClosedID = id
    }

    // MARK: Restoring

    /// What "Reopen Last Capture" brings back: the last closed card, else the newest capture,
    /// in either case only if it isn't already open.
    var reopenCandidate: HistoryEntry? {
        let open = model.openHistoryIDs
        if let last = entry(lastClosedID), !open.contains(last.id) { return last }
        return entries.first { !open.contains($0.id) }
    }

    /// The entry as a capture again, edits included (still editable).
    func capture(for entry: HistoryEntry) async -> CaptureItem? {
        if let open = model.openItem(historyID: entry.id) { return open }
        let fileURL = store.fileURL(for: entry)
        guard let (current, original, document) = await store.restorable(entry) else { return nil }
        let item = CaptureItem(image: original ?? current, scale: entry.scale, displayID: nil, createdAt: entry.createdAt)
        if entry.kind.isMedia {
            item.media = MediaFile(url: fileURL, duration: entry.duration ?? 0)
        } else if let document, original != nil {
            item.apply(document, rendered: current)
        }
        item.sourceName = item.fileBaseName
        item.historyID = entry.id
        item.historyFile = fileURL
        if let saved = entry.savedPath { item.lastSavedURL = URL(fileURLWithPath: saved) }
        return item
    }

    // MARK: Removing

    /// Deletes entries (files go to the store's `.deleted` folder until purged), with undo.
    func delete(_ ids: Set<UUID>, undoManager: UndoManager?) {
        let open = model.openHistoryIDs
        let ids = ids.subtracting(open)
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        Task {
            let removed = await store.delete(ids)
            Diagnostics.record("history deleted count=\(removed.count)")
            undoManager?.registerUndo(withTarget: self) { controller in
                MainActor.assumeIsolated { controller.undoDelete(removed, undoManager: undoManager) }
            }
            undoManager?.setActionName(removed.count == 1 ? "Delete Capture" : "Delete \(removed.count) Captures")
        }
    }

    private func undoDelete(_ removed: [HistoryEntry], undoManager: UndoManager?) {
        for entry in removed { insert(entry) }
        Task { await store.restoreDeleted(removed) }
        undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.delete(Set(removed.map(\.id)), undoManager: undoManager) }
        }
        undoManager?.setActionName(removed.count == 1 ? "Delete Capture" : "Delete \(removed.count) Captures")
    }

    /// Erases deleted captures for good (the History window closed: undo is over).
    func purgeDeleted() {
        Task { await store.purgeDeleted() }
    }

    func clear() {
        let open = model.openHistoryIDs
        entries.removeAll { !open.contains($0.id) }
        Task {
            let gone = await store.clear(protected: open)
            Diagnostics.record("history cleared count=\(gone.count)")
        }
    }

    /// Applies the retention setting (never to open cards, editors or pins).
    func prune() {
        let retention = retention, open = model.openHistoryIDs
        Task {
            let gone = await store.prune(retention: retention, now: Date(), protected: open)
            guard !gone.isEmpty else { return }
            let set = Set(gone)
            entries.removeAll { set.contains($0.id) }
            Diagnostics.record("history pruned count=\(gone.count)")
        }
    }

    // MARK: Index mirror

    private func insert(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        let index = entries.firstIndex { $0.createdAt < entry.createdAt } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

    private func replace(_ entry: HistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }
}

/// The app a capture comes from, for history's "source app".
@MainActor
enum CaptureSource {
    /// The front app when a capture starts (not Snapper itself). In test mode the captures
    /// only ever contain the test scene, so they're attributed to it, never to the owner's apps.
    static func current() -> SourceApp? {
        if TestScene.isActive { return testScene }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "App")
    }

    static func window(_ window: WindowInfo) -> SourceApp? {
        if TestScene.isActive { return testScene }
        let app = NSRunningApplication(processIdentifier: window.ownerPID)
        return SourceApp(bundleID: window.bundleID ?? app?.bundleIdentifier, name: app?.localizedName ?? window.ownerName)
    }

    private static var testScene: SourceApp {
        SourceApp(bundleID: Bundle.main.bundleIdentifier, name: "Snapper Test Scene")
    }
}
