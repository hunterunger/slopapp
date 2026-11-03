import Foundation

/// What a drop (or Open) should do, decided by what was dropped.
public enum DropRoute: Equatable, Sendable {
    /// One archive: show what's inside.
    case browse(URL)
    /// Archives to unpack right away (one URL per archive or split set).
    case extract([URL])
    /// Anything else: make an archive from these.
    case create([URL])
}

public enum Router {
    /// - `extractRightAway`: ⌥ held, or the "extract right away" setting.
    /// - `explicitOpen`: Open With / Dock icon / ⌘O, where zip-based documents count as archives.
    public static func route(_ urls: [URL], extractRightAway: Bool, explicitOpen: Bool = false,
                             isFolder: (URL) -> Bool = Router.isFolder) -> DropRoute? {
        guard !urls.isEmpty else { return nil }
        let allArchives = urls.allSatisfy { !isFolder($0) && ArchiveTypes.isArchive($0, explicitOpen: explicitOpen) }
        guard allArchives else { return .create(urls) }
        let sets = distinctSets(urls)
        if sets.count == 1, !extractRightAway { return .browse(sets[0]) }
        return .extract(sets)
    }

    /// One URL per archive: several parts of the same split set count once.
    public static func distinctSets(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = setKey(url)
            if seen.insert(key).inserted { result.append(url) }
        }
        return result
    }

    static func setKey(_ url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path.lowercased()
        let name = url.lastPathComponent
        let base = VolumeSet.setBaseName(of: name) ?? name
        return folder + "/" + base.lowercased()
    }

    public static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true
    }
}
