import Foundation
import Testing
@testable import DictateCore

let v3 = ModelCatalog.option(for: .parakeet, id: "v3")!
let whisperBase = ModelCatalog.option(for: .whisper, id: "openai_whisper-base")!

@Suite("Model host")
@MainActor
struct ModelHostTests {
    @Test func notInstalledUntilDownloadedThenReady() async throws {
        let engine = FakeEngine()
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        #expect(host.state == .notInstalled)
        await #expect(throws: ModelHostError.notInstalled("Parakeet TDT v3")) { try await host.prepare() }
        #expect(engine.loadCount == 0)

        await host.download(v3)
        #expect(host.state == .ready)
        #expect(host.downloads.isEmpty)
        #expect(engine.loadCount == 1)
        #expect(host.isInstalled(v3))
    }

    @Test func downloadFailureShowsOnTheRow() async {
        let engine = FakeEngine()
        engine.downloadError = URLError(.notConnectedToInternet)
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        await host.download(v3)
        #expect(host.downloadErrors[v3.key] != nil)
        #expect(host.downloads.isEmpty)
        if case .failed = host.state {} else { Issue.record("expected failed, got \(host.state)") }
    }

    @Test func timedTranscriptionLoadsAndFallsBackToPlainText() async throws {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        engine.transcript = "Hello there"
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        let timed = try await host.transcribeTimed(Array(repeating: 0.1, count: 16_000))
        #expect(timed == TimedTranscript(text: "Hello there"))
        #expect(engine.loadCount == 1)
        #expect(host.state == .ready)
    }

    @Test func loadsOnDemandOnceEvenWhenAskedTwice() async throws {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        engine.loadDelay = .milliseconds(30)
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        #expect(host.state == .unloaded)
        async let a: Void = host.prepare()
        async let b: Void = host.prepare()
        _ = try await (a, b)
        #expect(engine.loadCount == 1)
        #expect(host.state == .ready)
    }

    @Test func transcriptionsNeverOverlap() async throws {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        engine.transcriptDelay = .milliseconds(20)
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        async let one = host.transcribe([1])
        async let two = host.transcribe([2])
        async let three = host.transcribe([3])
        _ = try await (one, two, three)
        #expect(engine.transcribeCount == 3)
        #expect(engine.maxConcurrent == 1)
    }

    @Test func previewNeverLoads() async {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        #expect(await host.previewTranscribe([1]) == nil)
        #expect(engine.loadCount == 0)
    }

    @Test func unloadsAfterIdleTime() async throws {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        let gate = Gate()
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .tenMinutes, sleep: gate.sleep)
        _ = try await host.transcribe([1])
        #expect(await waitUntil { gate.waitingCount == 1 })
        #expect(gate.requested.last == .seconds(600))
        gate.open()
        #expect(await waitUntil { host.state == .unloaded })
        #expect(engine.unloadCount == 1)
        // It comes back on the next use.
        _ = try await host.transcribe([1])
        #expect(engine.loadCount == 2)
    }

    @Test func alwaysKeepsItLoaded() async throws {
        let engine = FakeEngine()
        engine.installed = [v3.key, whisperBase.key]
        let gate = Gate()
        let host = ModelHost(engines: [.parakeet: engine, .whisper: engine], selected: v3, retention: .always,
                             sleep: gate.sleep)
        _ = try await host.transcribe([1])
        #expect(gate.waitingCount == 0)
        // Switching models with "Always" loads the new one right away.
        host.select(whisperBase)
        #expect(await waitUntil { host.state == .ready })
        #expect(engine.loadCount == 2)
    }

    @Test func switchingModelsFreesTheOldOne() async throws {
        let parakeet = FakeEngine()
        let whisper = FakeEngine()
        parakeet.installed = [v3.key]
        let host = ModelHost(engines: [.parakeet: parakeet, .whisper: whisper], selected: v3, retention: .oneHour,
                             sleep: neverSleep)
        try await host.prepare()
        host.select(whisperBase)
        #expect(parakeet.loaded == nil)
        #expect(host.state == .notInstalled)
    }

    @Test func parakeetNeedsAppleSilicon() async {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, appleSilicon: false,
                             sleep: neverSleep)
        await #expect(throws: ModelHostError.unsupported("Parakeet TDT v3")) { try await host.prepare() }
        await host.download(v3)
        #expect(host.downloadErrors[v3.key] != nil)
    }

    @Test func removingMovesFilesAway() async throws {
        let engine = FakeEngine()
        engine.installed = [v3.key]
        let host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
        try await host.prepare()
        try host.remove(v3)
        #expect(engine.removed == [v3.key])
        #expect(engine.loaded == nil)
        #expect(host.state == .notInstalled)
    }
}

