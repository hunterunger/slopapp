import Foundation
import Observation

// MARK: - Storage

/// Where settings live. `UserDefaults` in the app; `MemoryStore` in tests.
public protocol KeyValueStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}

/// An in-memory `KeyValueStore` for tests and previews.
public final class MemoryStore: KeyValueStore {
    public private(set) var values: [String: Any]

    public init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    public func object(forKey defaultName: String) -> Any? { values[defaultName] }
    public func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    public func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

// MARK: - Choices

/// Which transcription backend is active.
public enum EngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case parakeet
    case whisper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parakeet: "Parakeet"
        case .whisper: "Whisper"
        }
    }
}

/// What physically starts a dictation.
public enum TriggerKind: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The Fn (Globe) key, watched with an event monitor.
    case function
    /// A recorded modifier + key shortcut.
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .function: "Fn (Globe) key"
        case .custom: "Keyboard shortcut"
        }
    }
}

/// How the trigger behaves.
public enum HotkeyMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Hold to record, release to transcribe.
    case pushToTalk
    /// Press to start, press again to stop.
    case toggle
    /// Hold to talk; a quick tap keeps recording until the next press (hands-free).
    case holdOrTap

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pushToTalk: "Hold to talk"
        case .toggle: "Press to start, press to stop"
        case .holdOrTap: "Hold to talk, tap for hands-free"
        }
    }
}

/// How finished text gets into the app you're using.
public enum InsertionMethod: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Put it on the clipboard and press ⌘V (fast, works everywhere), then restore the clipboard.
    case paste
    /// Type it as keystrokes. Never touches the clipboard; slower for long text.
    case type

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .paste: "Paste"
        case .type: "Type"
        }
    }
}

/// How long a speech model stays in memory after use.
public enum ModelRetention: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Loaded at launch and kept: the first dictation is as fast as every other one. The
    /// default: once macOS drops its cache of the compiled model (some time after it was last
    /// used), a reload takes 15 to 30 seconds instead of a tenth of one.
    case always
    /// Unloaded an hour after the last use.
    case oneHour
    /// Unloaded ten minutes after the last use.
    case tenMinutes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .always: "Always"
        case .oneHour: "For an hour after use"
        case .tenMinutes: "For 10 minutes after use"
        }
    }

    /// Idle time before unloading, or nil to keep it loaded.
    public var idleLimit: Duration? {
        switch self {
        case .always: nil
        case .oneHour: .seconds(3600)
        case .tenMinutes: .seconds(600)
        }
    }
}

/// A per-app override for one cleanup toggle.
public enum OverrideValue: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit
    case on
    case off

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inherit: "Default"
        case .on: "On"
        case .off: "Off"
        }
    }

    public func resolve(default value: Bool) -> Bool {
        switch self {
        case .inherit: value
        case .on: true
        case .off: false
        }
    }
}

/// A find/replace rule ("Katie" → "Kaity"). Whole words, case-insensitive.
public struct Replacement: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var from: String
    public var to: String

    public init(id: UUID = UUID(), from: String = "", to: String = "") {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// Cleanup overrides for one app, matched by bundle identifier.
public struct AppCleanupRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var bundleID: String
    public var name: String
    /// Path to the .app, for its icon.
    public var appPath: String
    public var removeFillers: OverrideValue
    public var lowercaseStyle: OverrideValue
    public var aiCleanup: OverrideValue

    public init(id: UUID = UUID(), bundleID: String = "", name: String = "", appPath: String = "",
                removeFillers: OverrideValue = .inherit, lowercaseStyle: OverrideValue = .inherit,
                aiCleanup: OverrideValue = .inherit) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.appPath = appPath
        self.removeFillers = removeFillers
        self.lowercaseStyle = lowercaseStyle
        self.aiCleanup = aiCleanup
    }

    // Tolerant decoding: rules written by older versions may miss fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        bundleID = (try? c.decode(String.self, forKey: .bundleID)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        appPath = (try? c.decode(String.self, forKey: .appPath)) ?? ""
        removeFillers = (try? c.decode(OverrideValue.self, forKey: .removeFillers)) ?? .inherit
        lowercaseStyle = (try? c.decode(OverrideValue.self, forKey: .lowercaseStyle)) ?? .inherit
        aiCleanup = (try? c.decode(OverrideValue.self, forKey: .aiCleanup)) ?? .inherit
    }
}

