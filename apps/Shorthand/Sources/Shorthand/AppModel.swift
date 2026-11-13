import AppKit
import Observation
import ShorthandCore
import SlopKit

extension KeyboardShortcuts.Name {
    /// Unset by default: every obvious combination is taken by some app or by macOS.
    static let togglePause = Self(Diagnostics.isTestMode ? "test.togglePause" : "togglePause")
}

/// What the menu bar icon and the status line show.
enum ExpansionStatus: Equatable {
    case expanding
    case paused
    case secureInput(app: String?)
    case needsPermission
    case inputMethod
    case excluded(app: String)
    case noSnippets

    var line: String {
        switch self {
        case .expanding: "Expanding"
        case .paused: "Paused"
        case .secureInput(let app?): "Paused: secure input is on, probably in \(app)"
        case .secureInput(nil): "Paused: secure input is on"
        case .needsPermission: "Needs permission to expand"
        case .inputMethod: "Paused while an input method is on"
        case .excluded(let app): "Not expanding in \(app)"
        case .noSnippets: "No snippets to expand yet"
        }
    }

    var symbol: String {
        switch self {
        case .expanding, .excluded, .noSnippets: "character.cursor.ibeam"
        case .paused, .inputMethod: "pause.circle"
        case .secureInput: "lock"
        case .needsPermission: "exclamationmark.triangle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .expanding, .excluded, .noSnippets: "Shorthand"
        case .paused, .inputMethod: "Shorthand, paused"
        case .secureInput: "Shorthand, blocked by secure input"
        case .needsPermission: "Shorthand, needs permission"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Library

    private(set) var library = Library()
    @ObservationIgnored let store: SnippetStore
    /// Set when the library file was damaged and a backup (or nothing) was loaded.
    var loadNotice: String?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    // MARK: Settings

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled); refreshTap() } }
    var wordStartOnly: Bool { didSet { defaults.set(wordStartOnly, forKey: Keys.wordStart); pushEngineSettings() } }
    var insertMode: InsertMode { didSet { defaults.set(insertMode.rawValue, forKey: Keys.insertMode); pushEngineSettings() } }
    var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard); pushEngineSettings() } }
    var undoWithBackspace: Bool { didSet { defaults.set(undoWithBackspace, forKey: Keys.undo); pushEngineSettings() } }
    var excludedApps: [Exclusions.App] { didSet { saveExclusions(); updateGate() } }
    /// The person has seen why long snippets don't put the clipboard back yet.
    var pasteNoticeDismissed: Bool { didSet { defaults.set(pasteNoticeDismissed, forKey: Keys.pasteNotice) } }

    // MARK: State

    private(set) var canPost = KeyboardPermissions.canPost
    private(set) var canListen = KeyboardPermissions.canListen
    private(set) var tapRefused = false
    private(set) var secureInputApp: String?
    private(set) var secureInputOn = false
    private(set) var inputMethodOn = InputSource.isInputMethod
    private(set) var frontApp: FrontApp?
    private(set) var pasteboardPrivacy: PasteboardAccessState = .allowed
    /// A long snippet was pasted but the clipboard couldn't be put back.
    private(set) var pastedWithoutRestore = false
    private(set) var tapGaveUp = false
    /// Shorthand's search or fill-in panel has the keyboard.
    private(set) var ownPanelOpen = false

    @ObservationIgnored let fillIn = FillInController()
    @ObservationIgnored let search = SearchController()
    @ObservationIgnored private var formattedCache: [UUID: (Data, NSAttributedString)] = [:]

    @ObservationIgnored let tapShared = TapShared()
    @ObservationIgnored private(set) lazy var tap = KeyTap(shared: tapShared)
    @ObservationIgnored private let environment: SystemEnvironment
    @ObservationIgnored private let poster: SystemPoster
    @ObservationIgnored private(set) var expander: Expander!
    @ObservationIgnored let pasteboard: NSPasteboard
    @ObservationIgnored let defaults = Diagnostics.defaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var secureTimer: Timer?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var timeouts: [Date] = []
    /// Expansion latency, match → last key posted (ms), for the log and the gate.
    @ObservationIgnored private(set) var typedLatency = LatencyStats()
    @ObservationIgnored private(set) var pastedLatency = LatencyStats()

    enum Keys {
        static let enabled = "expandAbbreviations"
        static let wordStart = "onlyAtWordStart"
        static let insertMode = "insertMode"
        static let restoreClipboard = "restoreClipboard"
        static let undo = "undoWithBackspace"
        static let exclusions = "excludedApps"
        static let pasteNotice = "pasteNoticeDismissed"
        static let openedLibrary = "openedLibraryOnce"
    }

    var selfBundleID: String { Bundle.main.bundleIdentifier ?? "app.slopapp.shorthand" }

    private init() {
        let directory = Diagnostics.dataDirectory ?? (try? AppPaths.applicationSupport)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/app.slopapp.shorthand")
        store = SnippetStore(directory: directory)
        if let name = Diagnostics.pasteboardName {
            pasteboard = NSPasteboard(name: .init(name))
        } else {
            pasteboard = .general
        }
        environment = SystemEnvironment(pasteboard: pasteboard)
        poster = SystemPoster(pasteboard: pasteboard, environment: environment)
        let defaults = Diagnostics.defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        wordStartOnly = defaults.object(forKey: Keys.wordStart) as? Bool ?? true
        insertMode = InsertMode(rawValue: defaults.string(forKey: Keys.insertMode) ?? "") ?? .automatic
        restoreClipboard = defaults.object(forKey: Keys.restoreClipboard) as? Bool ?? true
        undoWithBackspace = defaults.object(forKey: Keys.undo) as? Bool ?? true
        pasteNoticeDismissed = defaults.bool(forKey: Keys.pasteNotice)
        if let data = defaults.data(forKey: Keys.exclusions), let apps = try? JSONDecoder().decode([Exclusions.App].self, from: data) {
            excludedApps = apps
        } else {
            excludedApps = Exclusions.defaults(selfBundleID: Bundle.main.bundleIdentifier ?? "app.slopapp.shorthand")
        }
        expander = Expander(tap: TapController(shared: tapShared), poster: poster, environment: environment) { [weak self] id in
            self?.library.snippet(id)
        }
        expander.lookup = { [weak self] in self?.library.snippet(abbreviation: $0) }
        poster.formattedText = { [weak self] in self?.formattedText($0) }
    }

    /// A formatted snippet's decoded text (cached until it changes).
    func formattedText(_ id: UUID) -> NSAttributedString? {
        guard let data = library.snippet(id)?.richText else { return nil }
        if let cached = formattedCache[id], cached.0 == data { return cached.1 }
        guard let text = RichText.decode(data) else { return nil }
        formattedCache[id] = (data, text)
        return text
    }

    // MARK: Lifecycle

    func start() {
        load()
        pushEngineSettings()
        tapShared.onDecision = { [weak self] decision in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(decision) } }
        }
        tapShared.onDisabledByTimeout = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.tapTimedOut() } }
        }
        poster.onPasteFinished = { outcome in Diagnostics.record("clipboard \(outcome)") }
        fillIn.onShowingChange = { [weak self] showing in self?.setOwnPanel(showing) }
        search.onShowingChange = { [weak self] showing in self?.setOwnPanel(showing || (self?.fillIn.isShowing ?? false)) }
        search.state.library = { [weak self] in self?.library ?? Library() }
        search.state.hasFields = { [weak self] snippet in
            guard let self else { return false }
            return FillIn.hasFields(snippet, lookup: self.library.lookup)
        }
        search.state.preview = { [weak self] in self?.readablePreview($0) ?? $0.plainContent }
        search.onPick = { [weak self] snippet in Task { await self?.insertFromSearch(snippet.id) } }
        search.onCopy = { [weak self] snippet in self?.copySnippet(snippet.id) }
        search.onOpenLibrary = { LibraryOpener.open() }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontAppChanged() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: InputSource.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        })
        // Posted whenever any app's Accessibility trust changes: remove the tap the moment
        // ours is revoked (revoking under a live tap can stall input system-wide).
        observers.append(distributed.addObserver(forName: .init("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refreshPermissions() }
            }
        })
        frontAppChanged()
        refreshPermissions()
    }

    func stop() {
        tap.remove()
        // A borrowed clipboard goes back now, not after a delay that won't happen.
        ClipboardPaster.restorePendingNow()
        RichClipboardPaster.restorePendingNow()
        // Only an edit still waiting to be written; quitting never creates files on its own.
        if saveTask != nil { flushSave() }
    }

    // MARK: Library storage

    /// Snapshots only: show this library without saving it.
    func replaceForSnapshot(_ library: Library) {
        self.library = library
        libraryChanged(save: false)
    }

    private func load() {
        switch store.load() {
        case .fresh(let library):
            self.library = library
        case .loaded(let library):
            self.library = library
        case .recovered(let library, let backup):
            self.library = library
            loadNotice = "Your library file couldn't be read, so Shorthand opened the backup “\(backup)”."
        case .damaged(let library):
            self.library = library
            loadNotice = "Your library file couldn't be read and there was no backup. The damaged file was kept next to the new one."
        }
        store.backUpIfNeeded()
        libraryChanged(save: false)
    }

    /// Every edit goes through here: saved shortly after, the abbreviation live at once.
    func edit(_ body: (inout Library) -> Void) {
        var copy = library
        body(&copy)
        guard copy != library else { return }
        library = copy
        libraryChanged(save: true)
    }

    private func libraryChanged(save: Bool) {
        let index = AbbreviationIndex(snippets: library.expandable)
        tapShared.update { $0.index = index }
        refreshTap()
        if save { scheduleSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try store.save(library)
        } catch {
            Diagnostics.record("save failed")
            HUD.show("Couldn't save your snippets. Check that the disk isn't full.", systemImage: "exclamationmark.triangle")
        }
    }

    var hasExpandableSnippets: Bool { !library.expandable.isEmpty }

    // MARK: Library actions (with undo)

    @discardableResult
    func newSnippet(in groupID: UUID?, content: String = "") -> Snippet {
        let group = groupID.flatMap { library.group($0) }?.id ?? library.defaultGroupID
        let snippet = Snippet(groupID: group, abbreviation: "", content: content)
        edit { $0.addSnippet(snippet) }
        return snippet
    }

    func update(_ snippet: Snippet) {
        edit { $0.update(snippet) }
    }

    func duplicate(_ id: UUID) -> Snippet? {
        var copy: Snippet?
        edit { copy = $0.duplicate(id) }
        return copy
    }

    func deleteSnippets(_ ids: Set<UUID>, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        var removed: [(index: Int, snippet: Snippet)] = []
        edit { removed = $0.removeSnippets(ids) }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.edit { $0.restore(removed) }
                undoManager?.registerUndo(withTarget: model) { again in
                    MainActor.assumeIsolated { again.deleteSnippets(ids, undoManager: undoManager) }
                }
            }
        }
        undoManager?.setActionName(ids.count == 1 ? "Delete Snippet" : "Delete Snippets")
    }

    @discardableResult
    func newGroup() -> SnippetGroup {
        var group: SnippetGroup!
        edit { group = $0.addGroup(named: "New Group") }
        return group
    }

    func deleteGroup(_ id: UUID, undoManager: UndoManager?) {
        var removed: Library.RemovedGroup?
        edit { removed = $0.removeGroup(id) }
        guard let removed else { return }
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.edit { $0.restore(removed) }
                undoManager?.registerUndo(withTarget: model) { again in
                    MainActor.assumeIsolated { again.deleteGroup(id, undoManager: undoManager) }
                }
            }
        }
        undoManager?.setActionName("Delete Group")
    }

    func setGroup(_ id: UUID, enabled: Bool) { edit { $0.setGroup(id, enabled: enabled) } }
    func renameGroup(_ id: UUID, to name: String) { edit { $0.renameGroup(id, to: name) } }
    func move(_ ids: Set<UUID>, to group: UUID) { edit { $0.move(ids, to: group) } }

    /// For the editor's "Try it" field and conflict notes: the live index.
    var index: AbbreviationIndex { tapShared.read(\.index) }

    // MARK: Settings

    private func pushEngineSettings() {
        let wordStart = wordStartOnly
        let undo = undoWithBackspace
        tapShared.update {
            $0.wordStartOnly = wordStart
            $0.undoWithBackspace = undo
        }
        var settings = ExpansionSettings()
        settings.insertMode = insertMode
        settings.restoreClipboard = restoreClipboard
        settings.undoWithBackspace = undoWithBackspace
        expander?.settings = settings
    }

    private func saveExclusions() {
        if let data = try? JSONEncoder().encode(excludedApps) { defaults.set(data, forKey: Keys.exclusions) }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }

    func togglePause() {
        isEnabled.toggle()
        HUD.show(isEnabled ? "Expansion on" : "Expansion paused", systemImage: isEnabled ? "character.cursor.ibeam" : "pause.circle")
    }

    // MARK: Status

    var status: ExpansionStatus {
        if !isEnabled { return .paused }
        if !hasExpandableSnippets { return .noSnippets }
        if needsPermission { return .needsPermission }
        if secureInputOn { return .secureInput(app: secureInputApp) }
        if inputMethodOn { return .inputMethod }
        if let front = frontApp, isExcluded(front.bundleID), front.bundleID != selfBundleID {
            return .excluded(app: front.name ?? "this app")
        }
        return .expanding
    }

    var needsPermission: Bool { !canPost || !(canListen || tap.isInstalled) || tapRefused || tapGaveUp }

    /// Which permission to ask for next: Accessibility first (typing), then Input Monitoring
    /// (listening) if macOS still wants it.
    var nextPermission: NeededPermission? {
        if !canPost { return .accessibility }
        if !tap.isInstalled && (!canListen || tapRefused) { return .inputMonitoring }
        return nil
    }

    enum NeededPermission { case accessibility, inputMonitoring }

    // MARK: Permissions and the tap

    func refreshPermissions() {
        canPost = KeyboardPermissions.canPost
        canListen = KeyboardPermissions.canListen
        refreshPrivacy()
        refreshTap()
    }

    func refreshPrivacy() {
        pasteboardPrivacy = environment.pasteboardPrivacy
        if pasteboardPrivacy == .allowed { pastedWithoutRestore = false }
    }

    /// The tap exists only while there's something to expand, expansion is on and macOS
    /// allows it. Paused = removed, not just ignored.
    func refreshTap() {
        let wanted = isEnabled && hasExpandableSnippets && canPost && !Diagnostics.noTap && !tapGaveUp
        if wanted && !tap.isInstalled {
            tapRefused = !tap.install()
            if tap.isInstalled { installMouseMonitor() }
        } else if !wanted && tap.isInstalled {
            tap.remove()
            removeMouseMonitor()
        }
        if !wanted { tapRefused = false }
        updateGate()
        updatePermissionPolling()
    }

    /// While the permission row is visible, re-check every second so it updates by itself.
    private func updatePermissionPolling() {
        let waiting = isEnabled && hasExpandableSnippets && needsPermission && !Diagnostics.noTap && !tapGaveUp
        if waiting, permissionTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let post = KeyboardPermissions.canPost
                    let listen = KeyboardPermissions.canListen
                    if post != self.canPost || listen != self.canListen || self.tapRefused { self.refreshPermissions() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            permissionTimer = timer
        } else if !waiting {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    private func tapTimedOut() {
        let now = Date()
        timeouts = timeouts.filter { now.timeIntervalSince($0) < 60 } + [now]
        Diagnostics.record("tap disabled by timeout (\(timeouts.count) in the last minute)")
        if timeouts.count >= 3 {
            tapGaveUp = true
            tap.remove()
            removeMouseMonitor()
        } else if let port = tapShared.port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    func retryAfterGivingUp() {
        tapGaveUp = false
        timeouts = []
        refreshPermissions()
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        // Passive (not in the click path). A click may move the caret anywhere, and may focus
        // a password field: check secure input just after.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tapShared.reset()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkSecureInput() }
            }
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func frontAppChanged() {
        frontApp = environment.frontApp
        if tap.isInstalled || Diagnostics.insertOnlyInto != nil { environment.prewarmAccessibility() }
        tapShared.update { $0.frontChanged() }
        checkSecureInput()
        updateGate()
    }

    private func inputSourceChanged() {
        inputMethodOn = InputSource.isInputMethod
        tapShared.reset()
        updateGate()
    }

    func checkSecureInput() {
        let on = environment.secureInputActive
        secureInputOn = on
        secureInputApp = on ? SecureInputHolder.appName() : nil
        updateGate()
        // Only while it's on: a slow timer notices when it ends (no events arrive meanwhile).
        if on, secureTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkSecureInput() }
            }
            RunLoop.main.add(timer, forMode: .common)
            secureTimer = timer
        } else if !on {
            secureTimer?.invalidate()
            secureTimer = nil
        }
    }

    private func updateGate() {
        var gate = TapGate()
        gate.paused = !isEnabled
        gate.excludedApp = isExcluded(frontApp?.bundleID)
        gate.inputMethod = inputMethodOn
        gate.secureInput = secureInputOn
        gate.ownPanel = ownPanelOpen
        tapShared.update { $0.setGate(gate) }
    }

    private func setOwnPanel(_ open: Bool) {
        guard ownPanelOpen != open else { return }
        ownPanelOpen = open
        updateGate()
    }

    // MARK: Expanding

    func handle(_ decision: TapDecision) {
        switch decision {
        case .none:
            break
        case .expand(let match):
            Task { await expand(match) }
        case .undo(let id):
            if expander.undo(id) { Diagnostics.record("undo expansion #\(id)") }
        }
    }

    private func expand(_ match: Match) async {
        let state = Diagnostics.signposter.beginInterval("expand")
        let report = await expander.expand(match)
        let ms = Double(MonotonicClock.now() &- match.at) / 1_000_000
        Diagnostics.signposter.endInterval("expand", state)
        switch report.outcome {
        case .inserted(let method, let characters, let restored):
            if method == .type { typedLatency.record(microseconds: ms * 1_000) } else { pastedLatency.record(microseconds: ms * 1_000) }
            let t = report.timings.map { Double($0 &- match.at) / 1_000_000 }
            Diagnostics.record(String(format: "expanded #%llu by %@%@ chars=%d restore=%@ match_at=%.6f guards_ms=%.2f (field_check_ms=%.2f) resolved_ms=%.2f posted_ms=%.2f match_to_posted_ms=%.2f",
                                      match.id, method.rawValue, report.formatted ? " (formatted)" : "", characters, restored ? "yes" : "no", Double(match.at) / 1e9,
                                      environment.lastFieldCheckMilliseconds,
                                      t.count > 0 ? t[0] : -1, t.count > 1 ? t[1] : -1, t.count > 2 ? t[2] : -1, ms))
            inserted(report)
        case .needsFillIn:
            if let request = report.fillIn { presentFillIn(request) }
        case .dropped: Diagnostics.record("dropped #\(match.id)")
        case .blockedSecureInput: Diagnostics.record("blocked #\(match.id): secure input")
        case .blockedPasswordField: Diagnostics.record("blocked #\(match.id): password field")
        case .snippetMissing: Diagnostics.record("dropped #\(match.id): snippet gone")
        case .targetChanged: break
        }
    }

    /// After any insert: count the use, and explain once if the clipboard couldn't be put back.
    private func inserted(_ report: Expander.Report) {
        if let id = report.snippetID { recordUse(id) }
        if report.pastedWithoutRestore && !pastedWithoutRestore {
            pastedWithoutRestore = true
            if !pasteNoticeDismissed {
                HUD.show("Pasted. Allow Paste from Other Apps to get your clipboard back next time.", systemImage: "doc.on.clipboard",
                         duration: .seconds(3))
            }
        }
    }

    // MARK: Fill-ins

    /// The text with `values`, for the form's live preview: plain, and never the real
    /// clipboard (it shows where the clipboard goes instead).
    func previewText(_ snippetID: UUID, values: FillValues) -> String {
        guard let snippet = library.snippet(snippetID) else { return "" }
        return PlaceholderResolver(now: Date()).resolve(snippet, values: values, lookup: library.lookup) { .text("‹clipboard›") }.text
    }

    /// One readable line for lists: placeholders resolved, an empty fill-in shown as ‹Name›.
    func readablePreview(_ snippet: Snippet) -> String {
        let lookup = library.lookup
        var values = FillValues()
        for field in FillIn.fields(for: snippet, lookup: lookup) {
            if case .text(let value) = field.kind, value.isEmpty { values[field.name] = .text("‹\(field.name)›") }
        }
        return PlaceholderResolver(now: Date()).resolve(snippet, values: values, lookup: lookup) { .text("‹clipboard›") }.text
    }

    private func presentFillIn(_ request: FillInRequest) {
        guard let snippet = library.snippet(request.snippetID) else { expander.cancel(request); return }
        let state = FillInState(title: snippet.title, fields: request.fields) { [weak self] values in
            self?.previewText(request.snippetID, values: values) ?? ""
        }
        fillIn.present(state, targetPID: request.targetPID, onInsert: { [weak self] values in
            Task { await self?.completeFillIn(request, values: values) }
        }, onCancel: { [weak self] in
            self?.expander.cancel(request)
            Diagnostics.record("fill-in cancelled")
        })
    }

    private func completeFillIn(_ request: FillInRequest, values: FillValues) async {
        // Let the keyboard go back to the app before typing into it.
        try? await Task.sleep(for: .milliseconds(60))
        let report = await expander.complete(request, values: values)
        switch report.outcome {
        case .inserted(let method, let characters, _):
            Diagnostics.record("filled in and inserted by \(method.rawValue)\(report.formatted ? " (formatted)" : "") chars=\(characters)")
            inserted(report)
        case .targetChanged:
            if let resolved = report.resolved { copy(resolved) }
            HUD.show("Copied: another app came to the front.", systemImage: "doc.on.clipboard")
            Diagnostics.record("fill-in: target changed, copied")
        case .blockedSecureInput, .blockedPasswordField:
            HUD.show("Not inserted: a password field has the keyboard.", systemImage: "lock")
            Diagnostics.record("fill-in blocked")
        default:
            Diagnostics.record("fill-in dropped")
        }
    }

    // MARK: Search panel

    func toggleSearch() { search.toggle() }

    /// Inserts a snippet picked in the search panel into the app that was in front. Without
    /// permission to type (or when Shorthand itself is in front) it's copied instead.
    func insertFromSearch(_ id: UUID) async {
        let front = environment.frontApp
        guard canPost, front?.bundleID != selfBundleID || Diagnostics.insertOnlyInto != nil else {
            copySnippet(id)
            return
        }
        try? await Task.sleep(for: .milliseconds(60))
        let report = await expander.insert(id)
        switch report.outcome {
        case .inserted(let method, let characters, _):
            Diagnostics.record("search inserted by \(method.rawValue)\(report.formatted ? " (formatted)" : "") chars=\(characters)")
            inserted(report)
        case .needsFillIn:
            if let request = report.fillIn { presentFillIn(request) }
        case .blockedSecureInput, .blockedPasswordField:
            copySnippet(id)
        default:
            break
        }
    }

    /// Puts a snippet on the clipboard (formatted ones with their formatting). Fill-ins take
    /// their defaults.
    func copySnippet(_ id: UUID) {
        guard let snippet = library.snippet(id) else { return }
        let values = FillValues.defaults(FillIn.fields(for: snippet, lookup: library.lookup))
        guard let resolved = expander.resolved(id, values: values) else { return }
        copy(resolved)
        recordUse(id)
        HUD.show("Copied", systemImage: "doc.on.clipboard")
        Diagnostics.record("copied snippet")
    }

    private func copy(_ resolved: Resolved) {
        if resolved.isFormatted {
            let text = RichText.assemble(resolved) { [weak self] in self?.formattedText($0) }
            RichClipboardPaster.write(RichText.pasteboardTypes(text, plain: resolved.text), to: pasteboard, transient: false)
        } else {
            ClipboardSnapshot.write(resolved.text, to: pasteboard, transient: false)
        }
    }

    private func recordUse(_ id: UUID) {
        // Count and date only, never what was typed around it.
        var copy = library
        copy.recordUse(id, at: Date())
        library = copy
        scheduleSave()
    }

    // MARK: Test mode

    /// Feeds a timeline into the real engine and types each key into the test target (only
    /// with `SHORTHAND_INSERT_ONLY_INTO`).
    func replay(_ url: URL) async {
        guard let data = try? Data(contentsOf: url), let timeline = try? JSONDecoder().decode(ReplayTimeline.self, from: data) else {
            Diagnostics.record("replay: unreadable timeline")
            return
        }
        guard Diagnostics.insertOnlyInto != nil else {
            Diagnostics.record("replay refused: needs SHORTHAND_INSERT_ONLY_INTO")
            return
        }
        frontAppChanged()
        Diagnostics.record("replay start steps=\(timeline.steps.count)")
        let keyboard = SyntheticKeyboard(destination: .process(environment.frontApp?.pid ?? -1))
        for step in timeline.steps {
            if step.after > 0 { try? await Task.sleep(for: .milliseconds(step.after)) }
            // The key arrives in the app first (as a typed key would), then the tap sees it.
            if timeline.echo != false {
                if let text = step.text {
                    keyboard.typeNow(text)
                } else if step.key == "backspace" {
                    keyboard.press(51)
                }
            }
            for input in ReplayTimeline.inputs(for: step) {
                let start = MonotonicClock.now()
                let decision = tapShared.handle(input, start: start)
                if decision != .none { handle(decision) }
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
        Diagnostics.record("replay end interleaved=\(tapShared.read(\.interleavedKeys)) " + latencySummary())
    }

    func latencySummary() -> String {
        "tap_callback{\(tapShared.latency.summary)} match_to_typed{\(typedLatency.summary)} match_to_pasted{\(pastedLatency.summary)}"
    }
}
