import Foundation

/// The case of what was typed for an "adapt case" match.
public enum TypedCase: Sendable, Equatable {
    case asWritten
    /// `Addr`: first letter in capitals.
    case capitalized
    /// `ADDR`: all letters in capitals.
    case upper
}

/// A reversed trie of every expandable abbreviation, walked from the newest typed character
/// backwards. Immutable once built; the tap thread swaps in a new one when the library
/// changes. Lookups cost at most one dictionary probe per typed character (≤ 32) and never
/// allocate.
public final class AbbreviationIndex: @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public var snippetID: UUID
        public var length: Int
        public var caseMode: CaseMode
    }

    public let entries: [Entry]
    private let exact: Trie
    private let folded: Trie

    public static let empty = AbbreviationIndex(snippets: [])

    /// Snippets with a duplicated abbreviation are left out: none of them expand until the
    /// clash is fixed, so nobody gets the wrong text.
    public init(snippets: [Snippet]) {
        let duplicates = ConflictChecker.duplicateAbbreviations(in: snippets)
        var entries: [Entry] = []
        var exact = Trie()
        var folded = Trie()
        for snippet in snippets where !duplicates.contains(ConflictChecker.key(snippet)) {
            let scalars = snippet.abbreviation.unicodeScalars.map(\.value)
            guard !scalars.isEmpty, scalars.count <= RollingBuffer.capacity else { continue }
            let index = Int32(entries.count)
            entries.append(Entry(snippetID: snippet.id, length: scalars.count, caseMode: snippet.caseMode))
            switch snippet.caseMode {
            case .exact: exact.insert(scalars.reversed(), entry: index)
            case .adapt: folded.insert(scalars.reversed().map(CharacterClass.fold), entry: index)
            }
        }
        self.entries = entries
        self.exact = exact
        self.folded = folded
    }

    public var isEmpty: Bool { entries.isEmpty }

    public struct Hit: Sendable, Equatable {
        public var entry: Int
        public var length: Int
        public var typedCase: TypedCase
    }

    /// The longest abbreviation ending at the newest character that passes the word rule.
    /// Exact matches win ties.
    @inline(__always)
    public func match(_ buffer: RollingBuffer, wordStartOnly: Bool) -> Hit? {
        guard !buffer.isEmpty, !entries.isEmpty else { return nil }
        let exactHit = exact.longest(in: buffer, fold: false, wordStartOnly: wordStartOnly)
        let foldedHit = folded.longest(in: buffer, fold: true, wordStartOnly: wordStartOnly)
        let pick: (entry: Int32, length: Int)?
        switch (exactHit, foldedHit) {
        case let (e?, f?): pick = f.length > e.length ? f : e
        case let (e?, nil): pick = e
        case let (nil, f?): pick = f
        case (nil, nil): pick = nil
        }
        guard let pick else { return nil }
        let entry = entries[Int(pick.entry)]
        let typedCase = entry.caseMode == .adapt ? Self.typedCase(buffer, length: pick.length) : .asWritten
        return Hit(entry: Int(pick.entry), length: pick.length, typedCase: typedCase)
    }

    @inline(__always)
    static func typedCase(_ buffer: RollingBuffer, length: Int) -> TypedCase {
        var letters = 0
        var uppers = 0
        var firstLetterUpper = false
        for i in stride(from: length - 1, through: 0, by: -1) {
            let value = buffer.fromEnd(i)
            guard CharacterClass.isLetter(value) else { continue }
            let upper = CharacterClass.isUpper(value)
            if letters == 0 { firstLetterUpper = upper }
            letters += 1
            if upper { uppers += 1 }
        }
        if letters >= 2 && uppers == letters { return .upper }
        if firstLetterUpper { return .capitalized }
        return .asWritten
    }

    struct Trie {
        /// (node << 32 | scalar) → child node.
        var edges: [UInt64: Int32] = [:]
        /// Entry index per node, or -1.
        var terminal: [Int32] = [-1]

        mutating func insert<S: Sequence>(_ reversed: S, entry: Int32) where S.Element == UInt32 {
            var node: Int32 = 0
            for scalar in reversed {
                let key = UInt64(UInt32(bitPattern: node)) << 32 | UInt64(scalar)
                if let next = edges[key] {
                    node = next
                } else {
                    let next = Int32(terminal.count)
                    terminal.append(-1)
                    edges[key] = next
                    node = next
                }
            }
            terminal[Int(node)] = entry
        }

        @inline(__always)
        func longest(in buffer: RollingBuffer, fold: Bool, wordStartOnly: Bool) -> (entry: Int32, length: Int)? {
            guard !edges.isEmpty else { return nil }
            var node: Int32 = 0
            var best: (entry: Int32, length: Int)?
            for i in 0..<buffer.count {
                let raw = buffer.fromEnd(i)
                let scalar = fold ? CharacterClass.fold(raw) : raw
                guard let next = edges[UInt64(UInt32(bitPattern: node)) << 32 | UInt64(scalar)] else { break }
                node = next
                let entry = terminal[Int(node)]
                if entry >= 0 {
                    let length = i + 1
                    if !wordStartOnly || !buffer.isWordBefore(length: length) { best = (entry, length) }
                }
            }
            return best
        }
    }
}
