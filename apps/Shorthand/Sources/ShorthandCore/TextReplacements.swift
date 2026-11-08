import Foundation

/// One macOS Text Replacement offered for import.
public struct ImportCandidate: Sendable, Equatable, Identifiable {
    public enum Issue: Sendable, Equatable {
        /// Shorthand already has this abbreviation.
        case alreadyInLibrary
        /// The same shortcut appears earlier in what's being imported.
        case repeated
        case invalid(AbbreviationRules.Problem)
        case emptyText
    }

    public var id: Int
    public var shortcut: String
    public var phrase: String
    public var issue: Issue?
    /// Ticked for import: on unless there's an issue.
    public var isSelected: Bool

    public var reason: String? {
        switch issue {
        case nil: nil
        case .alreadyInLibrary: "Already in Shorthand"
        case .repeated: "Listed twice"
        case .emptyText: "No text"
        case .invalid(let problem): AbbreviationRules.message(for: problem)
        }
    }

    /// Only clean rows can be ticked; invalid shortcuts can't expand.
    public var canSelect: Bool {
        switch issue {
        case nil, .alreadyInLibrary, .repeated: true
        case .invalid, .emptyText: false
        }
    }
}

public enum TextReplacementsImport {
    public enum ReadError: Error, Equatable {
        case notAPropertyList
        /// A property list, but not System Settings' Text Replacements export.
        case notTextReplacements
    }

    public static let groupName = "Text Replacements"

    /// Reads System Settings › Keyboard › Text Replacements' export (rows dragged out: a
    /// plist array of `{phrase, shortcut}` dictionaries).
    public static func entries(fromPlist data: Data) throws -> [(shortcut: String, phrase: String)] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { throw ReadError.notAPropertyList }
        guard let array = plist as? [Any] else { throw ReadError.notTextReplacements }
        var result: [(String, String)] = []
        for element in array {
            guard let dictionary = element as? [String: Any],
                  let shortcut = dictionary["shortcut"] as? String,
                  let phrase = dictionary["phrase"] as? String else { throw ReadError.notTextReplacements }
            result.append((shortcut, phrase))
        }
        return result
    }

    /// `NSSpellChecker.userReplacementsDictionary` is shortcut → phrase.
    public static func entries(fromDictionary dictionary: [String: String]) -> [(shortcut: String, phrase: String)] {
        dictionary.map { ($0.key, $0.value) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    /// Rows for the preview sheet. Windows line endings become new lines.
    public static func candidates(_ entries: [(shortcut: String, phrase: String)], library: Library) -> [ImportCandidate] {
        let existing = Set(library.snippets.map(\.abbreviation))
        var seen = Set<String>()
        return entries.enumerated().map { index, entry in
            let shortcut = entry.shortcut.trimmingCharacters(in: .whitespaces)
            let phrase = entry.phrase.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            var issue: ImportCandidate.Issue?
            if let problem = AbbreviationRules.validate(shortcut) {
                issue = .invalid(problem)
            } else if phrase.isEmpty {
                issue = .emptyText
            } else if existing.contains(shortcut) {
                issue = .alreadyInLibrary
            } else if !seen.insert(shortcut).inserted {
                issue = .repeated
            }
            return ImportCandidate(id: index, shortcut: shortcut, phrase: phrase, issue: issue, isSelected: issue == nil)
        }
    }

    /// Adds the ticked rows to a "Text Replacements" group (made if needed). Returns how many.
    /// macOS's own list is never edited. Literal braces are escaped so they type as written.
    @discardableResult
    public static func apply(_ candidates: [ImportCandidate], to library: inout Library, now: Date = Date()) -> Int {
        let chosen = candidates.filter { $0.isSelected && $0.canSelect }
        guard !chosen.isEmpty else { return 0 }
        let groupID = library.groups.first { $0.name == groupName }?.id ?? library.addGroup(named: groupName).id
        for candidate in chosen {
            let content = candidate.phrase.replacingOccurrences(of: "{", with: "{{").replacingOccurrences(of: "}", with: "}}")
            library.addSnippet(Snippet(groupID: groupID, abbreviation: candidate.shortcut, content: content, created: now))
        }
        return chosen.count
    }
}
