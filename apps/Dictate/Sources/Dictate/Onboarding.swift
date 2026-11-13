import AppKit
import DictateCore
import SlopKit
import SwiftUI

/// The setup assistant: welcome (and import from the previous app), microphone,
/// accessibility, a speech model, the shortcut, then a place to try it.
struct OnboardingView: View {
    let model: AppModel
    @State private var step = Step.welcome
    @State private var legacy: LegacySources?
    @State private var imported: ImportSummary?
    @State private var legacyRunning = false
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool
    @Environment(\.dismissWindow) private var dismissWindow

    enum Step: Int, CaseIterable {
        case welcome, microphone, accessibility, model, shortcut, tryIt
    }

    var body: some View {
        VStack(spacing: 0) {
            // Each step sits in the middle of the space above the footer, so short steps
            // don't leave the bottom half of the window empty.
            content
                .padding(.horizontal, Spacing.xxl * 2)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            Hairline()
            footer
                .padding(Spacing.xl)
        }
        .frame(width: 580, height: 520)
        .background {
            // Esc closes the assistant, like ⌘W (the window has no focusable view to take
            // an exit command, so a cancel-action key equivalent does it).
            Button("Close Setup Assistant") { dismissWindow(id: WindowOpener.Kind.onboarding.rawValue) }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            legacy = model.legacySources
            imported = LegacyImport.lastSummary(in: model.store)
            legacyRunning = Self.legacyIsRunning
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            // Closed by the person (not app shutdown): don't show it again at launch.
            guard (note.object as? NSWindow)?.identifier?.rawValue == WindowOpener.Kind.onboarding.rawValue,
                  !model.isTerminating else { return }
            model.settings.hasCompletedOnboarding = true
            model.models.warmUp()
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .microphone: microphone
        case .accessibility: accessibility
        case .model: speechModel
        case .shortcut: shortcut
        case .tryIt: tryIt
        }
    }

    // MARK: Steps

