import Foundation
import Testing
@testable import DictateCore

@Suite("History")
@MainActor
struct HistoryTests {
    @Test func newestFirstTrimmedAndCapped() {
        let persistence = MemoryHistory()
        let history = HistoryStore(persistence: persistence, cap: 3)
        for i in 1...5 { history.add("  entry \(i) \n", appName: "Notes") }
        history.add("   ", appName: nil)
        #expect(history.entries.map(\.text) == ["entry 5", "entry 4", "entry 3"])
        #expect(persistence.box.entries.count == 3)
    }

    @Test func deleteAndUndoRestoreOrder() {
        let history = HistoryStore(persistence: MemoryHistory())
        ["a", "b", "c"].forEach { history.add($0, appName: nil) }   // c, b, a
        let b = history.entries[1].id
        history.delete(ids: [b])
        #expect(history.entries.map(\.text) == ["c", "a"])
        history.undoRemoval()
        #expect(history.entries.map(\.text) == ["c", "b", "a"])
        history.clear()
        #expect(history.entries.isEmpty)
        history.undoRemoval()
        #expect(history.entries.map(\.text) == ["c", "b", "a"])
    }

    @Test func searchMatchesEveryWordInTextOrApp() {
        let history = HistoryStore(persistence: MemoryHistory())
        history.add("Café meeting moved to Friday", appName: "Mail")
        history.add("Buy oat milk", appName: "Reminders")
        #expect(history.search("cafe friday").count == 1)
        #expect(history.search("milk reminders").count == 1)
        #expect(history.search("MILK mail").isEmpty)
        #expect(history.search("  ").count == 2)
    }

    @Test func fileFormatReadsThePreviousAppsHistory() throws {
        // Written by the app Dictate replaces: JSONEncoder defaults (dates as reference seconds).
        let json = #"[{"id":"0A4C5A57-8E52-4A47-9E0F-2C5E0B6F2D11","date":800000000.5,"text":"Hello","appName":"Notes"},{"id":"9B1E9D3C-7A55-4B0A-8F3E-55D1C2B3A4F6","date":799999999,"text":"No app"}]"#
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        try Data(json.utf8).write(to: url)
        let entries = HistoryFile(url: url).load()
        #expect(entries.map(\.text) == ["Hello", "No app"])
        #expect(entries[1].appName == nil)
        #expect(HistoryFile.isValid(Data(json.utf8)))
        #expect(!HistoryFile.isValid(Data("{}".utf8)))

        // Round trip keeps the same shape.
        let file = HistoryFile(url: dir.appendingPathComponent("sub/history.json"))
        file.save(entries)
        #expect(file.load() == entries)
    }
}

@Suite("Import from the previous app")
@MainActor
struct ImportTests {
    struct Fixture {
        let root: URL
        let legacySupport: URL
        let legacyModels: URL
        let ours: URL
        let store = MemoryStore()

        init() throws {
            root = try temporaryDirectory()
            legacySupport = root.appendingPathComponent("legacy-support")
            legacyModels = root.appendingPathComponent("legacy-models")
            ours = root.appendingPathComponent("ours")
            try FileManager.default.createDirectory(at: legacySupport, withIntermediateDirectories: true)
            // A complete-looking v3 model folder with a real file inside.
            let v3 = legacyModels.appendingPathComponent("parakeet-tdt-0.6b-v3/Encoder.mlmodelc")
            try FileManager.default.createDirectory(at: v3, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 4096).write(to: v3.appendingPathComponent("weight.bin"))
            // A folder with an old naming scheme that Dictate doesn't use.
            try FileManager.default.createDirectory(at: legacyModels.appendingPathComponent("parakeet-tdt-0.6b-v2-coreml"),
                                                    withIntermediateDirectories: true)
        }

        var destination: ImportDestination {
            ImportDestination(store: store, historyFile: ours.appendingPathComponent("history.json"),
                              modelsDirectory: ours.appendingPathComponent("Models"))
        }

        func sources(defaults: [String: Any]?) -> LegacySources {
            LegacySources(defaults: defaults, supportDirectory: legacySupport, parakeetModels: legacyModels, whisperBase: nil)
        }