@Suite("Dictation")
@MainActor
struct DictationTests {
    @MainActor
    final class Rig {
        let engine = FakeEngine()
        let audio = FakeAudio()
        let mic = FakeMicrophone()
        let delivery = FakeDelivery()
        let feedback = FakeFeedback()
        let ai = FakeAI()
        let history = HistoryStore(persistence: MemoryHistory())
        let settings = DictateSettings(store: MemoryStore())
        let host: ModelHost
        let controller: DictationController
        var front = FrontApp(bundleID: "com.apple.TextEdit", name: "TextEdit")
        var endedCount = 0

        init(previewInterval: Duration = .seconds(3600)) {
            engine.installed = [v3.key]
            host = ModelHost(engines: [.parakeet: engine], selected: v3, retention: .oneHour, sleep: neverSleep)
            let processor = TranscriptProcessor(settings: settings, ai: ai)
            var getFront: () -> FrontApp? = { nil }
            controller = DictationController(audio: audio, models: host, delivery: delivery, processor: processor,
                                             microphone: mic, frontApp: { getFront() }, feedback: feedback,
                                             history: history, settings: settings, previewInterval: previewInterval)
            getFront = { [unowned self] in self.front }
            controller.onEnded = { [unowned self] in self.endedCount += 1 }
        }

        func record() async -> Bool {
            controller.begin(.dictation)
            return await waitUntil { self.controller.phase == .recording }
        }

        func idle() async -> Bool {
            await waitUntil { !self.controller.isBusy }
        }
    }

