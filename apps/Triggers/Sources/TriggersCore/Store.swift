import Foundation

/// Reads and writes `Config` as versioned JSON. A file from a newer Triggers is never
/// overwritten: loading fails and the app keeps running with nothing bound.
public enum ConfigCodec {
    public enum Failure: Error, Equatable, LocalizedError {
        case newerVersion(Int)
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .newerVersion(let version):
                "These triggers were saved by a newer version of Triggers (format \(version)). Update Triggers to use them."
            case .unreadable(let reason):
                "The triggers file couldn't be read (\(reason)). It may be damaged."
            }
        }
    }

    private struct VersionProbe: Decodable { var schemaVersion: Int? }

    public static func decode(_ data: Data) throws -> Config {
        let probe: VersionProbe
        do {
            probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        } catch {
            throw Failure.unreadable("not JSON")
        }
        let version = probe.schemaVersion ?? 1
        guard version <= Config.currentSchema else { throw Failure.newerVersion(version) }
        do {
            var config = try JSONDecoder().decode(Config.self, from: data)
            config.schemaVersion = Config.currentSchema
            return config
        } catch {
            throw Failure.unreadable("unexpected contents")
        }
    }

    public static func encode(_ config: Config) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }

    /// Bindings from an exported file, added to `config` with new ids. Exact duplicates (same
    /// input, action and place) are skipped; apps they need are added to the sidebar.
    public static func merge(_ imported: Config, into config: Config) -> (config: Config, added: Int) {
        var result = config
        var added = 0
        for app in imported.apps where result.app(app.bundleID) == nil {
            result.apps.append(app)
        }
        result.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for binding in imported.bindings {
            let exists = result.bindings.contains {
                $0.trigger == binding.trigger && $0.action == binding.action && $0.scope == binding.scope
            }
            guard !exists else { continue }
            var copy = binding
            copy.id = UUID()
            result.bindings.append(copy)
            added += 1
        }
        return (result, added)
    }
}

/// Where the config lives. The app uses a file; tests use memory.
public protocol ConfigStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

public struct FileConfigStorage: ConfigStorage {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
