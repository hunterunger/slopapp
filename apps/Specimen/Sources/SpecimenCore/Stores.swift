import Foundation

/// Favourite families, kept as a small readable JSON file in the app's data folder.
public struct FavoritesStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("favorites.json")
    }

    struct File: Codable {
        var version = 1
        var families: [String]
    }

    /// A missing file is no favourites. A damaged one is set aside (never silently lost).
    public func load() -> Set<String> {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let file = try? JSONDecoder().decode(File.self, from: data) { return Set(file.families) }
        let backup = url.deletingPathExtension().appendingPathExtension("damaged.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return []
    }

    public func save(_ families: Set<String>) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(families: families.sorted()))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Per-family category corrections ("this is really a Display face"), in categories.json.
public struct CategoryOverridesStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("categories.json")
    }

    public func load() -> [String: FontCategory] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues(FontCategory.init(rawValue:))
    }

    public func save(_ overrides: [String: FontCategory]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(overrides.mapValues(\.rawValue)).write(to: url, options: .atomic)
    }
}

/// Where Specimen keeps things, and its test-mode switches. All from the environment so
/// tests and blind testers never touch the real data or the owner's fonts.
public struct SpecimenEnvironment: Sendable, Equatable {
    /// Favourites and the index cache. `SPECIMEN_DATA_DIR`, else Application Support.
    public var dataDirectory: URL
    /// Test mode (`SPECIMEN_TEST_FONTS`): fonts in this folder are registered for the session
    /// while Specimen runs, and they're the only fonts it may turn on or off.
    public var testFontsDirectory: URL?
    /// `SPECIMEN_STRESS=N`: repeat the library N times to measure performance at scale.
    public var stressCopies: Int
    /// `SPECIMEN_BENCH=scroll|typing`: run a benchmark, write results, and quit.
    public var benchmark: String?
    public var benchmarkOutput: URL?

    public init(dataDirectory: URL, testFontsDirectory: URL? = nil, stressCopies: Int = 1,
                benchmark: String? = nil, benchmarkOutput: URL? = nil) {
        self.dataDirectory = dataDirectory
        self.testFontsDirectory = testFontsDirectory
        self.stressCopies = stressCopies
        self.benchmark = benchmark
        self.benchmarkOutput = benchmarkOutput
    }

    public init(environment: [String: String], defaultDataDirectory: () -> URL) {
        func path(_ key: String) -> URL? {
            guard let value = environment[key], !value.isEmpty else { return nil }
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        }
        self.init(
            dataDirectory: path("SPECIMEN_DATA_DIR") ?? defaultDataDirectory(),
            testFontsDirectory: path("SPECIMEN_TEST_FONTS"),
            stressCopies: max(1, min(50, Int(environment["SPECIMEN_STRESS"] ?? "") ?? 1)),
            benchmark: environment["SPECIMEN_BENCH"].flatMap { $0.isEmpty ? nil : $0 },
            benchmarkOutput: path("SPECIMEN_BENCH_OUT")
        )
    }

    public var isTestMode: Bool { testFontsDirectory != nil }
    public var indexCacheURL: URL { dataDirectory.appendingPathComponent("Cache/index.plist") }

    /// "Test mode: only fonts in /tmp/specimen-test can be turned on or off."
    public var testModeSummary: String? {
        testFontsDirectory.map { "Test mode: \($0.path)" }
    }
}
