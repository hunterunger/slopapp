import Foundation

/// One speech model people can pick.
public struct ModelOption: Identifiable, Hashable, Sendable {
    public let engine: EngineKind
    /// The id the engine understands (exact Hugging Face folder name for Whisper).
    public let id: String
    public let name: String
    public let summary: String
    /// Approximate download size in bytes.
    public let downloadBytes: Int64
    /// Short facts shown under the row.
    public let tags: [String]
    /// Where the model's files live, relative to Dictate's Models folder.
    public let storagePath: String
    /// Other folders the model needs (fetched with it), relative to the Models folder.
    public var extraStoragePaths: [String] = []

    /// Unique across engines (ids can repeat between engines).
    public var key: String { "\(engine.rawValue):\(id)" }

    /// Parakeet runs on the Neural Engine and needs Apple silicon.
    public var needsAppleSilicon: Bool { engine == .parakeet }

    /// "≈460 MB"
    public var sizeText: String {
        "≈" + ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file)
    }
}

/// The models Dictate offers. Parakeet ids map to FluidAudio's model versions; Whisper ids
/// are the exact folder names in `argmaxinc/whisperkit-coreml` (short aliases silently fail).
public enum ModelCatalog {
    public static let defaultWhisper = "openai_whisper-base"
    public static let defaultParakeet = "v3"

    /// Folder (under Models) for FluidAudio's Parakeet models.
    public static let parakeetRoot = "FluidAudio"
    /// Folder (under Models) WhisperKit downloads into; it adds `models/<repo>/<variant>`.
    public static let whisperRoot = "WhisperKit"
    static let whisperRepoPath = "models/argmaxinc/whisperkit-coreml"

    private static func mb(_ value: Int64) -> Int64 { value * 1_000_000 }

    public static let parakeet: [ModelOption] = [
        ModelOption(engine: .parakeet, id: "v3", name: "Parakeet TDT v3",
                    summary: "The best all-round choice. Very fast on the Neural Engine.",
                    downloadBytes: mb(483), tags: ["Fastest", "25 European languages", "Recommended"],
                    storagePath: "\(parakeetRoot)/parakeet-tdt-0.6b-v3"),
        ModelOption(engine: .parakeet, id: "v2", name: "Parakeet TDT v2",
                    summary: "English only, a little more accurate on English than v3.",
                    downloadBytes: mb(465), tags: ["Fastest", "English"],
                    storagePath: "\(parakeetRoot)/parakeet-tdt-0.6b-v2"),
        ModelOption(engine: .parakeet, id: "tdtCtc110m", name: "Parakeet TDT-CTC 110M",
                    summary: "A small English model for Macs with little memory to spare.",
                    downloadBytes: mb(320), tags: ["Smallest", "English"],
                    storagePath: "\(parakeetRoot)/parakeet-tdt-ctc-110m",
                    extraStoragePaths: ["\(parakeetRoot)/parakeet-ctc-110m-coreml"]),
        ModelOption(engine: .parakeet, id: "tdtJa", name: "Parakeet Japanese",
                    summary: "A model trained for Japanese.",
                    downloadBytes: mb(624), tags: ["Japanese"],
                    storagePath: "\(parakeetRoot)/parakeet-ja"),
        ModelOption(engine: .parakeet, id: "ctcZhCn", name: "Parakeet Mandarin",
                    summary: "A model trained for Mandarin Chinese.",
                    downloadBytes: mb(611), tags: ["Mandarin"],
                    storagePath: "\(parakeetRoot)/parakeet-ctc-zh-cn"),
    ]

    public static let whisper: [ModelOption] = [
        whisperOption("openai_whisper-tiny", "Whisper Tiny",
                      "The smallest Whisper. Fast, least accurate.", 77, ["Smallest", "Many languages"]),
        whisperOption("openai_whisper-base", "Whisper Base",
                      "A good balance of speed and accuracy.", 147, ["Fast", "Many languages"]),
        whisperOption("openai_whisper-small", "Whisper Small",
                      "More accurate, still quick on Apple silicon.", 486, ["Balanced", "Many languages"]),
        whisperOption("distil-whisper_distil-large-v3_turbo", "Distil Large v3 Turbo",
                      "Close to the large model's accuracy, much faster. English.", 1527, ["Fast", "Accurate"]),
        whisperOption("openai_whisper-large-v3-v20240930_turbo", "Whisper Large v3 Turbo",
                      "A faster build of the large model.", 1638, ["Accurate", "Many languages"]),
        whisperOption("openai_whisper-large-v3", "Whisper Large v3",
                      "The most accurate in many languages, and the slowest.", 3090, ["Most accurate", "Many languages"]),
    ]

    private static func whisperOption(_ id: String, _ name: String, _ summary: String,
                                      _ megabytes: Int64, _ tags: [String]) -> ModelOption {
        ModelOption(engine: .whisper, id: id, name: name, summary: summary, downloadBytes: mb(megabytes),
                    tags: tags, storagePath: "\(whisperRoot)/\(whisperRepoPath)/\(id)")
    }

    public static let all: [ModelOption] = parakeet + whisper

    public static func options(for engine: EngineKind) -> [ModelOption] {
        engine == .whisper ? whisper : parakeet
    }

    public static func option(for engine: EngineKind, id: String) -> ModelOption? {
        options(for: engine).first { $0.id == id }
    }

    public static func option(key: String) -> ModelOption? {
        all.first { $0.key == key }
    }

    public static func isValid(engine: EngineKind, id: String) -> Bool {
        option(for: engine, id: id) != nil
    }

    /// The models this Mac can run.
    public static func available(appleSilicon: Bool) -> [ModelOption] {
        all.filter { appleSilicon || !$0.needsAppleSilicon }
    }
}
