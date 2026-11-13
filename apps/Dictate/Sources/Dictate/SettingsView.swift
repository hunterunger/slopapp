import AppKit
import DictateCore
import ServiceManagement
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Opens Settings on a given tab, from anywhere.
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var tab: SettingsTab = Diagnostics.initialSettingsTab ?? .general
    @ObservationIgnored static var openAction: (() -> Void)?

    static func open(_ tab: SettingsTab) {
        shared.tab = tab
        if Diagnostics.quiet {
            openAction?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { SettingsWindow.window?.orderBack(nil) }
            return
        }
        if let openAction {
            AppActivation.activate()
            openAction()
            SettingsWindow.bringToFront()
        } else {
            SettingsWindow.open()
        }
    }
}

/// Settings: General, Shortcuts, Models, Cleanup, Apps, About.
struct SettingsView: View {
    let model: AppModel
    @Bindable private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralTab(model: model)
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(settings: model.settings)
                .tag(SettingsTab.shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "command") }
            ModelsTab(model: model, models: model.models)
                .tag(SettingsTab.models)
                .tabItem { Label("Models", systemImage: "waveform") }
            CleanupTab(model: model, settings: model.settings)
                .tag(SettingsTab.cleanup)
                .tabItem { Label("Cleanup", systemImage: "wand.and.sparkles") }
            AppsTab(settings: model.settings)
                .tag(SettingsTab.apps)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            AboutSettingsTab(info: model.info)
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Metrics.settingsWidth)
        .onAppear { model.refreshPermissions() }
    }
}

/// A grouped form that scrolls, for tabs taller than a screenful.
struct ScrollingSettingsForm<Content: View>: View {
    var height: CGFloat = 540
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(height: height)
    }
}

// MARK: - General

struct GeneralTab: View {
    let model: AppModel
    @State private var microphones: [MicrophoneDevice] = []
    @AppStorage(MenuBarIcon.storageKey, store: Diagnostics.defaults) private var showMenuBarIcon = true

