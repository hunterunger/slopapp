import Foundation
import Testing
@testable import DictateCore

@Suite("Settings")
@MainActor
struct SettingsTests {
    @Test func defaultsForANewPerson() {
        let s = DictateSettings(store: MemoryStore())
        #expect(s.engine == .parakeet)
        #expect(s.selectedModel.id == "v3")
        #expect(s.triggerKind == .function)
        #expect(s.hotkeyMode == .pushToTalk)
        #expect(s.autoInsert)
        #expect(s.insertionMethod == .paste)
        #expect(s.playSounds)
        #expect(s.showLivePreview)
        #expect(s.saveHistory)
        #expect(!s.removeFillers)
        #expect(!s.aiCleanup)
        #expect(s.aiFixCorrections && s.aiFormatLists && s.aiGrammar && s.aiUseVocabulary)
        #expect(!s.hasCompletedOnboarding)
        #expect(s.modelRetention == .tenMinutes)
    }

    @Test func changesPersistAndReload() {
        let store = MemoryStore()
        let s = DictateSettings(store: store)
        s.select(ModelCatalog.option(for: .whisper, id: "openai_whisper-small")!)
        s.hotkeyMode = .holdOrTap
        s.insertionMethod = .type
        s.modelRetention = .always
        s.replacements = [Replacement(from: "a", to: "b")]
        s.appCleanupRules = [AppCleanupRule(bundleID: "com.apple.dt.Xcode", name: "Xcode", aiCleanup: .off)]

        let again = DictateSettings(store: store)
        #expect(again.engine == .whisper)
        #expect(again.selectedModelID == "openai_whisper-small")
        #expect(again.parakeetModel == "v3")
        #expect(again.hotkeyMode == .holdOrTap)
        #expect(again.insertionMethod == .type)
        #expect(again.modelRetention == .always)
        #expect(again.replacements.map(\.to) == ["b"])
        #expect(again.appCleanupRules.first?.aiCleanup == .off)
    }

    @Test func unknownStoredValuesFallBack() {
        let store = MemoryStore([
            SettingsKey.engine: "cloud",
            SettingsKey.whisperModel: "base",          // a short alias that never worked
            SettingsKey.parakeetModel: "v9",
            SettingsKey.hotkeyMode: "chord",
            SettingsKey.replacements: Data("not json".utf8),
        ])
        let s = DictateSettings(store: store)
        #expect(s.engine == .parakeet)
        #expect(s.whisperModel == ModelCatalog.defaultWhisper)
        #expect(s.parakeetModel == ModelCatalog.defaultParakeet)
        #expect(s.hotkeyMode == .pushToTalk)
        #expect(s.replacements.isEmpty)
    }

