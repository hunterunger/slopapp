import SlopKit
import SwiftUI
import TidyCore

enum MaintenancePane: String, CaseIterable, Identifiable, Hashable {
    case tasks, loginItems, backgroundItems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Maintenance Tasks"
        case .loginItems: "Login Items"
        case .backgroundItems: "Background Items"
        }
    }

    var systemImage: String {
        switch self {
        case .tasks: "checklist"
        case .loginItems: "power"
        case .backgroundItems: "gearshape.2"
        }
    }

    var detail: String {
        switch self {
        case .tasks: "Housekeeping macOS can do when something misbehaves. Each one says when it helps."
        case .loginItems: "Helpers your apps add to open when you log in. macOS keeps their on/off switches in System Settings."
        case .backgroundItems: "Launch agents and daemons start programs in the background. Ones whose program is gone do nothing and can go."
        }
    }
}

enum TaskOutcome: Equatable {
    case done(Date)
    case failed(String)
    case cancelled
}

@MainActor
@Observable
final class MaintenanceState {
    var pane: MaintenancePane = .tasks
    var phase: ScanPhase = .idle
    var launchItems: [LaunchItem] = []
    var loginItems: [AppLoginItem] = []
    /// Labels launchd has loaded, with their process ids.
    var loaded: [String: Int?] = [:]
    var checked: Set<String> = []
    var selection: Set<String> = []
    var checkedTasks: Set<MaintenanceTask> = []
    var runningTask: MaintenanceTask?
    var outcomes: [MaintenanceTask: TaskOutcome] = [:]
    var lastRun: [String: Date] = Keys.defaults.dictionary(forKey: "maintenanceLastRun") as? [String: Date] ?? [:] {
        didSet { Keys.defaults.set(lastRun, forKey: "maintenanceLastRun") }
    }
    var doneLines: [DoneLine] = []
}

extension AppModel {
    func startMaintenanceScan() {
        setStage(.scanning, for: .maintenance)
        Task {
            await refreshBackgroundItems()
            setStage(.results, for: .maintenance)
        }
    }

    func scanBackgroundItems() {
        guard maintenance.phase != .idle else { return }
        Task { await refreshBackgroundItems() }
    }

    func refreshBackgroundItems() async {
        maintenance.phase = .scanning("Checking background items…")
        // Owners are matched against installed apps, so wait for the list (it's quick).
        for _ in 0..<50 where !appsLoaded { try? await Task.sleep(for: .milliseconds(100)) }
        let scanner = BackgroundItemScanner(environment: environment, apps: apps)
        let reader: LaunchStatusReader = environment.isTestMode
            ? FixedLaunchStatusReader(Dictionary(uniqueKeysWithValues: Self.simulatedLoadedLabels.map { ($0, Optional(1)) }))
            : LaunchctlStatusReader()
        let (items, logins, loaded) = await Task.detached(priority: .userInitiated) {
            (scanner.launchItems(), scanner.appLoginItems(), reader.loaded())
        }.value
        let previous = Set(maintenance.launchItems.map(\.id))
        let ids = Set(items.map(\.id))
        maintenance.launchItems = items
        maintenance.loginItems = logins
        maintenance.loaded = loaded
        // Broken user agents (their program is gone) start checked, like other junk.
        let recommended = Set(items.filter { $0.isBroken && !$0.scope.needsAdmin }.map(\.id))
        maintenance.checked = maintenance.checked.intersection(ids).union(recommended.subtracting(previous))
        maintenance.selection.formIntersection(ids)
        maintenance.phase = .done
    }

