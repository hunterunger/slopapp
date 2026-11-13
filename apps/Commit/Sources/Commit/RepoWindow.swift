import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// One repository window: sidebar, content column, detail.
struct RepoWindow: View {
    let app: AppModel
    @State private var model: RepoModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.controlActiveState) private var activeState

    init(url: URL, app: AppModel) {
        self.app = app
        _model = State(initialValue: RepoModel(url: url, app: app))
    }

    var body: some View {
        Group {
            if let problem = model.openProblem {
                OpenProblemView(problem: problem, model: model)
            } else if app.isReady, model.repository == nil, !model.isOpening {
                GitMissingView(app: app)
            } else if model.repository == nil || !model.hasLoadedStatus {
                ProgressView("Opening \(model.url.lastPathComponent)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RepoSplitView(model: model)
            }
        }
        .navigationTitle(model.title)
        .focusedSceneValue(\.repoModel, model)
        .task { await model.open() }
        .onAppear {
            app.windowsAreAvailable(open: openWindow, dismiss: dismissWindow)
            model.undoManager = undoManager
        }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        .onChange(of: activeState) { _, state in if state == .key { model.windowActivated() } }
        .background(WindowCloseObserver(onWindow: { model.window = $0 }) { model.close() })
        .frame(minWidth: 820, minHeight: 480)
    }

    private var branchSubtitle: String {
        let branch = model.status.branch
        if branch.isUnborn { return "\(branch.branch ?? "main") · no commits yet" }
        guard let name = branch.branch else { return "Detached at \(branch.head?.short ?? "?")" }
        return name
    }
}

/// A window restored without a repository (or opened with File › New Window).
struct RepoPlaceholder: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label("No Repository", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Open a folder with a Git repository.")
        } actions: {
            Button("Open…") {
                app.chooseRepository()
                dismiss()
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear { app.windowsAreAvailable(open: openWindow, dismiss: dismissWindow) }
    }
}

struct OpenProblemView: View {
    let problem: OpenProblem
    let model: RepoModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(problem.message)
        } actions: {
            HStack {
                if case .notARepository(let url) = problem {
                    Button("Create Repository") {
                        Task {
                            guard let runner = model.app.runner else { return }
                            try? await Repository.initialize(url, runner: runner)
                            model.app.open(url)
                            dismiss()
                        }
                    }
                }
                Button("Choose Another Folder…") {
                    model.app.chooseRepository()
                    dismiss()
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    private var title: String {
        switch problem {
        case .notARepository: "Not a Git Repository"
        case .bare: "Bare Repository"
        case .insideGitDirectory: "Inside a .git Folder"
        case .missing: "Repository Not Found"
        case .git: "Couldn't Open the Repository"
        }
    }
}

struct GitMissingView: View {
    let app: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("Git Isn't Available", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(GitMissingView.message(app.installation))
        } actions: {
            if case .missing = app.installation {
                Button("Install Command Line Tools…") { app.installCommandLineTools() }
            }
            SettingsLink { Text("Open Settings…") }
        }
    }

    static func message(_ installation: GitInstallation?) -> String {
        switch installation {
        case .tooOld(let path, let version):
            "The Git at \(path) is version \(version). Commit needs \(GitVersion.minimum) or later. Install a newer Git, or choose one in Settings."
        case .badOverride(let path):
            "The Git chosen in Settings (\(path)) doesn't run. Choose another one, or switch back to Automatic."
        default:
            "Commit uses the Git that comes with Apple's command line tools. Install them, then open your repository again."
        }
    }
}

/// The three columns, toolbar, sheets and alerts.
struct RepoSplitView: View {
    @Bindable var model: RepoModel
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 340)
        } content: {
            ContentColumn(model: model)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 640)
        } detail: {
            DetailColumn(model: model)
        }
        .searchable(text: $model.searchText, isPresented: $model.isSearchPresented, placement: .toolbar, prompt: searchPrompt)
        .toolbar { RepoToolbar(model: model) }
        .sheet(item: $model.sheet) { sheet in
            SheetContent(sheet: sheet, model: model)
        }
        .alert(model.confirmation?.title ?? "", isPresented: confirmationShown, presenting: model.confirmation) { c in
            Button(c.confirmTitle, role: c.isDestructive ? .destructive : nil) { c.action() }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: { c in
            Text(c.message)
        }
        .background {
            // The prompt sheet sits on its own view so it can stack with other sheets.
            Color.clear.sheet(item: promptBinding) { pending in
                AskpassSheet(pending: pending) { model.answerPrompt($0) }
            }
        }
    }

    private var searchPrompt: String {
        switch model.sidebarSelection {
        case .history, .ref: "Filter commits"
        case .stashes: "Filter stashes"
        default: "Filter files"
        }
    }

    /// If the sheet goes away any other way, git gets "cancelled" instead of waiting forever.
    private var promptBinding: Binding<PendingPrompt?> {
        Binding(get: { model.prompt }, set: { if $0 == nil, model.prompt != nil { model.answerPrompt(nil) } })
    }

    private var confirmationShown: Binding<Bool> {
        Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } })
    }
}