    private var welcome: some View {
        StepLayout(image: .app, title: "Welcome to Dictate",
                   subtitle: "Hold Fn, speak, let go: your words appear wherever you're typing. Speech becomes text right here on your Mac, and nothing is sent anywhere.") {
            if let imported {
                Callout(symbol: "checkmark.circle.fill", tint: .green) {
                    Text("Brought over from \(LegacyLocations.appName)").font(.headline)
                    Text(importText(imported))
                }
            } else if legacy != nil {
                Callout(symbol: "arrow.down.doc", tint: .accentColor) {
                    Text("\(LegacyLocations.appName) is on this Mac").font(.headline)
                    Text("Dictate can bring over its settings, replacements, per-app rules, history and downloaded models. Nothing in \(LegacyLocations.appName) changes, and models aren't copied twice.")
                    Button("Bring Them Over") {
                        imported = model.importLegacy()
                        legacy = nil
                        // Compile the model for this Mac now, not on the first dictation.
                        model.models.warmUp()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Spacing.xs)
                }
            }
            if imported != nil || legacy != nil || legacyRunning {
                Text("macOS asks again for Microphone and Accessibility, because Dictate is a new app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if legacyRunning {
                HStack(spacing: Spacing.s) {
                    Text("Quit \(LegacyLocations.appName) so one Fn press doesn't dictate twice.")
                        .font(.callout)
                    Button("Quit It") {
                        NSRunningApplication.runningApplications(withBundleIdentifier: LegacyLocations.bundleID)
                            .forEach { $0.terminate() }
                        legacyRunning = false
                    }
                }
            }
        }
    }

    private var microphone: some View {
        let granted = model.microphoneStatus == .granted
        return StepLayout(image: .symbol(granted ? "checkmark.circle.fill" : "mic", granted ? .green : .accentColor),
                          title: "Microphone",
                          subtitle: "Dictate needs the microphone to hear you. Audio is turned into text on this Mac and never saved or uploaded.") {
            if granted {
                Label("Microphone allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.textGreen)
            } else if model.microphoneStatus == .undetermined {
                Button("Allow Microphone") { Task { await model.requestMicrophone() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button("Open System Settings") { NSWorkspace.shared.open(AppModel.microphoneSettingsURL) }
                    .buttonStyle(.borderedProminent)
                Text("Turn on Dictate under Privacy & Security › Microphone, then come back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            // Granting happens in System Settings; follow it while this step is open.
            while !Task.isCancelled, model.microphoneStatus != .granted {
                try? await Task.sleep(for: .seconds(1))
                model.refreshPermissions()
            }
        }
    }

    private var accessibility: some View {
        let granted = model.accessibilityGranted
        return StepLayout(image: .symbol(granted ? "checkmark.circle.fill" : "accessibility", granted ? .green : .accentColor),
                          title: "Accessibility",
                          subtitle: "Dictate needs Accessibility to type your words into other apps and to notice the Fn key. It doesn't read what's on your screen.") {
            if granted {
                Label("Accessibility allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.textGreen)
            } else {
                Button("Open System Settings") { Permission.accessibility.request() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Turn on Dictate in the list, then come back. This updates by itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            while !Task.isCancelled, !model.accessibilityGranted {
                try? await Task.sleep(for: .seconds(1))
                model.refreshPermissions()
            }
        }
    }

    private var speechModel: some View {
        let models = model.models
        let selected = models.selected
        let installed = models.isInstalled(selected)
        return StepLayout(image: .symbol(installed ? "checkmark.circle.fill" : "waveform", installed ? .green : .accentColor),
                          title: installed ? "Speech Model Is Ready" : "Download a Speech Model",
                          subtitle: installed
                            ? "\(selected.name) is on this Mac already, so there's nothing to download. You can choose another in Settings › Models."
                            : "Dictate turns speech into text with a model that runs on your Mac (\(selected.name), \(selected.sizeText)). It downloads once from Hugging Face; this is the only time Dictate uses the internet.") {
            if !installed {
                if let progress = models.downloads[selected.key] {
                    ProgressView(value: progress ?? 0, total: 1)
                        .frame(width: 240)
                        .accessibilityLabel("Downloading \(selected.name)")
                    Text("Downloading \(selected.name)…").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Download Speech Model") { Task { await models.download(selected) } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    if let error = models.downloadErrors[selected.key] {
                        Text(error).font(.callout).foregroundStyle(.textRed).multilineTextAlignment(.center)
                    }
                    Button("Choose Another Model…") { SettingsNavigation.open(.models) }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private var shortcut: some View {
        @Bindable var settings = model.settings
        return StepLayout(image: .symbol("keyboard", .accentColor), title: "How You Start",
                          subtitle: "Hold the key while you talk and let go to finish, or switch to press to start, press to stop.") {
            Form {
                Picker("Start with", selection: $settings.triggerKind) {
                    ForEach(TriggerKind.allCases) { Text($0.displayName).tag($0) }
                }
                if settings.triggerKind == .custom {
                    ShortcutRow("Shortcut", name: .record)
                }
                Picker("Behavior", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { Text($0.displayName).tag($0) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: settings.triggerKind == .custom ? 150 : 110)
            if settings.triggerKind == .function {
                Text("Tip: set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var tryIt: some View {
        let controller = model.controller
        return StepLayout(image: .symbol("text.bubble", .accentColor), title: "Try It",
                          subtitle: "Click in the box, then \(TriggerHint.action(for: model.settings)) and say something. Or use the button.") {
            TextEditor(text: $practice)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(Spacing.s)
                .background(.background, in: RoundedRectangle(cornerRadius: Radius.m))
                .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m))
                .frame(height: 110)
                .focused($practiceFocused)
                .accessibilityLabel("Practice text")
            HStack(spacing: Spacing.m) {
                if controller.isRecording {
                    Button("Stop Dictation") { controller.end() }
                } else {
                    Button("Start Dictation") {
                        // The words go into the box: it has to be the focused field.
                        practiceFocused = true
                        controller.begin(.dictation)
                    }
                    .disabled(controller.isBusy)
                }
                Text(controller.isBusy ? DictationStatus.text(model: model) : "Press Esc while dictating to cancel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Everything else is in the menu bar icon, and in the Dictation menu while Dictate is in front.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Footer

    private var footer: some View {
        ZStack {
            PageDots(count: Step.allCases.count, current: step.rawValue)
            HStack {
                if step != .welcome {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                }
                Spacer()
                Button(step == .tryIt ? "Done" : "Continue") {
                    if let next = Step(rawValue: step.rawValue + 1) {
                        step = next
                    } else {
                        finish()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func finish() {
        model.settings.hasCompletedOnboarding = true
        model.models.warmUp()
        dismissWindow(id: WindowOpener.Kind.onboarding.rawValue)
    }

    private func importText(_ summary: ImportSummary) -> String {
        var parts: [String] = []
        if summary.settings > 0 { parts.append("your settings") }
        if summary.historyEntries > 0 {
            parts.append(summary.historyEntries == 1 ? "1 dictation" : "\(summary.historyEntries.formatted()) dictations")
        }
        if summary.models.count == 1 {
            parts.append("the \(summary.models[0]) model (no download needed)")
        } else if summary.models.count > 1 {
            parts.append("\(summary.models.count) speech models (no download needed)")
        }
        let list = parts.isEmpty ? "Nothing needed bringing over." : ListFormatter.localizedString(byJoining: parts).capitalizedFirst + "."
        return summary.problems.isEmpty ? list : list + " " + summary.problems.joined(separator: " ")
    }

    private static var legacyIsRunning: Bool {
        !Diagnostics.isTestMode
            && !NSRunningApplication.runningApplications(withBundleIdentifier: LegacyLocations.bundleID).isEmpty
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// One step: a picture, a title, a sentence, then the step's controls.
private struct StepLayout<Content: View>: View {
    enum Picture {
        case app
        case symbol(String, Color)
    }

    let image: Picture
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Spacing.l) {
            Group {
                switch image {
                case .app:
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                case .symbol(let name, let tint):
                    Image(systemName: name)
                        .font(.system(size: 48, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                }
            }
            .frame(height: 72)
            .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Spacing.m) { content }
                .padding(.top, Spacing.s)
        }
    }
}

/// A rounded, tinted box for news (the import).
private struct Callout<Content: View>: View {
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.l)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.l))
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Spacing.s - 2) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
