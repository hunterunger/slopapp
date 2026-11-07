import Foundation

/// Moves files to the Trash. Behind a protocol so tests (and dry runs) never touch real files.
public protocol Trasher: Sendable {
    /// Returns where the file went in the Trash.
    func trash(_ url: URL) throws -> URL?
}

public struct SystemTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
}

/// What to do once files are converted (Settings ▸ General ▸ When Done).
public enum AfterConversion {
    /// Whether an original may go to the Trash: only when a real, non-empty new file exists
    /// somewhere else. Never for files left unchanged, failed or stopped.
    public static func mayTrash(original: URL, output: URL, files: any FileStore) -> Bool {
        let a = original.standardizedFileURL.resolvingSymlinksInPath()
        let b = output.standardizedFileURL.resolvingSymlinksInPath()
        guard a != b, files.fileExists(original), files.fileExists(output) else { return false }
        return (files.size(of: output) ?? 0) > 0
    }

    /// Moves the original to the Trash if that's safe. Returns whether it did.
    @discardableResult
    public static func trashOriginal(_ original: URL, output: URL, files: any FileStore = SystemFileStore(),
                                     trasher: any Trasher = SystemTrasher()) -> Bool {
        guard mayTrash(original: original, output: output, files: files) else { return false }
        do {
            _ = try trasher.trash(original)
            return true
        } catch {
            return false
        }
    }
}
