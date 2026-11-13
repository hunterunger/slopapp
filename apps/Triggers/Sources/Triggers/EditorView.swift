import AppKit
import SlopKit
import SwiftUI
import TriggersCore

/// The editor: places on the left (All Apps, Browsers, apps), that place's triggers on the
/// right, edits in a sheet. Library archetype (design system §2c).
struct EditorView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undo
    @State private var showsAppPicker = false

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model, showsAppPicker: $showsAppPicker)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 300)
        } detail: {
            BindingsPane(model: model)
        }
        .sheet(item: $model.draft) { draft in
            TriggerSheet(model: model, draft: draft)
        }
        .focusedSceneValue(\.editorUndo, undo)
        .onAppear {
            model.refreshSystemSettings()
            model.checkTrust()
            EditorWindow.addAppRequest = { showsAppPicker = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshSystemSettings()
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var model: AppModel
    @Binding var showsAppPicker: Bool
    @Environment(\.undoManager) private var undo

    var body: some View {
        List(selection: $model.selection) {
            Section {
                row(.allApps, title: "All Apps", systemImage: "square.grid.2x2")
                row(.browsers, title: "Browsers", systemImage: "globe")
            }
            Section {
                ForEach(model.config.apps) { app in
                    appRow(app)
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    AddAppMenu(model: model, isPresented: $showsAppPicker)
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if case .app(let id) = model.selection { model.removeApp(id, undo: undo) }
        }
    }

    private func count(_ item: SidebarItem) -> Int { model.config.bindings(in: item.scope).count }

    private func row(_ item: SidebarItem, title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .badge(count(item))
            .tag(item)
    }

    private func appRow(_ app: AppEntry) -> some View {
        Label {
            HStack(spacing: Spacing.xs) {
                Text(app.name).lineLimit(1).truncationMode(.middle)
                if !app.usesAllAppsTriggers {
                    Image(systemName: "nosign")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("All-apps triggers are off here")
                        .accessibilityLabel("All-apps triggers off")
                }
            }
        } icon: {
            Image(nsImage: AppCatalog.icon(for: app.bundleID))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
        .badge(count(.app(app.bundleID)))
        .tag(SidebarItem.app(app.bundleID))
        .contextMenu {
            Toggle("Use All-Apps Triggers Here", isOn: Binding(
                get: { app.usesAllAppsTriggers },
                set: { model.setUsesAllAppsTriggers($0, in: app.bundleID, name: app.name, undo: undo) }
            ))
            Divider()
            Button("Remove \(app.name)") { model.removeApp(app.bundleID, undo: undo) }
        }
    }
}

/// "+" next to the Apps header: running apps first, then Choose….
private struct AddAppMenu: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @Environment(\.undoManager) private var undo

    var body: some View {
        Menu {
            let present = Set(model.config.apps.map(\.bundleID))
            let running = AppCatalog.runningApps().filter { !present.contains($0.bundleID) }
            if !running.isEmpty {
                Section("Open Apps") {
                    ForEach(running) { app in
                        Button(app.name) { model.addApp(app, undo: undo) }
                    }
                }
            }
            Button("Choose App…") { choose() }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add an app")
        .accessibilityLabel("Add App")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            AppPickerList(model: model, isPresented: $isPresented) { choose() }
        }
    }

    private func choose() {
        if let app = AppCatalog.chooseApp(message: "Choose an app to give its own triggers.") { model.addApp(app, undo: undo) }
    }
}

/// The keyboard route to adding an app (File › Add App…): a short list, Return picks.
private struct AppPickerList: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    var choose: () -> Void
    @Environment(\.undoManager) private var undo

    var body: some View {
        let present = Set(model.config.apps.map(\.bundleID))
        let running = AppCatalog.runningApps().filter { !present.contains($0.bundleID) }
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Add App").font(.headline)
            ForEach(running) { app in
                Button(app.name) {
                    model.addApp(app, undo: undo)
                    isPresented = false
                }
                .buttonStyle(.link)
            }
            Button("Choose App…") {
                isPresented = false
                choose()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.l)
        .frame(minWidth: 220, alignment: .leading)
    }
}

// MARK: - Bindings

private struct BindingsPane: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        VStack(spacing: 0) {
            InfoBars(model: model)
            ScopeHeader(model: model)
            content
        }
        .navigationTitle(title)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search Triggers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.beginNew()
                } label: {
                    Label("New Trigger", systemImage: "plus")
                }
                .help("New Trigger (⌘N)")
            }
        }
    }

    private var title: String {
        switch model.selection {
        case .allApps: "All Apps"
        case .browsers: "Browsers"
        case .app(let id): model.appName(id)
        }
    }

    @ViewBuilder private var content: some View {
        let bindings = model.bindings(for: model.selection)
        if model.config.bindings.isEmpty, model.selection == .allApps, model.searchText.isEmpty {
            FirstRunView(model: model)
        } else if bindings.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Triggers in \(title)", systemImage: "hand.tap")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button("Add Trigger") { model.beginNew() }
                }
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            BindingsTable(model: model, bindings: bindings)
        }
    }

    private var emptyDescription: String {
        switch model.selection {
        case .allApps: "Triggers here work in every app."
        case .browsers: "Triggers here work in Safari, Chrome, Firefox, Arc and other browsers."
        case .app(let id): "Triggers here work only in \(model.appName(id)), and replace All Apps triggers for the same input."
        }
    }
}