    var body: some View {
        @Bindable var settings = model.settings
        SettingsForm {
            Section {
                if Diagnostics.protectsLoginItems {
                    Toggle(isOn: .constant(SMAppService.mainApp.status == .enabled)) {
                        Text("Launch at login")
                        Text("Can't be changed in a test copy, so the installed app's login item stays as it is.")
                    }
                    .disabled(true)
                } else {
                    LaunchAtLoginToggle()
                }
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("To bring the icon back, open \(model.info.name) again. Everything in its menu is also in the Dictation menu while \(model.info.name) is in front.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.menuBarPresence.isHidden {
                    Label {
                        Text("The icon is hidden right now: the menu bar is too full to show it. Remove or rearrange some icons (⌘-drag them), or use the Dictation menu while \(model.info.name) is in front. \(TriggerHint.text(for: settings))")
                    } icon: {
                        Image(systemName: "menubar.rectangle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Microphone", selection: $settings.preferredMicrophoneUID) {
                    Text("System Default").tag("")
                    ForEach(microphones) { Text($0.name).tag($0.uid) }
                    if !settings.preferredMicrophoneUID.isEmpty,
                       !microphones.contains(where: { $0.uid == settings.preferredMicrophoneUID }) {
                        // Keep the choice while it's unplugged; it's used again when it's back.
                        Text("Not Connected").tag(settings.preferredMicrophoneUID)
                    }
                }
                Toggle(isOn: $settings.autoInsert) {
                    Text("Type into the app you're using")
                    Text("Otherwise the text is copied, ready to paste.")
                }
                if settings.autoInsert {
                    Picker(selection: $settings.insertionMethod) {
                        ForEach(InsertionMethod.allCases) { Text($0.displayName).tag($0) }
                    } label: {
                        Text("Insert by")
                        Text(settings.insertionMethod == .paste
                             ? "Fast and works everywhere. Your clipboard is put back right after."
                             : "Types the words as keystrokes and never touches the clipboard. Slower for long text.")
                    }
                }
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle(isOn: $settings.showLivePreview) {
                    Text("Show words as you speak")
                    Text("They run around the recording ring.")
                }
                Toggle(isOn: $settings.saveHistory) {
                    Text("Keep a history of dictations")
                    Text("Stored only on this Mac.")
                }
            }
            PermissionsSection(model: model)
        }
        .onAppear {
            microphones = AudioDevices.inputDevices()
            model.menuBarPresence.check()
        }
        .onChange(of: showMenuBarIcon) { model.menuBarPresence.check(after: .seconds(1)) }
    }
}

/// Microphone and Accessibility status, with the way to fix each.
struct PermissionsSection: View {
    let model: AppModel

    var body: some View {
        Section {
            PermissionRow(
                title: "Microphone",
                detail: "Needed to hear you. Audio never leaves this Mac.",
                granted: model.microphoneStatus == .granted,
                action: model.microphoneStatus == .undetermined
                    ? ("Allow…", { () -> Void in Task { @MainActor in await model.requestMicrophone() } })
                    : ("Open System Settings…", { () -> Void in NSWorkspace.shared.open(AppModel.microphoneSettingsURL) }))
            PermissionRow(
                title: "Accessibility",
                detail: "Needed to type into other apps and to use the Fn key.",
                granted: model.accessibilityGranted,
                action: ("Open System Settings…", { Permission.accessibility.request() }))
            LabeledContent {
                Button("Open Setup Assistant…") { WindowOpener.open(.onboarding) }
            } label: {
                Text("Setup assistant")
                Text("Permissions, a speech model and your shortcut, step by step.")
            }
        } header: {
            Text("Permissions")
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: (title: String, run: () -> Void)

    var body: some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.textGreen)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(action.title, action: action.run)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsTab: View {
    @Bindable var settings: DictateSettings

    var body: some View {
        SettingsForm {
            Section {
                Picker(selection: $settings.triggerKind) {
                    ForEach(TriggerKind.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    Text("Start dictation with")
                    if settings.triggerKind == .function {
                        Text("Set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard, so Fn doesn't also open emoji. Needs Accessibility.")
                    }
                }
                if settings.triggerKind == .custom {
                    ShortcutRow("Dictation shortcut", subtitle: "A modifier and a key, like ⌃⌥Space.", name: .record)
                }
                Picker("Behavior", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Press Esc while dictating to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ShortcutRow("Command Mode",
                            subtitle: "Select text, then hold this and say an edit, like “make this friendlier” or “turn this into a list”. Uses Apple Intelligence on this Mac.",
                            name: .commandMode)
                ShortcutRow("Paste last transcript", subtitle: "Types your last dictation again where you are.",
                            name: .pasteLast)
            }
        }
    }
}

// MARK: - Apps

/// Per-app cleanup overrides.
struct AppsTab: View {
    @Bindable var settings: DictateSettings

    var body: some View {
        // Short while there's nothing to list, taller (and scrolling) once there is.
        ScrollingSettingsForm(height: settings.appCleanupRules.isEmpty ? 196 : 440) {
            Section {
                if settings.appCleanupRules.isEmpty {
                    Text("No apps yet. Add one to use different cleanup there, like no AI cleanup in your code editor.")
                        .foregroundStyle(.secondary)
                }
                ForEach($settings.appCleanupRules) { $rule in
                    AppRuleRow(rule: $rule) {
                        settings.appCleanupRules.removeAll { $0.id == rule.id }
                    }
                }
            } header: {
                Text("Per-app cleanup")
            } footer: {
                HStack {
                    Text("Apps not listed use the Cleanup settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add App…") { addApp() }
                }
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose an app to give its own cleanup settings."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        DispatchQueue.main.async { [settings] in
            settings.addRule(bundleID: bundleID, name: name, appPath: url.path)
        }
    }
}

struct AppRuleRow: View {
    @Binding var rule: AppCleanupRule
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: rule.appPath))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(rule.name.isEmpty ? rule.bundleID : rule.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Remove", role: .destructive, action: remove)
                    .buttonStyle(.borderless)
                    .help("Remove \(rule.name)")
            }
            OverrideRow(title: "AI cleanup", value: $rule.aiCleanup)
            OverrideRow(title: "Remove filler words", value: $rule.removeFillers)
            OverrideRow(title: "Lowercase start", value: $rule.lowercaseStyle)
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct OverrideRow: View {
    let title: String
    @Binding var value: OverrideValue

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Picker(title, selection: $value) {
                ForEach(OverrideValue.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
    }
}
