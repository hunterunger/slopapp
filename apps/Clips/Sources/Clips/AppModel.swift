import AppKit
import ClipsCore
import Observation
import SlopKit

/// App state: the history, the user's settings, recording, and the actions every surface
/// (panel, history window, menu) shares.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: History

    private(set) var history = History()
    private(set) var isLoaded = false
    /// Shown in the panel and Settings if the history file couldn't be opened.
    private(set) var storageError: String?
    /// Bumped on every history change so views and the panel can refresh.
    private(set) var revision = 0

    // MARK: Settings (UserDefaults)

    var retention: HistoryRetention {
        didSet {
            defaults.set(retention.rawValue, forKey: Keys.retention)
            prune()
        }
    }

    /// Return pastes into the app you were in (needs Accessibility). Off: Return only copies.
    var pasteDirectly: Bool {
        didSet { defaults.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }

    var alwaysPlainText: Bool {
        didSet { defaults.set(alwaysPlainText, forKey: Keys.alwaysPlainText) }
    }

    /// Keep the panel and History window out of screen sharing, recordings and screenshots.
    var hideFromScreenSharing: Bool {
        didSet { defaults.set(hideFromScreenSharing, forKey: Keys.hideFromScreenSharing) }
    }

    /// The window sharing type to use, honoring the test override.
    var windowSharingType: NSWindow.SharingType {
        hideFromScreenSharing && !Diagnostics.allowCapture ? .none : .readOnly
    }

    /// A short sound when Clips pastes or copies a clip for you (on by default).
    var playsPasteSound: Bool {
        didSet {
            defaults.set(playsPasteSound, forKey: Keys.playsPasteSound)
            chime.playsPasteSound = playsPasteSound
        }
    }

    /// A short sound when a copy is recorded (on by default).
    var playsCopySound: Bool {
        didSet {
            defaults.set(playsCopySound, forKey: Keys.playsCopySound)
            chime.isEnabled = playsCopySound
        }
    }

    var copySound: CopySound {
        didSet {
            defaults.set(copySound.rawValue, forKey: Keys.copySound)
            chime.sound = copySound
        }
    }

    var ignoredApps: [IgnoredApp] {
        didSet { defaults.set(IgnoredApp.encode(ignoredApps), forKey: Keys.ignoredApps) }
    }

    // MARK: Recording state

    /// Recording is paused until this date (`.distantFuture` = until resumed).
    private(set) var pausedUntil: Date?
    /// Skip the next change (e.g. before copying something private).
    var ignoreNextCopy = false
    private(set) var clipboardAccess: ClipboardAccess = .allowed
    private(set) var hasAccessibility = Paster.isTrusted

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    // MARK: Wiring

    let pasteboard: SystemPasteboard
    let watcher: ClipboardWatcher
    @ObservationIgnored private var database: ClipDatabase?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored let chime: CopyChime
    @ObservationIgnored let soundPlayer = SystemSoundPlayer()
    @ObservationIgnored private var pauseTimer: Timer?
    @ObservationIgnored private var undoStack: [DeletedClips] = [] {
        didSet { undoableDeletes = undoStack.count }
    }
    /// How many deletions ⌘Z can bring back (observable, for the Undo menu item).
    private(set) var undoableDeletes = 0
    /// Called after every history change (the panel refreshes its results).
    @ObservationIgnored var onHistoryChange: (() -> Void)?

    var usesPrivatePasteboard: Bool { Diagnostics.pasteboardName != nil }

    private enum Keys {
        static let retention = "retention"
        static let pasteDirectly = "pasteDirectly"
        static let alwaysPlainText = "alwaysPlainText"
        static let ignoredApps = "ignoredApps"
        static let hideFromScreenSharing = "hideFromScreenSharing"
        static let pausedUntil = "pausedUntil"
        static let playsCopySound = "playsCopySound"
        static let copySound = "copySound"
        static let playsPasteSound = "playsPasteSound"
    }

    private init() {
        retention = defaults.string(forKey: Keys.retention).flatMap(HistoryRetention.init) ?? .default
        pasteDirectly = defaults.object(forKey: Keys.pasteDirectly) as? Bool ?? true
        alwaysPlainText = defaults.bool(forKey: Keys.alwaysPlainText)
        hideFromScreenSharing = defaults.object(forKey: Keys.hideFromScreenSharing) as? Bool ?? true
        ignoredApps = IgnoredApp.decode(defaults.data(forKey: Keys.ignoredApps))
        let playsSound = defaults.object(forKey: Keys.playsCopySound) as? Bool ?? true
        // No saved choice gets Clips' own Snap; a saved "Pop" (or another) is kept.
        let sound = CopySound.saved(defaults.string(forKey: Keys.copySound))
        let playsPaste = defaults.object(forKey: Keys.playsPasteSound) as? Bool ?? true
        // Assigning in init doesn't run didSet, so nothing is written back.
        playsCopySound = playsSound
        copySound = sound
        playsPasteSound = playsPaste
        chime = CopyChime(player: soundPlayer, isEnabled: playsSound, playsPasteSound: playsPaste, sound: sound,
                          systemSoundsEnabled: { SystemSoundPlayer.userInterfaceSoundsEnabled })
        let paused = defaults.double(forKey: Keys.pausedUntil)
        pausedUntil = paused > 0 ? Date(timeIntervalSinceReferenceDate: paused) : nil
        pasteboard = SystemPasteboard(name: Diagnostics.pasteboardName)
        watcher = ClipboardWatcher(pasteboard: pasteboard)
        watcher.onChange = { [weak self] in self?.pasteboardDidChange() }
        refreshPermissions()
        schedulePauseEnd()
    }

    // MARK: - Startup

    /// Opens the history file and loads it in the background, then starts recording.
    func start() {
        watcher.start()
        Task { await load() }
    }

    private func load() async {
        let started = Diagnostics.now()
        do {
            let directory = try Diagnostics.dataDirectory ?? AppPaths.applicationSupport
            let database = try ClipDatabase(directory: directory)
            self.database = database
            if let seed = Diagnostics.seedCount, Diagnostics.dataDirectory != nil, try await database.count() == 0 {
                try await database.saveAll(SyntheticHistory.make(count: seed, now: Date()).map { ($0.0, $0.1) })
                Diagnostics.record("seeded \(seed) synthetic clips")
            }
            let clips = try await database.loadAll()
            history = History(clips: clips)
            isLoaded = true
            prune()
            changed()
            Memory.relieveSoon()
            if #available(macOS 15.4, *) {
                Diagnostics.record("clipboard accessBehavior=\(pasteboard.board.accessBehavior.rawValue) accessibility=\(hasAccessibility)")
            }
            Diagnostics.record("loaded clips=\(clips.count) ms=\(Diagnostics.milliseconds(since: started))")
        } catch {
            storageError = "Clips couldn't open its history file, so nothing is being saved. Quit and reopen Clips; if that doesn't help, check the disk has space."
            isLoaded = true
            Diagnostics.logger.error("Couldn't open history: \(String(describing: error), privacy: .public)")
        }
    }

    /// Re-reads both permissions; only assigns on change so observers don't redraw for nothing.
    func refreshPermissions() {
        let trusted = Paster.isTrusted
        if trusted != hasAccessibility { hasAccessibility = trusted }
        let access = ClipboardAccess.current(for: pasteboard.board)
        if access != clipboardAccess { clipboardAccess = access }
    }

    // MARK: - Recording

    private func pasteboardDidChange() {
        if isPaused { return }
        if ignoreNextCopy {
            ignoreNextCopy = false
            Diagnostics.record("capture skipped reason=ignoreNext")
            return
        }
        refreshPermissions()
        if clipboardAccess == .denied {
            Diagnostics.record("capture skipped reason=accessDenied")
            return
        }
        // Types only: marked (concealed/transient) content is never read.
        let types = pasteboard.allTypes()
        let settings = CaptureSettings(isPaused: false, ignoredBundleIDs: Set(ignoredApps.map(\.bundleID)))
        if case .skip(let reason) = CapturePolicy.decide(types: types, sourceBundleID: nil, settings: settings) {
            Diagnostics.record("capture skipped reason=\(reason)")
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let ownID = Bundle.main.bundleIdentifier
        let sourceID = pasteboard.declaredSource()
            ?? (frontmost?.bundleIdentifier == ownID ? nil : frontmost?.bundleIdentifier)
        if case .skip(let reason) = CapturePolicy.decide(types: types, sourceBundleID: sourceID, settings: settings) {
            Diagnostics.record("capture skipped reason=\(reason)")
            return
        }
        let sourceName = sourceID.flatMap(AppIcons.name(for:))
        let boardName = pasteboard.name
        let expectedCount = pasteboard.changeCount
        let started = Diagnostics.now()
        Task.detached(priority: .userInitiated) {
            let (snapshot, count) = SystemPasteboard.snapshot(named: boardName)
            guard count == expectedCount else { return } // changed again; the next tick gets it
            let built = ClipBuilder.build(snapshot, sourceBundleID: sourceID, sourceName: sourceName, now: Date())
            var thumbnail: Data?
            if case .success(let (clip, payload)) = built, clip.kind == .image, let data = payload.items.first?.first?.data {
                thumbnail = ImageInfo.thumbnailPNG(of: data)
            }
            await MainActor.run { [thumbnail] in
                switch built {
                case .success(let (clip, payload)):
                    self.store(clip, payload: payload, thumbnail: thumbnail)
                    Diagnostics.record("captured kind=\(clip.kind) bytes=\(payload.byteCount) ms=\(Diagnostics.milliseconds(since: started))")
                case .failure(let reason):
                    Diagnostics.record("capture skipped reason=\(reason)")
                }
            }
        }
    }

    private func store(_ clip: Clip, payload: ClipPayload, thumbnail: Data?) {
        let result = history.record(clip)
        let saved: Clip
        switch result {
        case .inserted(let clip), .bumped(let clip): saved = clip
        }
        if let database {
            Task { try? await database.save(saved, payload: payload, thumbnail: thumbnail) }
        }
        // Only copies that were really recorded get here: skipped, ignored and concealed
        // content returns earlier, and Clips' own pastes never count as a change.
        if chime.copyRecorded() { Diagnostics.record("copy sound played sound=\(copySound.rawValue)") }
        prune()
        changed()
    }

    // MARK: - Pause

    func pause(for duration: TimeInterval?) {
        pausedUntil = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        defaults.set(pausedUntil!.timeIntervalSinceReferenceDate, forKey: Keys.pausedUntil)
        schedulePauseEnd()
    }

    func resume() {
        pausedUntil = nil
        defaults.removeObject(forKey: Keys.pausedUntil)
        pauseTimer?.invalidate()
    }

    var pauseDescription: String? {
        guard isPaused, let pausedUntil else { return nil }
        if pausedUntil == .distantFuture { return "Recording paused" }
        return "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
    }

    private func schedulePauseEnd() {
        pauseTimer?.invalidate()
        guard let pausedUntil, pausedUntil != .distantFuture else { return }
        guard pausedUntil > Date() else {
            self.pausedUntil = nil
            return
        }
        let timer = Timer(fire: pausedUntil, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterTimedPause() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    private func resumeAfterTimedPause() {
        pausedUntil = nil
        defaults.removeObject(forKey: Keys.pausedUntil)
    }

    // MARK: - Using clips

    enum Delivery {
        /// Paste into `target` if allowed, else copy.
        case paste(target: NSRunningApplication?)
        case copy
    }

    /// What Return will do right now, for the panel's hint line.
    func willPasteDirectly(into target: NSRunningApplication?) -> Bool {
        pasteDirectly && hasAccessibility && !usesPrivatePasteboard
            && target != nil && target?.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    /// Puts the clip on the clipboard, moves it to the top, and pastes it if asked and allowed.
    func use(_ clip: Clip, _ delivery: Delivery, plainText: Bool? = nil) {
        guard let database else { return }
        let plain = plainText ?? alwaysPlainText
        refreshPermissions()
        Task {
            guard var payload = try? await database.payload(for: clip.id) else {
                HUD.show("Couldn't read that clip", systemImage: "exclamationmark.triangle")
                return
            }
            if plain, let text = payload.plainText() { payload = text }
            let count = pasteboard.write(payload)
            watcher.noteOwnWrite(changeCount: count)
            if let touched = history.touch(id: clip.id, now: Date()) {
                try? await database.update(touched)
            }
            changed()
            switch delivery {
            case .paste(let target) where willPasteDirectly(into: target):
                // Give the target app a moment to take key focus back from the panel.
                try? await Task.sleep(for: .milliseconds(60))
                Paster.sendPaste()
                clipDelivered()
                Diagnostics.record("pasted kind=\(clip.kind) plain=\(plain)")
            case .paste:
                clipDelivered()
                HUD.show(hasAccessibility || !pasteDirectly ? "Copied. Press ⌘V to paste." : "Copied. Allow Accessibility to paste directly.",
                         systemImage: "doc.on.clipboard")
                Diagnostics.record("copied kind=\(clip.kind) plain=\(plain) reason=noDirectPaste")
            case .copy:
                clipDelivered()
                HUD.show("Copied", systemImage: "doc.on.doc")
                Diagnostics.record("copied kind=\(clip.kind) plain=\(plain)")
            }
        }
    }

    /// Copies plain text that isn't a single clip (several clips joined in the History window).
    func copyText(_ text: String) {
        let payload = ClipPayload(items: [[Representation(type: PasteboardType.string, data: Data(text.utf8))]])
        watcher.noteOwnWrite(changeCount: pasteboard.write(payload))
        clipDelivered()
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    /// Clips pasted or copied a clip for you (or you dragged a card into an app): the paste
    /// sound. Clips' own pasteboard write doesn't count as a copy, so no copy sound follows.
    func clipDelivered() {
        if chime.clipUsed() { Diagnostics.record("paste sound played") }
    }

    func togglePin(_ clip: Clip) {
        guard let updated = history.setPinned(!clip.isPinned, id: clip.id) else { return }
        if let database { Task { try? await database.update(updated) } }
        changed()
    }

    /// Deleted clips kept for undo. The payloads are read before the rows are deleted.
    @MainActor
    private final class DeletedClips {
        let clips: [Clip]
        var payloads: [UUID: ClipPayload] = [:]
        var deletion: Task<Void, Never>?

        init(clips: [Clip]) {
            self.clips = clips
        }
    }

    /// Deletes clips; `undoDelete()` brings them back.
    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty, let database else { return }
        let removed = history.remove(ids: ids)
        guard !removed.isEmpty else { return }
        let entry = DeletedClips(clips: removed)
        undoStack.append(entry)
        if undoStack.count > 20 { undoStack.removeFirst() }
        changed()
        entry.deletion = Task {
            entry.payloads = (try? await database.payloads(for: removed.map(\.id))) ?? [:]
            try? await database.delete(ids: removed.map(\.id))
        }
    }

    var canUndoDelete: Bool { undoableDeletes > 0 }

    @discardableResult
    func undoDelete() -> [Clip] {
        guard let entry = undoStack.popLast(), let database else { return [] }
        history.restore(entry.clips)
        changed()
        Task {
            // Let the deletion finish first, so it can't remove what we put back.
            await entry.deletion?.value
            try? await database.saveAll(entry.clips.map { ($0, entry.payloads[$0.id]) })
        }
        return entry.clips
    }

    /// Removes every unpinned clip. Not undoable (the caller confirms first).
    func clearHistory() {
        let removed = history.clear(keepPinned: true)
        undoStack.removeAll()
        changed()
        guard let database else { return }
        Task {
            try? await database.delete(ids: removed.map(\.id))
            try? await database.compact()
        }
    }

    /// How many clips a shorter retention would remove, so Settings can confirm first.
    func clipsRemoved(by retention: HistoryRetention) -> Int {
        var copy = history
        return copy.prune(retention: retention, now: Date()).count
    }

    func thumbnail(for id: UUID) async -> Data? {
        try? await database?.thumbnail(for: id)
    }

    func payload(for id: UUID) async -> ClipPayload? {
        try? await database?.payload(for: id)
    }

    private func prune() {
        let removed = history.prune(retention: retention, now: Date())
        guard !removed.isEmpty else { return }
        changed()
        if let database { Task { try? await database.delete(ids: removed) } }
    }

    private func changed() {
        revision &+= 1
        onHistoryChange?()
    }

    // MARK: - Ignored apps

    func ignore(appAt url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              !ignoredApps.contains(where: { $0.bundleID == id }) else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        ignoredApps.append(IgnoredApp(bundleID: id, name: name))
    }
}