/// Toolbar: branch switcher in the middle, activity, and the sync buttons.
struct RepoToolbar: ToolbarContent {
    @Bindable var model: RepoModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BranchButton(model: model)
        }
        if model.activity != nil {
            ToolbarItem(placement: .principal) {
                ActivityView(model: model)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.fetch() } label: { Label("Fetch", systemImage: "arrow.down.circle") }
                .help("Fetch from every remote (⌥⌘F)")
                .disabled(!model.canSync)
            Button { model.pull() } label: { Label("Pull", systemImage: "arrow.down.to.line") }
                .help(model.status.branch.behind > 0 ? "Pull \(model.status.branch.behind) commits (⌥⌘P)" : "Pull (⌥⌘P)")
                .disabled(!model.canPull)
            Button { model.push() } label: { Label("Push", systemImage: "arrow.up.to.line") }
                .help(model.status.branch.upstream == nil ? "Push and track this branch (⌥⌘U)" : "Push (⌥⌘U)")
                .disabled(!model.canPush)
            Button { model.showStashSheet() } label: { Label("Stash", systemImage: "tray.and.arrow.down") }
                .help("Stash changes (⌥⌘S)")
                .disabled(model.status.isClean)
        }
    }
}

/// Current branch with ahead/behind; opens the branch switcher.
struct BranchButton: View {
    @Bindable var model: RepoModel

    var body: some View {
        Button {
            model.showBranchSwitcher.toggle()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: model.status.branch.isDetached ? "exclamationmark.triangle" : "arrow.triangle.branch")
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.status.branch.ahead > 0 {
                    Text("↑\(model.status.branch.ahead)").monospacedDigit()
                }
                if model.status.branch.behind > 0 {
                    Text("↓\(model.status.branch.behind)").monospacedDigit()
                }
            }
            .frame(maxWidth: 260)
        }
        .help("Switch branch (⇧⌘B)")
        .accessibilityLabel(accessibilityText)
        .popover(isPresented: $model.showBranchSwitcher, arrowEdge: .bottom) {
            BranchSwitcher(model: model)
        }
    }

    private var name: String {
        let b = model.status.branch
        if let branch = b.branch { return branch }
        return "Detached at \(b.head?.short ?? "?")"
    }

    private var accessibilityText: String {
        var parts = ["Branch \(name)"]
        if model.status.branch.ahead > 0 { parts.append("\(model.status.branch.ahead) to push") }
        if model.status.branch.behind > 0 { parts.append("\(model.status.branch.behind) to pull") }
        return parts.joined(separator: ", ")
    }
}

/// What's running, with progress and Cancel. Empty when idle (no layout jump: fixed width).
struct ActivityView: View {
    let model: RepoModel

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let activity = model.activity {
                if let fraction = activity.progress?.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(activity.progress.map { "\(activity.title): \($0.phase)" } ?? "\(activity.title)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if activity.isCancellable {
                    Button {
                        model.cancelActivity()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel")
                    .accessibilityLabel("Cancel \(activity.title)")
                }
            }
        }
        .frame(minWidth: 0, idealWidth: 220, maxWidth: 280)
        .animation(.easeOut(duration: 0.15), value: model.activity)
    }
}

/// Banners above the content: problems, operations in progress, detached HEAD.
struct BannerStack: View {
    @Bindable var model: RepoModel