/// Per-place explanation and the "use all-apps triggers" switch for apps.
private struct ScopeHeader: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        switch model.selection {
        case .allApps:
            EmptyView()
        case .browsers:
            header { Text("Works in Safari, Chrome, Firefox, Arc and other browsers.").foregroundStyle(.secondary) }
        case .app(let id):
            let name = model.appName(id)
            header {
                Toggle("Use All Apps triggers in \(name)", isOn: Binding(
                    get: { model.usesAllAppsTriggers(in: id) },
                    set: { model.setUsesAllAppsTriggers($0, in: id, name: name, undo: undo) }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }

    private func header<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack { content(); Spacer() }
                .font(.callout)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
            Hairline()
        }
    }
}

private struct BindingsTable: View {
    @Bindable var model: AppModel
    let bindings: [TriggerBinding]
    @Environment(\.undoManager) private var undo

    var body: some View {
        Table(bindings, selection: $model.selectedBindings) {
            TableColumn("On") { binding in
                Toggle("Turn \(KeyDisplay.title(binding.trigger)) on or off", isOn: Binding(
                    get: { binding.isEnabled },
                    set: { model.setEnabled([binding.id], $0, undo: undo) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            .width(32)
            TableColumn("Trigger") { binding in
                TriggerCell(model: model, binding: binding)
            }
            .width(min: 180, ideal: 240)
            TableColumn("Action") { binding in
                Text(KeyDisplay.summary(binding))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(binding.isEnabled ? .primary : .secondary)
                    .help(binding.steps.count > 1 ? KeyDisplay.summary(binding) : "")
            }
            .width(min: 160, ideal: 260)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Edit Trigger…") { model.beginEdit(id) }
                Button("Run Action Now") { model.runNow(id) }
            }
            if !ids.isEmpty {
                let allOn = model.config.bindings.filter { ids.contains($0.id) }.allSatisfy(\.isEnabled)
                Button(allOn ? "Turn Off" : "Turn On") { model.setEnabled(ids, !allOn, undo: undo) }
                Button("Duplicate") { model.duplicate(ids, undo: undo) }
                Divider()
                Button("Delete") { model.delete(ids, undo: undo) }
            }
        } primaryAction: { ids in
            if let id = ids.first { model.beginEdit(id) }
        }
        .onDeleteCommand { model.delete(model.selectedBindings, undo: undo) }
    }
}

/// The input with its symbol, plus a badge when something needs attention.
private struct TriggerCell: View {
    let model: AppModel
    let binding: TriggerBinding

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: binding.trigger.systemImage)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(KeyDisplay.title(binding.trigger))
                .lineLimit(1)
                .foregroundStyle(binding.isEnabled ? .primary : .secondary)
            if !binding.conditions.isEmpty {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .help("Only when: \(binding.conditions.summary)")
                    .accessibilityLabel("Only when \(binding.conditions.summary)")
            }
            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help(warning)
                    .accessibilityLabel("Warning: \(warning)")
            }
        }
    }

    private var warning: String? {
        if model.needsGestures(binding) { return "Trackpad gestures aren't available." }
        if model.needsAccessibility(binding) { return "Needs Accessibility access." }
        guard binding.isEnabled else { return nil }
        return model.conflicts(for: binding).first(where: \.isWarning).map(ConflictText.message)
    }
}

