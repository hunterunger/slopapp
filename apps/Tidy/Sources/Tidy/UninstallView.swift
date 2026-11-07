import SlopKit
import SwiftUI
import TidyCore
import UniformTypeIdentifiers

/// App list on the left, the selected app's files on the right. Drop an app anywhere here.
struct UninstallView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            AppList(model: model)
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
            AppDetail(model: model)
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Non-apps are accepted too, so Tidy can say why it ignores them.
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "app" }) ?? urls.first else { return false }
            model.open(appAt: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                // Inset 4 pt from the content's edges; the bottom-right corner is the window's
                // (about 17 pt on macOS 26), so 17 − 4 ≈ Radius.l keeps it concentric.
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    // Stays accent in a background window: you're dragging from Finder, so Tidy
                    // is never key while this shows.
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(Spacing.xs)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    AppSortPicker(model: model)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort apps")
            }
            ToolbarItem {
                Button { model.chooseApp() } label: { Label("Choose App…", systemImage: "plus.app") }
                    .help("Choose an app from anywhere (⌘O)")
            }
        }
    }
}

/// Sort options; Last Opened only when Spotlight has dates for the apps.
struct AppSortPicker: View {
    @Bindable var model: AppModel
    var title = "Sort By"

    var body: some View {
        Picker(title, selection: $model.appSort) {
            ForEach(AppSort.allCases.filter { $0 != .lastOpened || model.canSortByLastOpened }) { Text($0.title).tag($0) }
        }
        .pickerStyle(.inline)
    }
}

struct AppList: View {
    @Bindable var model: AppModel

