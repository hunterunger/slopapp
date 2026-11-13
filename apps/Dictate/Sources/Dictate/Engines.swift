import CoreML
import DictateCore
import FluidAudio
import Foundation
@preconcurrency import WhisperKit

/// Parakeet models through FluidAudio (CoreML on the Neural Engine). Models live in
/// Dictate's own Models folder, never in FluidAudio's shared one, so repairs or downloads
/// here can't touch another app's copy.
final class ParakeetEngine: SpeechEngine {
    private let modelsRoot: URL
    private var manager: AsrManager?
    private var mandarin: CtcZhCnManager?
    private var loadedVersion: AsrModelVersion?

    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    private func directory(_ option: ModelOption) -> URL {
        modelsRoot.appendingPathComponent(option.storagePath, isDirectory: true)
    }

    private static func version(_ option: ModelOption) -> AsrModelVersion {
        switch option.id {
        case "v2": .v2
        case "tdtCtc110m": .tdtCtc110m
        case "ctcZhCn": .ctcZhCn
        case "tdtJa": .tdtJa
        default: .v3
        }
    }

    func isInstalled(_ option: ModelOption) -> Bool {
        let version = Self.version(option)
        return version.isCtcOnly
            ? CtcZhCnModels.modelsExist(at: directory(option))
            : AsrModels.modelsExist(at: directory(option), version: version)
    }

    func download(_ option: ModelOption, progress: @escaping @MainActor (Double?) -> Void) async throws {
        let handler: DownloadUtils.ProgressHandler = { update in
            // FluidAudio reports 0...0.5 for the download and the rest for compiling.
            let fraction = min(1, update.fractionCompleted / 0.5)
            Task { @MainActor in progress(fraction) }
        }
        let version = Self.version(option)
        if version.isCtcOnly {
            try await CtcZhCnModels.download(to: directory(option), progressHandler: handler)
        } else {
            try await AsrModels.download(to: directory(option), version: version, progressHandler: handler)
        }
    }

    func load(_ option: ModelOption) async throws {
        let version = Self.version(option)
        let start = Diagnostics.now()
        unload()
        if version.isCtcOnly {
            let models = try await CtcZhCnModels.load(from: directory(option))
            mandarin = CtcZhCnManager(models: models)
        } else {
            let models = try await AsrModels.load(from: directory(option), version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager
        }
        loadedVersion = version
        Diagnostics.record("load parakeet:\(option.id) ms=\(Diagnostics.milliseconds(since: start))")
    }

    func unload() {
        if let manager { Task { await manager.cleanup() } }
        manager = nil
        mandarin = nil
        loadedVersion = nil
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await transcribeTimed(samples).text
    }

    func transcribeTimed(_ samples: [Float]) async throws -> TimedTranscript {
        if let mandarin {
            // The Mandarin model takes 15 s at a time.
            let window = 240_000
            var text = ""
            var start = 0
            while start < samples.count {
                let chunk = Array(samples[start..<min(samples.count, start + window)])
                text += try await mandarin.transcribe(audio: chunk)
                start += window
            }
            // No timings from this model: subtitles spread the text over the audio.
            return TimedTranscript(text: text)
        }
        guard let manager, let loadedVersion else { throw ModelHostError.notInstalled("Parakeet") }
        var state = try TdtDecoderState(decoderLayers: loadedVersion.decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &state)
        let tokens = (result.tokenTimings ?? []).map { (text: $0.token, start: $0.startTime, end: $0.endTime) }
        return TimedTranscript(text: result.text, words: TimedWord.words(fromTokens: tokens))
    }

    func remove(_ option: ModelOption) throws {
        try FileManager.default.trashItem(at: directory(option), resultingItemURL: nil)
    }
}

/// Whisper models through WhisperKit. Downloads go to Dictate's Models/WhisperKit; loading
/// always uses the local folder and never touches the network.
final class WhisperEngine: SpeechEngine {
    private let modelsRoot: URL
    private var pipe: WhisperPipe?

    init(modelsRoot: URL) {
        self.modelsRoot = modelsRoot
    }

    private var base: URL { modelsRoot.appendingPathComponent(ModelCatalog.whisperRoot, isDirectory: true) }