// MARK: - Info bars

/// Slim notices above the table: what's stopping triggers from working, with the fix.
struct InfoBars: View {
    @Bindable var model: AppModel

    var body: some View {
        if let error = model.loadError {
            InfoBar(systemImage: "exclamationmark.triangle.fill", text: error)
        }
        if model.isPaused {
            InfoBar(systemImage: "pause.circle.fill", text: "Triggers is paused. Nothing you do runs an action.",
                    button: "Resume") { model.isPaused = false }
        }
        if !model.isTrusted && model.needsAccessibility {
            InfoBar(systemImage: "accessibility",
                    text: "Triggers needs Accessibility access to press keys, click, move windows, use mouse buttons and watch key sequences for you.",
                    button: "Open System Settings") { model.openAccessibilitySettings() }
        }
        if let problem = model.gestureProblem, model.config.bindings.contains(where: { $0.trigger.family == .trackpad }) {
            InfoBar(systemImage: "hand.raised.slash", text: problem)
        }
        if model.tapGaveUp {
            InfoBar(systemImage: "computermouse", text: "macOS kept stopping Triggers' mouse buttons because the Mac was very busy.",
                    button: "Try Again") { model.retryTap() }
        }
    }
}

struct InfoBar: View {
    let systemImage: String
    let text: String
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.s)
                if let button, let action {
                    Button(button, action: action)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .background(.bar)
            Hairline()
        }
    }
}

// MARK: - First run

/// Empty state for a brand-new setup: what Triggers does, one action, three starters.
private struct FirstRunView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undo

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 40, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.xs) {
                    Text("No Triggers Yet").font(.title2.bold())
                    Text("Make a trackpad gesture, a mouse button or keys do something, or a list of things, in every app or just one.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Add Trigger") { model.beginNew() }
                    .buttonStyle(.borderedProminent)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Or start with one of these. Nothing is on until you add it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(Starter.all.enumerated()), id: \.element.id) { index, starter in
                            if index > 0 { Hairline().padding(.leading, StarterRow.textInset) }
                            StarterRow(model: model, starter: starter)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.l))
                    .hairlineBorder(RoundedRectangle(cornerRadius: Radius.l))
                }
                .frame(maxWidth: 480)
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StarterRow: View {
    static let iconWidth: CGFloat = 20
    /// Where the title starts, so the separator lines up with the text (Mail-style inset).
    static let textInset = Spacing.m + iconWidth + Spacing.m

    @Bindable var model: AppModel
    let starter: Starter
    @Environment(\.undoManager) private var undo

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: starter.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: Self.iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(starter.title).font(.headline)
                Text(starter.detail).font(.callout).foregroundStyle(.secondary)
                if let note {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: Spacing.s)
            Button("Add") { model.applyStarter(starter, undo: undo) }
                .accessibilityLabel("Add \(starter.title)")
        }
        .padding(Spacing.m)
    }

    /// The first macOS gesture this starter overlaps on this Mac, if any.
    private var note: String? {
        for binding in starter.bindings {
            if case .gesture(let gesture, _) = binding.trigger, let use = model.systemGestures.systemUse(of: gesture) {
                return use.message
            }
        }
        return nil
    }
}

/// Words for conflicts, shared by the table badge and the sheet.
enum ConflictText {
    static func message(_ conflict: Conflict) -> String {
        switch conflict {
        case .system(let use): use.message
        case .duplicate(let other):
            other.conditions.isEmpty
                ? "Another trigger here uses the same input (\(KeyDisplay.summary(other))). Only the first one runs. Add a condition to choose between them."
                : "Another trigger here uses the same input with the same conditions (\(KeyDisplay.summary(other))). Only the first one runs."
        case .systemShortcut: "macOS already uses this key combination. Pick another, or change it in Keyboard Shortcuts."
        case .shortcutTaken: "Another app is using this key combination, so Triggers can't. Pick another."
        case .pressesItself: "The action presses the same keys as the trigger, so it would only trigger itself."
        case .overrides(let other):
            "Replaces the \(other.scope == .browsers ? "Browsers" : "All Apps") trigger for this input (\(KeyDisplay.summary(other)))."
        case .sequenceTypes: "These keys still type in the app; Triggers only watches for them."
        case .sequenceEverywhere: "These keys still type, and Triggers watches for them in every app. Add a modifier, or make it work in one app only."
        }
    }
}
