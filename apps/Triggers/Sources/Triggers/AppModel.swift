import AppKit
import Observation
import SlopKit
import TriggersCore
import UniformTypeIdentifiers

/// The sidebar's places.
enum SidebarItem: Hashable {
    case allApps, browsers, app(String)

    var scope: Scope {
        switch self {
        case .allApps: .allApps
        case .browsers: .browsers
        case .app(let id): .app(bundleID: id)
        }
    }

    init(_ scope: Scope) {
        switch scope {
        case .allApps: self = .allApps
        case .browsers: self = .browsers
        case .app(let id): self = .app(id)
        }
    }
}

/// A binding being added or edited in the sheet.
struct Draft: Identifiable {
    var binding: TriggerBinding
    var isNew: Bool
    var id: UUID { binding.id }
}

/// App state: the triggers, the engine that runs them and everything the UI shows.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var config = Config()
    var isPaused = false {
        didSet {
            engine.isPaused = isPaused
            Diagnostics.record(isPaused ? "paused" : "resumed")
        }
    }
    private(set) var isTrusted = false
    private(set) var frontApp: FrontApp?
    private(set) var recent = RecentLog()
    private(set) var loadError: String?
    private(set) var gestureProblem: String?
    private(set) var tapGaveUp = false
    private(set) var systemGestures = SystemGestureSettings()
    private(set) var systemShortcuts: Set<KeyCombo> = []

    // Editor state
    var selection: SidebarItem = .allApps
    var selectedBindings: Set<UUID> = []
    var draft: Draft?
    var searchText = ""

    // Recording (the sheet's "Do it now" area)
    private(set) var isRecording = false
    var recordedTrigger: Trigger?
    private(set) var liveFingers = 0

    let engine: TriggerEngine
    let touch: MultitouchSource
    let tap: MouseTap
    let performer: SystemPerformer
    private let hotkeys: CarbonHotkeys
    private let front = FrontAppTracker()
    private let storage: FileConfigStorage
    private var trustTimer: Timer?

    var settings = UserSettings()

    private init() {
        let directory = Diagnostics.dataDirectory ?? (try? AppPaths.applicationSupport) ?? FileManager.default.temporaryDirectory
        storage = FileConfigStorage(url: directory.appendingPathComponent("Triggers.json"))
        touch = MultitouchSource()
        tap = MouseTap()
        hotkeys = CarbonHotkeys()
        performer = SystemPerformer()
        engine = TriggerEngine(touch: touch, mouse: tap, hotkeys: hotkeys, performer: performer,
                               modifiers: SystemModifiers(), clock: { Diagnostics.now() })
        gestureProblem = touch.unavailableReason
        touch.tuning = settings.tuning
    }

    func start() {
        load()
        isTrusted = AccessibilityTrust.isTrusted
        engine.isAccessibilityTrusted = isTrusted && !Diagnostics.noInput
        engine.onFired = { [weak self] binding, app, result in self?.fired(binding, app: app, result: result) }
        engine.onRecord = { [weak self] trigger in self?.recorded(trigger) }
        touch.onFingers = { [weak self] count in self?.liveFingers = count }
        tap.onGaveUp = { [weak self] in
            self?.tapGaveUp = true
            Diagnostics.record("mouse tap gave up after repeated timeouts")
        }
        front.onChange = { [weak self] app in
            self?.frontApp = app
            self?.engine.frontApp = app
        }
        front.start()
        engine.update(config: config)
        refreshSystemSettings()
        watchTrust()
        // Off the launch path: the first key post shouldn't pay for creating its event source.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { KeyPoster.warmUp() }
        NotificationCenter.default.addObserver(forName: .touchSourceChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.gestureProblem = AppModel.shared.touch.unavailableReason }
        }
        NotificationCenter.default.addObserver(forName: .actionFailed, object: nil, queue: .main) { note in
            let message = note.object as? String
            MainActor.assumeIsolated { if let message { HUD.show(message, systemImage: "exclamationmark.triangle") } }
        }
    }

    // MARK: Storage

    private func load() {
        do {
            if let data = try storage.load() { config = try ConfigCodec.decode(data) }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "The triggers file couldn't be read."
            Diagnostics.record("load failed: \(error)")
        }
    }

    private func save() {
        // A file from a newer version is never overwritten.
        guard loadError == nil else { return }
        do {
            try storage.save(ConfigCodec.encode(config))
        } catch {
            Diagnostics.record("save failed: \(error)")
        }
    }

    /// Every change goes through here: saved, live immediately, undoable.
    func change(_ actionName: String, undo: UndoManager?, _ body: (inout Config) -> Void) {
        let before = config
        var after = config
        body(&after)
        guard after != before else { return }
        apply(after, undoTo: before, name: actionName, undo: undo)
    }

    private func apply(_ new: Config, undoTo old: Config, name: String, undo: UndoManager?) {
        config = new
        engine.update(config: config)
        save()
        selectedBindings = selectedBindings.filter { id in config.bindings.contains { $0.id == id } }
        undo?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.apply(old, undoTo: new, name: name, undo: undo) }
        }
        undo?.setActionName(name)
    }

    /// Offscreen snapshots only: show this config without saving it.
    func replaceForSnapshot(_ new: Config) {
        config = new
        engine.update(config: config)
    }

    // MARK: Bindings

    func bindings(for item: SidebarItem) -> [TriggerBinding] {
        let all = config.bindings(in: item.scope)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { binding in
            KeyDisplay.title(binding.trigger).localizedCaseInsensitiveContains(query)
                || KeyDisplay.title(binding.action).localizedCaseInsensitiveContains(query)
        }
    }

    func binding(_ id: UUID) -> TriggerBinding? { config.bindings.first { $0.id == id } }

    func newDraft(in item: SidebarItem? = nil) -> Draft {
        let scope = (item ?? selection).scope
        // Middle click in All Apps, Back in browsers: a sensible start the person changes.
        let action: Action = scope == .browsers ? .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)) : .click(.middle)
        return Draft(binding: TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: action, scope: scope), isNew: true)
    }

    func beginNew() { draft = newDraft() }

    func beginEdit(_ id: UUID) {
        guard let binding = binding(id) else { return }
        draft = Draft(binding: binding, isNew: false)
    }

    func commit(_ draft: Draft, undo: UndoManager?) {
        change(draft.isNew ? "Add Trigger" : "Edit Trigger", undo: undo) { config in
            if case .app(let id) = draft.binding.scope, config.app(id) == nil {
                config.addApp(bundleID: id, name: appName(id))
            }
            if let index = config.bindings.firstIndex(where: { $0.id == draft.binding.id }) {
                config.bindings[index] = draft.binding
            } else {
                config.bindings.append(draft.binding)
            }
        }
        selection = SidebarItem(draft.binding.scope)
        selectedBindings = [draft.binding.id]
        self.draft = nil
    }

    func setEnabled(_ ids: Set<UUID>, _ enabled: Bool, undo: UndoManager?) {
        change(enabled ? "Turn On" : "Turn Off", undo: undo) { config in
            for index in config.bindings.indices where ids.contains(config.bindings[index].id) {
                config.bindings[index].isEnabled = enabled
            }
        }
    }

    func toggle(_ ids: Set<UUID>, undo: UndoManager?) {
        let bindings = config.bindings.filter { ids.contains($0.id) }
        setEnabled(ids, !bindings.allSatisfy(\.isEnabled), undo: undo)
    }

    func delete(_ ids: Set<UUID>, undo: UndoManager?) {
        guard !ids.isEmpty else { return }
        change(ids.count == 1 ? "Delete Trigger" : "Delete Triggers", undo: undo) { config in
            config.bindings.removeAll { ids.contains($0.id) }
        }
    }

    func duplicate(_ ids: Set<UUID>, undo: UndoManager?) {
        var copies: [TriggerBinding] = []
        change("Duplicate", undo: undo) { config in
            for binding in config.bindings where ids.contains(binding.id) {
                var copy = binding
                copy.id = UUID()
                copy.isEnabled = false // an exact twin would only ever be a duplicate
                copies.append(copy)
                config.bindings.append(copy)
            }
        }
        selectedBindings = Set(copies.map(\.id))
    }

    @discardableResult
    func runNow(_ id: UUID) -> ActionResult? {
        guard let binding = binding(id) else { return nil }
        return engine.runNow(binding)
    }

    func applyStarter(_ starter: Starter, undo: UndoManager?) {
        var added: [TriggerBinding] = []
        change("Add \(starter.title)", undo: undo) { config in added = starter.apply(to: &config) }
        if let first = added.first {
            selection = SidebarItem(first.scope)
            selectedBindings = Set(added.filter { $0.scope == first.scope }.map(\.id))
        }
    }

    // MARK: Apps

    func appName(_ bundleID: String) -> String {
        if let entry = config.app(bundleID) { return entry.name }
        if let fake = (FakeCatalog.apps).first(where: { $0.bundleID == bundleID }) { return fake.name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    func addApp(_ app: AppChoice, undo: UndoManager?) {
        change("Add App", undo: undo) { $0.addApp(bundleID: app.bundleID, name: app.name) }
        selection = .app(app.bundleID)
    }

    func removeApp(_ bundleID: String, undo: UndoManager?) {
        change("Remove App", undo: undo) { config in
            config.apps.removeAll { $0.bundleID == bundleID }
            config.bindings.removeAll { $0.scope == .app(bundleID: bundleID) }
        }
        if selection == .app(bundleID) { selection = .allApps }
    }

    func usesAllAppsTriggers(in bundleID: String) -> Bool { config.usesAllAppsTriggers(in: bundleID) }

    func setUsesAllAppsTriggers(_ value: Bool, in bundleID: String, name: String, undo: UndoManager?) {
        change(value ? "Use All-Apps Triggers" : "Turn Off All-Apps Triggers", undo: undo) {
            $0.setUsesAllAppsTriggers(value, in: bundleID, name: name)
        }
    }

    /// The app "Turn Off in…" talks about: the one in front, or the last one before Triggers.
    var menuTargetApp: FrontApp? {
        let candidate = frontApp?.bundleID == Bundle.main.bundleIdentifier ? front.lastOther : frontApp
        return candidate?.bundleID == nil ? nil : candidate
    }

    // MARK: Conflicts and permissions

    var checker: ConflictChecker {
        ConflictChecker(system: systemGestures, systemShortcuts: systemShortcuts, unavailableShortcuts: engine.unavailableShortcuts)
    }

    func conflicts(for binding: TriggerBinding) -> [Conflict] {
        var result = checker.conflicts(for: binding, in: config)
        // Registration failures are only known for combos in use right now; say so for this one too.
        if case .keyCombo(let combo) = binding.trigger, engine.unavailableShortcuts.contains(combo), !result.contains(.shortcutTaken) {
            result.insert(.shortcutTaken, at: 0)
        }
        return result
    }

    func refreshSystemSettings() {
        systemGestures = SystemGestureReader.read()
        if !Diagnostics.noInput { systemShortcuts = SystemShortcuts.current() }
    }

    /// Accessibility is needed if any enabled binding posts, clicks, moves windows or swallows buttons.
    var needsAccessibility: Bool {
        config.enabledBindings.contains { $0.action.needsAccessibility || $0.trigger.family == .mouse }
    }

    func needsAccessibility(_ binding: TriggerBinding) -> Bool {
        !isTrusted && (binding.action.needsAccessibility || binding.trigger.family == .mouse)
    }

    func needsGestures(_ binding: TriggerBinding) -> Bool { gestureProblem != nil && binding.trigger.family == .trackpad }

    func openAccessibilitySettings() { Permission.accessibility.request() }

    /// Live re-check: the system's notification when any app's trust changes, plus a slow
    /// check only while the tap is installed (trust lost with an active tap can freeze input)
    /// or while something is waiting for the permission.
    private func watchTrust() {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"),
                                                            object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                MainActor.assumeIsolated { AppModel.shared.checkTrust() }
            }
        }
        updateTrustTimer()
    }

    func checkTrust() {
        let trusted = AccessibilityTrust.isTrusted
        defer { updateTrustTimer() }
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        if trusted {
            tapGaveUp = false
            engine.isAccessibilityTrusted = !Diagnostics.noInput
        } else {
            engine.accessibilityRevoked()
        }
        Diagnostics.record("accessibility \(trusted ? "granted" : "revoked")")
    }

    private func updateTrustTimer() {
        let wanted = tap.isInstalled || (!isTrusted && needsAccessibility)
        if wanted, trustTimer == nil {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { AppModel.shared.checkTrust() }
            }
            trustTimer?.tolerance = 0.5
        } else if !wanted, let timer = trustTimer {
            timer.invalidate()
            trustTimer = nil
        }
    }

    // MARK: Firing

    private func fired(_ binding: TriggerBinding, app: FrontApp?, result: ActionResult) {
        var outcome: String?
        switch result {
        case .done:
            if settings.showsConfirmation {
                HUD.show("\(KeyDisplay.title(binding.trigger)): \(KeyDisplay.title(binding.action))", systemImage: binding.trigger.systemImage)
            }
        case .skipped(let reason):
            outcome = reason
        case .failed(let message):
            outcome = message
            HUD.show(message, systemImage: "exclamationmark.triangle", duration: .seconds(3))
        }
        recent.record(binding, appName: app?.name, date: Date(), outcome: outcome)
    }

    // MARK: Recording

    func startRecording() {
        recordedTrigger = nil
        isRecording = true
        touch.reportsFingers = true
        engine.startRecording()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        touch.reportsFingers = false
        liveFingers = 0
        engine.stopRecording()
    }

    /// Live finger count from a replay (test mode), as the touch source reports it.
    func touchFingers(_ count: Int) { liveFingers = count }

    /// The tap gave up after repeated timeouts: try once more.
    func retryTap() {
        tapGaveUp = false
        engine.apply()
    }

    /// Mouse buttons and keys arrive from the sheet's own event monitor; gestures from the engine.
    func recorded(_ trigger: Trigger) {
        guard isRecording else { return }
        recordedTrigger = trigger
        Diagnostics.record("recognized \(trigger.fallbackTitle) (recording)")
    }

    // MARK: Import, export, diagnostics

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Triggers.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigCodec.encode(config).write(to: url, options: .atomic)
        } catch {
            HUD.show("Couldn't save \(url.lastPathComponent).", systemImage: "exclamationmark.triangle")
        }
    }

    func importFile(undo: UndoManager?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try ConfigCodec.decode(Data(contentsOf: url))
            var added = 0
            change("Import Triggers", undo: undo) { config in
                let merged = ConfigCodec.merge(imported, into: config)
                config = merged.config
                added = merged.added
            }
            HUD.show(added == 1 ? "Added 1 trigger" : "Added \(added) triggers", systemImage: "square.and.arrow.down")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "It may be damaged."
            HUD.show("Couldn't import \(url.lastPathComponent). \(message)", systemImage: "exclamationmark.triangle", duration: .seconds(3))
        }
    }

    /// Versions, permission state, tap statistics and counts. No inputs, apps or content.
    func diagnosticsReport() -> String {
        let info = AppInfo.current(fallbackName: "Triggers")
        let frames = touch.frameStats
        let families = Dictionary(grouping: config.bindings, by: { $0.trigger.family.rawValue }).mapValues(\.count)
        return """
        Triggers \(info.version) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        accessibility=\(isTrusted) paused=\(isPaused) gestures=\(gestureProblem == nil ? "available" : "unavailable")
        touch_devices=\(touch.deviceSummary.isEmpty ? "none started" : touch.deviceSummary.joined(separator: ", "))
        touch_frames=\(frames.frames) bad_frames=\(frames.bad)
        frame_interval \(frames.intervals.summary)
        recognizer_cost \(frames.cost.summary)
        tap_installed=\(tap.isInstalled) tap_callback \(tap.callbackLatency.summary)
        window_server \(EventTapStats.summary())
        dispatch \(engine.dispatchLatency.summary)
        posts \(performer.postLatency.summary)
        window_moves \(performer.windowLatency.summary)
        bindings=\(config.bindings.count) enabled=\(config.enabledBindings.count) by_family=\(families) apps=\(config.apps.count)
        hotkeys_unavailable=\(engine.unavailableShortcuts.count)
        """
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Triggers Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? diagnosticsReport().write(to: url, atomically: true, encoding: .utf8)
    }

    /// The menu's status line.
    var statusLine: String {
        if loadError != nil { return "Couldn't read your triggers" }
        if isPaused { return "Paused" }
        if !isTrusted && needsAccessibility { return "Needs Accessibility access" }
        let count = config.enabledBindings.count
        return count == 0 ? "No triggers on" : count == 1 ? "1 trigger on" : "\(count) triggers on"
    }
}