    private func folder(_ option: ModelOption) -> URL {
        modelsRoot.appendingPathComponent(option.storagePath, isDirectory: true)
    }

    func isInstalled(_ option: ModelOption) -> Bool {
        let fm = FileManager.default
        let parts = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
        return parts.allSatisfy { fm.fileExists(atPath: folder(option).appendingPathComponent($0).path) }
            && Self.tokenizerFolder(for: option, base: base).map { fm.fileExists(atPath: $0.appendingPathComponent("tokenizer.json").path) } ?? true
    }

    /// Where WhisperKit keeps the tokenizer for a model (fetched with the model).
    private static func tokenizerFolder(for option: ModelOption, base: URL) -> URL? {
        tokenizerName(for: option).map { base.appendingPathComponent("models/\($0)", isDirectory: true) }
    }

    private static func tokenizerName(for option: ModelOption) -> String? {
        let id = option.id
        if id.contains("large-v3") { return "openai/whisper-large-v3" }
        if id.hasSuffix("-tiny") { return "openai/whisper-tiny" }
        if id.hasSuffix("-base") { return "openai/whisper-base" }
        if id.hasSuffix("-small") { return "openai/whisper-small" }
        return nil
    }

    private static func variant(for option: ModelOption) -> ModelVariant {
        let id = option.id
        if id.contains("large-v3") { return .largev3 }
        if id.hasSuffix("-tiny") { return .tiny }
        if id.hasSuffix("-small") { return .small }
        return .base
    }

    func download(_ option: ModelOption, progress: @escaping @MainActor (Double?) -> Void) async throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try await Self.fetch(variant: option.id, tokenizer: Self.variant(for: option), base: base) { fraction in
            Task { @MainActor in progress(fraction) }
        }
    }

    private nonisolated static func fetch(variant: String, tokenizer: ModelVariant, base: URL,
                                          report: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await WhisperKit.download(variant: variant, downloadBase: base) { report($0.fractionCompleted) }
        // The tokenizer comes from a separate repository; fetch it now so loading stays offline.
        _ = try await ModelUtilities.loadTokenizer(for: tokenizer, tokenizerFolder: base)
    }

    func load(_ option: ModelOption) async throws {
        unload()
        let start = Diagnostics.now()
        pipe = try await WhisperPipe.make(model: option.id, folder: folder(option), base: base)
        Diagnostics.record("load whisper:\(option.id) ms=\(Diagnostics.milliseconds(since: start))")
    }

    func unload() {
        pipe = nil
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let pipe else { throw ModelHostError.notInstalled("Whisper") }
        return try await pipe.transcribe(samples, wordTimings: false).text
    }

    func transcribeTimed(_ samples: [Float]) async throws -> TimedTranscript {
        guard let pipe else { throw ModelHostError.notInstalled("Whisper") }
        return try await pipe.transcribe(samples, wordTimings: true)
    }

    func remove(_ option: ModelOption) throws {
        try FileManager.default.trashItem(at: folder(option), resultingItemURL: nil)
    }
}

/// WhisperKit isn't Sendable; this keeps it off the main actor. ModelHost guarantees only
/// one call runs at a time.
private nonisolated final class WhisperPipe: @unchecked Sendable {
    private let kit: WhisperKit

    private init(kit: WhisperKit) {
        self.kit = kit
    }

    static func make(model: String, folder: URL, base: URL) async throws -> WhisperPipe {
        let config = WhisperKitConfig(model: model, downloadBase: base, modelFolder: folder.path,
                                      tokenizerFolder: base, verbose: false, logLevel: .none,
                                      prewarm: false, load: true, download: false)
        return WhisperPipe(kit: try await WhisperKit(config))
    }

    func transcribe(_ samples: [Float], wordTimings: Bool) async throws -> TimedTranscript {
        let options = DecodingOptions(skipSpecialTokens: true, wordTimestamps: wordTimings)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        let words = results.flatMap(\.segments).flatMap { $0.words ?? [] }.map {
            TimedWord($0.word.trimmingCharacters(in: .whitespaces), start: TimeInterval($0.start), end: TimeInterval($0.end))
        }
        return TimedTranscript(text: text, words: words)
    }
}
