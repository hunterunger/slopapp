import Foundation
import UniformTypeIdentifiers

/// Turns dropped URLs into the files a queue should process: folders are searched
/// (recursively, skipping hidden files and packages), unaccepted types are dropped,
/// duplicates are removed, order is kept. Pure apart from reading the file system.
public enum FileIntake {
    public struct Found: Equatable, Sendable {
        public let url: URL
        public let bytes: Int64?
    }

    /// Upper bound on files taken from one drop, so dropping a home folder can't hang the app.
    public static let limit = 5_000

    public static func expand(_ urls: [URL], types: [UTType], limit: Int = FileIntake.limit) -> [Found] {
        var seen = Set<String>()
        var found: [Found] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey, .fileSizeKey, .isHiddenKey]

        func consider(_ url: URL, values: URLResourceValues?) {
            guard found.count < limit else { return }
            let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
            guard let type, types.contains(where: { type.conforms(to: $0) }) else { return }
            guard seen.insert(url.standardizedFileURL.path).inserted else { return }
            found.append(Found(url: url, bytes: values?.fileSize.map(Int64.init)))
        }

        for url in urls where url.isFileURL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isPackage != true {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                var children: [(URL, URLResourceValues?)] = []
                while let child = enumerator?.nextObject() as? URL {
                    let childValues = try? child.resourceValues(forKeys: Set(keys))
                    if childValues?.isDirectory == true { continue }
                    children.append((child, childValues))
                    // Bound the scan too (other file types count), so a huge folder can't hang us.
                    if children.count >= limit * 4 { break }
                }
                // Finder order: by path, numbers compared as numbers.
                children.sort { $0.0.path.localizedStandardCompare($1.0.path) == .orderedAscending }
                children.forEach { consider($0.0, values: $0.1) }
            } else {
                consider(url, values: values)
            }
        }
        return found
    }

    public struct Rejected: Equatable, Sendable {
        public let url: URL
        public let bytes: Int64?
        public let reason: String
    }

    /// The files in `urls` (not inside folders) that aren't one of `types`, with the reason
    /// `reason` gives (nil skips the file). Folders and packages are never rejected.
    public static func unaccepted(_ urls: [URL], types: [UTType], reason: (URL) -> String?) -> [Rejected] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentTypeKey, .fileSizeKey]
        var seen = Set<String>()
        return urls.compactMap { url in
            guard url.isFileURL, seen.insert(url.standardizedFileURL.path).inserted else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isDirectory != true else { return nil }
            if let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension),
               types.contains(where: { type.conforms(to: $0) }) {
                return nil
            }
            guard let message = reason(url) else { return nil }
            return Rejected(url: url, bytes: values?.fileSize.map(Int64.init), reason: message)
        }
    }
}
