import AppKit
import ShorthandCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// General, Apps, Shortcuts, Advanced, About. Built from SlopKit's tab pieces because
/// Shorthand needs an extra Apps tab.
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                Toggle("Expand abbreviations", isOn: $model.isEnabled)
                Toggle(isOn: $model.wordStartOnly) {
                    Text("Only expand at the start of a word")
                    Text("After a space, punctuation or a new line, so “sig” doesn't fire inside “design”.")
                }
                Toggle(isOn: $model.undoWithBackspace) {
                    Text("Undo an expansion with Backspace")
                    Text("Pressing Backspace straight after a typed expansion puts the abbreviation back.")
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            AppsTab(model: model)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }

            SettingsForm {
                ShortcutRow("Insert a snippet", subtitle: "Search all your snippets and insert one where you're typing.", name: .searchSnippets)
                ShortcutRow("Pause or resume expansion", name: .togglePause)
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }

            AdvancedTab(model: model)
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }

            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
    }
}

/// "Don't expand in": password managers and Shorthand by default. While one is in front,
/// keys aren't even buffered.
struct AppsTab: View {
    @Bindable var model: AppModel
    @State private var selection: Exclusions.App.ID?

    var body: some View {
        SettingsForm {
            Section {
                List(selection: $selection) {
                    ForEach(model.excludedApps) { app in
                        HStack(spacing: Spacing.s) {
                            AppIconView(bundleID: app.bundleID)
                            Text(app.name)
                            Spacer()
                            if app.bundleID == model.selfBundleID {
                                Text("Always").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                        .tag(app.id)
                    }
                }
                .frame(height: 180)
                .onDeleteCommand { removeSelected() }
                HStack(spacing: Spacing.s) {
                    Menu("Add App") {
                        ForEach(candidates, id: \.bundleID) { app in
                            Button(app.name) { add(app) }
                        }
                        if !candidates.isEmpty { Divider() }
                        Button("Choose…") { choose() }
                    }
                    .fixedSize()
                    Button("Remove") { removeSelected() }
                        .disabled(selection == nil || selection == model.selfBundleID)
                    Spacer()
                    Button("Restore Defaults") {
                        model.excludedApps = Exclusions.defaults(selfBundleID: model.selfBundleID)
                    }
                }
            } header: {
                Text("Don't expand in")
            } footer: {
                Text("While one of these apps is in front, Shorthand doesn't look at what you type. Password fields everywhere are already off limits: macOS hides them from every app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Running apps (or made-up ones in test mode) not on the list yet.
    private var candidates: [Exclusions.App] {
        let apps: [Exclusions.App]
        if Diagnostics.fakeApps {
            apps = [Exclusions.App(bundleID: "test.slopapp.terminal", name: "Example Terminal"),
                    Exclusions.App(bundleID: "test.slopapp.remote", name: "Example Remote Desktop"),
                    Exclusions.App(bundleID: "test.slopapp.game", name: "Example Game")]
        } else {
            apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return Exclusions.App(bundleID: id, name: name)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return apps.filter { app in !model.excludedApps.contains { $0.bundleID == app.bundleID } }
    }

    private func add(_ app: Exclusions.App) {
        model.excludedApps.append(app)
        selection = app.id
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app where abbreviations shouldn't expand."
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        guard !model.excludedApps.contains(where: { $0.bundleID == id }) else { return }
        add(Exclusions.App(bundleID: id, name: name))
    }

    private func removeSelected() {
        guard let selection, selection != model.selfBundleID else { return }
        model.excludedApps.removeAll { $0.bundleID == selection }
        self.selection = nil
    }
}

struct AppIconView: View {
    let bundleID: String

    var body: some View {
        Group {
            if !Diagnostics.fakeApps, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

struct AdvancedTab: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsForm {
            Section {
                Picker("Insert text by", selection: $model.insertMode) {
                    Text("Automatic").tag(InsertMode.automatic)
                    Text("Always pasting").tag(InsertMode.alwaysPaste)
                    Text("Always typing").tag(InsertMode.alwaysType)
                }
                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Put the clipboard back after pasting", isOn: $model.restoreClipboard)
                if model.restoreClipboard && model.pasteboardPrivacy != .allowed {
                    PrivacyNote(text: model.pasteboardPrivacy == .denied
                                ? "macOS doesn't let Shorthand read the clipboard, so pasted snippets stay on it."
                                : "macOS asks before Shorthand reads the clipboard, so pasted snippets stay on it for now.")
                }
            }
            Section {
                LabeledContent("Backups") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: model.store.backupsURL, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.backupsURL])
                    }
                }
                Text("Shorthand keeps a copy of your library each day, for the last 7 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { model.refreshPrivacy() }
    }

    private var modeExplanation: String {
        switch model.insertMode {
        case .automatic: "Short, single-line snippets are typed and leave the clipboard alone. Longer ones, and anything with several lines or a tab, are pasted."
        case .alwaysPaste: "Every snippet is pasted. Fast in every app, but uses the clipboard."
        case .alwaysType: "Every snippet is typed (formatted ones are still pasted). A new line is typed as Return, which sends the message in some chat apps."
        }
    }
}
