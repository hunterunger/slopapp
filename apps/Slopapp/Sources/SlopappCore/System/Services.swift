import Foundation

// The launcher's contact points with the system. Each has a real implementation in this
// folder and a fake in the tests.

/// Fetches the feed.
public protocol FeedFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

/// Downloads a file, reporting progress from 0 to 1.
public protocol Downloading: Sendable {
    func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

/// Unpacks a zip.
public protocol Unarchiving: Sendable {
    func extract(_ archive: URL, to directory: URL) async throws
}

/// Moves, removes and trashes files.
public protocol FileOperating: Sendable {
    func exists(_ url: URL) -> Bool
    func contents(of directory: URL) -> [URL]
    func createDirectory(_ url: URL) throws
    /// A scratch folder on the same volume as `url`, so the final move is a rename.
    func scratchDirectory(near url: URL) throws -> URL
    func move(_ source: URL, to destination: URL) throws
    func remove(_ url: URL) throws
    /// Moves to the Trash and returns where it went.
    @discardableResult func trash(_ url: URL) throws -> URL
    func isWritable(_ url: URL) -> Bool
    /// Free bytes on the volume holding `url`, if known.
    func availableSpace(at url: URL) -> Int64?
    /// Strips com.apple.quarantine (the signature was already verified).
    func clearQuarantine(_ url: URL)
}

/// Network failures, in words a person can act on.
public enum NetworkError: Error, Equatable, Sendable {
    case offline
    case notFound
    case server(Int)
    case other(String)
}

/// Checks code signatures.
public protocol SignatureChecking: Sendable {
    func signature(at url: URL) -> SignatureInfo
}
