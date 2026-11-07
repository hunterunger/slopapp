import SlopKit
import SwiftUI
import TidyCore

/// Files from apps that are no longer installed. Nothing starts checked.
struct LeftoversView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            switch model.orphanPhase {
            case .idle, .scanning:
                ProgressView("Looking for leftovers…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done, .stopped:
                if model.orphanGroups.isEmpty {
                    ContentUnavailableView {
                        Label("No Leftovers", systemImage: "checkmark.circle")
                    } description: {
                        Text("Every app file Tidy recognizes belongs to an app on this Mac.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SectionIntro(text: "Files left behind by apps that are no longer on this Mac. Check the ones you want to remove.")
                    if !model.hasFullDiskAccess && model.orphanGroups.contains(where: { $0.items.contains(where: \.needsFullDiskAccess) }) {
                        Notice(systemImage: "lock.shield", text: "Some items are protected by macOS. Allow Full Disk Access to measure and move them.") {
                            Button("Allow…") { model.showingAccessSheet = true }
                        }
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.s)
                    }
                    let adminItems = model.orphanGroups.flatMap(\.items).filter(\.needsAdmin)
                    if !adminItems.isEmpty {
                        Notice(systemImage: "person.badge.key",
                               text: "Items that need an administrator can't be moved by Tidy. Show them in Finder and move them to the Trash there.") {
                            Button("Show in Finder") { Finder.reveal(adminItems.map(\.url)) }
                        }
                        .padding(.horizontal, Spacing.l)
                        .padding(.bottom, Spacing.s)
                    }
                    Hairline()
                    let sections = self.sections
                    if sections.isEmpty {
                        ContentUnavailableView.search(text: model.query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ReviewList(sections: sections, checked: $model.orphanChecked, selection: $model.orphanSelection,
                                   sizes: model.sizes, home: model.environment.home)
                    }
                }
                ActionBar(model: model, section: .leftovers, checkedURLs: model.actionableOrphans.map(\.url))
            }
        }
        .onAppear { model.sectionAppeared(.leftovers) }
    }

    private var sections: [ReviewSection] {
        let home = model.environment.home
        return model.visibleOrphanGroups.map { group in
            let lastUsed = group.lastModified.map { " · last changed \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
            let inTrash = group.appName != nil ? " · app is in the Trash" : ""
            return ReviewSection(id: group.bundleID, title: group.displayName, systemImage: "questionmark.app.dashed",
                                 detail: group.bundleID + inTrash + lastUsed,
                                 items: group.items.map { item in
                                     ReviewItem(url: item.url, title: item.url.lastPathComponent,
                                                subtitle: PathDisplay.parent(item.url, home: home), note: item.kind.title,
                                                lockReason: item.needsAdmin ? "Needs an administrator"
                                                    : (item.needsFullDiskAccess && !model.hasFullDiskAccess ? "Needs Full Disk Access" : nil))
                                 })
        }
    }
}

struct SectionIntro: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
    }
}

/// Large & Old as a module page: intro with Scan, the scanning screen, then the table.
struct LargeModuleView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.stage(.large) == .intro {
            ModuleIntro(systemImage: SidebarSection.large.systemImage, title: "Large & Old Files",
                        subtitle: "Find big files you haven't opened in a while, sorted by size, kind and when you last used them.",
                        features: [ModuleFeature(systemImage: "chart.bar.xaxis", title: "By size"),
                                   ModuleFeature(systemImage: "clock", title: "By last used"),
                                   ModuleFeature(systemImage: "doc.on.doc", title: "By kind, including installers")],
                        buttonHelp: "Look for large files (⌘R)", action: model.startLargeScan) {
                FolderMenu(title: model.largeRoot == model.environment.home ? "Home Folder" : model.largeRoot.lastPathComponent,
                           home: { model.largeRoot = model.environment.home }, choose: model.chooseLargeFolder)
            }
        } else if case .scanning(let text) = model.largePhase {
            ModuleScanning(systemImage: SidebarSection.large.systemImage, title: "Looking for large files…",
                           detail: text, onStop: model.stopLarge)
        } else {
            LargeFilesView(model: model)
        }
    }
}

/// Big files in the home folder, filtered by size, age and kind. Nothing starts checked.
struct LargeFilesView: View {
    @Bindable var model: AppModel
    @State private var sortOrder = [KeyPathComparator(\LargeFile.size, order: .reverse)]
    /// Gives columns stable identifiers (and lets people hide or reorder them).
    @State private var columns = TableColumnCustomization<LargeFile>()

