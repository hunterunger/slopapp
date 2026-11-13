import Foundation

/// A kind of file Switchboard opens (once the user makes it the app for that type), so rules
/// can choose where those files go. Web pages (.html) are part of being the default browser
/// and aren't listed here.
public struct FileType: Codable, Identifiable, Hashable, Sendable {
    /// Stable key: a preset id ("pdf", "weblocation") or the type identifier.
    public var id: String
    /// "PDF documents".
    public var name: String
    /// Uniform type identifiers macOS uses for these files ("com.adobe.pdf").
    public var typeIdentifiers: [String]
    /// Lowercased, without dots ("pdf").
    public var extensions: [String]
    /// The app these files opened in before Switchboard took them over. Where they go when no
    /// rule matches (unless `fallback` says otherwise), and where they go back to.
    public var app: Target?
    /// When no rule matches.
    public var fallback: Fallback

    public init(id: String, name: String, typeIdentifiers: [String], extensions: [String],
                app: Target? = nil, fallback: Fallback = .ask) {
        self.id = id
        self.name = name
        self.typeIdentifiers = typeIdentifiers
        self.extensions = extensions.map { $0.lowercased() }
        self.app = app
        self.fallback = fallback
    }

    /// Web locations hold a link: Switchboard opens the link inside, like any other link.
    public var opensLinkInside: Bool { id == FileType.webLocationID }

    public static let pdfID = "pdf"
    public static let webLocationID = "weblocation"

    /// The types Settings offers without choosing a file.
    public static let presets: [FileType] = [
        FileType(id: pdfID, name: "PDF documents", typeIdentifiers: ["com.adobe.pdf"], extensions: ["pdf"]),
        FileType(id: webLocationID, name: "Web locations", typeIdentifiers: ["com.apple.web-internet-location", "com.microsoft.internet-shortcut"],
                 extensions: ["webloc", "url"]),
    ]

    /// Extensions people type for a file rule: "PDF, .docx *.txt" → ["pdf", "docx", "txt"].
    public static func parseExtensions(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { part -> String in
                var ext = part.trimmingCharacters(in: .whitespaces).lowercased()
                if ext.hasPrefix("*") { ext.removeFirst() }
                while ext.hasPrefix(".") { ext.removeFirst() }
                return ext
            }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// True if `ext` is something a file name can end with ("pdf", "tar.gz").
    public static func isValidExtension(_ ext: String) -> Bool {
        !ext.isEmpty && ext.count <= 32 && ext.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
            && !ext.hasPrefix(".") && !ext.hasSuffix(".")
    }
}

extension Array where Element == FileType {
    /// The listed type a file belongs to, by extension.
    public func type(for url: URL) -> FileType? {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return first { $0.extensions.contains(ext) }
    }
}

/// Reads the link out of a web location file: `.webloc` (a property list with a "URL" key)
/// or `.url` (an `[InternetShortcut]` text file with a `URL=` line).
public enum InternetLocation {
    public static func url(from data: Data) -> URL? {
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = plist as? [String: Any], let text = dict["URL"] as? String {
            return link(text)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("url=") {
                return link(String(trimmed.dropFirst(4)))
            }
        }
        return nil
    }

    /// Only web and email links; a location pointing at a file or an app link is refused.
    private static func link(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let kind = LinkKind.of(url), kind != .file, !url.isFileURL else { return nil }
        return url
    }
}
