import Foundation
@testable import DictateCore

/// Waits (on the main actor, yielding) until `condition` holds, or fails after `timeout`.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

/// A sleep that only finishes when the test says so.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Error>] = []
    private(set) var requested: [Duration] = []

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                requested.append(duration)
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    var waitingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return waiting.count
    }

    /// Finishes every sleep in progress.
    func open() {
        lock.lock()
        let all = waiting
        waiting = []
        lock.unlock()
        all.forEach { $0.resume() }
    }
}

/// A sleep that never finishes (timers that must not fire during a test).
let neverSleep: @Sendable (Duration) async throws -> Void = { _ in
    try await Task.sleep(for: .seconds(3600))
}

@MainActor
final class FakeEngine: SpeechEngine {
    var installed: Set<String> = []
    private(set) var loaded: String?
    private(set) var loadCount = 0
    private(set) var unloadCount = 0
    private(set) var transcribeCount = 0
    private(set) var maxConcurrent = 0
    private var active = 0
    var transcript = "Hello world"
    var transcriptDelay: Duration = .zero
    var loadDelay: Duration = .zero
    var loadError: Error?
    var downloadError: Error?
    private(set) var removed: [String] = []
    private(set) var lastSamples: [Float] = []

    func isInstalled(_ option: ModelOption) -> Bool { installed.contains(option.key) }

    func download(_ option: ModelOption, progress: @escaping @MainActor (Double?) -> Void) async throws {
        progress(nil)
        progress(0.5)
        if let downloadError { throw downloadError }
        installed.insert(option.key)
        progress(1)
    }

    func load(_ option: ModelOption) async throws {
        loadCount += 1
        if loadDelay > .zero { try await Task.sleep(for: loadDelay) }
        if let loadError { throw loadError }
        loaded = option.key
    }

    func unload() {
        if loaded != nil { unloadCount += 1 }
        loaded = nil
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard loaded != nil else { throw ModelHostError.notInstalled("not loaded") }
        transcribeCount += 1
        lastSamples = samples
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        defer { active -= 1 }
        if transcriptDelay > .zero { try await Task.sleep(for: transcriptDelay) }
        return transcript
    }

    func remove(_ option: ModelOption) throws {
        installed.remove(option.key)
        removed.append(option.key)
    }
}

@MainActor
final class FakeAudio: AudioCapturing {
    var samples: [Float] = Array(repeating: 0.1, count: 16_000)
    var startError: Error?
    private(set) var isRunning = false
    private(set) var startCount = 0
    var features = AudioFeatures()

    func start() throws {
        if let startError { throw startError }
        startCount += 1
        isRunning = true
    }

    func stop() -> [Float] {
        guard isRunning else { return [] }
        isRunning = false
        return samples
    }

    func recentSamples(seconds: Double) -> [Float] {
        Array(samples.suffix(Int(seconds * 16_000)))
    }
}

@MainActor
final class FakeMicrophone: MicrophoneAuthorizing {
    var status: MicrophoneStatus = .granted
    var grantOnRequest = true
    private(set) var requests = 0

    func request() async -> Bool {
        requests += 1
        status = grantOnRequest ? .granted : .denied
        return grantOnRequest
    }
}

@MainActor
final class FakeDelivery: TextDelivering {
    var outcome: DeliveryOutcome = .inserted
    var selection: SelectionResult = .text("the selected text")
    private(set) var delivered: [(text: String, insert: Bool, method: InsertionMethod)] = []

    func deliver(_ text: String, insert: Bool, method: InsertionMethod) async -> DeliveryOutcome {
        delivered.append((text, insert, method))
        return insert ? outcome : .copied
    }

    func copySelection() async -> SelectionResult { selection }
}

@MainActor
final class FakeFeedback: DictationFeedback {
    private(set) var started: [DictationMode] = []
    private(set) var ended: [DictationOutcome] = []
    private(set) var cues: [SoundCue] = []
    private(set) var messages: [(String, ProblemFix?)] = []

    func dictationStarted(mode: DictationMode) { started.append(mode) }
    func dictationEnded(_ outcome: DictationOutcome) { ended.append(outcome) }
    func play(_ cue: SoundCue) { cues.append(cue) }
    func notify(_ message: String, fix: ProblemFix?) { messages.append((message, fix)) }
}

@MainActor
final class FakeAI: AITextService {
    var unavailableReason: String?
    var reply: String? = "Polished text."
    private(set) var prompts: [(instructions: String, prompt: String)] = []
    private(set) var prewarmed = 0

    init(available: Bool = true) {
        unavailableReason = available ? nil : "Turn on Apple Intelligence."
    }

    func prewarm(instructions: String) { prewarmed += 1 }

    func respond(instructions: String, prompt: String) async -> String? {
        prompts.append((instructions, prompt))
        return reply
    }
}

struct MemoryHistory: HistoryPersistence {
    final class Box: @unchecked Sendable { var entries: [TranscriptEntry] = []; var saves = 0 }
    let box = Box()

    func load() -> [TranscriptEntry] { box.entries }
    func save(_ entries: [TranscriptEntry]) {
        box.entries = entries
        box.saves += 1
    }
}

/// A fresh temporary folder, removed by the caller.
func temporaryDirectory(_ name: String = #function) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("dictate-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
