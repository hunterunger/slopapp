import AppKit
import ClipsCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings: General, Shortcuts, Privacy, About. Clips needs a custom Privacy tab, so it
/// composes SlopKit's tabs instead of using `SlopSettings`.
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        TabView {
            GeneralSettingsTab(isMenuBarApp: true, appName: info.name) {
                GeneralRows(model: model)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            SettingsForm { ShortcutRows() }
                .tabItem { Label("Shortcuts", systemImage: "command") }

            PrivacyTab(model: model)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }

            AboutSettingsTab(info: info)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
        .task {
            // Live permission status while Settings is open.
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - General

private struct GeneralRows: View {
    @Bindable var model: AppModel
    @State private var pendingRetention: HistoryRetention?

    var body: some View {
        Toggle("Paste into the app you were using", isOn: $model.pasteDirectly)
        if model.pasteDirectly {
            if model.hasAccessibility {
                Label {
                    Text("Accessibility is allowed")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.callout)
            } else {
                LabeledContent {
                    Button("Open System Settings") { Permission.accessibility.request() }
                } label: {
                    Text("Clips needs Accessibility to press ⌘V for you. Until then, Return copies the clip.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("Return copies the clip. Press ⌘V to paste it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Toggle("Always paste as plain text", isOn: $model.alwaysPlainText)

        Picker("Keep clips for", selection: Binding(
            get: { model.retention },
            set: { newValue in
                if model.clipsRemoved(by: newValue) > 0 {
                    pendingRetention = newValue
                } else {
                    model.retention = newValue
                }
            }
        )) {
            ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(
            get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } }
        )) {
            Button("Remove Clips", role: .destructive) {
                if let pendingRetention { model.retention = pendingRetention }
                pendingRetention = nil
            }
            Button("Cancel", role: .cancel) { pendingRetention = nil }
        } message: {
            Text("Pinned clips are kept. You can't undo this.")
        }
        LabeledContent("History") {
            HStack(spacing: Spacing.s) {
                Text(model.history.clips.count == 1 ? "1 clip" : "\(model.history.clips.count.formatted()) clips")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Clear History…") { ClearHistory.confirm(model: model) }
                    .disabled(model.history.clips.allSatisfy(\.isPinned))
            }
        }
        if let error = model.storageError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private var confirmTitle: String {
        guard let pendingRetention else { return "" }
        let count = model.clipsRemoved(by: pendingRetention)
        let clips = count == 1 ? "1 clip" : "\(count.formatted()) clips"
        return "Remove \(clips) older than \(pendingRetention.title.lowercased())?"
    }
}

// MARK: - Shortcuts

private struct ShortcutRows: View {
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .showClips)

    var body: some View {
        LabeledContent("Show Clips") {
            KeyboardShortcuts.Recorder(for: .showClips) { shortcut = $0 }
        }
        ForEach(warnings, id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("Press the shortcut in any app to search your clips. You can also open Clips from its menu bar icon.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var warnings: [String] {
        guard let shortcut else {
            return ["No shortcut set. Open Clips from the menu bar icon, or record a shortcut above."]
        }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        var result = KnownShortcutOwner.conflicts(for: shortcut.description, runningBundleIDs: running).map {
            "\($0.name) is running and uses \(shortcut.description) unless you changed it. If both apps use it, only one will respond. Pick another shortcut here or in \($0.name)."
        }
        if let advice = ShortcutAdvice.appConflict(for: shortcut.description) {
            result.append(advice + " Pick another one.")
        }
        return result
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @Bindable var model: AppModel
    @State private var selection: String?

    var body: some View {
        SettingsForm {
            Section {
                Label("Passwords and anything else an app marks as private are never recorded.", systemImage: "lock")
                    .fixedSize(horizontal: false, vertical: true)
                Label("Your history stays on this Mac. Clips never connects to the internet.", systemImage: "internaldrive")
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Hide Clips from screen sharing and recordings", isOn: $model.hideFromScreenSharing)
            }
            .symbolRenderingMode(.hierarchical)

            Section {
                List(selection: $selection) {
                    ForEach(model.ignoredApps) { app in
                        HStack(spacing: Spacing.s) {
                            if let icon = AppIcons.icon(for: app.bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                                    .accessibilityHidden(true)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 18, height: 18)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            Text(app.name)
                            if AppIcons.icon(for: app.bundleID) == nil {
                                Text("Not installed").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tag(app.bundleID)
                    }
                }
                .frame(height: 170)
                .onDeleteCommand(perform: removeSelected)
                HStack(spacing: Spacing.s) {
                    Menu {
                        Button("Choose App…") { chooseApp() }
                        let running = runningApps
                        if !running.isEmpty {
                            Divider()
                            ForEach(running, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                    if let url = app.bundleURL { model.ignore(appAt: url) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 16, height: 16)
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Add App")
                    .help("Add an app")
                    Button(action: removeSelected) {
                        Image(systemName: "minus")
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .disabled(selection == nil)
                    .accessibilityLabel("Remove App")
                    .help("Remove the selected app")
                    Spacer()
                    Button("Restore Defaults") { model.ignoredApps = IgnoredApp.presets }
                        .disabled(model.ignoredApps == IgnoredApp.presets)
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Nothing you copy in these apps is recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard access") {
                switch model.clipboardAccess {
                case .allowed:
                    Label {
                        Text("macOS lets Clips read the clipboard")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                case .asks, .denied:
                    LabeledContent {
                        Button("Open System Settings") { ClipboardAccess.openSettings() }
                    } label: {
                        Text(model.clipboardAccess == .asks
                             ? "macOS asks before Clips reads each copy. Allow Clips under Paste from Other Apps."
                             : "macOS blocks Clips from reading the clipboard. Allow Clips under Paste from Other Apps.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var runningApps: [NSRunningApplication] {
        let ignored = Set(model.ignoredApps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !ignored.contains($0.bundleIdentifier!)
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func removeSelected() {
        guard let selection else { return }
        model.ignoredApps.removeAll { $0.bundleID == selection }
        self.selection = nil
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { model.ignore(appAt: url) }
        }
    }
}
