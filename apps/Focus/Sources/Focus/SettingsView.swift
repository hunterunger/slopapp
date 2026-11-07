import AppKit
import FocusCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String {
    case general, timer, categories, blocking, shortcuts, automation, about

    static let storageKey = "settingsTab"

    /// Picks the tab the Settings window shows (now if open, or when it opens).
    static func select(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: storageKey)
    }
}

/// General, Timer, Categories, Hide Apps, Shortcuts, Automation, About. Built from SlopKit's pieces rather than
/// `SlopSettings` so the menu's "Custom…" can open straight to the Timer tab.
struct FocusSettingsView: View {
    @Bindable var controller: FocusController
    let info: AppInfo
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                GeneralRows(controller: controller)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general)

            TimerTab(controller: controller)
                .tabItem { Label("Timer", systemImage: "timer") }
                .tag(SettingsTab.timer)

            CategoriesTab(controller: controller)
                .tabItem { Label("Categories", systemImage: "circle.grid.2x2") }
                .tag(SettingsTab.categories)

            HideAppsTab(controller: controller)
                .tabItem { Label("Hide Apps", systemImage: "eye.slash") }
                .tag(SettingsTab.blocking)

            SettingsForm {
                Section {
                    ShortcutRow("Start or pause", name: .startPause)
                    ShortcutRow("Show the Focus window", name: .showWindow)
                } footer: {
                    Text("These work from any app. Start or pause starts a focus session, or pauses and resumes the one that's running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section("In the Focus window") {
                    KeyRow(title: "Start focus or save reflection", keys: "⌘↩")
                    KeyRow(title: "Pause or resume", keys: "⌘P")
                    KeyRow(title: "Finish session", keys: "⇧⌘↩")
                    KeyRow(title: "Stop", keys: "⌘.")
                    KeyRow(title: "Add or remove 5 minutes", keys: "⇧⌘.  ⇧⌘,")
                    KeyRow(title: "Timer, Stats", keys: "⌘1  ⌘2")
                    KeyRow(title: "Category and length in the intention", keys: "@work 45m")
                }
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }
            .tag(SettingsTab.shortcuts)

            AutomationTab(controller: controller)
                .tabItem { Label("Automation", systemImage: "wand.and.stars") }
                .tag(SettingsTab.automation)

            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        // Seven tabs don't fit the standard 480 pt toolbar.
        .frame(width: 580)
    }
}

/// Binds a settings field through the controller, which clamps and saves it.
@MainActor
private func setting<Value>(_ controller: FocusController, _ keyPath: WritableKeyPath<TimerSettings, Value>) -> Binding<Value> {
    Binding(
        get: { controller.settings[keyPath: keyPath] },
        set: { value in controller.updateSettings { $0[keyPath: keyPath] = value } }
    )
}

private struct GeneralRows: View {
    let controller: FocusController

    var body: some View {
        Picker("Daily goal", selection: setting(controller, \.dailyGoal)) {
            Text("None").tag(0)
            ForEach(1...TimerSettings.dailyGoalRange.upperBound, id: \.self) { count in
                Text(count == 1 ? "1 session" : "\(count) sessions").tag(count)
            }
        }
        Toggle(isOn: setting(controller, \.askReflection)) {
            Text("Ask how it went after each session")
            Text("A mood and a note, saved with the session for your stats.")
        }
        Toggle(isOn: setting(controller, \.showSeconds)) {
            Text("Show seconds in menu bar")
            Text("Updates every second, which uses a little more battery.")
        }
        Toggle("Play a sound when time is up", isOn: setting(controller, \.playSound))
        Picker("Sound", selection: Binding(
            get: { controller.settings.soundName },
            set: { name in
                controller.updateSettings { $0.soundName = name }
                controller.previewSound(name)
            }
        )) {
            ForEach(controller.availableSounds, id: \.self) { Text($0).tag($0) }
        }
        .disabled(!controller.settings.playSound)
        NotificationRow(controller: controller, appName: AppInfo.current(fallbackName: "Focus").name)
    }
}

/// Whether macOS lets Focus post its "time's up" notifications, with the way to fix it.
private struct NotificationRow: View {
    let controller: FocusController
    let appName: String

    var body: some View {
        content.task { await controller.refreshPermission() }
    }

    @ViewBuilder private var content: some View {
        switch controller.permission {
        case .denied:
            LabeledContent {
                Button("Open Notification Settings…") { NSWorkspace.shared.open(SystemNotifier.settingsURL) }
            } label: {
                Text("Notifications are off")
                Text("When time is up, a bell flashes in the menu bar instead, and the sound plays if it's on.")
            }
        case .authorized:
            LabeledContent("Notifications") {
                Text("On").foregroundStyle(.secondary)
            }
        case .notDetermined:
            LabeledContent {
                Text("Not asked yet").foregroundStyle(.secondary)
            } label: {
                Text("Notifications")
                Text("\(appName) asks the first time you start a session.")
            }
        }
    }
}

