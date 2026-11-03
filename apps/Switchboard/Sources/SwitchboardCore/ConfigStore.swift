import Foundation

/// Loads and saves `Config` as JSON. A missing file is a fresh install; an unreadable one is
/// kept aside (config.json.broken) instead of being overwritten, so nothing is lost.
public struct ConfigStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public enum LoadResult: Equatable, Sendable {
        case loaded(Config)
        case fresh
        /// The file couldn't be parsed; it was moved to `backupURL`.
        case recovered(backupURL: URL)
    }

    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: fileURL) else { return .fresh }
        do {
            let config = try JSONDecoder().decode(Config.self, from: data)
            return .loaded(config)
        } catch {
            let backup = fileURL.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return .recovered(backupURL: backup)
        }
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
