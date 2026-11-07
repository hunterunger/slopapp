import Foundation
import Observation

// MARK: - System seams

/// The microphone. `AudioRecorder` (AVAudioEngine) in the app; a fake in tests and a file
/// player in scripted walkthroughs.
@MainActor
public protocol AudioCapturing: AnyObject {
    func start() throws
    /// Stops and returns everything captured, 16 kHz mono.
    @discardableResult func stop() -> [Float]
    /// The last `seconds` of audio so far, without stopping.
    func recentSamples(seconds: Double) -> [Float]
    /// Live voice features for the recording ring.
    var features: AudioFeatures { get }
}

public enum MicrophoneStatus: Sendable {
    case granted, denied, undetermined
}

@MainActor
public protocol MicrophoneAuthorizing: AnyObject {
    var status: MicrophoneStatus { get }
    func request() async -> Bool
}

/// What happened to a finished transcript.
public enum DeliveryOutcome: Equatable, Sendable {
    /// Pasted or typed into the focused app.
    case inserted
    /// Left on the clipboard (insertion is off).
    case copied
    /// Left on the clipboard because Dictate isn't allowed to type (Accessibility is off).
    case copiedNeedsAccessibility
    /// Not inserted: test mode refused to type into an app that isn't the test target.
    case skipped
}

public enum SelectionResult: Equatable, Sendable {
    case text(String)
    case nothingSelected
    case needsAccessibility
}

/// Gets text into the app in front, and reads its selection for Command Mode.
@MainActor
public protocol TextDelivering: AnyObject {
    func deliver(_ text: String, insert: Bool, method: InsertionMethod) async -> DeliveryOutcome
    func copySelection() async -> SelectionResult
}

/// The app in front when a dictation started.
public struct FrontApp: Equatable, Sendable {
    public var bundleID: String?
    public var name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum DictationMode: Sendable, Equatable {
    case dictation
    /// Speak an instruction that rewrites the selected text.
    case command
}

public enum SoundCue: Sendable {
    case start, stop
}

/// How a dictation ended, for the recording ring.
public enum DictationOutcome: Equatable, Sendable {
    case success
    case failure
    /// Nothing to do (silence, too short, cancelled).
    case nothing
}

/// What fixes a problem, so the menu and messages can offer it.
public enum ProblemFix: Equatable, Sendable {
    case downloadModel
    case microphoneSettings
    case accessibilitySettings
}

/// Sound and the on-screen ring/messages.
@MainActor
public protocol DictationFeedback: AnyObject {
    func dictationStarted(mode: DictationMode)
    func dictationEnded(_ outcome: DictationOutcome)
    func play(_ cue: SoundCue)
    /// A short message for something the person should know ("Copied to the clipboard").
    func notify(_ message: String, fix: ProblemFix?)
}

// MARK: - Controller

/// Where a dictation is.
public enum DictationPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    /// AI cleanup is running.
    case polishing
    /// Command Mode is rewriting the selection.
    case editing
    case inserting
    case error(String)

    public var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .polishing, .editing, .inserting: true
        case .idle, .error: false
        }
    }
}

/// Record → transcribe → clean up → insert, and Command Mode's record → rewrite selection.
@MainActor
@Observable
public final class DictationController {
    public private(set) var phase: DictationPhase = .idle
    public private(set) var mode: DictationMode = .dictation
    /// Words recognised so far while recording (best effort), for the ring.
    public private(set) var livePreview = ""
    public private(set) var lastTranscript = ""
    /// The fix for the current error, if there's one.
    public private(set) var problemFix: ProblemFix?

    @ObservationIgnored private let audio: AudioCapturing
    @ObservationIgnored private let models: ModelHost
    @ObservationIgnored private let delivery: TextDelivering
    @ObservationIgnored private let processor: TranscriptProcessor
    @ObservationIgnored private let microphone: MicrophoneAuthorizing
    @ObservationIgnored private let frontApp: () -> FrontApp?
    @ObservationIgnored private let feedback: DictationFeedback
    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private let settings: DictateSettings
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let previewInterval: Duration
    /// Called when a dictation ends by itself (error, cancel), so the trigger forgets it.
    @ObservationIgnored public var onEnded: () -> Void = {}

    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var pendingStop = false
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var errorResetTask: Task<Void, Never>?
    @ObservationIgnored private var target: FrontApp?
    /// Bumped per dictation so late results from a cancelled one are dropped.
    @ObservationIgnored private var generation = 0

