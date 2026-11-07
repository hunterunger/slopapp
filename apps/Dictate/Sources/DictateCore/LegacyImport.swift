import Darwin
import Foundation

/// Where the app Dictate replaces keeps its things. All read-only: the import never writes,
/// moves or deletes anything here.
public struct LegacySources {
    /// Its preferences, already read (nil when it was never installed).
    public var defaults: [String: Any]?
    /// Its Application Support folder (holds `history.json`).
    public var supportDirectory: URL?
    /// FluidAudio's shared model folder (`~/Library/Application Support/FluidAudio/Models`).
    public var parakeetModels: URL?
    /// WhisperKit's download base (`~/Documents/huggingface`). Only looked at when the old
    /// app used Whisper, because reading Documents makes macOS ask for permission.
    public var whisperBase: URL?

    public init(defaults: [String: Any]?, supportDirectory: URL?, parakeetModels: URL?, whisperBase: URL?) {
        self.defaults = defaults
        self.supportDirectory = supportDirectory
        self.parakeetModels = parakeetModels
        self.whisperBase = whisperBase
    }

    /// Whether the old app used Whisper (so its Whisper models are worth looking for).
    public var usedWhisper: Bool {
        (defaults?[SettingsKey.engine] as? String) == EngineKind.whisper.rawValue
    }
}

/// Where Dictate keeps its own copies.
public struct ImportDestination {
    public var store: KeyValueStore
    public var historyFile: URL
    public var modelsDirectory: URL

    public init(store: KeyValueStore, historyFile: URL, modelsDirectory: URL) {
        self.store = store
        self.historyFile = historyFile
        self.modelsDirectory = modelsDirectory
    }
}

/// What an import brought over, for the welcome screen.
public struct ImportSummary: Codable, Equatable, Sendable {
    public var settings: Int = 0
    public var shortcuts: Int = 0
    public var historyEntries: Int = 0
    /// Names of the models now available without a download.
    public var models: [String] = []
    public var problems: [String] = []

    public init() {}

    public var isEmpty: Bool { settings == 0 && shortcuts == 0 && historyEntries == 0 && models.isEmpty }
}

/// Brings settings, history and downloaded models over from the app Dictate replaces, once.
///
/// - Settings: same key names, copied only where Dictate has no value of its own yet.
///   Onboarding isn't marked done: macOS asks for Microphone and Accessibility again.
/// - History: `history.json` is copied when Dictate has none.
/// - Models: model folders are cloned (APFS copy-on-write), so they take no extra disk
///   space and the originals are never touched, even if a model library later
///   repairs or re-downloads Dictate's copy.
public enum LegacyImport {
    /// Settings copied as they are (types checked).
    static let settingKeys: [String] = [
        SettingsKey.engine, SettingsKey.whisperModel, SettingsKey.parakeetModel, SettingsKey.triggerKind,
        SettingsKey.preferredMicrophoneUID, SettingsKey.hotkeyMode, SettingsKey.autoInsert, SettingsKey.playSounds,
        SettingsKey.removeFillers, SettingsKey.lowercaseStyle, SettingsKey.replacements, SettingsKey.aiCleanup,
        SettingsKey.aiFixCorrections, SettingsKey.aiFormatLists, SettingsKey.aiGrammar, SettingsKey.aiUseVocabulary,
        SettingsKey.customVocabulary, SettingsKey.aiCustomPrompt, SettingsKey.saveHistory, SettingsKey.appCleanupRules,
    ]

    /// Global shortcut names (KeyboardShortcuts stores them as `KeyboardShortcuts_<name>`).
    public static let shortcutNames = ["record", "commandMode"]

    /// The old app's shortcuts, by name: a KeyboardShortcuts JSON string, or nil for "none".
    /// The app applies them through KeyboardShortcuts so they're registered right away.
    public static func shortcuts(from defaults: [String: Any]) -> [(name: String, json: String?)] {
        shortcutNames.compactMap { name in
            switch defaults["KeyboardShortcuts_\(name)"] {
            case let json as String: (name, json)
            case is Bool: (name, nil)
            default: nil
            }
        }
    }

    /// Whether there's anything to import and it hasn't been done.
    public static func isNeeded(store: KeyValueStore, sources: LegacySources) -> Bool {
        guard store.object(forKey: SettingsKey.importedLegacyAt) == nil else { return false }
        if let defaults = sources.defaults, !defaults.isEmpty { return true }
        if let support = sources.supportDirectory,
           FileManager.default.fileExists(atPath: support.appendingPathComponent("history.json").path) {
            return true
        }
        return false
    }

