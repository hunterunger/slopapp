import Foundation
import Observation

/// A speech-to-text backend (Parakeet via FluidAudio, Whisper via WhisperKit). The app
/// implements these; tests use a fake.
@MainActor
public protocol SpeechEngine: AnyObject {
    /// The model's files are on disk and complete.
    func isInstalled(_ option: ModelOption) -> Bool
    /// Downloads the model. `progress` gets 0...1, or nil when the size isn't known yet.
    func download(_ option: ModelOption, progress: @escaping @MainActor (Double?) -> Void) async throws
    /// Loads a downloaded model into memory. Never downloads.
    func load(_ option: ModelOption) async throws
    /// Frees the loaded model.
    func unload()
    /// 16 kHz mono samples to text, with the loaded model.
    func transcribe(_ samples: [Float]) async throws -> String
    /// Like `transcribe`, with word timings when the engine reports them (for subtitles).
    func transcribeTimed(_ samples: [Float]) async throws -> TimedTranscript
    /// Moves the model's files to the Trash.
    func remove(_ option: ModelOption) throws
}

extension SpeechEngine {
    /// Engines without timings: the text alone (subtitles then spread it evenly).
    public func transcribeTimed(_ samples: [Float]) async throws -> TimedTranscript {
        TimedTranscript(text: try await transcribe(samples))
    }
}

/// Where the selected model is.
public enum ModelState: Equatable, Sendable {
    /// Not on this Mac yet: needs a download.
    case notInstalled
    case downloading(Double?)
    /// On disk, not in memory.
    case unloaded
    case loading
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }
}

public enum ModelHostError: LocalizedError, Equatable {
    case notInstalled(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            "\(name) isn't downloaded yet. Download it in Settings › Models."
        case .unsupported(let name):
            "\(name) needs a Mac with Apple silicon. Choose a Whisper model instead."
        }
    }
}

/// Owns the speech engines: downloads (only when asked), loads on demand, keeps the model
/// warm for a while after use and frees it afterwards, and runs one transcription at a time.
@MainActor
@Observable
public final class ModelHost {
    public private(set) var selected: ModelOption
    public private(set) var state: ModelState = .unloaded
    /// Downloads in progress, by model key: 0...1 or nil (unknown size).
    public private(set) var downloads: [String: Double?] = [:]
    /// Download errors by model key, shown on the model's row.
    public private(set) var downloadErrors: [String: String] = [:]
    /// Bumped when files change, so views re-check `isInstalled`.
    public private(set) var installGeneration = 0

    public var retention: ModelRetention {
        didSet { if retention != oldValue { scheduleUnload() } }
    }
    /// Whether this Mac can run Parakeet.
    public let appleSilicon: Bool

    @ObservationIgnored private let engines: [EngineKind: SpeechEngine]
    @ObservationIgnored private var loadedKey: String?
    @ObservationIgnored private var loadTask: Task<Void, Error>?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var queueTail: Task<Void, Never>?
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var unloadTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    public init(engines: [EngineKind: SpeechEngine], selected: ModelOption, retention: ModelRetention,
                appleSilicon: Bool = true,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.engines = engines
        self.selected = selected
        self.retention = retention
        self.appleSilicon = appleSilicon
        self.sleep = sleep
        refreshState()
    }

    // MARK: Installed models

    public func isInstalled(_ option: ModelOption) -> Bool {
        _ = installGeneration
        return engines[option.engine]?.isInstalled(option) ?? false
    }

    public func isSupported(_ option: ModelOption) -> Bool {
        appleSilicon || !option.needsAppleSilicon
    }

    /// Re-reads whether the selected model is on disk (after an import or a download).
    public func refreshState() {
        installGeneration += 1
        guard loadedKey != selected.key, loadTask == nil else { return }
        if downloads[selected.key] != nil { return }
        state = isInstalled(selected) ? .unloaded : .notInstalled
    }

    // MARK: Selection

    /// Switches models. The old one is freed; the new one loads when it's next needed, or
    /// right away when it should always be in memory.
    public func select(_ option: ModelOption) {
        guard option.key != selected.key else { return }
        selected = option
        loadGeneration += 1
        loadTask = nil
        if loadedKey != nil {
            engines.values.forEach { $0.unload() }
            loadedKey = nil
        }
        if let progress = downloads[option.key] {
            state = .downloading(progress)
        } else {
            state = isInstalled(option) ? .unloaded : .notInstalled
        }
        if retention == .always { warmUp() }
    }

    // MARK: Download

