import Foundation

/// Reads the profile list of a Chromium-based browser from its "Local State" file.
public enum ChromiumProfiles {
    public enum Failure: Error, Equatable, Sendable {
        /// macOS refused access (privacy protection for other apps' data).
        case notPermitted
        /// No Local State file: the browser was never opened, or uses another folder.
        case notFound
        /// The file exists but isn't in the format we expect.
        case unreadable
    }

    /// Profiles from Local State JSON, in the browser's own order (`profiles_order`) when
    /// present, else "Default" first and the rest by folder name.
    public static func parse(_ data: Data) throws(Failure) -> [BrowserProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { throw .unreadable }

        var profiles: [BrowserProfile] = []
        for (directory, value) in cache {
            guard !directory.isEmpty, !directory.contains("/") else { continue }
            let info = value as? [String: Any]
            let rawName = (info?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (rawName?.isEmpty == false ? rawName : nil) ?? directory
            profiles.append(BrowserProfile(directory: directory, name: name))
        }

        let order = (profile["profiles_order"] as? [String]) ?? []
        func rank(_ p: BrowserProfile) -> (Int, Int, String) {
            if let index = order.firstIndex(of: p.directory) { return (0, index, "") }
            return (1, p.directory == "Default" ? 0 : 1, p.directory)
        }
        return profiles.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra.0 != rb.0 { return ra.0 < rb.0 }
            if ra.1 != rb.1 { return ra.1 < rb.1 }
            return ra.2.localizedStandardCompare(rb.2) == .orderedAscending
        }
    }

    /// Reads and parses `<home>/Library/Application Support/<dataDirectory>/Local State`.
    /// Call off the main thread: macOS may hold the read while it asks the user.
    public static func load(dataDirectory: String, home: URL = FileManager.default.homeDirectoryForCurrentUser)
        throws(Failure) -> [BrowserProfile]
    {
        let file = home.appending(path: "Library/Application Support")
            .appending(path: dataDirectory)
            .appending(path: "Local State")
        switch read(file) {
        case .success(let data): return try parse(data)
        case .failure(let failure): throw failure
        }
    }

    // Kept separate from `load`: a typed-throws function with an `as NSError` catch crashes
    // the Swift 6.4 compiler.
    private static func read(_ file: URL) -> Result<Data, Failure> {
        do {
            return .success(try Data(contentsOf: file))
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
                return .failure(.notPermitted)
            }
            if let posix = error.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain,
               posix.code == Int(EPERM) || posix.code == Int(EACCES) {
                return .failure(.notPermitted)
            }
            return .failure(.notFound)
        }
    }

    public enum FolderCheck: Equatable, Sendable {
        case exists
        /// The browser's data folder is there but this profile folder isn't: the browser
        /// would create a new, empty profile with that name.
        case missing
        /// Can't tell (the data folder can't be seen at all).
        case unknown
    }

    /// Checks a manually entered profile folder. Only looks at whether the folder exists,
    /// which macOS allows even when the profile list itself is protected.
    public static func checkFolder(_ folder: String, dataDirectory: String,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> FolderCheck {
        let name = folder.trimmingCharacters(in: .whitespaces)
        guard isValidDirectoryName(name) else { return .unknown }
        let base = home.appending(path: "Library/Application Support").appending(path: dataDirectory)
        let fm = FileManager.default
        if fm.fileExists(atPath: base.appending(path: name).path) { return .exists }
        // "Local State" sits next to the profile folders; if we can see it, the data folder is real.
        if fm.fileExists(atPath: base.appending(path: "Local State").path) { return .missing }
        return .unknown
    }

    /// Valid folder names look like "Default", "Profile 3", "Guest Profile".
    public static func isValidDirectoryName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("/") && trimmed != "." && trimmed != ".."
            && trimmed.count <= 128
    }
}
