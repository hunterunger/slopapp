import Foundation

/// What an abbreviation may be: 1–32 characters of letters, digits, punctuation and symbols.
/// No spaces, no emoji, no combining sequences, so one Backspace removes one typed character
/// in every app.
public enum AbbreviationRules {
    public static let maxLength = 32

    public enum Problem: Equatable, Sendable {
        case empty
        case tooLong
        case whitespace
        /// Emoji, combining marks, control characters: things one Backspace may not undo.
        case unsupportedCharacter(Character)
    }

    public static func validate(_ abbreviation: String) -> Problem? {
        if abbreviation.isEmpty { return .empty }
        var count = 0
        for character in abbreviation {
            count += 1
            if character.isWhitespace || character.isNewline { return .whitespace }
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
                  isAllowed(scalar) else { return .unsupportedCharacter(character) }
        }
        if count > maxLength { return .tooLong }
        return nil
    }

    static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isEmojiPresentation || properties.generalCategory == .control || properties.generalCategory == .format {
            return false
        }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .surrogate, .privateUse, .unassigned:
            return false
        default:
            return !properties.isWhitespace
        }
    }

    public static func message(for problem: Problem) -> String {
        switch problem {
        case .empty: "Type an abbreviation."
        case .tooLong: "Use \(maxLength) characters or fewer."
        case .whitespace: "Abbreviations can't contain spaces or line breaks."
        case .unsupportedCharacter(let character): "“\(character)” can't be used in an abbreviation. Use letters, digits and symbols."
        }
    }
}

/// Warnings shown under the abbreviation field as you type.
public enum AbbreviationWarning: Equatable, Sendable {
    /// Another snippet has the same abbreviation. Blocks it from expanding.
    case duplicate(title: String)
    /// `shorter` will always fire first, so `longer` can never be typed.
    case shadowedBy(shorter: String)
    /// This one fires before `longer` can be typed.
    case shadows(longer: String)
    /// Letters only: it could expand while you type normally.
    case plainWord

    public var blocksExpansion: Bool {
        if case .duplicate = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .duplicate(let title): "“\(title)” already uses this abbreviation. Change one of them."
        case .shadowedBy(let shorter): "“\(shorter)” will always expand before this one can be typed."
        case .shadows(let longer): "This expands before “\(longer)” can be typed."
        case .plainWord: "This could expand while you type normally. Starting it with ; or another symbol helps."
        }
    }
}

public enum ConflictChecker {
    /// Warnings for `snippet` against the rest of the library. Only snippets in enabled groups
    /// count as clashes (a disabled group never expands). Case-insensitive when either side
    /// adapts its case.
    public static func warnings(for snippet: Snippet, in library: Library) -> [AbbreviationWarning] {
        let abbreviation = snippet.abbreviation
        guard AbbreviationRules.validate(abbreviation) == nil else { return [] }
        let enabled = Set(library.groups.filter(\.isEnabled).map(\.id))
        let others = library.snippets.filter {
            $0.id != snippet.id && enabled.contains($0.groupID) && AbbreviationRules.validate($0.abbreviation) == nil
        }
        var result: [AbbreviationWarning] = []
        for other in others {
            let folded = snippet.caseMode == .adapt || other.caseMode == .adapt
            let mine = folded ? abbreviation.lowercased() : abbreviation
            let theirs = folded ? other.abbreviation.lowercased() : other.abbreviation
            if mine == theirs {
                result.append(.duplicate(title: other.title))
            } else if mine.hasPrefix(theirs) {
                result.append(.shadowedBy(shorter: other.abbreviation))
            } else if theirs.hasPrefix(mine) {
                result.append(.shadows(longer: other.abbreviation))
            }
        }
        if abbreviation.allSatisfy({ $0.isLetter }) && abbreviation.count >= 1 {
            result.append(.plainWord)
        }
        // Duplicates first, then clashes, each once.
        var seen = Set<String>()
        return result.sorted { rank($0) < rank($1) }.filter { seen.insert($0.message).inserted }
    }

    /// Abbreviations shared by more than one expandable snippet: none of them expand until
    /// it's resolved (so the person never gets the wrong one).
    public static func duplicateAbbreviations(in snippets: [Snippet]) -> Set<String> {
        var counts: [String: Int] = [:]
        for snippet in snippets { counts[key(snippet), default: 0] += 1 }
        // An adapt-case snippet clashes with any exact one that folds to the same text.
        let foldedAdapt = Set(snippets.filter { $0.caseMode == .adapt }.map { $0.abbreviation.lowercased() })
        var result = Set(counts.filter { $0.value > 1 }.map(\.key))
        for snippet in snippets where snippet.caseMode == .exact && foldedAdapt.contains(snippet.abbreviation.lowercased()) {
            result.insert(key(snippet))
            result.insert("~" + snippet.abbreviation.lowercased())
        }
        return result
    }

    static func key(_ snippet: Snippet) -> String {
        snippet.caseMode == .adapt ? "~" + snippet.abbreviation.lowercased() : snippet.abbreviation
    }

    private static func rank(_ warning: AbbreviationWarning) -> Int {
        switch warning {
        case .duplicate: 0
        case .shadowedBy: 1
        case .shadows: 2
        case .plainWord: 3
        }
    }
}
