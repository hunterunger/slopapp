import AppKit
import FocusCore
import SlopKit
import SwiftUI

enum SettingsTab: String {
    case general, timer, shortcuts, automation, about

    static let storageKey = "settingsTab"

    /// Picks the tab the Settings window shows (now if open, or when it opens).
    static func select(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: storageKey)
    }
}

/// General, Timer, Shortcuts, Automation, About. Built from SlopKit's pieces rather than
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

            SettingsForm {
                ShortcutRow("Start or pause", name: .startPause)
                Text("Starts a focus session, or pauses and resumes the one that's running. Works from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: Metrics.settingsWidth)
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
