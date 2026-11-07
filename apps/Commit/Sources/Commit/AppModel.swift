import AppKit
import CommitCore
import Observation
import SlopKit
import SwiftUI

/// Settings keys (UserDefaults), shared by the Settings window and the models.
enum Preference {
    static let gitOverride = "gitExecutableOverride"
    static let useShellPath = "useLoginShellPath"
    static let showUntracked = "showUntrackedFiles"
    static let autoFetchMinutes = "autoFetchMinutes"
    static let recents = "recentRepositories"
    static let contextLines = "diffContextLines"
}

/// App-wide state: which git, its environment, recent repositories, the askpass server, and
/// the open repository windows.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// nil while checking.
    private(set) var installation: GitInstallation?
    private(set) var environment = GitEnvironment(base: ProcessInfo.processInfo.environment)
    private(set) var recents: RecentRepositories
    private(set) var isReady = false

    /// Repository windows by model id (askpass routing) .
    @ObservationIgnored private var repositories: [UUID: WeakRepo] = [:]
    @ObservationIgnored private var askpassServer: AskpassServer?
    @ObservationIgnored private var pendingOpens: [URL] = []
    /// Set by the first window that appears; lets AppKit code (the app delegate) open windows.
    @ObservationIgnored var openWindowAction: OpenWindowAction?
    @ObservationIgnored var dismissWindowAction: DismissWindowAction?
    @ObservationIgnored private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    private struct WeakRepo { weak var model: RepoModel? }

    init() {
        UserDefaults.standard.register(defaults: [
            Preference.useShellPath: true,
            Preference.showUntracked: true,
            Preference.autoFetchMinutes: 0,
            Preference.contextLines: 3,
        ])
        if Diagnostics.resetRecents { UserDefaults.standard.removeObject(forKey: Preference.recents) }
        recents = RecentRepositories(paths: UserDefaults.standard.stringArray(forKey: Preference.recents) ?? [])
    }

    var runner: ProcessGitRunner? {
        guard case .found(let path, _) = installation else { return nil }
        return ProcessGitRunner(executable: URL(fileURLWithPath: path), environment: environment.variables())
    }

    /// A runner whose askpass prompts go to `repository`'s window.
    func runner(for repository: UUID) -> ProcessGitRunner? {
        guard case .found(let path, _) = installation else { return nil }
        return ProcessGitRunner(executable: URL(fileURLWithPath: path),
                                environment: environment.variables(repositoryID: repository.uuidString))
    }

    // MARK: Launch

    /// Finds git, resolves the login shell's PATH and starts the prompt server, off the main
    /// thread. Windows wait for this before running git.
    func prepare() {
        guard !isReady, installation == nil else { return }
        Task {
            let start = ContinuousClock.now
            let override = UserDefaults.standard.string(forKey: Preference.gitOverride)
            let useShell = UserDefaults.standard.bool(forKey: Preference.useShellPath) && !Diagnostics.skipShellPath
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            async let located = GitLocator(probe: SystemGitProbe()).locate(override: override)
            async let path: String? = useShell ? ShellPath.resolve(shell: shell) : nil
            let (found, shellPath) = await (located, path)
            var environment = GitEnvironment(base: ProcessInfo.processInfo.environment, shellPath: shellPath)
            if let server = startAskpass() {
                environment.askpass = .init(helper: Bundle.main.executablePath ?? CommandLine.arguments[0],
                                            socket: server.socketPath, token: server.token)
            }
            self.environment = environment
            self.installation = found
            self.isReady = true
            Diagnostics.record("prepare_ms=\(Diagnostics.milliseconds(since: start)) git=\(found.path ?? "none") shell_path=\(shellPath != nil)")
            for waiter in readyWaiters { waiter.resume() }
            readyWaiters = []
        }
    }

    /// Re-checks git after a Settings change.
    func reloadGit() {
        isReady = false
        installation = nil
        askpassServer?.stop()
        askpassServer = nil
        prepare()
    }

    func waitUntilReady() async {
        if isReady { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    private func startAskpass() -> AskpassServer? {
        if let askpassServer { return askpassServer }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("commit-\(getpid())", isDirectory: true)
        let server = try? AskpassServer(directory: directory) { prompt in
            await AppModel.shared.answer(prompt)
        }
        askpassServer = server
        return server
    }

    /// Shows the prompt on its repository's window and waits for the answer.
    private func answer(_ prompt: AskpassPrompt) async -> String? {
        let target = prompt.repositoryID.flatMap(UUID.init(uuidString:)).flatMap { repositories[$0]?.model }
            ?? repositories.values.compactMap(\.model).first
        guard let target else { return nil }
        NSApp.activate()
        return await target.ask(prompt)
    }

    func quit() {
        askpassServer?.stop()
    }

    // MARK: Windows

    func register(_ model: RepoModel) {
        repositories[model.id] = WeakRepo(model: model)
    }

    func unregister(_ model: RepoModel) {
        repositories.removeValue(forKey: model.id)
    }

    var openRepositoryCount: Int { repositories.values.filter { $0.model != nil }.count }

    /// Opens a repository window (or brings the existing one forward).
    func open(_ url: URL) {
        guard let openWindowAction else {
            pendingOpens.append(url)
            return
        }
        // Open the top level, so a subfolder and the root share one window (SwiftUI brings
        // the existing window forward when the value matches).
        Task {
            await waitUntilReady()
            var target = url.standardizedFileURL
            if let runner, let location = try? await Repository.locate(url, runner: runner) {
                target = location.root.standardizedFileURL
            }
            openWindowAction(id: "repository", value: target)
            dismissWindowAction?(id: "welcome")
        }
    }

    /// Windows call this once they can open others.
    func windowsAreAvailable(open: OpenWindowAction, dismiss: DismissWindowAction) {
        openWindowAction = open
        dismissWindowAction = dismiss
        let pending = pendingOpens + (Diagnostics.openAtLaunch.isEmpty || didOpenLaunchRepos ? [] : Diagnostics.openAtLaunch)
        didOpenLaunchRepos = true
        pendingOpens = []
        for url in pending { self.open(url) }
    }
    @ObservationIgnored private var didOpenLaunchRepos = false

    func showWelcome() {
        openWindowAction?(id: "welcome")
    }

    /// The Open panel (⌘O).
    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder with a Git repository."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in AppModel.shared.open(url) }
        }
    }

    // MARK: Recents

    func noteOpened(_ root: URL) {
        recents.add(root.path)
        UserDefaults.standard.set(recents.paths, forKey: Preference.recents)
        NSDocumentController.shared.noteNewRecentDocumentURL(root)
    }

    func forgetRecent(_ path: String) {
        recents.remove(path)
        UserDefaults.standard.set(recents.paths, forKey: Preference.recents)
    }

    func clearRecents() {
        recents.clear()
        UserDefaults.standard.set(recents.paths, forKey: Preference.recents)
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    // MARK: Install

    func installCommandLineTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
    }
}