        func writeHistory(_ text: String = #"[{"id":"0A4C5A57-8E52-4A47-9E0F-2C5E0B6F2D11","date":800000000,"text":"Hello"}]"#) throws {
            try Data(text.utf8).write(to: legacySupport.appendingPathComponent("history.json"))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    let legacyDefaults: [String: Any] = [
        "engine": "parakeet", "parakeetModel": "v3", "triggerKind": "function", "hotkeyMode": "pushToTalk",
        "lowercaseStyle": true, "removeFillers": true, "aiCleanup": false, "autoInsert": true,
        "replacements": try! JSONEncoder().encode([Replacement(from: "katie", to: "Kaity")]),
        "preferredMicrophoneUID": "BuiltInMicrophoneDevice",
        "hasCompletedOnboarding": true,
        "KeyboardShortcuts_record": false, "KeyboardShortcuts_commandMode": false,
        "SUHasLaunchedBefore": true, "NSStatusItem Preferred Position Item-0": 1200.0,
        "lowercaseStyleTypo": "ignored", "aiGrammar": "not a bool",
    ]

    @Test func copiesSettingsShortcutsHistoryAndModels() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try f.writeHistory()
        let sources = f.sources(defaults: legacyDefaults)
        #expect(LegacyImport.isNeeded(store: f.store, sources: sources))

        let settings = DictateSettings(store: f.store)
        #expect(!settings.lowercaseStyle)
        let summary = LegacyImport.run(from: sources, to: f.destination)
        settings.reload()
        #expect(settings.lowercaseStyle && settings.removeFillers)
        #expect(settings.replacements.first?.to == "Kaity")
        #expect(settings.preferredMicrophoneUID == "BuiltInMicrophoneDevice")
        // Onboarding runs again: permissions have to be granted to the new app.
        #expect(!settings.hasCompletedOnboarding)
        #expect(settings.aiGrammar)   // the wrong-typed value was skipped
        // Shortcuts are applied by the app through KeyboardShortcuts, not written here.
        #expect(f.store.object(forKey: "KeyboardShortcuts_record") == nil)
        #expect(LegacyImport.shortcuts(from: legacyDefaults).map(\.name) == ["record", "commandMode"])
        #expect(LegacyImport.shortcuts(from: ["KeyboardShortcuts_record": "{\"carbonKeyCode\":49}"]).first?.json != nil)
        #expect(f.store.object(forKey: "SUHasLaunchedBefore") == nil)
        #expect(summary.settings == 10)
        #expect(summary.shortcuts == 2)
        #expect(summary.historyEntries == 1)
        #expect(summary.models == ["Parakeet TDT v3"])

        let copied = f.ours.appendingPathComponent("Models/FluidAudio/parakeet-tdt-0.6b-v3/Encoder.mlmodelc/weight.bin")
        #expect(try Data(contentsOf: copied).count == 4096)
        // The originals are still there.
        #expect(FileManager.default.fileExists(atPath: f.legacyModels.appendingPathComponent("parakeet-tdt-0.6b-v3/Encoder.mlmodelc/weight.bin").path))
        #expect(FileManager.default.fileExists(atPath: f.legacySupport.appendingPathComponent("history.json").path))
        #expect(!FileManager.default.fileExists(atPath: f.ours.appendingPathComponent("Models/FluidAudio/parakeet-tdt-0.6b-v2-coreml").path))

        // Once only.
        #expect(!LegacyImport.isNeeded(store: f.store, sources: sources))
        #expect(LegacyImport.lastSummary(in: f.store) == summary)
    }

    @Test func neverOverwritesDictatesOwnChoices() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        f.store.set("toggle", forKey: SettingsKey.hotkeyMode)
        let existingHistory = f.ours.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: f.ours, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: existingHistory)
        try f.writeHistory()

        let summary = LegacyImport.run(from: f.sources(defaults: legacyDefaults), to: f.destination)
        #expect(f.store.object(forKey: SettingsKey.hotkeyMode) as? String == "toggle")
        #expect(summary.historyEntries == 0)
        #expect(try Data(contentsOf: existingHistory) == Data("[]".utf8))
    }

    @Test func unreadableHistoryIsLeftAlone() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try f.writeHistory("not json")
        let summary = LegacyImport.run(from: f.sources(defaults: nil), to: f.destination)
        #expect(summary.historyEntries == 0)
        #expect(summary.problems.count == 1)
        #expect(!FileManager.default.fileExists(atPath: f.destination.historyFile.path))
    }

    @Test func nothingToImport() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let empty = LegacySources(defaults: nil, supportDirectory: f.root.appendingPathComponent("missing"),
                                  parakeetModels: nil, whisperBase: nil)
        #expect(!LegacyImport.isNeeded(store: f.store, sources: empty))
        #expect(!LegacyImport.isNeeded(store: f.store, sources: LegacySources(defaults: [:], supportDirectory: nil,
                                                                              parakeetModels: nil, whisperBase: nil)))
    }

    @Test func whisperModelsComeAlongWhenTheOldAppUsedWhisper() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let base = f.root.appendingPathComponent("huggingface")
        let model = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-base/AudioEncoder.mlmodelc")
        let tokenizer = base.appendingPathComponent("models/openai/whisper-base")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tokenizer.appendingPathComponent("tokenizer.json"))

        let sources = LegacySources(defaults: ["engine": "whisper"], supportDirectory: nil, parakeetModels: nil, whisperBase: base)
        #expect(sources.usedWhisper)
        let summary = LegacyImport.run(from: sources, to: f.destination)
        #expect(summary.models == ["Whisper Base"])
        #expect(FileManager.default.fileExists(atPath: f.ours.appendingPathComponent(
            "Models/WhisperKit/models/openai/whisper-base/tokenizer.json").path))
    }

    @Test func modelsBringTheirExtraFolders() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        for folder in ["parakeet-tdt-ctc-110m/Preprocessor.mlmodelc", "parakeet-ctc-110m-coreml/AudioEncoder.mlmodelc"] {
            try FileManager.default.createDirectory(at: f.legacyModels.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let summary = LegacyImport.run(from: f.sources(defaults: nil), to: f.destination)
        #expect(summary.models.contains("Parakeet TDT-CTC 110M"))
        #expect(FileManager.default.fileExists(atPath: f.ours.appendingPathComponent(
            "Models/FluidAudio/parakeet-ctc-110m-coreml/AudioEncoder.mlmodelc").path))
    }

    @Test func clonesShareStorageButNotChanges() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: source.appendingPathComponent("f"))
        let target = dir.appendingPathComponent("deep/b")
        try FileCloner().clone(source, to: target)
        try Data("changed".utf8).write(to: target.appendingPathComponent("f"))
        #expect(try String(contentsOf: source.appendingPathComponent("f"), encoding: .utf8) == "original")
        #expect(throws: (any Error).self) { try FileCloner().clone(source, to: target) }
    }
}
