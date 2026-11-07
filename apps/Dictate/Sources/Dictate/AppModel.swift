import AppKit
import ApplicationServices
import DictateCore
import Observation
import SlopKit

/// Wires everything together and owns the app's state.
@Observable
final class AppModel {
    static let shared = AppModel()

    let info = AppInfo.current(fallbackName: "Dictate")
    @ObservationIgnored let store: UserDefaults = Diagnostics.defaults
    let settings: DictateSettings
    let history: HistoryStore
    let models: ModelHost
    let processor: TranscriptProcessor
    let controller: DictationController
    @ObservationIgnored let ai = AppleIntelligence()
    @ObservationIgnored let inserter = TextInserter()
    @ObservationIgnored let audio: AudioCapturing
    @ObservationIgnored let feedback: Feedback
    @ObservationIgnored let hotkeys: Hotkeys
    let files: FileTranscriber
    let supportDirectory: URL
    let modelsDirectory: URL

    /// Set when the app starts quitting: windows closing then weren't closed by the person.
    @ObservationIgnored var isTerminating = false

    /// Accessibility (typing into other apps, the Fn key). Re-checked when it matters.
    private(set) var accessibilityGranted = AXIsProcessTrusted()
    private(set) var microphoneStatus: MicrophoneStatus

    private init() {
        let support = Diagnostics.dataDirectory ?? ((try? AppPaths.applicationSupport)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("app.slopapp.dictate"))
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        supportDirectory = support
        modelsDirectory = Diagnostics.modelsDirectory ?? support.appendingPathComponent("Models", isDirectory: true)

        settings = DictateSettings(store: Diagnostics.defaults)
        history = HistoryStore(persistence: HistoryFile(url: support.appendingPathComponent("history.json")))
        models = ModelHost(
            engines: [.parakeet: ParakeetEngine(modelsRoot: modelsDirectory), .whisper: WhisperEngine(modelsRoot: modelsDirectory)],
            selected: settings.selectedModel, retention: settings.modelRetention,
            appleSilicon: Self.isAppleSilicon)
        processor = TranscriptProcessor(settings: settings, ai: ai)

        let microphone: MicrophoneAuthorizing
        if let fake = Diagnostics.fakeAudio {
            audio = FileAudioSource(url: fake)
            microphone = NoMicrophoneNeeded()
        } else {
            let recorder = AudioRecorder(microphoneUID: { [settings] in settings.preferredMicrophoneUID })
            audio = recorder
            microphone = SystemMicrophone()
        }
        microphoneStatus = microphone.status
        feedback = Feedback()
        controller = DictationController(
            audio: audio, models: models, delivery: inserter, processor: processor, microphone: microphone,
            frontApp: {
                let app = NSWorkspace.shared.frontmostApplication
                return app.map { FrontApp(bundleID: $0.bundleIdentifier, name: $0.localizedName) }
            },
            feedback: feedback, history: history, settings: settings)
        hotkeys = Hotkeys(settings: settings, controller: controller)
        files = FileTranscriber(models: models)
        feedback.attach(audio: audio, controller: controller)
        if let recorder = audio as? AudioRecorder {
            recorder.onInterruption = { [controller] in
                // The microphone went away: transcribe what was said so far.
                controller.end()
            }
        }
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    // MARK: Launch

    func launch() {
        let start = Diagnostics.now()
        // Smoke tests run the binary as a child of the terminal, which can pass on the
        // terminal's Accessibility and microphone grants: never listen for the trigger then.
        if !Diagnostics.noHotkey && !Diagnostics.isSmokeTest { hotkeys.start() }
        hotkeys.onPasteLast = { [weak self] in self?.pasteLastTranscript() }
        follow()
        if settings.modelRetention == .always {
            // Out of the launch path: menu bar icon first, model second.
            Task {
                try? await Task.sleep(for: .seconds(2))
                models.warmUp()
            }
        }
        if Diagnostics.testHooks { TestHooks.install(model: self) }
        if let file = Diagnostics.transcribeFile {
            TestHooks.transcribeHeadless(file, model: self)
            return
        }
        if (!settings.hasCompletedOnboarding && !Diagnostics.isSmokeTest) || Diagnostics.showOnboarding {
            // Next turn, so the scenes exist to open the window.
            DispatchQueue.main.async { WindowOpener.open(.onboarding, force: false) }
        } else if let tab = Diagnostics.initialSettingsTab {
            DispatchQueue.main.async { SettingsNavigation.open(tab) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        Diagnostics.record("launch ms=\(Diagnostics.milliseconds(since: start))")
    }

    /// Keeps the model host in step with settings.
    private func follow() {
        withObservationTracking {
            _ = settings.selectedModel
            _ = settings.modelRetention
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.models.retention = self.settings.modelRetention
                self.models.select(self.settings.selectedModel)
                self.follow()
            }
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
            // A global monitor started before the grant sees nothing until it's restarted.
            if trusted, !Diagnostics.noHotkey, !Diagnostics.isSmokeTest { hotkeys.refreshMonitor() }
        }
        if Diagnostics.fakeAudio == nil { microphoneStatus = SystemMicrophone().status }
    }

    func requestMicrophone() async {
        _ = await SystemMicrophone().request()
        refreshPermissions()
    }

    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    func fix(_ fix: ProblemFix) {
        switch fix {
        case .downloadModel: SettingsNavigation.open(.models)
        case .microphoneSettings: NSWorkspace.shared.open(Self.microphoneSettingsURL)
        case .accessibilitySettings: Permission.accessibility.request()
        }
    }

    // MARK: Actions

    func copyLastTranscript() {
        guard !controller.lastTranscript.isEmpty else { return }
        inserter.copy(controller.lastTranscript)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    /// Types the last transcript again into the app in front (after the menu closes).
    func pasteLastTranscript() {
        let text = controller.lastTranscript.isEmpty ? (history.entries.first?.text ?? "") : controller.lastTranscript
        guard !text.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await controller.reinsert(text)
        }
    }

    // MARK: Import

    /// The previous app's data, if there's something to bring over.
    var legacySources: LegacySources? {
        let sources = LegacyLocations.sources()
        return LegacyImport.isNeeded(store: store, sources: sources) ? sources : nil
    }

    /// Brings settings, shortcuts, history and models over from the previous app.
    @discardableResult
    func importLegacy() -> ImportSummary {
        let sources = LegacyLocations.sources()
        let destination = ImportDestination(store: store, historyFile: supportDirectory.appendingPathComponent("history.json"),
                                            modelsDirectory: modelsDirectory)
        let summary = LegacyImport.run(from: sources, to: destination)
        for (name, json) in LegacyImport.shortcuts(from: sources.defaults ?? [:]) {
            let shortcut = json.flatMap { try? JSONDecoder().decode(KeyboardShortcuts.Shortcut.self, from: Data($0.utf8)) }
            KeyboardShortcuts.setShortcut(shortcut, for: KeyboardShortcuts.Name(name))
        }
        settings.reload()
        history.reload()
        models.refreshState()
        Diagnostics.record("import settings=\(summary.settings) history=\(summary.historyEntries) models=\(summary.models)")
        return summary
    }
}

/// Where the app Dictate replaces kept its data. Read-only.
enum LegacyLocations {
    static let bundleID = "oxen.Better-Transcriber"
    static let appName = "Better Transcriber"

    static func sources() -> LegacySources {
        if Diagnostics.isTestMode {
            // Tests only ever import from fixtures.
            let defaults = Diagnostics.legacyDefaults.flatMap { NSDictionary(contentsOf: $0) as? [String: Any] }
            return LegacySources(defaults: defaults, supportDirectory: Diagnostics.legacySupport,
                                 parakeetModels: Diagnostics.legacyModels, whisperBase: nil)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let keys = CFPreferencesCopyKeyList(bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let defaults = keys.flatMap {
            CFPreferencesCopyMultiple($0, bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
        }
        var sources = LegacySources(
            defaults: defaults,
            supportDirectory: support.appendingPathComponent(bundleID, isDirectory: true),
            parakeetModels: support.appendingPathComponent("FluidAudio/Models", isDirectory: true),
            whisperBase: nil)
        // Whisper models sit in Documents, which macOS guards: only look when they were used.
        if sources.usedWhisper {
            sources.whisperBase = home.appendingPathComponent("Documents/huggingface", isDirectory: true)
        }
        return sources
    }
}
