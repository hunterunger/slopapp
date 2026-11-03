import AppKit
import Observation
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

    private(set) var isDefaultBrowser = false
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

    private init() {
        let support = (try? AppPaths.applicationSupport)
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/app.slopapp.switchboard")
        let file = Diagnostics.configOverride ?? support.appending(path: "config.json")
        store = ConfigStore(fileURL: file)
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

        if !config.didSeedTargets {
            config.targets = BrowserDiscovery.defaultTargets(from: split.browsers)
            config.didSeedTargets = true
        }
    }

    static func displayName(of appURL: URL) -> String {
        FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Default browser

    func refreshDefaultStatus() {
        guard let probe = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else {
            isDefaultBrowser = false
            return
        }
        let ours = Bundle.main.bundleIdentifier
        isDefaultBrowser = Bundle(url: handler)?.bundleIdentifier == ours && ours != nil
    }

    /// Asks macOS to make Switchboard the default browser. macOS shows its own confirmation.
    func makeDefaultBrowser() {
        setDefault(to: Bundle.main.bundleURL) { [weak self] in
            guard let self else { return }
            self.refreshDefaultStatus()
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
        setDefault(to: URL(fileURLWithPath: app.path)) { [weak self] in self?.refreshDefaultStatus() }
    }

    private func setDefault(to appURL: URL, completion: @escaping @MainActor () -> Void) {
        let schemes = ["http", "https"]
        Task { @MainActor in
            for scheme in schemes {
                try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme)
            }
            try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: .html)
            completion()
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

    func removeTarget(id: UUID, undoManager: UndoManager? = nil) {
        let name = config.target(id: id)?.displayName ?? "Browser"
        changeUndoably("Remove \(name)", undoManager: undoManager) { $0.removeTarget(id: id) }
    }

    func removeRule(id: UUID, undoManager: UndoManager?) {
        changeUndoably("Delete Rule", undoManager: undoManager) { config in
            config.rules.removeAll { $0.id == id }
        }
    }

    /// Applies a change and registers ⌘Z to restore the settings as they were.
    private func changeUndoably(_ actionName: String, undoManager: UndoManager?, _ change: (inout Config) -> Void) {
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