    /// Shorter than this can't hold a word: accidental taps are dropped without transcribing.
    public static let minimumSamples = Int(AudioDecoder.sampleRate / 4)
    /// The preview re-transcribes this much recent audio (the ring only shows the latest words).
    public static let previewWindowSeconds = 20.0

    public init(audio: AudioCapturing, models: ModelHost, delivery: TextDelivering, processor: TranscriptProcessor,
                microphone: MicrophoneAuthorizing, frontApp: @escaping () -> FrontApp?, feedback: DictationFeedback,
                history: HistoryStore, settings: DictateSettings,
                previewInterval: Duration = .milliseconds(900),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.audio = audio
        self.models = models
        self.delivery = delivery
        self.processor = processor
        self.microphone = microphone
        self.frontApp = frontApp
        self.feedback = feedback
        self.history = history
        self.settings = settings
        self.previewInterval = previewInterval
        self.sleep = sleep
    }

    public var isBusy: Bool { isStarting || phase.isBusy }
    public var isRecording: Bool { phase == .recording }
    public var targetAppName: String? { target?.name }

    // MARK: Start

    /// Starts recording. Returns false when it can't start right now (already busy).
    @discardableResult
    public func begin(_ mode: DictationMode) -> Bool {
        guard !isBusy else { return false }
        if mode == .command, let reason = processor.commandUnavailableReason {
            fail(reason, fix: nil)
            return false
        }
        errorResetTask?.cancel()
        generation += 1
        self.mode = mode
        target = frontApp()
        isStarting = true
        pendingStop = false
        cancelled = false
        problemFix = nil
        let generation = self.generation

        Task {
            defer { if generation == self.generation { isStarting = false } }
            guard models.isSupported(models.selected) else {
                fail(ModelHostError.unsupported(models.selected.name).errorDescription ?? "", fix: .downloadModel)
                return
            }
            guard models.isInstalled(models.selected) else {
                fail("Dictate needs a speech model first. Download one in Settings › Models.", fix: .downloadModel)
                return
            }
            switch microphone.status {
            case .granted: break
            case .undetermined:
                guard await microphone.request() else {
                    fail("Dictate can't hear you. Allow Microphone for Dictate in System Settings.", fix: .microphoneSettings)
                    return
                }
            case .denied:
                fail("Dictate can't hear you. Allow Microphone for Dictate in System Settings.", fix: .microphoneSettings)
                return
            }
            guard generation == self.generation, !cancelled else { return }
            // The model loads while you talk, so a cold start costs nothing you'd notice.
            models.warmUp()
            if mode == .dictation { processor.prepare(for: settings.cleanupConfig(forBundleID: target?.bundleID)) }
            do {
                try audio.start()
            } catch {
                fail("Couldn't start recording: \(ModelHost.describe(error))", fix: nil)
                return
            }
            if pendingStop {
                // Released before recording began: drop it quietly.
                pendingStop = false
                audio.stop()
                isStarting = false
                onEnded()
                return
            }
            phase = .recording
            isStarting = false
            livePreview = ""
            startPreview(generation: generation)
            feedback.dictationStarted(mode: mode)
            if settings.playSounds { feedback.play(.start) }
        }
        return true
    }

    // MARK: Stop

    /// Stops recording and transcribes (dictation) or rewrites the selection (Command Mode).
    public func end() {
        if isStarting {
            pendingStop = true
            return
        }
        guard phase == .recording else { return }
        let samples = audio.stop()
        stopPreview()
        if settings.playSounds { feedback.play(.stop) }
        guard samples.count >= Self.minimumSamples else {
            finishQuietly()
            return
        }
        phase = .transcribing
        let generation = self.generation
        let mode = self.mode
        let config = settings.cleanupConfig(forBundleID: target?.bundleID)
        Task {
            await self.finish(samples: samples, mode: mode, config: config, generation: generation)
        }
    }

    /// Toggle from the menu: start, or stop if recording.
    public func toggle(_ mode: DictationMode = .dictation) {
        if phase == .recording { end() } else { begin(mode) }
    }

    /// Esc: throw this dictation away (recording, transcribing or polishing).
    public func cancel() {
        guard isBusy, phase != .inserting else { return }
        cancelled = true
        generation += 1
        if isStarting { pendingStop = true }
        if phase == .recording { audio.stop() }
        stopPreview()
        isStarting = false
        finishQuietly()
    }