    /// Runs the import and records that it happened (also when there was nothing to bring).
    @discardableResult
    public static func run(from sources: LegacySources, to destination: ImportDestination,
                           cloner: FolderCloning = FileCloner(), now: Date = Date()) -> ImportSummary {
        var summary = ImportSummary()
        let store = destination.store

        // 1. Settings and shortcuts.
        if let defaults = sources.defaults {
            for key in settingKeys where store.object(forKey: key) == nil {
                guard let value = defaults[key], isPlausible(value, for: key) else { continue }
                store.set(value, forKey: key)
                summary.settings += 1
            }
            summary.shortcuts = shortcuts(from: defaults).count
        }

        // 2. History.
        if let support = sources.supportDirectory {
            let source = support.appendingPathComponent("history.json")
            let fm = FileManager.default
            if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.historyFile.path) {
                if let data = try? Data(contentsOf: source), HistoryFile.isValid(data) {
                    do {
                        try fm.createDirectory(at: destination.historyFile.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
                        try data.write(to: destination.historyFile, options: .atomic)
                        summary.historyEntries = HistoryFile(url: destination.historyFile).load().count
                    } catch {
                        summary.problems.append("Couldn't copy the history: \(error.localizedDescription)")
                    }
                } else {
                    summary.problems.append("The old history file couldn't be read, so it was left where it is.")
                }
            }
        }

        // 3. Models.
        for (option, folders) in modelSources(sources) {
            guard let main = folders.first, cloner.exists(main.source) else { continue }
            do {
                for folder in folders where cloner.exists(folder.source) {
                    let target = destination.modelsDirectory.appendingPathComponent(folder.path)
                    if !cloner.exists(target) { try cloner.clone(folder.source, to: target) }
                }
                summary.models.append(option.name)
            } catch {
                summary.problems.append("Couldn't reuse \(option.name): \(error.localizedDescription)")
            }
        }
        // Whisper tokenizers sit next to the models; small, but needed offline.
        if let base = sources.whisperBase {
            let source = base.appendingPathComponent("models/openai")
            let target = destination.modelsDirectory.appendingPathComponent("\(ModelCatalog.whisperRoot)/models/openai")
            if cloner.exists(source), !cloner.exists(target) { try? cloner.clone(source, to: target) }
        }

        store.set(now.timeIntervalSinceReferenceDate, forKey: SettingsKey.importedLegacyAt)
        if let data = try? JSONEncoder().encode(summary) { store.set(data, forKey: SettingsKey.importSummary) }
        return summary
    }

    /// The summary of the import, if one ran.
    public static func lastSummary(in store: KeyValueStore) -> ImportSummary? {
        (store.object(forKey: SettingsKey.importSummary) as? Data).flatMap { try? JSONDecoder().decode(ImportSummary.self, from: $0) }
    }

    /// Each catalog model and its folders: where Dictate keeps them (relative to Models) and
    /// where the old app would have stored them. The first folder is the model itself.
    static func modelSources(_ sources: LegacySources) -> [(ModelOption, [(path: String, source: URL)])] {
        var result: [(ModelOption, [(path: String, source: URL)])] = []
        if let parakeet = sources.parakeetModels {
            for option in ModelCatalog.parakeet {
                let folders = ([option.storagePath] + option.extraStoragePaths).map { path in
                    (path: path, source: parakeet.appendingPathComponent((path as NSString).lastPathComponent))
                }
                result.append((option, folders))
            }
        }
        if let whisper = sources.whisperBase {
            for option in ModelCatalog.whisper {
                let source = whisper.appendingPathComponent("\(ModelCatalog.whisperRepoPath)/\(option.id)")
                result.append((option, [(path: option.storagePath, source: source)]))
            }
        }
        return result
    }

    static func isPlausible(_ value: Any, for key: String) -> Bool {
        switch key {
        case SettingsKey.replacements, SettingsKey.appCleanupRules: value is Data
        case SettingsKey.autoInsert, SettingsKey.playSounds, SettingsKey.removeFillers, SettingsKey.lowercaseStyle,
             SettingsKey.aiCleanup, SettingsKey.aiFixCorrections, SettingsKey.aiFormatLists, SettingsKey.aiGrammar,
             SettingsKey.aiUseVocabulary, SettingsKey.saveHistory:
            value is Bool
        default: value is String
        }
    }
}

/// Copies a folder tree cheaply. The app uses `FileCloner`; tests can count calls.
public protocol FolderCloning: Sendable {
    func exists(_ url: URL) -> Bool
    func clone(_ source: URL, to destination: URL) throws
}

/// APFS clones (`clonefile`): instant and sharing the same disk blocks until either copy
/// changes. Falls back to a normal copy across volumes or file systems without clones.
public struct FileCloner: FolderCloning {
    public init() {}

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func clone(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if Darwin.clonefile(source.path, destination.path, 0) == 0 { return }
        let code = errno
        // Not cloneable here (another volume, not APFS): copy instead. Anything else is an error.
        guard code == EXDEV || code == ENOTSUP || code == EOPNOTSUPP else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        try fm.copyItem(at: source, to: destination)
    }
}