    var body: some View {
        VStack(spacing: 0) {
            if let problem = model.problem {
                ProblemBanner(problem: problem, model: model)
                Hairline()
            }
            if let op = model.inProgress {
                Banner(symbol: "arrow.triangle.merge", tint: .orange,
                       title: "\(op.noun) in progress",
                       message: model.status.conflicted.isEmpty
                           ? "No conflicts left. Continue to finish it."
                           : model.status.conflicted.count == 1
                               ? "1 conflicted file. Choose what to keep in each conflict, then mark it resolved."
                               : "\(model.status.conflicted.count) conflicted files. Choose what to keep in each conflict, then mark them resolved.") {
                    Button("Abort…") { model.confirmAbort() }
                    Button("Continue") { model.continueOperation() }
                        .disabled(!model.status.conflicted.isEmpty)
                }
                Hairline()
            } else if model.status.branch.isDetached && !model.status.branch.isUnborn {
                Banner(symbol: "exclamationmark.triangle", tint: .orange, title: "Not on a branch",
                       message: "New commits here won't belong to any branch.") {
                    Button("New Branch Here…") { model.showNewBranch(from: nil) }
                }
                Hairline()
            }
        }
    }
}

struct ProblemBanner: View {
    let problem: Problem
    let model: RepoModel

    var body: some View {
        Banner(symbol: "exclamationmark.triangle.fill", tint: .orange, title: problem.explanation.title,
               message: problem.explanation.message) {
            if problem.explanation.action == .pull {
                if model.canForcePush && problem.explanation.cause == .rejectedPush {
                    Button("Force Push…") { model.problem = nil; model.confirmForcePush() }
                        .help("Only if you meant to rewrite the remote branch (after a rebase or amend)")
                }
                Button("Pull") { model.problem = nil; model.pull() }
            }
            if problem.explanation.action == .openPrivacySettings {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if problem.explanation.title == "Pushed", let url = URL(string: problem.explanation.output) {
                Button("Open Pull Request Page") { NSWorkspace.shared.open(url); model.problem = nil }
            } else if !problem.explanation.output.isEmpty {
                Button("Show Details") {
                    model.sheet = .output(title: problem.explanation.title, output: detailText)
                }
            }
        } dismiss: {
            model.problem = nil
        }
    }

    private var detailText: String {
        problem.command.isEmpty ? problem.explanation.output : "$ \(problem.command)\n\(problem.explanation.output)"
    }
}

/// A slim bar: symbol, title and message, actions, optional close button.
struct Banner<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: Actions
    var dismiss: (() -> Void)?

    init(symbol: String, tint: Color, title: String, message: String, @ViewBuilder actions: () -> Actions, dismiss: (() -> Void)? = nil) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
        self.dismiss = dismiss
    }

    var body: some View {
        // Stacked, not side by side: the content column can be narrow, and a message squeezed
        // next to buttons wraps word by word and inflates the whole window's height.
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(title).font(.headline)
                Spacer(minLength: Spacing.s)
                if let dismiss {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                    .keyboardShortcut(.cancelAction)
                }
            }
            // A line limit, not fixedSize: measured at a narrow width, fixed-size wrapping
            // text reports a huge minimum height and stretches the window's content.
            Text(message)
                .font(.callout)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(message)
            HStack(spacing: Spacing.s) {
                Spacer(minLength: 0)
                actions
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}

/// Sheets by kind.
struct SheetContent: View {
    let sheet: RepoSheet
    let model: RepoModel

    var body: some View {
        switch sheet {
        case .newBranch(let from, let label):
            NewBranchSheet(model: model, from: from, fromLabel: label)
        case .stash:
            StashSheet(model: model)
        case .output(let title, let output):
            OutputSheet(title: title, output: output)
        case .divergentPull:
            DivergentPullSheet(model: model)
        case .identity:
            IdentitySheet(model: model)
        case .integrate(let kind, let preselected):
            IntegrateSheet(model: model, kind: kind, preselected: preselected)
        case .interactiveRebase(let plan, let pushed):
            InteractiveRebaseSheet(model: model, plan: plan, pushedCount: pushed)
        case .remotes:
            RemotesSheet(model: model)
        case .newTag(let commit, let label):
            NewTagSheet(model: model, commit: commit, label: label)
        }
    }
}

/// Calls `onClose` when the hosting window really closes (not when a tab is merely hidden,
/// which `onDisappear` can't tell apart).
struct WindowCloseObserver: NSViewRepresentable {
    var onWindow: (@MainActor (NSWindow) -> Void)? = nil
    let onClose: @MainActor () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onClose = onClose
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onClose = onClose
    }

    final class ObserverView: NSView {
        var onClose: (@MainActor () -> Void)?
        var onWindow: (@MainActor (NSWindow) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
            guard let window else { return }
            onWindow?(window)
            token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onClose?()
                    self?.onClose = nil
                }
            }
        }

        override var acceptsFirstResponder: Bool { false }
    }
}
