import Foundation

/// A UTF-16 range of some text and what replaces it.
public struct TextEdit: Sendable, Equatable {
    public var range: Range<Int>
    public var replacement: String

    public init(_ range: Range<Int>, _ replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    /// Applies edits (any order, not overlapping) to plain text.
    public static func apply(_ edits: [TextEdit], to text: String) -> String {
        var units = Array(text.utf16)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) where edit.range.upperBound <= units.count {
            units.replaceSubrange(edit.range, with: Array(edit.replacement.utf16))
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Edits that double every brace (so text from elsewhere types exactly as written).
    public static func escapingBraces(in text: String, from offset: Int = 0) -> [TextEdit] {
        var edits: [TextEdit] = []
        var position = offset
        for unit in text.utf16 {
            if unit == 0x7B { edits.append(TextEdit(position..<position + 1, "{{")) }
            if unit == 0x7D { edits.append(TextEdit(position..<position + 1, "}}")) }
            position += 1
        }
        return edits
    }
}

/// One snippet found in a file from another app (or this Mac's Text Replacements), already
/// in Shorthand's terms.
public struct ImportEntry: Sendable, Equatable {
    public var abbreviation: String
    /// Shorthand placeholders, braces escaped. For a formatted one, the plain text of `richText`.
    public var content: String
    public var richText: Data?
    public var name: String
    public var groupName: String
    public var caseMode: CaseMode
    /// Shown in the preview instead of `content` (Text Replacements show what macOS types).
    public var preview: String?
    /// What couldn't be carried over, in plain words ("A key press (Tab) was left out").
    public var notes: [String]
    /// Can't be imported at all (a script, a regex trigger), and why.
    public var unsupported: String?

    public init(abbreviation: String, content: String, richText: Data? = nil, name: String = "", groupName: String,
                caseMode: CaseMode = .exact, preview: String? = nil, notes: [String] = [], unsupported: String? = nil) {
        self.abbreviation = abbreviation
        self.content = content
        self.richText = richText
        self.name = name
        self.groupName = groupName
        self.caseMode = caseMode
        self.preview = preview
        self.notes = notes
        self.unsupported = unsupported
    }
}

/// One row of the import preview.
public struct ImportCandidate: Sendable, Equatable, Identifiable {
    public enum Issue: Sendable, Equatable {
        /// Shorthand already has this abbreviation.
        case alreadyInLibrary
        /// The same abbreviation appears earlier in what's being imported.
        case repeated
        case invalid(AbbreviationRules.Problem)
        case emptyText
        /// Something Shorthand can't do at all (a script snippet).
        case unsupported(String)
    }

    public var id: Int
    public var entry: ImportEntry
    public var issue: Issue?
    /// Ticked for import: on unless there's an issue.
    public var isSelected: Bool

    public var shortcut: String { entry.abbreviation }
    /// What the preview shows as the text.
    public var phrase: String { entry.preview ?? entry.content.filter { $0 != attachmentCharacter } }
    public var notes: [String] { entry.notes }

    public var reason: String? {
        switch issue {
        case nil: nil
        case .alreadyInLibrary: "Already in Shorthand"
        case .repeated: "Listed twice"
        case .emptyText: "No text"
        case .invalid(let problem): AbbreviationRules.message(for: problem)
        case .unsupported(let why): why
        }
    }

    /// Only clean rows can be ticked; invalid abbreviations can't expand.
    public var canSelect: Bool {
        switch issue {
        case nil, .alreadyInLibrary, .repeated: true
        case .invalid, .emptyText, .unsupported: false
        }
    }
}

/// Importing from any supported source: Text Replacements, TextExpander, espanso, CSV and
/// Shorthand's own export. The readers produce `ImportEntry`s; this checks and applies them.
public enum SnippetImport {
    public enum Format: String, Sendable, Equatable {
        case textReplacements, textExpander, espanso, csv, shorthand

        public var displayName: String {
            switch self {
            case .textReplacements: "Text Replacements"
            case .textExpander: "TextExpander"
            case .espanso: "espanso"
            case .csv: "CSV"
            case .shorthand: "Shorthand"
            }
        }
    }

    public enum ReadError: Error, Equatable {
        /// Not a file Shorthand knows how to read.
        case unrecognised
        /// Looks like the format, but couldn't be read (with the reader's reason).
        case damaged(String)
    }

    public struct Result: Sendable, Equatable {
        public var format: Format
        public var entries: [ImportEntry]
        /// Notes about the file as a whole ("imports: in this file weren't followed").
        public var fileNotes: [String] = []
    }

    /// Reads a dropped or chosen file, working out which app it came from.
    /// `fileURL` (the file itself) resolves relative paths (espanso images).
    @MainActor
    public static func read(_ data: Data, fileURL: URL) throws -> Result {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil), !(plist is String) {
            if let array = plist as? [Any], let entries = try? TextReplacementsImport.entries(fromPlistArray: array) {
                return Result(format: .textReplacements, entries: TextReplacementsImport.importEntries(entries))
            }
            if let dictionary = plist as? [String: Any], dictionary["snippetsTE2"] != nil || dictionary["snippets"] != nil {
                return Result(format: .textExpander, entries: try TextExpanderImport.entries(fromPlist: dictionary, fallbackGroup: name))
            }
            if ext == "plist" || ext == "textexpander" { throw ReadError.unrecognised }
        }
        if ext == "json" || data.first == UInt8(ascii: "{") {
            if let library = try? SnippetStore.decode(data) { return Result(format: .shorthand, entries: ShorthandImport.entries(library)) }
            if ext == "json" { throw ReadError.unrecognised }
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ReadError.unrecognised }
        if ext == "csv" || ext == "tsv" {
            return Result(format: .csv, entries: CSVImport.entries(text, separator: ext == "tsv" ? "\t" : ",", groupName: name))
        }
        if ext == "yml" || ext == "yaml" || text.contains("matches:") {
            do {
                let (entries, notes) = try EspansoImport.entries(fromYAML: text, fileURL: fileURL)
                return Result(format: .espanso, entries: entries, fileNotes: notes)
            } catch let error as MiniYAML.ParseError {
                throw ReadError.damaged(error.description)
            }
        }
        throw ReadError.unrecognised
    }

    /// Rows for the preview sheet.
    public static func candidates(_ entries: [ImportEntry], library: Library) -> [ImportCandidate] {
        let existing = Set(library.snippets.map(\.abbreviation))
        var seen = Set<String>()
        return entries.enumerated().map { index, entry in
            var entry = entry
            entry.abbreviation = entry.abbreviation.trimmingCharacters(in: .whitespaces)
            entry.content = entry.content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            if let preview = entry.preview {
                entry.preview = preview.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            }
            var issue: ImportCandidate.Issue?
            if let why = entry.unsupported {
                issue = .unsupported(why)
            } else if let problem = AbbreviationRules.validate(entry.abbreviation) {
                issue = .invalid(problem)
            } else if entry.content.isEmpty {
                issue = .emptyText
            } else if existing.contains(entry.abbreviation) {
                issue = .alreadyInLibrary
            } else if !seen.insert(entry.abbreviation).inserted {
                issue = .repeated
            }
            return ImportCandidate(id: index, entry: entry, issue: issue, isSelected: issue == nil)
        }
    }

    /// Adds the ticked rows, each to its group (made if needed). Returns how many.
    @discardableResult
    public static func apply(_ candidates: [ImportCandidate], to library: inout Library, now: Date = Date()) -> Int {
        let chosen = candidates.filter { $0.isSelected && $0.canSelect }
        var groups: [String: UUID] = [:]
        for candidate in chosen {
            let entry = candidate.entry
            let groupID = groups[entry.groupName] ?? library.groups.first { $0.name == entry.groupName }?.id
                ?? library.addGroup(named: entry.groupName).id
            groups[entry.groupName] = groupID
            library.addSnippet(Snippet(groupID: groupID, name: entry.name, abbreviation: entry.abbreviation, content: entry.content,
                                       richText: entry.richText, caseMode: entry.caseMode, created: now))
        }
        return chosen.count
    }
}

/// macOS Text Replacements.
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
        return try entries(fromPlistArray: array)
    }

    static func entries(fromPlistArray array: [Any]) throws -> [(shortcut: String, phrase: String)] {
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

    /// In Shorthand's terms: literal braces are escaped so they type as written.
    public static func importEntries(_ entries: [(shortcut: String, phrase: String)]) -> [ImportEntry] {
        entries.map { entry in
            ImportEntry(abbreviation: entry.shortcut, content: PlaceholderParser.escape(entry.phrase), groupName: groupName, preview: entry.phrase)
        }
    }

    /// Rows for the preview sheet. Windows line endings become new lines.
    public static func candidates(_ entries: [(shortcut: String, phrase: String)], library: Library) -> [ImportCandidate] {
        SnippetImport.candidates(importEntries(entries), library: library)
    }

    /// Adds the ticked rows to a "Text Replacements" group (made if needed). Returns how many.
    /// macOS's own list is never edited.
    @discardableResult
    public static func apply(_ candidates: [ImportCandidate], to library: inout Library, now: Date = Date()) -> Int {
        SnippetImport.apply(candidates, to: &library, now: now)
    }
}