    @Test func perAppOverridesWin() {
        let s = DictateSettings(store: MemoryStore())
        s.removeFillers = true
        s.aiCleanup = true
        s.appCleanupRules = [
            AppCleanupRule(bundleID: "com.apple.dt.Xcode", name: "Xcode", lowercaseStyle: .on, aiCleanup: .off),
        ]
        #expect(s.cleanupConfig(forBundleID: "COM.APPLE.DT.XCODE")
            == CleanupConfig(removeFillers: true, lowercaseStyle: true, aiCleanup: false))
        #expect(s.cleanupConfig(forBundleID: "com.apple.Notes")
            == CleanupConfig(removeFillers: true, lowercaseStyle: false, aiCleanup: true))
        #expect(s.cleanupConfig(forBundleID: nil)
            == CleanupConfig(removeFillers: true, lowercaseStyle: false, aiCleanup: true))
    }

    @Test func addingAnAppTwiceKeepsOneRule() {
        let s = DictateSettings(store: MemoryStore())
        let first = s.addRule(bundleID: "com.apple.Notes", name: "Notes", appPath: "/System/Applications/Notes.app")
        let second = s.addRule(bundleID: "com.apple.notes", name: "Notes", appPath: "")
        #expect(first == second)
        #expect(s.appCleanupRules.count == 1)
    }

    @Test func rulesFromOlderVersionsDecode() throws {
        // An older rule without the lowercase field, as the previous app may have written it.
        let json = #"[{"id":"6F2C2C1E-0B0D-4D7B-9A8B-1C2D3E4F5A6B","bundleID":"com.x","name":"X","appPath":"","removeFillers":"on","aiCleanup":"off"}]"#
        let store = MemoryStore([SettingsKey.appCleanupRules: Data(json.utf8)])
        let s = DictateSettings(store: store)
        #expect(s.appCleanupRules.first?.lowercaseStyle == .inherit)
        #expect(s.appCleanupRules.first?.removeFillers == .on)
    }

    @Test func aiOptionsIncludeReplacementTargets() {
        let s = DictateSettings(store: MemoryStore())
        s.customVocabulary = "Slopapp"
        s.replacements = [Replacement(from: "katie", to: "Kaity")]
        #expect(s.aiOptions.vocabularyTerms == ["Slopapp", "Kaity"])
        #expect(s.teach("Parakeet"))
        #expect(!s.teach("parakeet"))
        #expect(s.customVocabulary == "Slopapp\nParakeet")
    }

    @Test func catalogIsConsistent() {
        #expect(Set(ModelCatalog.all.map(\.key)).count == ModelCatalog.all.count)
        #expect(ModelCatalog.isValid(engine: .whisper, id: ModelCatalog.defaultWhisper))
        #expect(ModelCatalog.isValid(engine: .parakeet, id: ModelCatalog.defaultParakeet))
        #expect(ModelCatalog.available(appleSilicon: false).allSatisfy { $0.engine == .whisper })
        #expect(ModelCatalog.option(key: "parakeet:v3")?.storagePath == "FluidAudio/parakeet-tdt-0.6b-v3")
        #expect(ModelCatalog.option(key: "whisper:openai_whisper-base")?.storagePath
            == "WhisperKit/models/argmaxinc/whisperkit-coreml/openai_whisper-base")
        #expect(ModelCatalog.option(key: "parakeet:v3")?.sizeText.hasPrefix("≈") == true)
    }

    @Test func retentionLimits() {
        #expect(ModelRetention.always.idleLimit == nil)
        #expect(ModelRetention.tenMinutes.idleLimit == .seconds(600))
    }
}

@Suite("Trigger gestures")
struct GestureTests {
    @Test func holdToTalkIgnoresKeyRepeat() {
        var g = TriggerGesture()
        #expect(g.press(mode: .pushToTalk, at: 0) == .start)
        #expect(g.press(mode: .pushToTalk, at: 0.1) == .none)
        #expect(g.release(mode: .pushToTalk, at: 2) == .stop)
        #expect(g.release(mode: .pushToTalk, at: 2.1) == .none)
        #expect(!g.isActive)
    }

    @Test func togglePressesStartAndStop() {
        var g = TriggerGesture()
        #expect(g.press(mode: .toggle, at: 0) == .start)
        #expect(g.release(mode: .toggle, at: 0.1) == .none)
        #expect(g.press(mode: .toggle, at: 5) == .stop)
        #expect(g.release(mode: .toggle, at: 5.1) == .none)
    }

    @Test func holdOrTapHoldBehavesLikePushToTalk() {
        var g = TriggerGesture()
        #expect(g.press(mode: .holdOrTap, at: 0) == .start)
        #expect(g.release(mode: .holdOrTap, at: 1.5) == .stop)
        #expect(!g.isActive)
    }

    @Test func holdOrTapTapLocksUntilNextPress() {
        var g = TriggerGesture()
        #expect(g.press(mode: .holdOrTap, at: 0) == .start)
        #expect(g.release(mode: .holdOrTap, at: 0.15) == .none)
        #expect(g.isLocked)
        #expect(g.press(mode: .holdOrTap, at: 10) == .stop)
        #expect(g.release(mode: .holdOrTap, at: 10.1) == .none)
        #expect(!g.isActive && !g.isLocked)
    }

    @Test func resetForgetsARecording() {
        var g = TriggerGesture()
        _ = g.press(mode: .toggle, at: 0)
        g.reset()
        _ = g.release(mode: .toggle, at: 0.1)
        // The next press starts again rather than stopping something that already ended.
        #expect(g.press(mode: .toggle, at: 1) == .start)
    }
}
