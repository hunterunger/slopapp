import AppKit
import DictateCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility + overlay (the recording ring) + small windows for history,
// file transcription and setup. See docs/design-system.md, section 2.

@main
struct DictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey, store: Diagnostics.defaults) private var showMenuBarIcon = true
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            DictateMenu(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Dictation History", id: WindowOpener.Kind.history.rawValue) {
            HistoryWindow(model: model)
        }
        .defaultSize(width: 620, height: 520)
        .defaultPosition(.leading)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)

        Window("Transcribe Audio Files", id: WindowOpener.Kind.files.rawValue) {
            FileTranscriptionWindow(model: model, files: model.files)
        }
        .defaultSize(width: 620, height: 480)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)

        Window("Set Up Dictate", id: WindowOpener.Kind.onboarding.rawValue) {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model)
        }
        .commands {
            DictationCommands(model: model)
            HelpCommands(info: model.info)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let slop = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        slop.applicationWillFinishLaunching(notification)
        // Edit › Start Dictation… is macOS's own dictation: confusing next to Dictate's
        // Dictation menu. Registered (in memory only), so nothing is written to settings.
        UserDefaults.standard.register(defaults: ["NSDisabledDictationMenuItem": true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.launch()
    }

    /// Opened again (Finder, Spotlight): bring the icon back and open Settings, the way in
    /// when the icon is out of sight.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        defer { AppModel.shared.menuBarPresence.check(after: .seconds(1)) }
        guard Diagnostics.isTestMode, Diagnostics.sharesInstalledAppsDomain else {
            return slop.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
        }
        // A test copy sharing the installed app's domain: same as SlopKit's, but the icon
        // setting lives in the test domain so the installed copy's is never touched.
        Diagnostics.defaults.set(true, forKey: MenuBarIcon.storageKey)
        if !flag {
            DispatchQueue.main.async {
                guard !NSApp.windows.contains(where: { $0.isVisible && $0.level == .normal && !($0 is NSPanel) }) else { return }
                SettingsWindow.open()
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Windows closing after this are the app quitting, not the person closing them.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.isTerminating = true
        return .terminateNow
    }

    /// Audio files opened with Dictate (Open With, dropped on the icon) get transcribed.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.files.add(urls)
        WindowOpener.open(.files)
    }
}

/// The menu bar icon. It exists from launch, so it's where SwiftUI's window and Settings
/// actions are captured for code outside views (test hooks, the app delegate).
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel(accessibilityLabel)
            .onAppear {
                WindowOpener.action = { openWindow(id: $0.rawValue) }
                SettingsNavigation.openAction = { openSettings() }
                model.menuBarPresence.check(after: .seconds(3))
            }
    }

    private var symbol: String {
        switch model.controller.phase {
        case .recording: "mic.fill"
        case .transcribing, .polishing, .editing, .inserting: "waveform"
        case .error: "exclamationmark.triangle"
        case .idle: "mic"
        }
    }

    private var accessibilityLabel: String {
        switch model.controller.phase {
        case .recording: "Dictate, listening"
        case .transcribing, .polishing, .editing, .inserting: "Dictate, working"
        case .error: "Dictate, something went wrong"
        case .idle: "Dictate"
        }
    }
}

/// Status line → main actions → options → footer (Settings…, About, Report a Problem…, Quit).
struct DictateMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var controller: DictationController { model.controller }

    var body: some View {
        Text(DictationStatus.text(model: model))
        if let fix = controller.problemFix ?? setupFix {
            Button(ProblemFix.menuTitle(fix)) { model.fix(fix) }
        }
        Divider()

        StartStopItems(controller: controller)
        Button("Transcribe Audio Files…") {
            WindowOpener.action = { openWindow(id: $0.rawValue) }
            WindowOpener.open(.files)
            model.files.choose()
        }
        .keyboardShortcut("o")
        Divider()

        if !controller.lastTranscript.isEmpty {
            Button("Copy Last Transcript") { model.copyLastTranscript() }
            Button("Paste Last Transcript") { model.pasteLastTranscript() }
        }
        Button("Open History") {
            WindowOpener.action = { openWindow(id: $0.rawValue) }
            WindowOpener.open(.history)
        }
        .keyboardShortcut("y")
        Button("Setup Assistant…") {
            WindowOpener.action = { openWindow(id: $0.rawValue) }
            WindowOpener.open(.onboarding)
        }

        MenuFooter(info: model.info)
    }

    /// A problem that isn't an error yet: no model, so nothing will work.
    private var setupFix: ProblemFix? {
        model.models.state == .notInstalled ? .downloadModel : nil
    }

}

