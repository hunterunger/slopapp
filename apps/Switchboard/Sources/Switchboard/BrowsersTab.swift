import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore
import UniformTypeIdentifiers

/// The list of places links can open. Order = number keys in the picker.
struct BrowsersTab: View {
    @Bindable var model: AppModel
    // Store screenshots show one browser's options.
    @State private var selection: UUID? = Showcase.isActive ? ShowcaseFixtures.selectedTarget : nil
    @Environment(\.undoManager) private var undoManager
    @State private var profileSheetFor: InstalledApp?
    @State private var safariProfileSheetFor: InstalledApp?
    @State private var pendingRemoval: Target?
    @State private var showUndo = false

    private var selectedIndex: Int? {
        selection.flatMap { id in model.config.targets.firstIndex { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if model.config.targets.isEmpty {
                ContentUnavailableView {
                    Label("No Browsers", systemImage: "safari")
                } description: {
                    Text("Add a browser so links have somewhere to go.")
                } actions: {
                    addMenu(title: true)
                    // Removing the last browser lands here: keep its Undo in reach.
                    UndoRemovalButton(label: "Undo Remove", isVisible: $showUndo)
                }
                .frame(height: 220)
            } else {
                List(selection: $selection) {
                    ForEach(model.config.targets) { target in
                        TargetListRow(target: target, number: pickerNumber(of: target), isInstalled: model.isInstalled(target))
                            .tag(target.id)
                            .listRowSeparator(.hidden)
                            .contextMenu { contextMenu(for: target) }
                    }
                    .onMove { model.config.targets.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                // As tall as the rows need (no big empty well), up to a scrolling maximum.
                .frame(height: min(max(CGFloat(model.config.targets.count) * 34 + 14, 110), 240))
                .accessibilityLabel("Browsers")
                .onDeleteCommand(perform: removeSelected)

                ListButtonBar(
                    canRemove: selectedIndex != nil,
                    canMoveUp: (selectedIndex ?? 0) > 0,
                    canMoveDown: selectedIndex.map { $0 < model.config.targets.count - 1 } ?? false,
                    remove: removeSelected,
                    moveUp: { move(by: -1) },
                    moveDown: { move(by: 1) }
                ) { addMenu(title: false) } trailing: {
                    UndoRemovalButton(label: "Undo Remove", isVisible: $showUndo)
                }
            }

            if !model.config.targets.isEmpty {
                optionsArea
            }
        }
        .padding(Spacing.xl)
        .onReceive(NotificationCenter.default.publisher(for: .switchboardOpenSheet)) { note in
            switch note.object as? String {
            case "safari-profile": safariProfileSheetFor = model.installedBrowsers.first { $0.bundleID == "com.apple.Safari" }
            case "select-private": selection = model.config.targets.first { $0.privateWindow }?.id
            default: break
            }
        }
        .confirmationDialog(
            pendingRemoval.map { removalTitle(for: $0) } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { target in
            Button("Remove", role: .destructive) { remove(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(removalMessage(for: target))
        }
        .sheet(item: $profileSheetFor) { app in
            ProfileSheet(app: app, model: model) { added in
                if let added { selection = added }
            }
        }
        .sheet(item: $safariProfileSheetFor) { app in
            SafariProfileSheet(app: app, model: model) { added in
                if let added { selection = added }
            }
        }
    }

    /// The selected browser's options, or a hint. Same height either way, so the window
    /// doesn't jump when the selection changes.
    private var optionsArea: some View {
        Group {
            if let index = selectedIndex {
                TargetOptions(target: $model.config.targets[index])
            } else {
                Text("The order here is the order of the number keys in the picker. Drag to reorder, or select a browser for its options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
    }

    private func pickerNumber(of target: Target) -> Int? {
        guard !target.isHidden, let index = model.config.pickerTargets.firstIndex(where: { $0.id == target.id }), index < 9 else {
            return nil
        }
        return index + 1
    }

    /// - Parameter title: a labelled button (empty state) instead of the list bar's "+".
    private func addMenu(title: Bool) -> some View {
        Menu {
            Section("Browsers") {
                ForEach(model.installedBrowsers, id: \.bundleID) { app in
                    Button(isListed(app) ? "\(app.name) (Added)" : app.name) { selection = model.addTarget(app: app) }
                        .disabled(isListed(app))
                }
            }
            let profileBrowsers = model.installedBrowsers.filter { BrowserCatalog.family(for: $0.bundleID).supportsProfiles }
            if !profileBrowsers.isEmpty {
                Section("Profiles") {
                    ForEach(profileBrowsers, id: \.bundleID) { app in
                        Button("\(app.name) Profiles…") {
                            if BrowserCatalog.family(for: app.bundleID) == .safari { safariProfileSheetFor = app } else { profileSheetFor = app }
                        }
                    }
                }
            }
            let privateBrowsers = model.installedBrowsers.filter { BrowserCatalog.family(for: $0.bundleID).supportsPrivateWindow }
            if !privateBrowsers.isEmpty {
                Section("Private Windows") {
                    ForEach(privateBrowsers, id: \.bundleID) { app in
                        Button(isListed(app, privateWindow: true) ? "\(app.name), Private Window (Added)" : "\(app.name), Private Window") {
                            selection = model.addTarget(app: app, privateWindow: true)
                        }
                        .disabled(isListed(app, privateWindow: true))
                    }
                }
            }
            Section("Other Apps") {
                ForEach(model.otherLinkApps, id: \.bundleID) { app in
                    Button(isListed(app) ? "\(app.name) (Added)" : app.name) { selection = model.addTarget(app: app) }
                        .disabled(isListed(app))
                }
                Button("Choose App…") { chooseApp() }
            }
            Divider()
            Button("Refresh List") { model.refreshInstalledApps() }
        } label: {
            if title {
                Text("Add Browser")
            } else {
                Label("Add", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
            }
        }
        .menuIndicator(title ? .visible : .hidden)
        .fixedSize()
        .help("Add a browser, profile or app")
        .accessibilityLabel("Add")
    }

    /// Already in the list and visible (a hidden one can be added to show it again).
    private func isListed(_ app: InstalledApp, privateWindow: Bool = false) -> Bool {
        model.config.targets.contains {
            $0.bundleID == app.bundleID && $0.profile == nil && $0.privateWindow == privateWindow && !$0.isHidden
        }
    }

    @ViewBuilder private func contextMenu(for target: Target) -> some View {
        Button(target.isHidden ? "Show in Picker" : "Hide from Picker") {
            update(target.id) { $0.isHidden.toggle() }
        }
        Button("Remove", role: .destructive) { requestRemoval(of: target) }
    }

    private func update(_ id: UUID, _ change: (inout Target) -> Void) {
        guard let index = model.config.targets.firstIndex(where: { $0.id == id }) else { return }
        change(&model.config.targets[index])
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        requestRemoval(of: model.config.targets[index])
    }

    /// Asks first when rules (or the fallback) use the browser; removes right away otherwise.
    private func requestRemoval(of target: Target) {
        if usage(of: target) > 0 {
            pendingRemoval = target
        } else {
            remove(target)
        }
    }

    private func usage(of target: Target) -> Int {
        model.config.rulesUsing(target.id).count + (model.config.fallback == .open(targetID: target.id) ? 1 : 0)
    }

    private func removalTitle(for target: Target) -> String {
        let rules = model.config.rulesUsing(target.id).count
        let usesFallback = model.config.fallback == .open(targetID: target.id)
        var parts: [String] = []
        if rules > 0 { parts.append(rules == 1 ? "1 rule uses" : "\(rules) rules use") }
        if usesFallback { parts.append(parts.isEmpty ? "\"When no rule matches\" uses" : "and \"When no rule matches\" use") }
        return "\(parts.joined(separator: " ")) \(target.displayName). Remove it?"
    }

    private func removalMessage(for target: Target) -> String {
        let rules = model.config.rulesUsing(target.id).count
        let subject = switch rules {
        case 0: "Links no rule matches"
        case 1: "That rule"
        default: "Those rules"
        }
        let verb = rules == 1 ? "shows" : "show"
        let pronoun = rules == 1 ? "it" : "them"
        return "\(subject) \(verb) the picker until you add \(target.displayName) back. Adding it back reconnects \(pronoun)."
    }

    private func remove(_ target: Target) {
        guard let index = model.config.targets.firstIndex(where: { $0.id == target.id }) else { return }
        model.removeTarget(id: target.id, undoManager: undoManager)
        showUndo = true
        let remaining = model.config.targets
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    private func move(by offset: Int) {
        guard let index = selectedIndex else { return }
        model.config.targets.moveElement(at: index, by: offset)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose an app to open links in."
        if panel.runModal() == .OK, let url = panel.url {
            if let id = model.addTarget(appAt: url) {
                selection = id
            } else {
                HUD.show("That app can't be added.", systemImage: "exclamationmark.triangle")
            }
        }
    }
}

struct TargetListRow: View {
    let target: Target
    let number: Int?
    let isInstalled: Bool
    @Environment(\.self) private var environment

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Opener.appURL(for: target)?.path ?? target.appPath))
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(target.isHidden ? 0.4 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(target.displayName)
                    .foregroundStyle(target.isHidden ? .secondary : .primary)
                if !isInstalled {
                    Text("Not installed")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                } else if target.isHidden {
                    Text("Hidden from the picker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if target.opensInBackground {
                    Text("Opens in the background")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let number {
                Text("\(number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18)
                    .accessibilityLabel("Key \(number)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct TargetOptions: View {
    @Binding var target: Target

    var body: some View {
        let family = BrowserCatalog.family(for: target.bundleID)
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(target.displayName)
                    .font(.headline)
                if let folder = target.profile?.directory, family != .safari {
                    Text("Folder: \(folder)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Toggle("Show in picker", isOn: Binding(get: { !target.isHidden }, set: { target.isHidden = !$0 }))
            Toggle("Open in the background", isOn: $target.opensInBackground)
            if target.opensInBackground, case .chromium = family {
                Text("Chrome-based browsers come forward anyway when they open a link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if family.supportsPrivateWindow {
                Toggle("Private window", isOn: $target.privateWindow)
            }
            if family.windowsNeedAccessibility, target.privateWindow || target.profile != nil {
                AccessibilityNote()
            }
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - Profiles

/// Lists a Chromium browser's profiles to add. Reading another app's data may need the
/// user's OK; if macOS says no, profiles can be added by folder name instead.
private struct ProfileSheet: View {
    let app: InstalledApp
    @Bindable var model: AppModel
    let onDone: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case loaded([BrowserProfile])
        case failed(ChromiumProfiles.Failure)
    }

    @State private var phase: Phase = .loading
    @State private var chosen: Set<String> = []
    @State private var manualName = ""
    @State private var manualFolder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("\(app.name) Profiles")
                .font(.headline)
            content
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { close(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Looking for profiles…").foregroundStyle(.secondary)
            }
        case .loaded(let profiles) where profiles.isEmpty:
            Text("\(app.name) has no profiles yet. Open it once, then try again.")
                .foregroundStyle(.secondary)
            manualEntry
        case .loaded(let profiles):
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(profiles, id: \.directory) { profile in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(profile.directory) },
                        set: { on in if on { chosen.insert(profile.directory) } else { chosen.remove(profile.directory) } }
                    )) {
                        Text(profile.name)
                        + Text(profile.name == profile.directory ? "" : "  \(profile.directory)").foregroundStyle(.secondary)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        case .failed(let failure):
            Text(message(for: failure))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if failure == .notPermitted {
                Button("Open Privacy Settings…") {
                    NSWorkspace.shared.open(Permission.fullDiskAccess.settingsURL)
                }
            }
            manualEntry
        }
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
                GridRow {
                    Text("Name").gridColumnAlignment(.trailing)
                    TextField("Name", text: $manualName, prompt: Text("Work"))
                        .labelsHidden()
                        .accessibilityLabel("Name")
                }
                GridRow {
                    Text("Folder")
                    TextField("Folder", text: $manualFolder, prompt: Text("Profile 1"))
                        .labelsHidden()
                        .accessibilityLabel("Folder")
                }
            }
            .textFieldStyle(.roundedBorder)
            folderCheckNote
            Text("To find the folder, open \(app.name), go to chrome://version and look at the end of Profile Path.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var folderCheckNote: some View {
        let folder = manualFolder.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty, case .chromium(let dir?) = BrowserCatalog.family(for: app.bundleID) {
            switch ChromiumProfiles.checkFolder(folder, dataDirectory: dir) {
            case .exists:
                Label("Found this profile folder.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .missing:
                Label("\(app.name) has no profile folder named “\(folder)”. Opening links there would create a new, empty profile.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.textOrange)
                    .fixedSize(horizontal: false, vertical: true)
            case .unknown:
                EmptyView()
            }
        }
    }

    private func message(for failure: ChromiumProfiles.Failure) -> String {
        switch failure {
        case .notPermitted:
            "macOS didn't let Switchboard read \(app.name)'s profile list. Add a profile by its folder name below, or give Switchboard Full Disk Access and try again."
        case .notFound:
            "\(app.name) hasn't saved any profiles yet. Open it once, or add a profile by its folder name below."
        case .unreadable:
            "\(app.name)'s profile list is in a format Switchboard doesn't recognise. Add a profile by its folder name below."
        }
    }

    private var canAdd: Bool {
        switch phase {
        case .loaded(let profiles) where !profiles.isEmpty: !chosen.isEmpty
        case .loading: false
        default: ChromiumProfiles.isValidDirectoryName(manualFolder)
        }
    }

    private func load() async {
        guard case .chromium(let dir?) = BrowserCatalog.family(for: app.bundleID) else {
            phase = .failed(.notFound)
            return
        }
        switch await ProfileLoader.load(dataDirectory: dir) {
        case .success(let profiles):
            phase = .loaded(profiles)
            let existing = Set(model.config.targets.filter { $0.bundleID == app.bundleID }.compactMap { $0.profile?.directory })
            chosen = Set(profiles.map(\.directory)).subtracting(existing)
        case .failure(let failure):
            phase = .failed(failure)
        }
    }

    private func add() {
        var lastAdded: UUID?
        switch phase {
        case .loaded(let profiles) where !profiles.isEmpty:
            for profile in profiles where chosen.contains(profile.directory) {
                lastAdded = model.addTarget(app: app, profile: profile)
            }
        default:
            let folder = manualFolder.trimmingCharacters(in: .whitespaces)
            let name = manualName.trimmingCharacters(in: .whitespaces)
            lastAdded = model.addTarget(app: app, profile: BrowserProfile(directory: folder, name: name.isEmpty ? folder : name))
        }
        close(lastAdded)
    }

    private func close(_ added: UUID?) {
        onDone(added)
        dismiss()
    }
}
