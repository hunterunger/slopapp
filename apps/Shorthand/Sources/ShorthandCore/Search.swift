import Foundation

/// Library search: name, abbreviation and content, case- and accent-insensitive. Every word
/// of the query must appear somewhere.
public enum SnippetSearch {
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static func matches(_ snippet: Snippet, words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let haystack = fold(snippet.abbreviation + "\n" + snippet.name + "\n" + snippet.content)
        return words.allSatisfy { haystack.contains($0) }
    }

    public static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Filtered, abbreviation matches first, then the most used.
    public static func search(_ snippets: [Snippet], query: String) -> [Snippet] {
        let words = words(query)
        guard !words.isEmpty else { return snippets }
        let hits = snippets.filter { matches($0, words: words) }
        let first = words[0]
        return hits.enumerated().sorted { a, b in
            let aHit = fold(a.element.abbreviation).hasPrefix(first)
            let bHit = fold(b.element.abbreviation).hasPrefix(first)
            if aHit != bHit { return aHit }
            if a.element.useCount != b.element.useCount { return a.element.useCount > b.element.useCount }
            return a.offset < b.offset
        }.map(\.element)
    }
}

/// Apps where nothing is expanded (or even buffered).
public enum Exclusions {
    public struct App: Codable, Sendable, Equatable, Hashable, Identifiable {
        public var bundleID: String
        public var name: String
        public var id: String { bundleID }

        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// Password managers and Shorthand itself.
    public static func defaults(selfBundleID: String) -> [App] {
        [
            App(bundleID: selfBundleID, name: "Shorthand"),
            App(bundleID: "com.apple.Passwords", name: "Passwords"),
            App(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
            App(bundleID: "com.1password.1password", name: "1Password"),
            App(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
            App(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
        ]
    }
}