/// The cleanup toggles that apply to one dictation, after per-app overrides.
public struct CleanupConfig: Equatable, Sendable {
    public var removeFillers: Bool
    public var lowercaseStyle: Bool
    public var aiCleanup: Bool

    public init(removeFillers: Bool, lowercaseStyle: Bool, aiCleanup: Bool) {
        self.removeFillers = removeFillers
        self.lowercaseStyle = lowercaseStyle
        self.aiCleanup = aiCleanup
    }
}

// MARK: - Keys

/// UserDefaults keys. The names match the app Dictate replaces, so its settings import as is.
public enum SettingsKey {
    public static let engine = "engine"
    public static let whisperModel = "whisperModel"
    public static let parakeetModel = "parakeetModel"
    public static let triggerKind = "triggerKind"
    public static let preferredMicrophoneUID = "preferredMicrophoneUID"
    public static let hotkeyMode = "hotkeyMode"
    public static let autoInsert = "autoInsert"
    public static let playSounds = "playSounds"
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    public static let removeFillers = "removeFillers"
    public static let lowercaseStyle = "lowercaseStyle"
    public static let replacements = "replacements"
    public static let aiCleanup = "aiCleanup"
    public static let aiFixCorrections = "aiFixCorrections"
    public static let aiFormatLists = "aiFormatLists"
    public static let aiGrammar = "aiGrammar"
    public static let aiUseVocabulary = "aiUseVocabulary"
    public static let customVocabulary = "customVocabulary"
    public static let aiCustomPrompt = "aiCustomPrompt"
    public static let saveHistory = "saveHistory"
    public static let appCleanupRules = "appCleanupRules"
    // New in Dictate.
    public static let insertionMethod = "insertionMethod"
    public static let modelRetention = "modelRetention"
    public static let showLivePreview = "showLivePreview"
    public static let importedLegacyAt = "importedLegacyAt"
    public static let importSummary = "importSummary"
}

// MARK: - Settings

/// Every user preference, persisted as it changes.
@MainActor
@Observable
public final class DictateSettings {
    @ObservationIgnored private let store: KeyValueStore

    public var engine: EngineKind { didSet { store.set(engine.rawValue, forKey: SettingsKey.engine) } }
    public var whisperModel: String { didSet { store.set(whisperModel, forKey: SettingsKey.whisperModel) } }
    public var parakeetModel: String { didSet { store.set(parakeetModel, forKey: SettingsKey.parakeetModel) } }
    public var triggerKind: TriggerKind { didSet { store.set(triggerKind.rawValue, forKey: SettingsKey.triggerKind) } }
    /// Core Audio device UID; empty follows the system default input.
    public var preferredMicrophoneUID: String {
        didSet { store.set(preferredMicrophoneUID, forKey: SettingsKey.preferredMicrophoneUID) }
    }
    public var hotkeyMode: HotkeyMode { didSet { store.set(hotkeyMode.rawValue, forKey: SettingsKey.hotkeyMode) } }
    /// Put the text into the focused app (otherwise: clipboard only).
    public var autoInsert: Bool { didSet { store.set(autoInsert, forKey: SettingsKey.autoInsert) } }
    public var insertionMethod: InsertionMethod {
        didSet { store.set(insertionMethod.rawValue, forKey: SettingsKey.insertionMethod) }
    }
    public var playSounds: Bool { didSet { store.set(playSounds, forKey: SettingsKey.playSounds) } }
    public var showLivePreview: Bool { didSet { store.set(showLivePreview, forKey: SettingsKey.showLivePreview) } }
    public var modelRetention: ModelRetention {
        didSet { store.set(modelRetention.rawValue, forKey: SettingsKey.modelRetention) }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { store.set(hasCompletedOnboarding, forKey: SettingsKey.hasCompletedOnboarding) }
    }
    public var removeFillers: Bool { didSet { store.set(removeFillers, forKey: SettingsKey.removeFillers) } }
    /// Lowercase the first letter and drop the trailing period.
    public var lowercaseStyle: Bool { didSet { store.set(lowercaseStyle, forKey: SettingsKey.lowercaseStyle) } }
    public var replacements: [Replacement] { didSet { persist(replacements, SettingsKey.replacements) } }
    public var aiCleanup: Bool { didSet { store.set(aiCleanup, forKey: SettingsKey.aiCleanup) } }
    public var aiFixCorrections: Bool { didSet { store.set(aiFixCorrections, forKey: SettingsKey.aiFixCorrections) } }
    public var aiFormatLists: Bool { didSet { store.set(aiFormatLists, forKey: SettingsKey.aiFormatLists) } }
    public var aiGrammar: Bool { didSet { store.set(aiGrammar, forKey: SettingsKey.aiGrammar) } }
    public var aiUseVocabulary: Bool { didSet { store.set(aiUseVocabulary, forKey: SettingsKey.aiUseVocabulary) } }
    /// Terms the AI should spell exactly, one per line (commas also separate).
    public var customVocabulary: String { didSet { store.set(customVocabulary, forKey: SettingsKey.customVocabulary) } }
    public var aiCustomPrompt: String { didSet { store.set(aiCustomPrompt, forKey: SettingsKey.aiCustomPrompt) } }
    public var saveHistory: Bool { didSet { store.set(saveHistory, forKey: SettingsKey.saveHistory) } }
    public var appCleanupRules: [AppCleanupRule] { didSet { persist(appCleanupRules, SettingsKey.appCleanupRules) } }