/// Shorthand's own export, as import rows (formatting, case and groups kept).
public enum ShorthandImport {
    public static func entries(_ library: Library) -> [ImportEntry] {
        library.snippets.map { snippet in
            ImportEntry(abbreviation: snippet.abbreviation, content: snippet.content, richText: snippet.richText, name: snippet.name,
                        groupName: library.group(snippet.groupID)?.name ?? Library.defaultGroupName, caseMode: snippet.caseMode)
        }
    }
}

/// Comma- (or tab-) separated rows: abbreviation, text, and optionally a name. A header row
/// is skipped. Quoted cells may hold commas, quotes ("") and new lines.
public enum CSVImport {
    public static func entries(_ text: String, separator: Character = ",", groupName: String) -> [ImportEntry] {
        var rows = parse(text, separator: separator)
        if let first = rows.first?.first?.lowercased().trimmingCharacters(in: .whitespaces),
           ["abbreviation", "shortcut", "trigger", "keyword", "abbr", "snippet"].contains(first) {
            rows.removeFirst()
        }
        return rows.compactMap { row in
            guard row.count >= 2 else { return nil }
            return ImportEntry(abbreviation: row[0], content: PlaceholderParser.escape(row[1]), name: row.count > 2 ? row[2] : "",
                               groupName: groupName, preview: row[1])
        }
    }

    public static func parse(_ text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var characters = Array(text)
        if characters.first == "\u{FEFF}" { characters.removeFirst() }
        var i = 0
        func endRow() {
            row.append(cell)
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
            cell = ""
        }
        while i < characters.count {
            let c = characters[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < characters.count, characters[i + 1] == "\"" { cell.append("\""); i += 1 } else { quoted = false }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" && cell.isEmpty {
                quoted = true
            } else if c == separator {
                row.append(cell)
                cell = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                endRow()
            } else {
                cell.append(c)
            }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