    /// Test mode: `TIDY_LOADED_LABELS=label,...` pretends those are loaded.
    static var simulatedLoadedLabels: [String] {
        (ProcessInfo.processInfo.environment["TIDY_LOADED_LABELS"] ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var visibleLaunchItems: [LaunchItem] {
        guard !query.isEmpty, section == .maintenance else { return maintenance.launchItems }
        return maintenance.launchItems.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query)
                || ($0.program?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var actionableLaunchItems: [LaunchItem] {
        let visible = visibleLaunchItems.filter { !$0.scope.needsAdmin }
        let ids = Set(ReviewRules.actionable(checked: maintenance.checked, visible: visible.map(\.id)))
        return visible.filter { ids.contains($0.id) }
    }

    func reviewMaintenance(_ pane: MaintenancePane) {
        maintenance.pane = pane
        query = ""
        setStage(.review, for: .maintenance)
    }

    var taskRunner: TaskRunner {
        if let log = environment.maintenanceLog {
            let failing = Set((ProcessInfo.processInfo.environment["TIDY_TASK_FAIL"] ?? "").split(separator: ",").map(String.init))
            return RecordingTaskRunner(log: log, failing: failing)
        }
        return SystemTaskRunner()
    }

    /// Runs the checked tasks one by one, then shows what happened.
    func runMaintenanceTasks() {
        let tasks = MaintenanceTask.allCases.filter(maintenance.checkedTasks.contains)
        guard !tasks.isEmpty, maintenance.runningTask == nil else { return }
        setStage(.running, for: .maintenance)
        let runner = taskRunner
        Task {
            var lines: [DoneLine] = []
            for task in tasks {
                maintenance.runningTask = task
                let outcome: TaskOutcome = await Task.detached(priority: .userInitiated) {
                    do {
                        try runner.run(task)
                        return .done(Date())
                    } catch TaskError.cancelled {
                        return .cancelled
                    } catch {
                        return .failed((error as? TaskError)?.description ?? error.localizedDescription)
                    }
                }.value
                maintenance.outcomes[task] = outcome
                switch outcome {
                case .done(let date):
                    maintenance.lastRun[task.rawValue] = date
                    lines.append(DoneLine(systemImage: "checkmark.circle.fill", title: task.title, subtitle: "Done."))
                case .cancelled:
                    lines.append(DoneLine(systemImage: "xmark.circle.fill", title: task.title,
                                          subtitle: "Didn't run: the password prompt was cancelled.", isFailure: true))
                case .failed(let message):
                    lines.append(DoneLine(systemImage: "exclamationmark.triangle.fill", title: task.title,
                                          subtitle: "Didn't finish: \(message)", isFailure: true))
                }
            }
            maintenance.runningTask = nil
            maintenance.checkedTasks = []
            maintenance.doneLines = lines
            setStage(.done, for: .maintenance)
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: Views

struct MaintenanceModuleView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.stage(.maintenance) {
        case .intro:
            ModuleIntro(systemImage: SidebarSection.maintenance.systemImage, title: "Maintenance",
                        subtitle: "Run housekeeping tasks, and see what your apps start at login and in the background.",
                        features: MaintenancePane.allCases.map { ModuleFeature(systemImage: $0.systemImage, title: $0.title) },
                        buttonHelp: "Check background items (⌘R)", action: model.startMaintenanceScan) { EmptyView() }
        case .scanning:
            ModuleScanning(systemImage: SidebarSection.maintenance.systemImage, title: "Checking background items…",
                           detail: "Reading launch agents, launch daemons and login items")
        case .results:
            ModuleResults(headline: "Here's what runs on your Mac, and what you can do.",
                          reviewAllTitle: "Review All", onReviewAll: { model.reviewMaintenance(.tasks) },
                          tiles: tiles) { EmptyView() }
        case .review:
            MaintenanceReview(model: model)
        case .running:
            ModuleScanning(systemImage: SidebarSection.maintenance.systemImage, title: "Running tasks…",
                           detail: model.maintenance.runningTask.map { "\($0.title)\($0.needsAdmin ? " (macOS asks for your password)" : "")" } ?? "")
        case .done:
            ModuleDone(systemImage: "checkmark", title: "Tasks Finished", lines: model.maintenance.doneLines) {
                Spacer()
                Button("Manage More Items") { model.reviewMaintenance(model.maintenance.pane) }
                Button("Done") { model.setStage(.results, for: .maintenance) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var tiles: [TileModel] {
        let state = model.maintenance
        let broken = state.launchItems.filter(\.isBroken).count
        let items = state.launchItems.count
        return [
            TileModel(id: "background", systemImage: MaintenancePane.backgroundItems.systemImage, label: "Background Items",
                      value: items == 1 ? "1 background item" : "\(items) background items",
                      caption: broken == 0 ? "to review" : "\(broken) with a missing program",
                      detail: MaintenancePane.backgroundItems.detail,
                      actions: [TileAction(title: "Review", isProminent: broken > 0) { model.reviewMaintenance(.backgroundItems) }],
                      isQuiet: items == 0),
            TileModel(id: "tasks", systemImage: MaintenancePane.tasks.systemImage, label: "Maintenance Tasks",
                      value: "\(MaintenanceTask.allCases.count) tasks", caption: "to run when needed",
                      actions: [TileAction(title: "Review") { model.reviewMaintenance(.tasks) }]),
            TileModel(id: "login", systemImage: MaintenancePane.loginItems.systemImage, label: "Login Items",
                      value: state.loginItems.count == 1 ? "1 login item" : "\(state.loginItems.count) login items",
                      caption: "from your apps",
                      actions: [TileAction(title: "Review") { model.reviewMaintenance(.loginItems) }],
                      isQuiet: state.loginItems.isEmpty),
        ]
    }
}

struct MaintenanceReview: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { model.maintenance.pane }, set: { if let pane = $0 { model.maintenance.pane = pane; model.query = "" } })) {
                ForEach(MaintenancePane.allCases) { pane in
                    HStack {
                        Label(pane.title, systemImage: pane.systemImage)
                        Spacer()
                        Text(count(pane)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Categories")
            .reviewCategoryColumn()
            Hairline(axis: .vertical)
            VStack(spacing: 0) {
                PaneHeader(title: model.maintenance.pane.title, detail: model.maintenance.pane.detail)
                Hairline()
                switch model.maintenance.pane {
                case .tasks: TasksPane(model: model)
                case .loginItems: LoginItemsPane(model: model)
                case .backgroundItems: BackgroundItemsPane(model: model)
                }
            }
        }
    }

    private func count(_ pane: MaintenancePane) -> String {
        switch pane {
        case .tasks: "\(MaintenanceTask.allCases.count)"
        case .loginItems: "\(model.maintenance.loginItems.count)"
        case .backgroundItems: "\(model.maintenance.launchItems.count)"
        }
    }
}

struct TasksPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(MaintenanceTask.allCases) { task in
                    TaskRow(model: model, task: task)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            BottomBar {
                let count = model.maintenance.checkedTasks.count
                Text(count == 0 ? "No tasks selected" : count == 1 ? "1 task selected" : "\(count) tasks selected")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Run") { model.runMaintenanceTasks() }
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0 || model.maintenance.runningTask != nil)
                    .help("Run the selected tasks. Ones marked with a key ask for your password.")
            }
        }
    }
}

struct TaskRow: View {
    var model: AppModel
    @Environment(\.controlActiveState) private var activeState
    let task: MaintenanceTask

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Toggle(isOn: Binding(get: { model.maintenance.checkedTasks.contains(task) },
                                 set: { if $0 { model.maintenance.checkedTasks.insert(task) } else { model.maintenance.checkedTasks.remove(task) } })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(task.title)
            Image(systemName: task.systemImage)
                .font(.title2)
                .foregroundStyle(Color.windowAccent(activeState))
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.headline)
                Text(task.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: Spacing.s)
            if task.needsAdmin {
                Label("Needs your password", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("macOS asks for an administrator's password before running it.")
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.maintenance.checkedTasks.contains(task) { model.maintenance.checkedTasks.remove(task) } else { model.maintenance.checkedTasks.insert(task) }
        }
        .accessibilityElement(children: .combine)
    }

    private var status: String? {
        switch model.maintenance.outcomes[task] {
        case .failed(let message): return "Last time it didn't finish: \(message)"
        case .cancelled: return "Last time the password prompt was cancelled."
        default:
            return model.maintenance.lastRun[task.rawValue].map { "Last run \($0.formatted(.relative(presentation: .named)))" }
        }
    }
}

struct LoginItemsPane: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Notice(systemImage: "gearshape", text: "Turn these on or off in System Settings › General › Login Items, or in the app's own settings.") {
                Button("Open Login Items Settings") { model.openLoginItemsSettings() }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            Hairline()
            if model.maintenance.loginItems.isEmpty {
                ContentUnavailableView {
                    Label("No Login Items", systemImage: "power")
                } description: {
                    Text("None of your apps carry a helper that opens at login.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.maintenance.loginItems) { item in
                        HStack(spacing: Spacing.s) {
                            Image(nsImage: Icons.icon(for: item.appURL)).resizable().frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                Text("Inside \(item.appName)\(item.bundleID.map { " · \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Show in Finder") { Finder.reveal([item.url]) }
                                .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Show in Finder") { Finder.reveal([item.url]) }
                            Button("Show \(item.appName) in Finder") { Finder.reveal([item.appURL]) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct BackgroundItemsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            let admin = model.maintenance.launchItems.filter(\.scope.needsAdmin)
            if !admin.isEmpty {
                Notice(systemImage: "person.badge.key",
                       text: "Items for all users need an administrator. Show them in Finder and move them to the Trash there.") {
                    Button("Show in Finder") { Finder.reveal(admin.map(\.url)) }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                Hairline()
            }
            if model.visibleLaunchItems.isEmpty {
                if !model.query.isEmpty {
                    ContentUnavailableView.search(text: model.query).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No Background Items", systemImage: "gearshape.2")
                    } description: {
                        Text("No app has added launch agents or daemons.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ReviewList(sections: sections, checked: Binding(get: { model.maintenance.checked }, set: { model.maintenance.checked = $0 }),
                           selection: Binding(get: { model.maintenance.selection }, set: { model.maintenance.selection = $0 }),
                           sizes: model.sizes, home: model.environment.home)
            }
            ActionBar(model: model, section: .maintenance, checkedURLs: model.actionableLaunchItems.map(\.url), showsBytes: false)
        }
    }

    private var sections: [ReviewSection] {
        let home = model.environment.home
        let grouped = Dictionary(grouping: model.visibleLaunchItems, by: \.scope)
        return LaunchScope.allCases.compactMap { scope in
            guard let items = grouped[scope], !items.isEmpty else { return nil }
            return ReviewSection(id: scope.rawValue, title: scope.title, systemImage: scope == .systemDaemon ? "gearshape.2" : "gearshape",
                                 detail: scope == .userAgent ? "Run while you're logged in. Moving one to the Trash stops it after you log out."
                                    : "Installed for every user.",
                                 items: items.map { item in
                                     ReviewItem(url: item.url, title: item.displayName,
                                                subtitle: "\(item.label) · \(PathDisplay.parent(item.url, home: home))",
                                                note: note(item), lockReason: scope.needsAdmin ? "Needs an administrator" : nil,
                                                help: item.program.map { "Runs \($0)" }, iconURL: item.appURL, showsSize: false)
                                 })
        }
    }

    private func note(_ item: LaunchItem) -> String? {
        if item.isBroken { return "Program is missing" }
        if model.maintenance.loaded[item.label] != nil { return "Running" }
        if item.isDisabled { return "Turned off" }
        if item.keepsAlive { return "Always running" }
        if item.runsAtLoad { return "Starts at login" }
        return nil
    }
}