    @Test func happyPathInsertsAndRemembers() async {
        let rig = Rig()
        #expect(await rig.record())
        #expect(rig.feedback.started == [.dictation])
        #expect(rig.feedback.cues == [.start])
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.delivery.delivered.map(\.text) == ["Hello world"])
        #expect(rig.delivery.delivered.first?.insert == true)
        #expect(rig.controller.lastTranscript == "Hello world")
        #expect(rig.history.entries.first?.appName == "TextEdit")
        #expect(rig.feedback.ended == [.success])
        #expect(rig.feedback.cues == [.start, .stop])
        #expect(rig.endedCount == 1)
    }

    @Test func cleanupFollowsTheTargetApp() async {
        let rig = Rig()
        rig.settings.lowercaseStyle = true
        rig.settings.appCleanupRules = [AppCleanupRule(bundleID: "com.apple.TextEdit", lowercaseStyle: .off)]
        rig.engine.transcript = "Um, hello there."
        rig.settings.removeFillers = true
        #expect(await rig.record())
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.delivery.delivered.last?.text == "Hello there.")
    }

    @Test func aiPolishingShowsItsOwnPhase() async {
        let rig = Rig()
        rig.settings.aiCleanup = true
        rig.ai.reply = "Polished."
        #expect(await rig.record())
        #expect(rig.ai.prewarmed == 1)
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.delivery.delivered.last?.text == "Polished.")
    }

    @Test func tooShortIsDroppedQuietly() async {
        let rig = Rig()
        rig.audio.samples = Array(repeating: 0, count: 1000)
        #expect(await rig.record())
        rig.controller.end()
        #expect(rig.controller.phase == .idle)
        #expect(rig.engine.transcribeCount == 0)
        #expect(rig.feedback.ended == [.nothing])
        #expect(rig.delivery.delivered.isEmpty)
    }

    @Test func shorterThanTheEnginesMinimumIsDroppedToo() async {
        // Parakeet refuses audio under 0.3 s ("invalid audio data"): a 0.28 s tap isn't an error.
        let rig = Rig()
        rig.audio.samples = Array(repeating: 0.1, count: 4_480)
        #expect(await rig.record())
        rig.controller.end()
        #expect(rig.controller.phase == .idle)
        #expect(rig.engine.transcribeCount == 0)
        #expect(rig.feedback.ended == [.nothing])
    }

    @Test func silenceIsNotAnError() async {
        let rig = Rig()
        rig.engine.transcript = "[BLANK_AUDIO]"
        #expect(await rig.record())
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.controller.phase == .idle)
        #expect(rig.feedback.ended == [.nothing])
        #expect(rig.history.entries.isEmpty)
    }

    @Test func releasedBeforeRecordingStartedIsDropped() async {
        let rig = Rig()
        rig.mic.status = .undetermined
        rig.controller.begin(.dictation)
        rig.controller.end()   // released while the permission prompt was up
        #expect(await rig.idle())
        #expect(rig.audio.startCount == 1)
        #expect(!rig.audio.isRunning)
        #expect(rig.controller.phase == .idle)
        #expect(rig.feedback.started.isEmpty)
    }

    @Test func secondStartWhileBusyIsRefused() async {
        let rig = Rig()
        #expect(await rig.record())
        #expect(!rig.controller.begin(.dictation))
    }

    @Test func microphoneDeniedExplainsTheFix() async {
        let rig = Rig()
        rig.mic.status = .denied
        rig.controller.begin(.dictation)
        #expect(await waitUntil { if case .error = rig.controller.phase { true } else { false } })
        #expect(rig.controller.problemFix == .microphoneSettings)
        #expect(rig.feedback.messages.first?.1 == .microphoneSettings)
        #expect(rig.audio.startCount == 0)
        #expect(rig.endedCount == 1)
    }

    @Test func askingForTheMicrophoneThenRecording() async {
        let rig = Rig()
        rig.mic.status = .undetermined
        #expect(await rig.record())
        #expect(rig.mic.requests == 1)
    }

    @Test func noModelPointsToTheDownload() async {
        let rig = Rig()
        rig.engine.installed = []
        rig.host.refreshState()
        rig.controller.begin(.dictation)
        #expect(await waitUntil { rig.controller.problemFix == .downloadModel })
        #expect(rig.audio.startCount == 0)
    }

    @Test func modelLoadsWhileYouTalk() async {
        let rig = Rig()
        rig.engine.loadDelay = .milliseconds(50)
        #expect(rig.host.state == .unloaded)
        #expect(await rig.record())
        // Recording started before the model finished loading.
        #expect(!rig.host.state.isReady)
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.delivery.delivered.count == 1)
        #expect(rig.engine.loadCount == 1)
    }

    @Test func loadFailureIsReported() async {
        let rig = Rig()
        rig.engine.loadError = CocoaError(.fileReadCorruptFile)
        #expect(await rig.record())
        rig.controller.end()
        #expect(await waitUntil { if case .error = rig.controller.phase { true } else { false } })
        #expect(rig.feedback.ended == [.failure])
        #expect(rig.delivery.delivered.isEmpty)
    }

    @Test func escapeDuringTranscriptionDiscardsTheResult() async {
        let rig = Rig()
        rig.engine.transcriptDelay = .milliseconds(80)
        #expect(await rig.record())
        rig.controller.end()
        #expect(rig.controller.phase == .transcribing)
        rig.controller.cancel()
        #expect(rig.controller.phase == .idle)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.delivery.delivered.isEmpty)
        #expect(rig.history.entries.isEmpty)
        // And a new dictation works right away.
        #expect(await rig.record())
    }

    @Test func escapeWhileRecordingStopsTheMicrophone() async {
        let rig = Rig()
        #expect(await rig.record())
        rig.controller.cancel()
        #expect(!rig.audio.isRunning)
        #expect(rig.feedback.ended == [.nothing])
        #expect(rig.engine.transcribeCount == 0)
    }

    @Test func clipboardOnlyAndMissingAccessibilityAreExplained() async {
        let rig = Rig()
        rig.settings.autoInsert = false
        #expect(await rig.record())
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.delivery.delivered.last?.insert == false)
        #expect(rig.feedback.messages.last?.0 == "Copied to the clipboard")

        rig.settings.autoInsert = true
        rig.delivery.outcome = .copiedNeedsAccessibility
        #expect(await rig.record())
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.feedback.messages.last?.1 == .accessibilitySettings)
    }

    @Test func historyCanBeOff() async {
        let rig = Rig()
        rig.settings.saveHistory = false
        #expect(await rig.record())
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.history.entries.isEmpty)
        #expect(rig.controller.lastTranscript == "Hello world")
    }

    @Test func commandModeRewritesTheSelection() async {
        let rig = Rig()
        rig.engine.transcript = "Make it formal."
        rig.ai.reply = "Good afternoon."
        rig.controller.begin(.command)
        #expect(await waitUntil { rig.controller.phase == .recording })
        #expect(rig.controller.mode == .command)
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.ai.prompts.last?.prompt.contains("the selected text") == true)
        #expect(rig.delivery.delivered.last?.text == "Good afternoon.")
        #expect(rig.delivery.delivered.last?.insert == true)
    }

    @Test func commandModeNeedsASelectionAndAccessibility() async {
        let rig = Rig()
        rig.delivery.selection = .nothingSelected
        rig.controller.begin(.command)
        #expect(await waitUntil { rig.controller.phase == .recording })
        rig.controller.end()
        #expect(await waitUntil { if case .error = rig.controller.phase { true } else { false } })
        #expect(rig.delivery.delivered.isEmpty)

        let other = Rig()
        other.delivery.selection = .needsAccessibility
        other.controller.begin(.command)
        #expect(await waitUntil { other.controller.phase == .recording })
        other.controller.end()
        #expect(await waitUntil { other.controller.problemFix == .accessibilitySettings })
    }

    @Test func commandModeWithoutAppleIntelligenceSaysWhy() {
        let rig = Rig()
        rig.ai.unavailableReason = "Turn on Apple Intelligence."
        #expect(!rig.controller.begin(.command))
        if case .error(let message) = rig.controller.phase {
            #expect(message.contains("Apple Intelligence"))
        } else {
            Issue.record("expected an error")
        }
    }

    @Test func livePreviewShowsWordsWhileRecording() async throws {
        let rig = Rig(previewInterval: .milliseconds(5))
        rig.engine.transcript = "Hello wor"
        try await rig.host.prepare()
        #expect(await rig.record())
        #expect(await waitUntil { rig.controller.livePreview == "Hello wor" })
        rig.engine.transcript = "Hello world"
        rig.controller.end()
        #expect(await rig.idle())
        #expect(rig.delivery.delivered.last?.text == "Hello world")
        #expect(rig.engine.maxConcurrent == 1)
    }

    @Test func previewIsOffWhenTurnedOff() async throws {
        let rig = Rig(previewInterval: .milliseconds(5))
        rig.settings.showLivePreview = false
        try await rig.host.prepare()
        #expect(await rig.record())
        try await Task.sleep(for: .milliseconds(40))
        #expect(rig.controller.livePreview.isEmpty)
        #expect(rig.engine.transcribeCount == 0)
    }

    @Test func recorderFailureIsReported() async {
        let rig = Rig()
        rig.audio.startError = CocoaError(.featureUnsupported)
        rig.controller.begin(.dictation)
        #expect(await waitUntil { if case .error = rig.controller.phase { true } else { false } })
    }

    @Test func reinsertTypesAPastTranscript() async {
        let rig = Rig()
        await rig.controller.reinsert("From history")
        #expect(rig.delivery.delivered.last?.text == "From history")
        #expect(rig.delivery.delivered.last?.insert == true)
    }
}
