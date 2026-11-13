import Foundation

/// Library search: name, abbreviation and content, case- and accent-insensitive. Every word
/// of the query must appear somewhere.
public enum SnippetSearch {
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static func matches(_ snippet: Snippet, words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let haystack = fold(snippet.abbreviation + "\n" + snippet.name + "\n" + snippet.plainContent)
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

/// The quick search panel's list: every snippet with text (groups that are off too: picking
/// one by hand is deliberate). Empty query: most used first, then most recent.
public enum QuickSearch {
    public static let limit = 50

    public static func results(_ snippets: [Snippet], query: String, limit: Int = QuickSearch.limit) -> [Snippet] {
        let candidates = snippets.filter { !$0.content.isEmpty }
        let words = SnippetSearch.words(query)
        guard !words.isEmpty else {
            return Array(candidates.enumerated().sorted { a, b in
                if a.element.useCount != b.element.useCount { return a.element.useCount > b.element.useCount }
                let aDate = a.element.lastUsed ?? .distantPast
                let bDate = b.element.lastUsed ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.offset < b.offset
            }.prefix(limit).map(\.element))
        }
        let first = words[0]
        let hits = candidates.filter { SnippetSearch.matches($0, words: words) }
        // `sig` finds `;sig` as readily as `sig`: the prefix symbol isn't part of the word.
        let bare = String(first.drop { !$0.isLetter && !$0.isNumber })
        func rank(_ snippet: Snippet) -> Int {
            let abbreviation = SnippetSearch.fold(snippet.abbreviation)
            let bareAbbreviation = String(abbreviation.drop { !$0.isLetter && !$0.isNumber })
            if abbreviation == first || (!bare.isEmpty && bareAbbreviation == bare) { return 0 }
            if abbreviation.hasPrefix(first) || (!bare.isEmpty && bareAbbreviation.hasPrefix(bare)) { return 1 }
            let titleWords = SnippetSearch.fold(snippet.title).split { !$0.isLetter && !$0.isNumber }
            if titleWords.contains(where: { $0.hasPrefix(first) }) { return 2 }
            return 3
        }
        return Array(hits.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra != rb { return ra < rb }
            if a.element.useCount != b.element.useCount { return a.element.useCount > b.element.useCount }
            return a.offset < b.offset
        }.prefix(limit).map(\.element))
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
