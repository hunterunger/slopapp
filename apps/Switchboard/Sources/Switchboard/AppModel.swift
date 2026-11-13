import AppKit
import Observation
import UniformTypeIdentifiers
import SlopKit
import SwitchboardCore

/// App state: the user's settings, what's installed, and whether we're the default browser.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// The user's settings. Every change is saved (debounced).
    var config: Config {
        didSet {
            guard config != oldValue else { return }
            scheduleSave()
        }
    }

    /// Real browsers found on this Mac, and other apps that can open web links.
    private(set) var installedBrowsers: [InstalledApp] = []
    private(set) var otherLinkApps: [InstalledApp] = []

    /// Mail apps found on this Mac, and other apps that can open mailto: links.
    private(set) var installedMailApps: [InstalledApp] = []
    private(set) var otherMailApps: [InstalledApp] = []

    private(set) var isDefaultBrowser = false
    /// Who opens email links now (nil: nobody, or unknown).
    private(set) var emailHolder: AppRef?
    var isDefaultEmailApp: Bool { roles.isOurs(emailHolder) }
    /// Who opens each listed file type now, by `FileType.id`.
    private(set) var fileTypeHolders: [String: AppRef] = [:]
    /// Bumped when the handoff apps are looked up again (Settings shows what's installed).
    private(set) var handoffRefresh = 0
    /// Shown once in Settings if the settings file was unreadable and had to be set aside.
    var recoveryNotice: String?

    /// True after becoming the default browser turned on launch at login (shown in General).
    var launchAtLoginWasTurnedOn = UserDefaults.standard.bool(forKey: "didEnableLaunchAtLogin")

    /// The most recent "always open here" rule, so it can be undone from the menu too.
    var learnedRuleUndo: LearnedRuleUndo?

    /// The last link dismissed from the picker, so it can be brought back from the menu.
    var lastDismissedLink: URL?

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// macOS's default apps: the real ones, or an in-memory copy in dry runs.
    @ObservationIgnored let roles: HandlerRoles

    private init() {
        let own = AppRef(path: Bundle.main.bundlePath, bundleID: Bundle.main.bundleIdentifier)
        let registry: DefaultAppRegistry = Diagnostics.isDryRun || Showcase.isActive
            ? WorkspaceRegistry.dryRunCopy(own: own) : WorkspaceRegistry()
        roles = HandlerRoles(registry: registry, own: own)
        let support = (try? AppPaths.applicationSupport)
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/app.slopapp.switchboard")
        let file = Diagnostics.configOverride ?? support.appending(path: "config.json")
        store = ConfigStore(fileURL: file)
        if Showcase.isActive {
            // Store screenshots: synthetic settings, never the person's own.
            func path(_ id: String, _ fallback: String) -> String {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? fallback
            }
            config = ShowcaseFixtures.config(
                safariPath: path(ShowcaseFixtures.safariID, "/Applications/Safari.app"),
                chromePath: path(ShowcaseFixtures.chromeID, "/Applications/Google Chrome.app"))
            refreshInstalledApps()
            isDefaultBrowser = true
            return
        }
        switch store.load() {
        case .loaded(let config):
            self.config = config
        case .fresh:
            self.config = Config()
        case .recovered(let backup):
            self.config = Config()
            recoveryNotice = "Your settings file couldn't be read, so Switchboard started fresh. The old file is at \(backup.path)."
        }
        refreshInstalledApps()
        refreshDefaultStatus()
    }

    // MARK: - Installed apps

    func refreshInstalledApps() {
        Opener.forgetLocations()
        guard let probe = URL(string: "https://example.com") else { return }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> InstalledApp? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            return InstalledApp(bundleID: id, path: url.path, name: Self.displayName(of: url))
        }
        let split = BrowserDiscovery.classify(apps, excluding: Bundle.main.bundleIdentifier)
        installedBrowsers = split.browsers
        otherLinkApps = split.others
        HandoffApps.forget()
        handoffRefresh += 1

        if !config.didSeedTargets {
            config.targets = BrowserDiscovery.defaultTargets(from: split.browsers)
            config.didSeedTargets = true
        }
    }

    static func displayName(of appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Apps that can open email links. Read when Settings opens, not at launch.
    func refreshMailApps() {
        guard let probe = WorkspaceRegistry.probe("mailto") else { return }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> InstalledApp? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            return InstalledApp(bundleID: id, path: url.path, name: Self.displayName(of: url))
        }
        let split = MailAppCatalog.classify(apps, excluding: Bundle.main.bundleIdentifier)
        installedMailApps = split.mailApps
        otherMailApps = split.others
        // Like browsers: start the email list with the mail apps that are here.
        if !config.didSeedEmailTargets { config.seedEmailTargets(from: split.mailApps) }
    }

    /// Before the first email link is routed: make sure the list has been seeded.
    func seedEmailTargetsIfNeeded() {
        if !config.didSeedEmailTargets { refreshMailApps() }
    }

    // MARK: - Default browser, email app, file types

    func refreshDefaultStatus() {
        if Diagnostics.assumesDefault || Showcase.isActive {
            isDefaultBrowser = true
        } else {
            isDefaultBrowser = roles.holds(.browser)
        }
        emailHolder = roles.holder(of: .email)
        // The menu offers mail apps to hand email back to; look them up once when needed.
        if isDefaultEmailApp, installedMailApps.isEmpty { refreshMailApps() }
        var holders: [String: AppRef] = [:]
        for type in config.fileTypes + FileType.presets where holders[type.id] == nil {
            holders[type.id] = roles.holder(of: .fileType(type))
        }
        fileTypeHolders = holders
    }

    /// Asks macOS to make Switchboard the default browser. macOS shows its own confirmation.
    func makeDefaultBrowser() {
        change(.browser, to: nil) { [weak self] in
            guard let self else { return }
            // Links should never wait for a launch: start at login once we're the default,
            // unless the user already decided.
            if self.isDefaultBrowser, !UserDefaults.standard.bool(forKey: "didEnableLaunchAtLogin") {
                UserDefaults.standard.set(true, forKey: "didEnableLaunchAtLogin")
                let login = LaunchAtLogin()
                login.set(true)
                if login.isEnabled {
                    self.launchAtLoginWasTurnedOn = true
                    HUD.show("Switchboard now opens at login, so links never wait", systemImage: "person.badge.clock", duration: .seconds(3))
                }
            }
        }
    }

    /// Hands default-browser status to another app. macOS shows its own confirmation.
    func handBack(to app: InstalledApp) {
        change(.browser, to: AppRef(path: app.path, bundleID: app.bundleID))
    }

    /// Asks macOS to send email links to Switchboard. macOS shows its own confirmation.
    /// The app that had them is offered as an email target, so nothing is lost.
    func makeDefaultEmailApp() {
        let previous = emailHolder
        change(.email, to: nil) { [weak self] in
            guard let self, self.isDefaultEmailApp else { return }
            if let previous, !self.roles.isOurs(previous), let id = previous.bundleID,
               !self.config.emailTargets.contains(where: { $0.bundleID == id && $0.webmail == nil }) {
                self.config.addEmailTarget(Target(bundleID: id, appPath: previous.path,
                                                  appName: Self.displayName(of: URL(fileURLWithPath: previous.path))))
            }
        }
    }

    func handBackEmail(to app: InstalledApp) {
        change(.email, to: AppRef(path: app.path, bundleID: app.bundleID))
    }

    /// Makes Switchboard the app for a file type. The app that had it is remembered: files
    /// of that type keep opening there unless a rule says otherwise, and go back to it when
    /// the user stops.
    func takeOver(_ preset: FileType) {
        let previous = fileTypeHolders[preset.id] ?? roles.holder(of: .fileType(preset))
        change(.fileType(preset), to: nil) { [weak self] in
            guard let self, self.roles.holds(.fileType(preset)) else { return }
            var type = self.config.fileTypes.first { $0.id == preset.id } ?? preset
            if type.app == nil, let previous, !self.roles.isOurs(previous), let id = previous.bundleID {
                let app = Target(bundleID: id, appPath: previous.path, appName: Self.displayName(of: URL(fileURLWithPath: previous.path)))
                type.app = app
                if type.fallback == .ask { type.fallback = .open(targetID: app.id) }
            }
            if let index = self.config.fileTypes.firstIndex(where: { $0.id == type.id }) {
                self.config.fileTypes[index] = type
            } else {
                self.config.fileTypes.append(type)
            }
        }
    }

    /// Gives a file type back to the app it came from (or another one the user picks).
    func handBack(_ type: FileType, to app: AppRef) {
        change(.fileType(type), to: app)
    }

    /// Apps (other than Switchboard) that can open this file type, for "Give Back To".
    func candidates(for type: FileType) -> [InstalledApp] {
        var seen = Set<String>()
        return type.typeIdentifiers.compactMap(UTType.init).flatMap(NSWorkspace.shared.urlsForApplications(toOpen:))
            .compactMap { url -> InstalledApp? in
                guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      seen.insert(id.lowercased()).inserted else { return nil }
                return InstalledApp(bundleID: id, path: url.path, name: Self.displayName(of: url))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Changes who holds `role`: Switchboard (`app` nil) or another app. In dry runs only the
    /// in-memory copy changes.
    private func change(_ role: HandlerRole, to app: AppRef?, completion: (@MainActor () -> Void)? = nil) {
        Task { @MainActor in
            do {
                if let app {
                    try await roles.handBack(role, to: app)
                } else {
                    try await roles.become(role)
                }
            } catch {
                Diagnostics.record("default app change failed role=\(role) error=\(error)")
            }
            refreshDefaultStatus()
            completion?()
        }
    }

    // MARK: - Targets

    func target(id: UUID) -> Target? { config.target(id: id) }

    /// Adds a target unless the exact same destination is already listed (then shows it).
    @discardableResult
    func addTarget(_ target: Target) -> UUID {
        let restoring = config.removedTargets.contains { $0.destinationKey == target.destinationKey }
        let id = config.addTarget(target)
        if restoring {
            let count = config.rulesUsing(id).count
            if count > 0 {
                HUD.show(count == 1 ? "1 rule uses \(target.displayName) again" : "\(count) rules use \(target.displayName) again",
                         systemImage: "arrow.uturn.backward.circle")
            }
        }
        return id
    }

    /// Display name for a rule's destination, including removed browsers.
    func destinationName(_ action: RuleAction) -> (name: String, isMissing: Bool) {
        switch action {
        case .ask:
            return ("Show the picker", false)
        case .open(let id):
            if let target = config.target(id: id) {
                return (target.displayName, !isInstalled(target))
            }
            return (config.removedTarget(id: id)?.displayName ?? "A removed browser", true)
        }
    }

    func addTarget(app: InstalledApp, profile: BrowserProfile? = nil, privateWindow: Bool = false) -> UUID {
        addTarget(Target(bundleID: app.bundleID, appPath: app.path, appName: app.name, profile: profile, privateWindow: privateWindow))
    }

    /// Adds any app the user picked with an open panel.
    func addTarget(appAt url: URL) -> UUID? {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        if id == Bundle.main.bundleIdentifier { return nil }
        return addTarget(Target(bundleID: id, appPath: url.path, appName: Self.displayName(of: url)))
    }

    /// Adds a mail app or webmail to the email list.
    @discardableResult
    func addEmailTarget(_ target: Target) -> UUID {
        config.addEmailTarget(target)
    }

    func removeTarget(id: UUID, undoManager: UndoManager? = nil) {
        let name = config.target(id: id)?.displayName ?? "Browser"
        changeUndoably("Remove \(name)", undoManager: undoManager) { $0.removeTarget(id: id) }
    }

    func removeRule(id: UUID, undoManager: UndoManager?) {
        changeUndoably("Delete Rule", undoManager: undoManager) { config in
            config.rules.removeAll { $0.id == id }
        }
    }

    /// Replaces or merges in imported settings; ⌘Z (and the Undo button) puts them back.
    func applyImport(_ plan: SettingsTransfer.Plan, mode: SettingsTransfer.Mode, undoManager: UndoManager?) {
        changeUndoably(mode == .replace ? "Replace Settings" : "Import Settings", undoManager: undoManager) { config in
            config = plan.result
        }
        refreshDefaultStatus()
    }

    /// Applies a change and registers ⌘Z to restore the settings as they were.
    func changeUndoably(_ actionName: String, undoManager: UndoManager?, _ change: (inout Config) -> Void) {
        let before = config
        change(&config)
        guard let undoManager, before != config else { return }
        undoManager.registerUndo(withTarget: self) { model in
            let after = model.config
            model.config = before
            undoManager.registerUndo(withTarget: model) { $0.config = after }
        }
        undoManager.setActionName(actionName)
    }

    func isInstalled(_ target: Target) -> Bool { Opener.isInstalled(target) }

    // MARK: - Learned rules

    func undoLearnedRule(_ undo: LearnedRuleUndo) {
        guard let index = config.rules.firstIndex(where: { $0.id == undo.ruleID }) else { return }
        if let previous = undo.previous {
            config.rules[index] = previous
        } else {
            config.rules.remove(at: index)
        }
        if learnedRuleUndo == undo { learnedRuleUndo = nil }
        UndoToast.hide()
        HUD.show("Removed the rule for \(undo.host)", systemImage: "arrow.uturn.backward.circle")
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            try store.save(config)
        } catch {
            Diagnostics.logger.error("Couldn't save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Loads Chromium profile lists off the main thread (macOS may pause the read to ask the user).
enum ProfileLoader {
    static func load(dataDirectory: String) async -> Result<[BrowserProfile], ChromiumProfiles.Failure> {
        await Task.detached(priority: .userInitiated) { () -> Result<[BrowserProfile], ChromiumProfiles.Failure> in
            do {
                return .success(try ChromiumProfiles.load(dataDirectory: dataDirectory))
            } catch let failure as ChromiumProfiles.Failure {
                return .failure(failure)
            } catch {
                return .failure(.unreadable)
            }
        }.value
    }
}

/// Enough to take back an "always open here" pick.
struct LearnedRuleUndo: Equatable {
    let ruleID: UUID
    /// The rule it replaced (same host, no other conditions), if any.
    let previous: Rule?
    let host: String
}