/// Preferences (UserDefaults, or the test domain).
@MainActor
@Observable
final class UserSettings {
    private let defaults = Diagnostics.defaults

    var showsConfirmation: Bool {
        didSet { defaults.set(showsConfirmation, forKey: "showsConfirmation") }
    }
    var tapSensitivity: GestureTuning.TapSensitivity {
        didSet { defaults.set(tapSensitivity.rawValue, forKey: "tapSensitivity"); AppModel.shared.touch.tuning = tuning }
    }
    var swipeDistance: GestureTuning.SwipeDistance {
        didSet { defaults.set(swipeDistance.rawValue, forKey: "swipeDistance"); AppModel.shared.touch.tuning = tuning }
    }
    var didShowFirstRun: Bool {
        didSet { defaults.set(didShowFirstRun, forKey: "didShowFirstRun") }
    }

    var tuning: GestureTuning { GestureTuning(tap: tapSensitivity, swipe: swipeDistance) }

    init() {
        showsConfirmation = defaults.bool(forKey: "showsConfirmation")
        tapSensitivity = defaults.string(forKey: "tapSensitivity").flatMap(GestureTuning.TapSensitivity.init(rawValue:)) ?? .standard
        swipeDistance = defaults.string(forKey: "swipeDistance").flatMap(GestureTuning.SwipeDistance.init(rawValue:)) ?? .standard
        didShowFirstRun = defaults.bool(forKey: "didShowFirstRun")
    }
}