private struct TimerTab: View {
    let controller: FocusController

    var body: some View {
        SettingsForm {
            Section {
                MinutesRow(title: "Focus session", value: setting(controller, \.focusMinutes), range: TimerSettings.focusRange)
                MinutesRow(title: "Short break", value: setting(controller, \.shortBreakMinutes), range: TimerSettings.breakRange)
                MinutesRow(title: "Long break", value: setting(controller, \.longBreakMinutes), range: TimerSettings.breakRange)
                Picker("Take a long break", selection: setting(controller, \.longBreakEvery)) {
                    ForEach(TimerSettings.longBreakEveryOptions, id: \.self) { count in
                        Text(count == 0 ? "Never" : "After every \(count) sessions").tag(count)
                    }
                }
            }
            Section {
                Toggle("Start breaks automatically", isOn: setting(controller, \.autoStartBreaks))
                Toggle("Start the next session after a break", isOn: setting(controller, \.autoStartFocus))
                Toggle(isOn: setting(controller, \.breakScreen)) {
                    Text("Cover the screen during breaks")
                    Text("A full-screen reminder to rest. Press Esc to hide it.")
                }
            } footer: {
                Text("A session counts toward today's total when at least \(Int(SessionRecord.countThreshold * 100))% of it ran. New lengths apply from the next session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "Focus session   [25] min [-|+]"
private struct MinutesRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Spacing.xs) {
                TextField(title, value: $value, format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 48)
                Text("min")
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
            }
        }
    }
}

private struct AutomationTab: View {
    @Bindable var controller: FocusController
    @State private var names: [String] = []
    @State private var listError: String?
    @State private var testResult: String?
    @State private var testFailed = false
    @State private var isTesting = false

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Run a shortcut when a session starts or ends", isOn: setting(controller, \.runShortcuts))
                if controller.settings.runShortcuts {
                    shortcutRow("When a session starts", keyPath: \.startShortcut)
                    shortcutRow("When a session ends", keyPath: \.endShortcut)
                    if let listError {
                        Text(listError).font(.caption).foregroundStyle(.red)
                    }
                    if let testResult {
                        Text(testResult).font(.caption).foregroundStyle(testFailed ? .red : .secondary)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("To turn on a Focus mode while you work, make two shortcuts in the Shortcuts app with the “Set Focus” action: one that turns it on, one that turns it off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: controller.settings.runShortcuts) {
            // Only read the user's shortcuts once they've asked for this.
            guard controller.settings.runShortcuts else { return }
            do {
                names = try await controller.availableShortcuts()
                listError = nil
            } catch {
                listError = (error as? ShortcutError)?.message ?? ShortcutError.couldntList.message
            }
        }
    }

    private func shortcutRow(_ title: String, keyPath: WritableKeyPath<TimerSettings, String?>) -> some View {
        let selected = controller.settings[keyPath: keyPath]
        return LabeledContent(title) {
            HStack(spacing: Spacing.s) {
                Picker(title, selection: Binding(
                    get: { selected ?? "" },
                    set: { name in controller.updateSettings { $0[keyPath: keyPath] = name.isEmpty ? nil : name } }
                )) {
                    Text("None").tag("")
                    if let selected, !names.contains(selected) {
                        Text(selected).tag(selected)
                    }
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Test") { test(selected) }
                    .disabled(selected == nil || isTesting)
                    .accessibilityLabel("Test “\(title)” shortcut")
            }
        }
    }

    private func test(_ name: String?) {
        guard let name else { return }
        isTesting = true
        testResult = "Running “\(name)”…"
        testFailed = false
        Task {
            let error = await controller.testShortcut(name)
            testResult = error ?? "“\(name)” ran."
            testFailed = error != nil
            isTesting = false
        }
    }
}

/// "Pause or resume      ⌘P" (read-only list of in-window shortcuts).
private struct KeyRow: View {
    let title: String
    let keys: String

    var body: some View {
        LabeledContent(title) {
            // The system font, like menus show shortcuts (monospaced key glyphs didn't line up).
            Text(keys)
                .foregroundStyle(.secondary)
        }
    }
}

/// The categories: colour, name, reorder by dragging, add and delete.
private struct CategoriesTab: View {
    static let rowHeight: CGFloat = 28
    /// The plain list's own vertical row insets (measured: 36 pt pitch for 28 pt rows).
    static let rowGap: CGFloat = Spacing.s
    static let visibleRows = 8

    let controller: FocusController
    @State private var pendingDelete: FocusCore.Category?

    var body: some View {
        SettingsForm {
            Section {
                if controller.settings.categories.isEmpty {
                    Text("No categories. Add one to colour your sessions and compare them in Stats.")
                        .foregroundStyle(.secondary)
                } else {
                    // A list (for drag to reorder) sized to its rows, so the section has no
                    // empty block under the last category.
                    List {
                        ForEach(controller.settings.categories) { category in
                            CategoryRow(controller: controller, category: category) { pendingDelete = category }
                                .frame(height: Self.rowHeight)
                                // The form draws the line above Add Category; the list's own
                                // full-width one under the last row doubled it.
                                .listRowSeparator(category.id == controller.settings.categories.last?.id ? .hidden : .automatic,
                                                  edges: .bottom)
                        }
                        .onMove { controller.moveCategories(from: $0, to: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(controller.settings.categories.count <= Self.visibleRows)
                    .frame(height: CGFloat(min(controller.settings.categories.count, Self.visibleRows)) * (Self.rowHeight + Self.rowGap))
                }
                HStack {
                    Button {
                        let used = Set(controller.settings.categories.map(\.color))
                        let color = CategoryColor.allCases.first { $0 != .accent && !used.contains($0) } ?? .blue
                        controller.addCategory(name: "New Category", color: color)
                    } label: {
                        Label("Add Category", systemImage: "plus")
                    }
                    Spacer()
                }
            } footer: {
                Text("Type @ and a name in the intention to pick a category, like “Draft intro @work”. Drag to reorder. Deleting a category keeps its name on past sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { category in
            Button("Delete", role: .destructive) { controller.deleteCategory(id: category.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Past sessions keep the name. New sessions won't use it.")
        }
    }
}

private struct CategoryRow: View {
    let controller: FocusController
    let category: FocusCore.Category
    let onDelete: () -> Void
    @State private var name = ""
    @State private var choosingColor = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            Button {
                choosingColor = true
            } label: {
                Circle().fill(category.color.color).frame(width: 14, height: 14)
                    .hairlineBorder(Circle())
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colour of \(category.name): \(category.color.title)")
            .help("Colour")
            .popover(isPresented: $choosingColor, arrowEdge: .bottom) {
                ColorGrid(selected: category.color) { color in
                    var changed = category
                    changed.color = color
                    controller.updateCategory(changed)
                    choosingColor = false
                }
            }
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .accessibilityLabel("Name of \(category.name)")
                .onSubmit(commit)
                .onAppear { name = category.name }
                .onChange(of: category.name) { name = category.name }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(category.name)")
            .help("Delete")
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard name != category.name else { return }
        var changed = category
        changed.name = name
        controller.updateCategory(changed)
    }
}

/// The category colours as a grid of swatches.
private struct ColorGrid: View {
    let selected: CategoryColor
    let pick: (CategoryColor) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: Spacing.s), count: 7), spacing: Spacing.s) {
            ForEach(CategoryColor.allCases, id: \.self) { color in
                Button { pick(color) } label: {
                    // Selected: a ring around the swatch (a white checkmark vanished on yellow).
                    Circle().fill(color.color)
                        .frame(width: 18, height: 18)
                        .hairlineBorder(Circle())
                        .frame(width: 24, height: 24)
                        .overlay {
                            if color == selected {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(color == selected ? .isSelected : [])
                .help(color.title)
            }
        }
        .padding(Spacing.m)
    }
}

/// Apps to hide while focusing.
private struct HideAppsTab: View {
    let controller: FocusController
    @State private var selection: String?

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: setting(controller, \.hideApps)) {
                    Text("Hide distracting apps during focus sessions")
                    Text("Apps on the list are hidden when a session starts, and again if you switch to one. Nothing is quit. Breaks and pauses leave them alone.")
                }
            }
            Section("Apps") {
                if controller.settings.blockedApps.isEmpty {
                    Text("No apps yet. Add the ones that pull you away, like chat or social apps.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.settings.blockedApps) { app in
                        HStack(spacing: Spacing.s) {
                            Image(nsImage: AppIcons.icon(for: app.bundleID))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text(app.name)
                            Spacer()
                            Button {
                                controller.removeBlockedApp(bundleID: app.bundleID)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(app.name)")
                            .help("Remove")
                        }
                    }
                }
                Button {
                    AppIcons.choose().forEach { controller.addBlockedApp($0) }
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
            }
            .disabled(!controller.settings.hideApps)
        }
    }
}

/// App names and icons for the hide list.
@MainActor
enum AppIcons {
    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    /// An open panel in /Applications for picking apps.
    static func choose() -> [BlockedApp] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose apps to hide while you focus."
        AppActivation.activate()
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return BlockedApp(bundleID: id, name: name)
        }
    }
}
