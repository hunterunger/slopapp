import AppKit
import DictateCore
import Foundation

/// Scripted-test entry points (`DICTATE_TEST_HOOKS=1`, `DICTATE_TRANSCRIBE`). See Diagnostics.
enum TestHooks {
    private static let prefix = "app.slopapp.dictate.test."

    static func install(model: AppModel) {
        let center = DistributedNotificationCenter.default()
        func on(_ name: String, _ action: @escaping @MainActor (String?) -> Void) {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { note in
                let object = note.object as? String
                MainActor.assumeIsolated { action(object) }
            }
        }
        on("start") { object in model.controller.begin(object == "command" ? .command : .dictation) }
        on("stop") { _ in model.controller.end() }
        on("cancel") { _ in model.controller.cancel() }
        on("file") { path in
            guard let path else { return }
            model.files.add([URL(fileURLWithPath: path)])
            WindowOpener.open(.files)
        }
        on("history") { _ in WindowOpener.open(.history) }
        on("onboarding") { _ in WindowOpener.open(.onboarding) }
        on("settings") { tab in SettingsNavigation.open(tab.flatMap(SettingsTab.init(rawValue:)) ?? .general) }
        on("download") { key in
            guard let option = key.flatMap(ModelCatalog.option(key:)) else { return }
            Task { await model.models.download(option) }
        }
        Diagnostics.record("test hooks installed")
    }

    /// Loads the model, transcribes one file, writes the text, quits. For checking the real
    /// engines without a microphone or any UI.
    static func transcribeHeadless(_ url: URL, model: AppModel) {
        Task {
            let output = Diagnostics.transcribeOutput ?? url.deletingPathExtension().appendingPathExtension("txt")
            var lines: [String] = []
            do {
                let loadStart = Diagnostics.now()
                try await model.models.prepare()
                let loadMs = Diagnostics.milliseconds(since: loadStart)
                let samples = try await AudioDecoder.decode(url: url)
                let start = Diagnostics.now()
                let raw = try await model.models.transcribe(samples)
                let ms = Diagnostics.milliseconds(since: start)
                let cleaned = await model.processor.process(TextCleanup.meaningfulText(raw) ?? "",
                                                            config: model.settings.cleanupConfig(forBundleID: nil))
                lines = ["model=\(model.models.selected.key)", "load_ms=\(loadMs)", "audio_s=\(Double(samples.count) / 16_000)",
                         "transcribe_ms=\(ms)", "raw=\(raw)", "cleaned=\(cleaned)"]
            } catch {
                lines = ["error=\(ModelHost.describe(error))"]
            }
            try? (lines.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
            Diagnostics.record("headless " + lines.joined(separator: " | "))
            NSApp.terminate(nil)
        }
    }
}