    /// Downloads a model (network: only ever started by the person). Loads it afterwards when
    /// it's the selected model, so "Ready" means it really works.
    public func download(_ option: ModelOption) async {
        guard downloads[option.key] == nil, let engine = engines[option.engine] else { return }
        guard isSupported(option) else {
            downloadErrors[option.key] = ModelHostError.unsupported(option.name).errorDescription
            return
        }
        downloadErrors[option.key] = nil
        downloads[option.key] = .some(nil)
        if option.key == selected.key { state = .downloading(nil) }
        do {
            try await engine.download(option) { [weak self] fraction in
                guard let self, self.downloads[option.key] != nil else { return }
                self.downloads[option.key] = .some(fraction)
                if option.key == self.selected.key { self.state = .downloading(fraction) }
            }
            downloads[option.key] = nil
            installGeneration += 1
            if option.key == selected.key {
                state = .unloaded
                try? await prepare()
            }
        } catch {
            downloads[option.key] = nil
            let message = Self.describe(error)
            downloadErrors[option.key] = message
            if option.key == selected.key { state = isInstalled(option) ? .unloaded : .failed(message) }
        }
    }

    /// Moves a downloaded model to the Trash. The selected model is unloaded first.
    public func remove(_ option: ModelOption) throws {
        guard let engine = engines[option.engine] else { return }
        if option.key == loadedKey {
            engine.unload()
            loadedKey = nil
            loadTask = nil
        }
        try engine.remove(option)
        installGeneration += 1
        if option.key == selected.key { state = .notInstalled }
    }

    // MARK: Loading

    /// Starts loading the selected model in the background, if it's downloaded.
    public func warmUp() {
        guard isInstalled(selected), isSupported(selected) else { return }
        Task { try? await prepare() }
    }

    /// Loads the selected model if needed. Throws when it isn't downloaded or fails to load.
    public func prepare() async throws {
        let option = selected
        if loadedKey == option.key, state == .ready { return }
        if let loadTask {
            try await loadTask.value
            return
        }
        guard isSupported(option) else { throw ModelHostError.unsupported(option.name) }
        guard let engine = engines[option.engine], engine.isInstalled(option) else {
            state = .notInstalled
            throw ModelHostError.notInstalled(option.name)
        }
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        let task = Task { @MainActor in
            if let loaded = self.loadedKey, loaded != option.key {
                self.engines.values.forEach { $0.unload() }
                self.loadedKey = nil
            }
            try await engine.load(option)
        }
        loadTask = task
        do {
            try await task.value
            guard generation == loadGeneration else {
                // The selection changed while loading: load the new one instead.
                try await prepare()
                return
            }
            loadTask = nil
            loadedKey = option.key
            state = .ready
            scheduleUnload()
        } catch {
            guard generation == loadGeneration else { throw error }
            loadTask = nil
            loadedKey = nil
            state = .failed(Self.describe(error))
            throw error
        }
    }

    // MARK: Transcription

    /// Transcribes with the selected model, loading it first if needed. One at a time: a
    /// second call waits for the first, so previews, dictation and files never overlap.
    public func transcribe(_ samples: [Float]) async throws -> String {
        try await enqueue { try await $0.transcribe(samples) }
    }

    /// Transcribes with word timings where the engine has them (file transcription, for
    /// subtitles). Queued with everything else, like `transcribe`.
    public func transcribeTimed(_ samples: [Float]) async throws -> TimedTranscript {
        try await enqueue { try await $0.transcribeTimed(samples) }
    }

    private func enqueue<Result: Sendable>(_ work: @escaping @MainActor (SpeechEngine) async throws -> Result) async throws -> Result {
        pending += 1
        unloadTask?.cancel()
        defer {
            pending -= 1
            scheduleUnload()
        }
        let previous = queueTail
        let job = Task { @MainActor () throws -> Result in
            await previous?.value
            try await self.prepare()
            guard let engine = self.engines[self.selected.engine] else {
                throw ModelHostError.notInstalled(self.selected.name)
            }
            return try await work(engine)
        }
        queueTail = Task { _ = try? await job.value }
        return try await job.value
    }

    /// Like `transcribe`, but only when the model is already loaded, never throwing: for the
    /// live preview, which must not trigger or wait for a load.
    public func previewTranscribe(_ samples: [Float]) async -> String? {
        guard state == .ready else { return nil }
        return try? await transcribe(samples)
    }

    // MARK: Unloading

    private func scheduleUnload() {
        unloadTask?.cancel()
        unloadTask = nil
        guard let limit = retention.idleLimit, loadedKey != nil, pending == 0 else {
            if retention == .always, loadedKey == nil, state == .unloaded { warmUp() }
            return
        }
        let sleep = self.sleep
        unloadTask = Task { [weak self] in
            do { try await sleep(limit) } catch { return }
            guard let self, !Task.isCancelled, self.pending == 0, self.loadTask == nil else { return }
            self.unloadNow()
        }
    }

    /// Frees the model now (it reloads on the next dictation).
    public func unloadNow() {
        guard pending == 0, loadTask == nil, loadedKey != nil else { return }
        engines.values.forEach { $0.unload() }
        loadedKey = nil
        state = isInstalled(selected) ? .unloaded : .notInstalled
    }

    nonisolated public static func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return (error as NSError).localizedDescription
    }
}