/// The status line at the top of the menus.
enum DictationStatus {
    static func text(model: AppModel) -> String {
        let controller = model.controller
        switch controller.phase {
        case .recording: return controller.mode == .command ? "Listening for an edit…" : "Listening…"
        case .transcribing: return "Transcribing…"
        case .polishing: return "Polishing…"
        case .editing: return "Rewriting the selection…"
        case .inserting: return "Typing…"
        case .error(let message): return message
        case .idle: break
        }
        let models = model.models
        switch models.state {
        case .notInstalled: return "No speech model yet"
        case .downloading(let fraction):
            let percent = fraction.map { " \(Int($0 * 100))%" } ?? ""
            return "Downloading \(models.selected.name)…\(percent)"
        case .failed: return "\(models.selected.name) didn't load"
        case .loading, .unloaded, .ready: break
        }
        return "Ready. \(TriggerHint.text(for: model.settings))"
    }
}

/// Start/Stop and Cancel, in the menu bar menu and the Dictation menu.
struct StartStopItems: View {
    let controller: DictationController

    var body: some View {
        if controller.isRecording {
            Button("Stop Dictation") { controller.end() }
        } else {
            Button("Start Dictation") { controller.begin(.dictation) }
                .disabled(controller.isBusy)
        }
        if controller.isBusy {
            Button("Cancel Dictation") { controller.cancel() }
        }
    }
}

/// The app's own menus, shown while one of its windows is in front: a Dictation menu with
/// everything the menu bar icon offers (the way in when the icon is hidden), and the
/// Transcribe window's file commands.
struct DictationCommands: Commands {
    let model: AppModel
    @FocusedValue(\.transcriptActions) private var transcript

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            TranscribeFilesItem(files: model.files)
        }
        CommandGroup(after: .newItem) {
            Button("Save Transcript…") { transcript?.save() }
                .keyboardShortcut("s")
                .disabled(transcript?.canSave != true)
        }
        CommandMenu("Dictation") {
            DictationMenuItems(model: model)
        }
    }
}

struct TranscribeFilesItem: View {
    let files: FileTranscriber
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Transcribe Audio Files…") {
            WindowOpener.action = { openWindow(id: $0.rawValue) }
            WindowOpener.open(.files)
            files.choose()
        }
        .keyboardShortcut("o")
    }
}

struct DictationMenuItems: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(DictationStatus.text(model: model))
        if let fix = model.controller.problemFix ?? (model.models.state == .notInstalled ? .downloadModel : nil) {
            Button(ProblemFix.menuTitle(fix)) { model.fix(fix) }
        }
        Divider()
        StartStopItems(controller: model.controller)
        Divider()
        Button("Copy Last Transcript") { model.copyLastTranscript() }
            .disabled(model.controller.lastTranscript.isEmpty)
        Button("Open History") { open(.history) }
            .keyboardShortcut("y")
        Button("Setup Assistant…") { open(.onboarding) }
    }

    private func open(_ kind: WindowOpener.Kind) {
        WindowOpener.action = { openWindow(id: $0.rawValue) }
        WindowOpener.open(kind)
    }
}

extension ProblemFix {
    static func menuTitle(_ fix: ProblemFix) -> String {
        switch fix {
        case .downloadModel: "Download a Speech Model…"
        case .microphoneSettings: "Open Microphone Settings…"
        case .accessibilitySettings: "Open Accessibility Settings…"
        }
    }
}

/// How to start a dictation, in words.
enum TriggerHint {
    /// "hold Fn", "press ⌃⌥Space"
    static func action(for settings: DictateSettings) -> String {
        let verb = settings.hotkeyMode == .toggle ? "press" : "hold"
        switch settings.triggerKind {
        case .function: return "\(verb) Fn"
        case .custom:
            guard let shortcut = KeyboardShortcuts.getShortcut(for: .record) else { return "use your shortcut" }
            return "\(verb) \(shortcut.description)"
        }
    }

    static func text(for settings: DictateSettings) -> String {
        let key: String
        switch settings.triggerKind {
        case .function: key = "Fn"
        case .custom:
            guard let shortcut = KeyboardShortcuts.getShortcut(for: .record) else { return "Set a shortcut in Settings." }
            key = shortcut.description
        }
        switch settings.hotkeyMode {
        case .pushToTalk, .holdOrTap: return "Hold \(key) to dictate."
        case .toggle: return "Press \(key) to dictate."
        }
    }
}

/// Opens Dictate's windows from anywhere (menus, test hooks, the app delegate).
enum WindowOpener {
    enum Kind: String {
        case history, files, onboarding
    }

    static var action: ((Kind) -> Void)?

    /// `force: false` asks politely (launch time): macOS may leave the app in front alone.
    static func open(_ kind: Kind, force: Bool = true) {
        if Diagnostics.quiet {
            action?(kind)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.windows.first { $0.identifier?.rawValue == kind.rawValue }?.orderBack(nil)
            }
            return
        }
        if force { AppActivation.activate() } else { NSApp.activate() }
        if let action {
            action(kind)
        } else {
            // The menu bar icon (where the action is captured) may be hidden: retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { action?(kind) }
        }
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.identifier?.rawValue == kind.rawValue }
            window?.makeKeyAndOrderFront(nil)
        }
    }
}
