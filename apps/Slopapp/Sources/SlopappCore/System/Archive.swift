import Foundation

public enum ArchiveError: Error, Equatable, Sendable {
    case damaged(String)
}

/// `ditto -x -k`, the same tool Finder's Archive Utility uses for zips.
public struct DittoUnarchiver: Unarchiving {
    public init() {}

    public func extract(_ archive: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let status = try await ProcessRunner.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        guard status.code == 0 else { throw ArchiveError.damaged(status.output) }
    }
}

/// Runs a tool and waits without blocking a thread.
public enum ProcessRunner {
    public struct Result: Sendable {
        public var code: Int32
        public var output: String
    }

    public static func run(_ tool: String, _ arguments: [String]) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: Result(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
