import Foundation

/// Which files are archives, and what an archive's contents should be called once
/// unpacked. Pure string logic, so it's tested directly.
public enum ArchiveTypes {
    /// Archive extensions that open in Crate when dropped (lowercased).
    public static let archiveExtensions: Set<String> = [
        "zip", "zipx", "7z", "rar", "tar", "tgz", "tbz", "tbz2", "tb2", "txz", "tlz",
        "gz", "gzip", "bz2", "bzip2", "xz", "lzma", "z", "cpio", "xar", "cab", "lha", "lzh",
        "iso", "deb", "ar", "rpm",
    ]

    /// Zip-based documents and installers libarchive can read. Dropping one compresses it;
    /// opening one explicitly (Open With, the Dock icon, ⌘O) browses it.
    public static let documentExtensions: Set<String> = [
        "jar", "war", "ear", "apk", "aar", "ipa", "epub", "docx", "xlsx", "pptx",
        "odt", "ods", "odp", "pkg", "xpi", "whl", "nupkg", "crx",
    ]

    /// Extensions stripped (once) after an archive extension, e.g. "x.tar" in "x.tar.gz".
    private static let compoundInner: Set<String> = ["tar", "cpio"]

    /// True when the file is an archive by name: a known extension or a split part.
    public static func isArchive(_ url: URL, explicitOpen: Bool = false) -> Bool {
        isArchive(name: url.lastPathComponent, explicitOpen: explicitOpen)
    }

    public static func isArchive(name: String, explicitOpen: Bool = false) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if archiveExtensions.contains(ext) { return true }
        if explicitOpen, documentExtensions.contains(ext) { return true }
        return VolumeSet.isPartName(name)
    }

    /// The name for what's inside: "photos.tar.gz" → "photos", "notes.txt.gz" → "notes.txt",
    /// "big.7z.001" → "big", "movie.part1.rar" → "movie".
    public static func baseName(of fileName: String) -> String {
        var name = VolumeSet.setBaseName(of: fileName) ?? fileName
        var ns = name as NSString
        let ext = ns.pathExtension.lowercased()
        if archiveExtensions.contains(ext) || documentExtensions.contains(ext) {
            name = ns.deletingPathExtension
            ns = name as NSString
            if compoundInner.contains(ns.pathExtension.lowercased()) {
                name = ns.deletingPathExtension
            }
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "." || trimmed.lowercased() == fileName.lowercased() && fileName.hasPrefix(".")
            ? "Archive" : trimmed
    }
}