    var body: some View {
        let apps = model.sortedApps
        Group {
            if !model.appsLoaded {
                ProgressView("Finding apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apps.isEmpty {
                if model.query.isEmpty {
                    ContentUnavailableView {
                        Label("No Apps Found", systemImage: "app.dashed")
                    } description: {
                        Text("There are no apps in \(model.environment.applicationDirectories.map { PathDisplay.short($0, home: model.environment.home) }.joined(separator: " or ")).")
                    } actions: {
                        Button("Choose App…") { model.chooseApp() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: model.query)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List(selection: $model.selectedAppID) {
                    if let external = model.externalApp {
                        Section("Chosen") { AppRow(app: external, model: model).tag(external.id) }
                        Section("Applications") {
                            ForEach(apps) { app in AppRow(app: app, model: model).tag(app.id) }
                        }
                    } else {
                        ForEach(apps) { app in AppRow(app: app, model: model).tag(app.id) }
                    }
                }
                .listStyle(.inset)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct AppRow: View {
    let app: InstalledApp
    var model: AppModel

    /// Version, last opened, and the folder when another app has the same name.
    private var details: String {
        var parts: [String] = []
        parts.append(app.version ?? "Unknown version")
        if let date = model.lastOpened[app.id] { parts.append("opened \(date.formatted(.relative(presentation: .named)))") }
        if model.apps.contains(where: { $0.name == app.name && $0.id != app.id }) {
            parts.append("in \(app.url.deletingLastPathComponent().lastPathComponent)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: Icons.icon(for: app.url))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    if app.isApple {
                        Text("macOS")
                    } else if model.running.isRunning(app) {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Open")
                    } else if !details.isEmpty {
                        Text(details)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            SizeText(url: app.url, sizes: model.sizes)
                .help("Size of the app itself. Select it to see its files too.")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .onAppear {
            model.sizes.request([app.url])
            model.requestLastOpened(app)
        }
    }
}

struct AppDetail: View {
    @Bindable var model: AppModel

    var body: some View {
        if let app = model.currentApp {
            VStack(spacing: 0) {
                AppHeader(app: app, model: model)
                Hairline()
                if let refusal = model.refusal(for: app) {
                    ContentUnavailableView {
                        Label("Can't Remove \(app.name)", systemImage: "lock")
                    } description: {
                        Text(refusal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    notices(for: app)
                    ReviewList(sections: sections, checked: $model.appChecked, selection: $model.appSelection,
                               sizes: model.sizes, home: model.environment.home)
                    ActionBar(model: model, section: .uninstall, checkedURLs: model.checkedLeftovers.map(\.url),
                              buttonTitle: buttonTitle(app))
                }
            }
        } else if let result = model.results[.uninstall] {
            ResultView(model: model, result: result)
        } else {
            ContentUnavailableView {
                Label("Choose an App", systemImage: "app.dashed")
            } description: {
                Text("Select an app, or drop one here, to see everything it keeps on your Mac.")
            } actions: {
                Button("Choose App…") { model.chooseApp() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func buttonTitle(_ app: InstalledApp) -> String {
        let includesApp = model.appChecked.contains(app.id)
        return includesApp ? "Move to Trash" : "Remove Files Only"
    }

    @ViewBuilder
    private func notices(for app: InstalledApp) -> some View {
        let needsAccess = model.leftovers.contains { $0.needsFullDiskAccess } && !model.hasFullDiskAccess
        let needsAdmin = model.leftovers.contains { $0.needsAdmin }
        if model.running.isRunning(app) || needsAccess || needsAdmin {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if model.running.isRunning(app) {
                    Notice(systemImage: "app.badge", text: "\(app.name) is open. Tidy will ask it to quit before moving anything.")
                }
                if needsAccess {
                    Notice(systemImage: "lock.shield", text: "Some items are protected by macOS. Allow Full Disk Access to measure and move them.") {
                        Button("Allow…") { model.showingAccessSheet = true }
                    }
                }
                if needsAdmin {
                    Notice(systemImage: "person.badge.key",
                           text: "Items marked with a lock need an administrator. Show them in Finder and move them to the Trash there.") {
                        Button("Show in Finder") { Finder.reveal(model.leftovers.filter(\.needsAdmin).map(\.url)) }
                    }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            Hairline()
        }
    }

    private var sections: [ReviewSection] {
        let home = model.environment.home
        let row = { (item: Leftover) in
            ReviewItem(url: item.url, title: item.url.lastPathComponent, subtitle: PathDisplay.parent(item.url, home: home),
                       note: note(for: item), lockReason: lockReason(for: item), help: item.reason.explanation)
        }
        let sure = model.leftovers.filter { !$0.reason.isPossibleMatch }
        let possible = model.leftovers.filter(\.reason.isPossibleMatch)
        var sections = Dictionary(grouping: sure, by: \.kind)
            .sorted { $0.key < $1.key }
            .map { kind, items in
                ReviewSection(id: kind.rawValue, title: kind.title, systemImage: kind.systemImage, detail: nil, items: items.map(row))
            }
        if !possible.isEmpty {
            sections.append(ReviewSection(id: "possible", title: "Possible Matches", systemImage: "questionmark.circle",
                                          detail: "Named like the app, but may belong to something else. Never checked for you.",
                                          items: possible.map(row)))
        }
        return sections
    }

    private func note(for item: Leftover) -> String? {
        switch item.reason {
        case .name: "Matched by name"
        case .launchProgram: "Runs this app"
        case .crashReport: "Crash report"
        case .possibleName(_, .commonName): "Common name"
        case .possibleName(_, .sharedWith(let others)): "Also \(others.joined(separator: ", "))"
        default: nil
        }
    }

    private func lockReason(for item: Leftover) -> String? {
        if item.needsAdmin { return "Needs an administrator" }
        if item.needsFullDiskAccess && !model.hasFullDiskAccess { return "Needs Full Disk Access" }
        return nil
    }
}

struct Notice<Accessory: View>: View {
    let systemImage: String
    let text: String
    let accessory: Accessory

    init(systemImage: String, text: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.systemImage = systemImage
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            accessory.controlSize(.small)
        }
    }
}

struct AppHeader: View {
    let app: InstalledApp
    var model: AppModel

    var body: some View {
        // The size of everything Tidy is sure about (possible matches aren't counted in).
        let removable = model.leftovers.filter { !$0.reason.isPossibleMatch }
        let total = model.sizes.total(removable.map(\.url))
        HStack(spacing: Spacing.m) {
            Image(nsImage: Icons.icon(for: app.url))
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.title2.bold()).lineLimit(1)
                Text([app.version.map { "Version \($0)" } ?? "Unknown version", app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            Spacer()
            if !app.isApple {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(total.bytes))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(total.isComplete ? .primary : .secondary)
                    Text(ItemCount.text(total: model.leftovers.count,
                                        checked: model.leftovers.filter { model.appChecked.contains($0.id) && model.isRemovable($0) }.count))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }
}

/// Shown after an app was moved to the Trash.
struct ResultView: View {
    var model: AppModel
    let result: ActionResult

    var body: some View {
        ContentUnavailableView {
            Label(result.isPutBack ? "Put Back" : "Moved to the Trash",
                  systemImage: result.isPutBack ? "arrow.uturn.backward.circle" : "checkmark.circle")
        } description: {
            VStack(spacing: Spacing.xs) {
                Text(result.summary)
                if !result.isPutBack, result.bytes > 0 {
                    Text("Empty the Trash to free \(ByteFormat.string(result.bytes)).")
                }
            }
        } actions: {
            VStack(spacing: Spacing.l) {
                if !result.isPutBack {
                    Button("Put Back") { model.putBack(.uninstall) }
                        .help("Move everything back to where it was (⌘Z)")
                        .fixedSize()
                }
                if let note = result.leftInPlaceNote {
                    LeftInPlaceList(note: note, items: result.leftInPlace, home: model.environment.home)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Items an uninstall couldn't move, kept visible with a way to finish the job in Finder.
struct LeftInPlaceList: View {
    let note: String
    let items: [Leftover]
    let home: URL

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(note).font(.callout)
            Text("Show them in Finder and move them to the Trash there; Finder asks for your password.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack(spacing: Spacing.s) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text("\(PathDisplay.parent(item.url, home: home)) · \(item.needsAdmin ? "Needs an administrator" : "Needs Full Disk Access")")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
            Button("Show in Finder") { Finder.reveal(items.map(\.url)) }
                .fixedSize()
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(Spacing.m)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
}