    static let thresholds: [(String, Int64)] = [("10 MB", 10_000_000), ("50 MB", 50_000_000), ("100 MB", 100_000_000),
                                                 ("500 MB", 500_000_000), ("1 GB", 1_000_000_000)]
    static let ages: [(String, TimeInterval?)] = [("Any Time", nil), ("1 Month", 30 * 86_400), ("6 Months", 182 * 86_400),
                                                   ("1 Year", 365 * 86_400), ("2 Years", 730 * 86_400)]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            let checked = model.actionableLarge
            ActionBar(model: model, section: .large, checkedURLs: checked.map(\.url),
                      knownBytes: checked.reduce(0) { $0 + $1.size })
        }
        .onAppear { model.sectionAppeared(.large) }
    }

    private var filterBar: some View {
        HStack(spacing: Spacing.m) {
            Picker("Larger than", selection: $model.largeFilter.minimumSize) {
                ForEach(Self.thresholds, id: \.1) { Text($0.0).tag($0.1) }
            }
            .fixedSize()
            Picker("Not opened in", selection: $model.largeFilter.olderThan) {
                ForEach(Self.ages, id: \.0) { Text($0.0).tag($0.1) }
            }
            .fixedSize()
            Picker("Kind", selection: $model.largeFilter.kind) {
                Text("All Kinds").tag(FileKind?.none)
                Divider()
                ForEach(FileKind.allCases) { Text($0.title).tag(FileKind?.some($0)) }
            }
            .fixedSize()
            Spacer()
            Menu {
                Button("Home Folder") { model.resetLargeRoot() }
                Button("Choose Folder…") { model.chooseLargeFolder() }
            } label: {
                Label(model.largeRoot == model.environment.home ? "Home Folder"
                      : PathDisplay.short(model.largeRoot, home: model.environment.home), systemImage: "folder")
            }
            .fixedSize()
            .help("Folder to look in")
        }
        .controlSize(.small)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    @ViewBuilder
    private var content: some View {
        if model.largeNeedsChoice {
            VStack(spacing: Spacing.m) {
                PermissionPrompt(permission: .fullDiskAccess, reason: """
                Desktop, Documents and Downloads are protected by macOS. With Full Disk Access, \
                Tidy can look through them without macOS asking about each folder.
                """)
                Button("Scan Without Those Folders") {
                    model.largeChoice = .withoutProtectedFolders
                    model.scanLarge()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch model.largePhase {
            case .idle, .scanning:
                if model.largeFiles.isEmpty || model.largePhase != .done {
                    VStack(spacing: Spacing.m) {
                        ProgressView()
                        Text(scanningText).foregroundStyle(.secondary).monospacedDigit()
                        Button("Stop") { model.stopLarge() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .stopped:
                ContentUnavailableView {
                    Label("Scan Stopped", systemImage: "stop.circle")
                } actions: {
                    Button("Scan Again") { model.scanLarge() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                let files = model.visibleLargeFiles.sorted(using: sortOrder)
                if files.isEmpty {
                    if !model.query.isEmpty {
                        ContentUnavailableView.search(text: model.query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView {
                            Label("No Files Match", systemImage: "doc.badge.clock")
                        } description: {
                            Text("Nothing in \(model.largeRoot == model.environment.home ? "your home folder" : PathDisplay.short(model.largeRoot, home: model.environment.home)) matches these filters. Try a smaller size or any age.")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        if model.largeSkippedProtected {
                            Notice(systemImage: "lock.shield", text: "Desktop, Documents and Downloads weren't searched.") {
                                Button("Allow Full Disk Access…") { model.showingAccessSheet = true }
                            }
                            .padding(.horizontal, Spacing.l)
                            .padding(.vertical, Spacing.s)
                            Hairline()
                        }
                        table(files)
                    }
                }
            }
        }
    }

    private var scanningText: String {
        if case .scanning(let text) = model.largePhase { return text }
        return "Looking for large files…"
    }

    private func table(_ files: [LargeFile]) -> some View {
        Table(files, selection: $model.largeSelection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("Name", value: \.name) { file in
                HStack(spacing: Spacing.s) {
                    Toggle(isOn: Binding(
                        get: { model.largeChecked.contains(file.id) },
                        set: { if $0 { model.largeChecked.insert(file.id) } else { model.largeChecked.remove(file.id) } }
                    )) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel(file.name)
                    Image(nsImage: Icons.icon(for: file.url)).resizable().frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                }
                .help(file.url.path)
            }
            .width(min: 180, ideal: 280)
            .customizationID("name")
            TableColumn("Size", value: \.size) { file in
                Text(ByteFormat.string(file.size)).monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            .customizationID("size")
            // Sizes line up on the right, header included, as in Finder.
            .alignment(.trailing)
            TableColumn("Last Used", value: \.lastUsed) { file in
                Text(file.lastUsed.formatted(date: .abbreviated, time: .omitted)).monospacedDigit()
                    .help(file.lastOpened == nil ? "Last modified" : "Last opened")
            }
            .width(min: 90, ideal: 110)
            .customizationID("lastUsed")
            TableColumn("Kind", value: \.kind.title) { file in
                Text(file.kind.title).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            .customizationID("kind")
            TableColumn("Where", value: \.url.path) { file in
                Text(PathDisplay.parent(file.url, home: model.environment.home))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 100, ideal: 200)
            .customizationID("where")
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Show in Finder") { Finder.reveal(ids.map { URL(fileURLWithPath: $0) }) }
            Button("Quick Look") { model.previewURL = ids.sorted().first.map { URL(fileURLWithPath: $0) } }
            Divider()
            Button("Check") { model.largeChecked.formUnion(ids) }
            Button("Uncheck") { model.largeChecked.subtract(ids) }
        } primaryAction: { ids in
            NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) })
        }
        .onKeyPress(.space) {
            let ids = model.largeSelection
            guard !ids.isEmpty else { return .ignored }
            if ids.isSubset(of: model.largeChecked) { model.largeChecked.subtract(ids) } else { model.largeChecked.formUnion(ids) }
            return .handled
        }
    }
}