    public init(store: KeyValueStore) {
        self.store = store
        func string(_ key: String) -> String? { store.object(forKey: key) as? String }
        func bool(_ key: String, _ fallback: Bool) -> Bool { store.object(forKey: key) as? Bool ?? fallback }
        func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
            (store.object(forKey: key) as? Data).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }

        engine = EngineKind(rawValue: string(SettingsKey.engine) ?? "") ?? .parakeet
        // Stored ids are checked against today's catalog: a model that's gone falls back to
        // the engine's default instead of failing to load.
        let whisper = string(SettingsKey.whisperModel) ?? ""
        whisperModel = ModelCatalog.isValid(engine: .whisper, id: whisper) ? whisper : ModelCatalog.defaultWhisper
        let parakeet = string(SettingsKey.parakeetModel) ?? ""
        parakeetModel = ModelCatalog.isValid(engine: .parakeet, id: parakeet) ? parakeet : ModelCatalog.defaultParakeet
        triggerKind = TriggerKind(rawValue: string(SettingsKey.triggerKind) ?? "") ?? .function
        preferredMicrophoneUID = string(SettingsKey.preferredMicrophoneUID) ?? ""
        hotkeyMode = HotkeyMode(rawValue: string(SettingsKey.hotkeyMode) ?? "") ?? .pushToTalk
        autoInsert = bool(SettingsKey.autoInsert, true)
        insertionMethod = InsertionMethod(rawValue: string(SettingsKey.insertionMethod) ?? "") ?? .paste
        playSounds = bool(SettingsKey.playSounds, true)
        showLivePreview = bool(SettingsKey.showLivePreview, true)
        modelRetention = ModelRetention(rawValue: string(SettingsKey.modelRetention) ?? "") ?? .always
        hasCompletedOnboarding = bool(SettingsKey.hasCompletedOnboarding, false)
        removeFillers = bool(SettingsKey.removeFillers, false)
        lowercaseStyle = bool(SettingsKey.lowercaseStyle, false)
        replacements = decode([Replacement].self, SettingsKey.replacements) ?? []
        aiCleanup = bool(SettingsKey.aiCleanup, false)
        aiFixCorrections = bool(SettingsKey.aiFixCorrections, true)
        aiFormatLists = bool(SettingsKey.aiFormatLists, true)
        aiGrammar = bool(SettingsKey.aiGrammar, true)
        aiUseVocabulary = bool(SettingsKey.aiUseVocabulary, true)
        customVocabulary = string(SettingsKey.customVocabulary) ?? ""
        aiCustomPrompt = string(SettingsKey.aiCustomPrompt) ?? ""
        saveHistory = bool(SettingsKey.saveHistory, true)
        appCleanupRules = decode([AppCleanupRule].self, SettingsKey.appCleanupRules) ?? []
    }

    /// Re-reads every value from the store (after an import wrote to it).
    public func reload() {
        let fresh = DictateSettings(store: store)
        if engine != fresh.engine { engine = fresh.engine }
        if whisperModel != fresh.whisperModel { whisperModel = fresh.whisperModel }
        if parakeetModel != fresh.parakeetModel { parakeetModel = fresh.parakeetModel }
        if triggerKind != fresh.triggerKind { triggerKind = fresh.triggerKind }
        if preferredMicrophoneUID != fresh.preferredMicrophoneUID { preferredMicrophoneUID = fresh.preferredMicrophoneUID }
        if hotkeyMode != fresh.hotkeyMode { hotkeyMode = fresh.hotkeyMode }
        if autoInsert != fresh.autoInsert { autoInsert = fresh.autoInsert }
        if insertionMethod != fresh.insertionMethod { insertionMethod = fresh.insertionMethod }
        if playSounds != fresh.playSounds { playSounds = fresh.playSounds }
        if showLivePreview != fresh.showLivePreview { showLivePreview = fresh.showLivePreview }
        if modelRetention != fresh.modelRetention { modelRetention = fresh.modelRetention }
        if hasCompletedOnboarding != fresh.hasCompletedOnboarding { hasCompletedOnboarding = fresh.hasCompletedOnboarding }
        if removeFillers != fresh.removeFillers { removeFillers = fresh.removeFillers }
        if lowercaseStyle != fresh.lowercaseStyle { lowercaseStyle = fresh.lowercaseStyle }
        if replacements != fresh.replacements { replacements = fresh.replacements }
        if aiCleanup != fresh.aiCleanup { aiCleanup = fresh.aiCleanup }
        if aiFixCorrections != fresh.aiFixCorrections { aiFixCorrections = fresh.aiFixCorrections }
        if aiFormatLists != fresh.aiFormatLists { aiFormatLists = fresh.aiFormatLists }
        if aiGrammar != fresh.aiGrammar { aiGrammar = fresh.aiGrammar }
        if aiUseVocabulary != fresh.aiUseVocabulary { aiUseVocabulary = fresh.aiUseVocabulary }
        if customVocabulary != fresh.customVocabulary { customVocabulary = fresh.customVocabulary }
        if aiCustomPrompt != fresh.aiCustomPrompt { aiCustomPrompt = fresh.aiCustomPrompt }
        if saveHistory != fresh.saveHistory { saveHistory = fresh.saveHistory }
        if appCleanupRules != fresh.appCleanupRules { appCleanupRules = fresh.appCleanupRules }
    }

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { store.set(data, forKey: key) }
    }

    /// The selected model's id for the active engine.
    public var selectedModelID: String {
        switch engine {
        case .whisper: whisperModel
        case .parakeet: parakeetModel
        }
    }

    /// The selected model.
    public var selectedModel: ModelOption {
        ModelCatalog.option(for: engine, id: selectedModelID)
            ?? ModelCatalog.option(for: .parakeet, id: ModelCatalog.defaultParakeet)!
    }

    /// Makes `option` the active model.
    public func select(_ option: ModelOption) {
        if engine != option.engine { engine = option.engine }
        switch option.engine {
        case .whisper: if whisperModel != option.id { whisperModel = option.id }
        case .parakeet: if parakeetModel != option.id { parakeetModel = option.id }
        }
    }

    /// The cleanup toggles for a dictation into the app with `bundleID`.
    public func cleanupConfig(forBundleID bundleID: String?) -> CleanupConfig {
        let rule = bundleID.flatMap { id in
            appCleanupRules.first { $0.bundleID.caseInsensitiveCompare(id) == .orderedSame }
        }
        return CleanupConfig(
            removeFillers: (rule?.removeFillers ?? .inherit).resolve(default: removeFillers),
            lowercaseStyle: (rule?.lowercaseStyle ?? .inherit).resolve(default: lowercaseStyle),
            aiCleanup: (rule?.aiCleanup ?? .inherit).resolve(default: aiCleanup)
        )
    }

    /// The options the AI cleanup pass uses right now.
    public var aiOptions: AICleanupOptions {
        AICleanupOptions(
            fixCorrections: aiFixCorrections,
            formatLists: aiFormatLists,
            grammar: aiGrammar,
            customVocabulary: aiUseVocabulary,
            vocabularyTerms: Vocabulary.terms(vocabulary: customVocabulary, replacements: replacements),
            customPrompt: aiCustomPrompt
        )
    }

    /// Adds a word to the custom vocabulary. Returns false when it was already there or blank.
    @discardableResult
    public func teach(_ word: String) -> Bool {
        guard let updated = Vocabulary.adding(word, to: customVocabulary) else { return false }
        customVocabulary = updated
        return true
    }

    /// Adds a per-app rule unless that app already has one. Returns the rule's id.
    @discardableResult
    public func addRule(bundleID: String, name: String, appPath: String) -> UUID? {
        if !bundleID.isEmpty, let existing = appCleanupRules.first(where: {
            $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame
        }) {
            return existing.id
        }
        let rule = AppCleanupRule(bundleID: bundleID, name: name, appPath: appPath)
        appCleanupRules.append(rule)
        return rule.id
    }
}
