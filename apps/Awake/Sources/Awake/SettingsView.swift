import AppKit
import AwakeCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings: General, Triggers, Shortcuts, Advanced, About. Built from SlopKit's pieces
/// (`GeneralSettingsTab`, `SettingsForm`, `ShortcutRow`, `AboutSettingsTab`) because
/// `SlopSettings` has no slot for an extra tab.
struct AwakeSettingsView: View {
    @Bindable var app: AppController
    let controller: AwakeController
    @Bindable var preferences: AwakePreferences

    var body: some View {
        TabView(selection: $app.settingsTab) {
            GeneralSettingsTab(isMenuBarApp: true, appName: app.info.name) {
                GeneralRows(preferences: preferences)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general)

            TriggersTab(controller: controller, preferences: preferences)
                .tabItem { Label("Triggers", systemImage: "bolt") }
                .tag(SettingsTab.triggers)

            SettingsForm {
                Section {
                    ShortcutRow("Turn Awake on or off", name: .toggleAwake)
                } footer: {
                    FooterText("Works from any app. Turns on for the default duration.")
                }
            }
            .tabItem { Label("Shortcuts", systemImage: "command") }
            .tag(SettingsTab.shortcuts)

            AdvancedTab(controller: controller, preferences: preferences)
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(SettingsTab.advanced)

            AboutSettingsTab(info: app.info)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: Metrics.settingsWidth)
    }
}

private struct GeneralRows: View {
    @Bindable var preferences: AwakePreferences

    var body: some View {
        Toggle("Turn on when Awake opens", isOn: $preferences.activateAtLaunch)
        Picker("Default duration", selection: $preferences.defaultDuration) {
            ForEach(AwakeDuration.presets) { Text($0.title).tag($0) }
            if !AwakeDuration.presets.contains(preferences.defaultDuration) {
                Text(preferences.defaultDuration.title).tag(preferences.defaultDuration)
            }
        }
        Picker(selection: $preferences.leftClick) {
            Text("Turns Awake on or off").tag(ClickAction.toggle)
            Text("Opens the menu").tag(ClickAction.openMenu)
        } label: {
            Text("Clicking the menu bar icon")
            Text(preferences.leftClick == .toggle
                 ? "Right-click or Control-click it for the menu."
                 : "Right-click or Control-click it to turn Awake on or off.")
        }
    }
}

private struct TriggersTab: View {
    let controller: AwakeController
    @Bindable var preferences: AwakePreferences

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Keep awake automatically", isOn: $preferences.triggersEnabled)
            } footer: {
                FooterText(footer)
            }

            Section("While an app is running") {
                if preferences.triggerApps.isEmpty {
                    Text("No apps yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(preferences.triggerApps) { ref in
                    HStack(spacing: Spacing.s) {
                        AppIconView(bundleID: ref.bundleID)
                        // The name and "Running" share a baseline, not a centre line.
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Text(ref.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if controller.runningApps.contains(where: { $0.bundleID == ref.bundleID }) {
                                Text("Running")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        Spacer(minLength: Spacing.s)
                        Button {
                            preferences.removeTriggerApp(bundleID: ref.bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(ref.name)")
                        .accessibilityLabel("Remove \(ref.name)")
                    }
                }
                AddAppMenu(controller: controller, preferences: preferences)
            }
            .disabled(!preferences.triggersEnabled)

            Section("Conditions") {
                Toggle("While connected to a power adapter", isOn: $preferences.triggerOnPowerAdapter)
                Toggle("While an external display is connected", isOn: $preferences.triggerOnExternalDisplay)
            }
            .disabled(!preferences.triggersEnabled)
        }
    }

    private var footer: String {
        if controller.isTriggerHolding, let reason = controller.activeTriggers.first {
            return "On now, because \(reason.phrase)."
        }
        if controller.triggersPaused {
            return "Paused because you turned Awake off. Triggers apply again once their conditions change."
        }
        return "Awake turns on while any of these is true, and off when none is. Turning Awake off pauses triggers until their conditions change."
    }
}

private struct AddAppMenu: View {
    let controller: AwakeController
    let preferences: AwakePreferences

    var body: some View {
        let added = Set(preferences.triggerApps.map(\.bundleID))
        let running = controller.runningApps
            .filter { !added.contains($0.bundleID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        Menu("Add App") {
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running) { ref in
                        Button(ref.name) { preferences.addTriggerApp(ref) }
                    }
                }
            }
            Button("Choose from Applications…") { chooseApp() }
        }
        .menuStyle(.button)
        .fixedSize()
        // Trailing, like every other control in the form.
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            preferences.addTriggerApp(AppRef(bundleID: id, name: name))
        }
    }
}

private struct AppIconView: View {
    let bundleID: String

    var body: some View {
        if let icon = AppIcons.icon(for: bundleID, size: 20) {
            Image(nsImage: icon)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct AdvancedTab: View {
    let controller: AwakeController
    @Bindable var preferences: AwakePreferences

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: Binding(
                    get: { !preferences.keepDisplayOn }, set: { preferences.keepDisplayOn = !$0 }
                )) {
                    Text("Allow display to sleep")
                    Text("The Mac stays awake but the screen can turn off. Good for downloads and builds.")
                }
                Toggle(isOn: $preferences.allowSleepWhenLocked) {
                    Text("Allow sleep while the screen is locked")
                    Text("Awake carries on when you unlock.")
                }
            }

            Section {
                Group {
                    Toggle("Turn off when switching to battery", isOn: $preferences.stopOnSwitchToBattery)
                    Toggle("Turn off when the battery is low", isOn: $preferences.stopOnLowBattery)
                    Picker("Low battery level", selection: $preferences.lowBatteryThreshold) {
                        ForEach(AwakePreferences.lowBatteryChoices, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .disabled(!preferences.stopOnLowBattery)
                }
                .disabled(!controller.power.hasBattery)
            } header: {
                Text("Battery")
            } footer: {
                // Outside the disabled group, so it reads at full secondary contrast.
                if !controller.power.hasBattery {
                    FooterText("This Mac has no battery, so these don't apply.")
                }
            }

            Section("Menu bar") {
                Toggle("Show time left next to the icon", isOn: $preferences.showTimeInMenuBar)
                Toggle("Dim the icon while off", isOn: $preferences.dimIconWhenOff)
            }
        }
    }
}

/// A Settings section footer: caption, secondary, leading-aligned like System Settings.
private struct FooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