    private func finish(samples: [Float], mode: DictationMode, config: CleanupConfig, generation: Int) async {
        do {
            let raw = try await models.transcribe(samples)
            guard generation == self.generation else { return }
            guard let spoken = TextCleanup.meaningfulText(raw) else {
                finishQuietly()
                return
            }
            switch mode {
            case .dictation:
                if processor.willRunAI(config) { phase = .polishing }
                let text = await processor.process(spoken, config: config)
                guard generation == self.generation else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    finishQuietly()
                    return
                }
                await deliver(text, insert: settings.autoInsert)
            case .command:
                let selection: String
                switch await delivery.copySelection() {
                case .text(let text): selection = text
                case .nothingSelected:
                    fail("Select some text first, then use Command Mode.", fix: nil)
                    return
                case .needsAccessibility:
                    fail("Command Mode needs Accessibility to read your selection. Allow it in System Settings.",
                         fix: .accessibilitySettings)
                    return
                }
                phase = .editing
                guard let edited = await processor.runCommand(instruction: spoken, on: selection) else {
                    fail("Couldn't apply “\(spoken)” to the selection. Try saying it another way.", fix: nil)
                    return
                }
                guard generation == self.generation else { return }
                await deliver(edited, insert: true)
            }
        } catch {
            guard generation == self.generation else { return }
            let fix: ProblemFix? = (error as? ModelHostError).map { _ in .downloadModel }
            fail(ModelHost.describe(error), fix: fix)
        }
    }

    private func deliver(_ text: String, insert: Bool) async {
        phase = .inserting
        lastTranscript = text
        if settings.saveHistory { history.add(text, appName: target?.name) }
        let outcome = await delivery.deliver(text, insert: insert, method: settings.insertionMethod)
        phase = .idle
        feedback.dictationEnded(.success)
        switch outcome {
        case .inserted, .skipped: break
        case .copied: feedback.notify("Copied to the clipboard", fix: nil)
        case .copiedNeedsAccessibility:
            feedback.notify("Copied. Allow Accessibility so Dictate can type for you.", fix: .accessibilitySettings)
        }
        onEnded()
    }

    /// Puts a past transcript back into the app in front.
    public func reinsert(_ text: String) async {
        guard !isBusy else { return }
        let outcome = await delivery.deliver(text, insert: true, method: settings.insertionMethod)
        if outcome == .copiedNeedsAccessibility {
            feedback.notify("Copied. Allow Accessibility so Dictate can type for you.", fix: .accessibilitySettings)
        }
    }

    private func finishQuietly() {
        livePreview = ""
        phase = .idle
        feedback.dictationEnded(.nothing)
        onEnded()
    }

    private func fail(_ message: String, fix: ProblemFix?) {
        if phase == .recording { audio.stop() }
        stopPreview()
        isStarting = false
        livePreview = ""
        problemFix = fix
        phase = .error(message)
        feedback.dictationEnded(.failure)
        feedback.notify(message, fix: fix)
        onEnded()
        errorResetTask?.cancel()
        let sleep = self.sleep
        errorResetTask = Task { [weak self] in
            try? await sleep(.seconds(4))
            guard let self, !Task.isCancelled, case .error = self.phase else { return }
            self.phase = .idle
            self.problemFix = nil
        }
    }

    // MARK: Live preview

    private func startPreview(generation: Int) {
        previewTask?.cancel()
        guard settings.showLivePreview else { return }
        let interval = previewInterval
        let sleep = self.sleep
        previewTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                guard let self, !Task.isCancelled, self.phase == .recording, generation == self.generation else { return }
                let samples = self.audio.recentSamples(seconds: Self.previewWindowSeconds)
                guard samples.count >= Self.minimumSamples else { continue }
                let partial = await self.models.previewTranscribe(samples)
                guard !Task.isCancelled, self.phase == .recording, generation == self.generation else { return }
                if let partial, let text = TextCleanup.meaningfulText(partial) { self.livePreview = text }
            }
        }
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
    }
}

extension TranscriptProcessor {
    /// Why Command Mode can't run, or nil when it can.
    public var commandUnavailableReason: String? {
        guard let reason = aiUnavailableReason else { return nil }
        return "Command Mode: \(reason)"
    }
}
