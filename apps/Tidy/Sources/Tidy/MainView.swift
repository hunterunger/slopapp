import QuickLook
import SlopKit
import SwiftUI
import TidyCore

/// The library window: sidebar of sections, each with its own list and review flow.
struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } detail: {
            Group {
                switch model.section {
                case .uninstall: UninstallView(model: model)
                case .leftovers: LeftoversView(model: model)
                case .junk: JunkView(model: model)
                case .large: LargeFilesView(model: model)
                }
            }
            .frame(minWidth: 560, minHeight: 380)
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: model.section.searchPrompt)
        .navigationTitle("Tidy")
        .navigationSubtitle(model.environment.testModeSummary ?? "")
        .onChange(of: model.section) {
            model.query = ""
            model.previewURL = nil
        }
        .quickLookPreview($model.previewURL)
        .sheet(item: $model.quitRequest) { app in
            QuitSheet(model: model, app: app)
        }
        .sheet(isPresented: $model.showingAccessSheet) {
            AccessSheet(model: model)
        }
        .sheet(isPresented: $model.showingHistory) {
            HistorySheet(model: model)
        }
        .alert(model.pendingUninstall?.title ?? "", isPresented: Binding(
            get: { model.pendingUninstall != nil }, set: { if !$0 { model.pendingUninstall = nil } }
        ), presenting: model.pendingUninstall) { _ in
            Button("Move to Trash") {
                model.pendingUninstall = nil
                model.uninstallChecked(.reviewButton)
            }
            Button("Cancel", role: .cancel) { model.pendingUninstall = nil }
        } message: { plan in
            Text(plan.message)
        }
        .alert(model.failureReport?.title ?? "", isPresented: Binding(
            get: { model.failureReport != nil }, set: { if !$0 { model.failureReport = nil } }
        ), presenting: model.failureReport) { report in
            Button("OK") {}
                .keyboardShortcut(.defaultAction)
            if report.offersReveal, report.failures.contains(where: { FileManager.default.fileExists(atPath: $0.url.path) }) {
                Button("Show in Finder") { Finder.reveal(report.failures.map(\.url)) }
            }
            if report.offersHistory {
                Button("Show What's Left…") { model.showingHistory = true }
            }
        } message: { report in
            Text(report.failures.prefix(6).map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "\n")
                 + (report.failures.count > 6 ? "\n…and \(report.failures.count - 6) more." : ""))
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.section)
    }
}

struct Sidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.section }, set: { if let value = $0 { model.section = value } })) {
            Section("Apps") {
                row(.uninstall, badge: model.appsLoaded ? model.apps.count : nil)
                row(.leftovers, badge: model.orphanPhase == .done ? model.orphanGroups.count : model.cachedOrphanCount)
            }
            Section("Files") {
                row(.junk, badge: nil)
                row(.large, badge: nil)
            }
            if !model.hasFullDiskAccess {
                Section {
                    Button {
                        model.showingAccessSheet = true
                    } label: {
                        Label("Full Disk Access…", systemImage: "lock.shield")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Some app data can only be measured and moved with Full Disk Access.")
                }
            }
        }
    }

    private func row(_ section: SidebarSection, badge: Int?) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .badge(badge ?? 0)
            .tag(section)
    }
}

/// Full Disk Access, explained with SlopKit's PermissionGate (live re-check).
struct AccessSheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if model.environment.isTestMode && model.hasFullDiskAccess {
                granted
            } else {
                PermissionGate(.fullDiskAccess, reason: """
                macOS protects some app data, like app containers. To measure and move it, \
                and to look for large files in Desktop, Documents and Downloads without \
                macOS asking about each folder, Tidy needs Full Disk Access. Tidy only reads \
                what you ask it to scan and never sends anything anywhere.
                """) {
                    granted
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    model.refreshAccess()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.l)
        }
        .frame(width: 440)
        .onExitCommand {
            model.refreshAccess()
            dismiss()
        }
    }

    private var granted: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Full Disk Access Is On").font(.title3.bold())
            Text("Tidy can now measure and move protected app data.")
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xxl)
        .onAppear { model.refreshAccess() }
    }
}

/// A running app has to quit before it's moved. Force Quit appears if it hasn't after 5 s.
struct QuitSheet: View {
    var model: AppModel
    let app: InstalledApp
    @Environment(\.dismiss) private var dismiss
    @State private var isQuitting = false
    @State private var offerForceQuit = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(nsImage: Icons.icon(for: app.url))
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Quit \(app.name)?").font(.headline)
                    Text("\(app.name) is open. It needs to quit before Tidy moves it and its files to the Trash. If it has unsaved changes, it may ask you about them.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if offerForceQuit {
                        Text("\(app.name) hasn't quit yet. Force Quit closes it right away; unsaved changes are lost.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                if isQuitting {
                    ProgressView().controlSize(.small).accessibilityLabel("Waiting for \(app.name) to quit")
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.quitRequest = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if offerForceQuit {
                    Button("Force Quit") { model.quitAndContinue(app, force: true) }
                }
                Button("Quit and Move to Trash") {
                    isQuitting = true
                    model.quitAndContinue(app, force: false)
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        if model.quitRequest != nil { offerForceQuit = true }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isQuitting && !offerForceQuit)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 440)
    }
}

/// Everything moved to the Trash this session, newest first, each with Put Back.
struct HistorySheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recently Moved to the Trash")
                .font(.headline)
                .padding(Spacing.l)
            Divider()
            if !model.historyFailures.isEmpty {
                Notice(systemImage: "exclamationmark.triangle",
                       text: "Some items couldn't be put back: " + model.historyFailures.prefix(4)
                        .map { "\($0.url.lastPathComponent) (\($0.message))" }.joined(separator: "; ")
                        + (model.historyFailures.count > 4 ? "; and \(model.historyFailures.count - 4) more." : ""))
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
                Divider()
            }
            List {
                ForEach(model.history.reversed()) { entry in
                    HistoryRow(model: model, entry: entry)
                }
            }
            .frame(minHeight: 200)
            Divider()
            HStack {
                Text("Put Back works while the items are still in the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.l)
        }
        .frame(width: 480, height: 360)
        .onExitCommand { dismiss() }
    }
}

/// One move in the history. A partly put back move lists what's still in the Trash, with
/// Show in Trash and, when the original place is taken, Keep Both.
struct HistoryRow: View {
    var model: AppModel
    let entry: ActionResult

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.partlyPutBack && !entry.wasPutBack ? "Partly put back" : entry.summary)
                    Text("\(entry.section.title) · \(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteFormat.string(entry.bytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.wasPutBack {
                    Text("Put back").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Put Back") { model.putBack(entry: entry.id) }
                }
            }
            if entry.partlyPutBack {
                ForEach(entry.moved, id: \.trashed) { item in
                    let taken = FileManager.default.fileExists(atPath: item.original.path)
                    HStack(spacing: Spacing.s) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.original.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(taken ? "Still in the Trash: something with this name is back in its place."
                                       : "Still in the Trash.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show in Trash") { Finder.reveal([item.trashed]) }
                        if taken {
                            Button("Keep Both") { model.putBack(entry: entry.id, keepBoth: true) }
                                .help("Put it back next to the new one as “\(item.original.deletingPathExtension().lastPathComponent) (restored)”")
                        }
                    }
                    .controlSize(.small)
                    .padding(.leading, Spacing.l)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
