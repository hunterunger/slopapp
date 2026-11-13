import Foundation

/// A placeholder inside snippet content, written in braces:
///
/// - `{date}` `{date:short}` `{date:long}` `{date:full}` `{date:iso}`: today in the system's
///   formats (`medium` is the default); `{time}` `{time:medium}`; `{datetime}`.
/// - Offsets: `{date:+1d}` `{date:long -2w}` `{time:+30m}` (d, w, M months, y, h, m).
/// - Custom: `{date:format=EEE d MMM}` (a Unicode date pattern, to the closing brace).
/// - `{clipboard}`: the clipboard's plain text.
/// - `{cursor}`: where the caret ends up.
/// - Fill-ins, asked for in a small form when the snippet expands (one field per name):
///   `{field:Name}` `{field:Name=default}`; `{choice:Name|first|second}` (the first is
///   preselected); `{optional:Name}…{/optional}` (on by default; `{optional:Name=off}`).
/// - `{snippet:;abbr}`: another snippet's text, by its abbreviation.
/// - `{{` and `}}` type a literal brace.
public enum Placeholder: Sendable, Equatable, Hashable {
    case date(DateSpec)
    case clipboard
    case cursor
    case field(name: String, defaultValue: String)
    case choice(name: String, options: [String])
    case optionalStart(name: String, defaultOn: Bool)
    case optionalEnd
    case snippet(abbreviation: String)
}

public struct DateSpec: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable { case date, time, datetime }
    public enum Style: String, Sendable, CaseIterable { case short, medium, long, full, iso }

    public var kind: Kind
    public var style: Style
    public var offset: DateOffset?
    /// A Unicode date pattern; wins over `style`.
    public var format: String?

    public init(kind: Kind, style: Style? = nil, offset: DateOffset? = nil, format: String? = nil) {
        self.kind = kind
        self.style = style ?? (kind == .time ? .short : .medium)
        self.offset = offset
        self.format = format
    }
}

public struct DateOffset: Sendable, Equatable, Hashable {
    public enum Unit: Character, Sendable { case day = "d", week = "w", month = "M", year = "y", hour = "h", minute = "m" }
    public var amount: Int
    public var unit: Unit

    public init(amount: Int, unit: Unit) {
        self.amount = amount
        self.unit = unit
    }

    /// `+1d`, `-2w`, `+3M`.
    public init?(_ text: Substring) {
        guard let sign = text.first, sign == "+" || sign == "-", let last = text.last,
              let unit = Unit(rawValue: last), text.count >= 3,
              let value = Int(text.dropFirst().dropLast()), value <= 100_000 else { return nil }
        self.amount = sign == "-" ? -value : value
        self.unit = unit
    }

    public var text: String { (amount < 0 ? "-" : "+") + "\(abs(amount))\(unit.rawValue)" }

    public func apply(to date: Date, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch unit {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .hour: .hour
        case .minute: .minute
        }
        return calendar.date(byAdding: component, value: amount, to: date) ?? date
    }
}

/// Parsed snippet content.
public enum Segment: Sendable, Equatable {
    case text(String)
    case placeholder(Placeholder, raw: String)
    /// Looks like a placeholder but isn't one we know: typed as written, flagged in the editor.
    case unknown(String)
}

/// A segment and where it sits in the content, in UTF-16 offsets (the same offsets as the
/// snippet's formatted text, so formatting can follow the text through placeholders).
/// A literal run never contains an escape: `{{` is its own token, so a literal token's text
/// is exactly its source.
public struct Token: Sendable, Equatable {
    public var segment: Segment
    public var range: Range<Int>

    public init(_ segment: Segment, _ range: Range<Int>) {
        self.segment = segment
        self.range = range
    }
}

public enum PlaceholderParser {
    /// Segments, adjacent literal text joined.
    public static func parse(_ content: String) -> [Segment] {
        var segments: [Segment] = []
        for token in tokens(content) {
            if case .text(let piece) = token.segment, case .text(let previous)? = segments.last {
                segments[segments.count - 1] = .text(previous + piece)
            } else {
                segments.append(token.segment)
            }
        }
        return segments
    }

    public static func tokens(_ content: String) -> [Token] {
        var tokens: [Token] = []
        var literal = ""
        var literalStart = 0
        var offset = 0
        var index = content.startIndex
        func flush() {
            if !literal.isEmpty { tokens.append(Token(.text(literal), literalStart..<offset)); literal = "" }
            literalStart = offset
        }
        while index < content.endIndex {
            let character = content[index]
            let next = content.index(after: index)
            if (character == "{" || character == "}"), next < content.endIndex, content[next] == character {
                flush()
                tokens.append(Token(.text(String(character)), offset..<offset + 2))
                offset += 2
                literalStart = offset
                index = content.index(after: next)
                continue
            }
            if character == "{", let close = content[next...].firstIndex(where: { $0 == "}" || $0 == "{" || $0 == "\n" }),
               content[close] == "}" {
                flush()
                let body = content[next..<close]
                let raw = String(content[index...close])
                let length = raw.utf16.count
                if let placeholder = placeholder(body) {
                    tokens.append(Token(.placeholder(placeholder, raw: raw), offset..<offset + length))
                } else {
                    tokens.append(Token(.unknown(raw), offset..<offset + length))
                }
                offset += length
                literalStart = offset
                index = content.index(after: close)
                continue
            }
            literal.append(character)
            offset += character.utf16.count
            index = next
        }
        flush()
        return tokens
    }

    static func placeholder(_ body: Substring) -> Placeholder? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "/optional" { return .optionalEnd }
        let name: Substring
        let argument: Substring
        if let colon = trimmed.firstIndex(of: ":") {
            name = trimmed[..<colon]
            argument = trimmed[trimmed.index(after: colon)...]
        } else {
            name = Substring(trimmed)
            argument = ""
        }
        switch name.lowercased() {
        case "clipboard": return argument.isEmpty ? .clipboard : nil
        case "cursor": return argument.isEmpty ? .cursor : nil
        case "date": return dateSpec(.date, argument).map(Placeholder.date)
        case "time": return dateSpec(.time, argument).map(Placeholder.date)
        case "datetime": return dateSpec(.datetime, argument).map(Placeholder.date)
        case "field":
            let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let fieldName = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard !fieldName.isEmpty else { return nil }
            return .field(name: fieldName, defaultValue: parts.count > 1 ? String(parts[1]) : "")
        case "choice":
            let parts = argument.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let choiceName = parts.first, !choiceName.isEmpty else { return nil }
            let options = parts.dropFirst().filter { !$0.isEmpty }
            guard !options.isEmpty else { return nil }
            return .choice(name: choiceName, options: Array(options))
        case "optional":
            let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let sectionName = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard !sectionName.isEmpty else { return nil }
            guard parts.count > 1 else { return .optionalStart(name: sectionName, defaultOn: true) }
            switch parts[1].trimmingCharacters(in: .whitespaces).lowercased() {
            case "on", "yes": return .optionalStart(name: sectionName, defaultOn: true)
            case "off", "no": return .optionalStart(name: sectionName, defaultOn: false)
            default: return nil
            }
        case "snippet":
            let abbreviation = argument.trimmingCharacters(in: .whitespaces)
            return abbreviation.isEmpty ? nil : .snippet(abbreviation: abbreviation)
        default: return nil
        }
    }

    static func dateSpec(_ kind: DateSpec.Kind, _ argument: Substring) -> DateSpec? {
        var spec = DateSpec(kind: kind)
        var rest = argument.drop { $0 == " " }
        while !rest.isEmpty {
            if rest.hasPrefix("format=") {
                let pattern = String(rest.dropFirst("format=".count))
                guard !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                spec.format = pattern
                return spec
            }
            let word = rest.prefix { $0 != " " }
            rest = rest.dropFirst(word.count).drop { $0 == " " }
            if let style = DateSpec.Style(rawValue: word.lowercased()) {
                spec.style = style
            } else if let offset = DateOffset(word) {
                guard spec.offset == nil else { return nil }
                spec.offset = offset
            } else {
                return nil
            }
        }
        return spec
    }

    /// The text that inserts `placeholder` in the editor.
    public static func token(for placeholder: Placeholder) -> String {
        switch placeholder {
        case .clipboard: return "{clipboard}"
        case .cursor: return "{cursor}"
        case .date(let spec):
            var parts: [String] = []
            let defaultStyle: DateSpec.Style = spec.kind == .time ? .short : .medium
            if spec.style != defaultStyle && spec.format == nil { parts.append(spec.style.rawValue) }
            if let offset = spec.offset { parts.append(offset.text) }
            if let format = spec.format { parts.append("format=" + format) }
            return "{" + spec.kind.rawValue + (parts.isEmpty ? "" : ":" + parts.joined(separator: " ")) + "}"
        case .field(let name, let defaultValue):
            return "{field:" + name + (defaultValue.isEmpty ? "" : "=" + defaultValue) + "}"
        case .choice(let name, let options):
            return "{choice:" + ([name] + options).joined(separator: "|") + "}"
        case .optionalStart(let name, let defaultOn):
            return "{optional:" + name + (defaultOn ? "" : "=off") + "}"
        case .optionalEnd:
            return "{/optional}"
        case .snippet(let abbreviation):
            return "{snippet:" + abbreviation + "}"
        }
    }

    /// Escapes literal text so it types exactly as written (braces doubled).
    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "{", with: "{{").replacingOccurrences(of: "}", with: "}}")
    }
}

/// What a `{clipboard}` placeholder can get.
public enum ClipboardValue: Sendable, Equatable {
    case text(String)
    /// Empty, an image or files: inserts nothing.
    case none
    /// A password manager marked it concealed: inserts nothing.
    case concealed
    /// macOS would ask (or refuses) before Shorthand reads it: inserts nothing.
    case notAllowed
}

/// One run of the resolved text and where it came from, so formatted snippets can carry
/// their formatting (and images) through: literal text keeps its own formatting; text a
/// placeholder made takes the formatting of the placeholder.
public struct Piece: Sendable, Equatable {
    public var text: String
    /// The snippet whose content this came from (nil: content resolved on its own).
    public var snippetID: UUID?
    /// UTF-16 range in that snippet's content: the literal text, or the placeholder.
    public var source: Range<Int>
    /// Made by a placeholder (date, field, clipboard...), not copied from the content.
    public var generated: Bool

    public init(text: String, snippetID: UUID?, source: Range<Int>, generated: Bool) {
        self.text = text
        self.snippetID = snippetID
        self.source = source
        self.generated = generated
    }
}

/// The resolved text of a snippet.
public struct Resolved: Sendable, Equatable {
    /// Plain text (images left out).
    public var text: String
    /// Characters after the `{cursor}` marker (← presses after inserting). 0 = at the end.
    public var charactersAfterCursor: Int
    public var usedClipboard: Bool
    /// `{clipboard}` couldn't be read because of macOS's paste privacy.
    public var clipboardBlocked: Bool
    public var unknownPlaceholders: [String]
    /// Every run, in order, images (U+FFFC) included.
    public var pieces: [Piece] = []
    /// Images after the cursor (each is one ← in a formatted paste).
    public var attachmentsAfterCursor = 0
    /// A formatted snippet (this one or one it includes) is part of it: it's pasted as rich text.
    public var isFormatted = false
    /// Snippets included with `{snippet:…}`, in order.
    public var includedSnippets: [UUID] = []
    /// `{snippet:…}` references with no such abbreviation.
    public var missingSnippets: [String] = []
    /// `{snippet:…}` references that would include themselves (left out).
    public var cyclicSnippets: [String] = []

    /// The text before the caret once inserted (the next abbreviation's context).
    public var textBeforeCursor: String {
        String(text.dropLast(charactersAfterCursor))
    }

    /// ← presses for a formatted paste, where an image is one position.
    public var formattedCharactersAfterCursor: Int { charactersAfterCursor + attachmentsAfterCursor }
}

/// The object replacement character an image stands on in formatted text.
public let attachmentCharacter: Character = "\u{FFFC}"

public struct PlaceholderResolver: Sendable {
    /// Longest clipboard text inserted.
    public static let clipboardLimit = 100_000
    /// How deep `{snippet:…}` may nest.
    public static let nestingLimit = 8

    public var now: Date
    public var locale: Locale
    public var calendar: Calendar
    public var timeZone: TimeZone

    public init(now: Date, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.now = now
        self.locale = locale
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    /// Whether `content` needs the clipboard (so it's only read when it does).
    public static func needsClipboard(_ content: String) -> Bool {
        PlaceholderParser.parse(content).contains { if case .placeholder(.clipboard, _) = $0 { true } else { false } }
    }

    /// Whether `snippet`, or a snippet it includes, needs the clipboard.
    public static func needsClipboard(_ snippet: Snippet, lookup: (String) -> Snippet?) -> Bool {
        var found = false
        TemplateWalker.walk(snippet, lookup: lookup) { token, _ in
            if case .placeholder(.clipboard, _) = token.segment { found = true }
        }
        return found
    }

    public func resolve(_ content: String, typedCase: TypedCase = .asWritten, clipboard: () -> ClipboardValue) -> Resolved {
        var state = ResolveState(values: FillValues(), lookup: { _ in nil })
        withoutActuallyEscaping(clipboard) { clipboard in
            resolveContent(content, snippetID: nil, formatted: false, typedCase: typedCase, outer: true, state: &state, clipboard: clipboard)
        }
        return state.result()
    }

    /// Resolves a snippet with fill-in `values` (missing ones take their defaults) and nested
    /// snippets found by abbreviation with `lookup`.
    public func resolve(_ snippet: Snippet, typedCase: TypedCase = .asWritten, values: FillValues = FillValues(),
                        lookup: @escaping (String) -> Snippet?, clipboard: () -> ClipboardValue) -> Resolved {
        // A name used twice fills once: missing values take the first occurrence's default.
        var merged = FillValues.defaults(FillIn.fields(for: snippet, lookup: lookup))
        merged.values.merge(values.values) { $1 }
        var state = ResolveState(values: merged, lookup: lookup)
        state.visiting = [snippet.id]
        withoutActuallyEscaping(clipboard) { clipboard in
            resolveContent(snippet.content, snippetID: snippet.id, formatted: snippet.isFormatted, typedCase: typedCase, outer: true,
                           state: &state, clipboard: clipboard)
        }
        return state.result()
    }

    private func resolveContent(_ content: String, snippetID: UUID?, formatted: Bool, typedCase: TypedCase, outer: Bool,
                                state: inout ResolveState, clipboard: () -> ClipboardValue) {
        if formatted { state.isFormatted = true }
        // Optional sections: whether each open one is included.
        var sections: [Bool] = []
        var included: Bool { sections.allSatisfy { $0 } }
        var capitalisePending = outer && typedCase == .capitalized
        for token in PlaceholderParser.tokens(content) {
            switch token.segment {
            case .placeholder(.optionalStart(let name, let defaultOn), _):
                sections.append(state.values.flag(name) ?? defaultOn)
                capitalisePending = false
                continue
            case .placeholder(.optionalEnd, _):
                if !sections.isEmpty { sections.removeLast() }
                continue
            default:
                break
            }
            guard included else { continue }
            func emit(_ text: String, generated: Bool) {
                state.append(Piece(text: text, snippetID: snippetID, source: token.range, generated: generated))
            }
            switch token.segment {
            case .text(let literal):
                var text = literal
                if outer && typedCase == .upper {
                    text = text.uppercased()
                } else if capitalisePending, text.contains(where: { $0.isLetter }) {
                    text = CaseAdapter.apply(.capitalized, toStartOf: text)
                    capitalisePending = false
                }
                emit(text, generated: false)
            case .unknown(let raw):
                state.unknown.append(raw)
                emit(raw, generated: false)
                capitalisePending = false
            case .placeholder(let placeholder, _):
                capitalisePending = false
                switch placeholder {
                case .cursor:
                    state.markCursor()
                case .clipboard:
                    let value = state.clipboard ?? clipboard()
                    state.clipboard = value
                    state.usedClipboard = true
                    switch value {
                    case .text(let string): emit(String(string.prefix(Self.clipboardLimit)), generated: true)
                    case .notAllowed: state.blocked = true
                    case .none, .concealed: break
                    }
                case .date(let spec):
                    emit(format(spec), generated: true)
                case .field(let name, let defaultValue):
                    emit(state.values.text(name) ?? defaultValue, generated: true)
                case .choice(let name, let options):
                    emit(state.values.text(name) ?? options[0], generated: true)
                case .snippet(let abbreviation):
                    guard let nested = state.lookup(abbreviation) else {
                        state.missing.append(abbreviation)
                        continue
                    }
                    guard !state.visiting.contains(nested.id), state.visiting.count < Self.nestingLimit else {
                        state.cyclic.append(abbreviation)
                        continue
                    }
                    state.visiting.append(nested.id)
                    state.included.append(nested.id)
                    resolveContent(nested.content, snippetID: nested.id, formatted: nested.isFormatted, typedCase: .asWritten,
                                   outer: false, state: &state, clipboard: clipboard)
                    state.visiting.removeLast()
                case .optionalStart, .optionalEnd:
                    break
                }
            }
        }
    }

    public func format(_ spec: DateSpec) -> String {
        let date = spec.offset?.apply(to: now, calendar: calendar) ?? now
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        if let format = spec.format {
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        if spec.style == .iso {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = switch spec.kind {
            case .date: "yyyy-MM-dd"
            case .time: "HH:mm"
            case .datetime: "yyyy-MM-dd'T'HH:mm"
            }
            return formatter.string(from: date)
        }
        let style: DateFormatter.Style = switch spec.style {
        case .short: .short
        case .medium, .iso: .medium
        case .long: .long
        case .full: .full
        }
        formatter.dateStyle = spec.kind == .time ? .none : style
        formatter.timeStyle = spec.kind == .date ? .none : (spec.kind == .datetime ? .short : style)
        return formatter.string(from: date)
    }
}

/// Everything collected while resolving (one snippet and the ones it includes).
struct ResolveState {
    var values: FillValues
    var lookup: (String) -> Snippet?
    var pieces: [Piece] = []
    /// Index of the first piece after the cursor.
    var cursorPiece: Int?
    var usedClipboard = false
    var blocked = false
    var clipboard: ClipboardValue?
    var unknown: [String] = []
    var isFormatted = false
    var visiting: [UUID] = []
    var included: [UUID] = []
    var missing: [String] = []
    var cyclic: [String] = []

    mutating func append(_ piece: Piece) {
        guard !piece.text.isEmpty else { return }
        pieces.append(piece)
    }

    mutating func markCursor() {
        if cursorPiece == nil { cursorPiece = pieces.count }
    }

    func result() -> Resolved {
        let split = cursorPiece ?? pieces.count
        var before = ""
        var after = ""
        var attachmentsAfter = 0
        for (index, piece) in pieces.enumerated() {
            if index < split {
                before += piece.text
            } else {
                after += piece.text
                attachmentsAfter += piece.text.reduce(0) { $0 + ($1 == attachmentCharacter ? 1 : 0) }
            }
        }
        let plainBefore = before.filter { $0 != attachmentCharacter }
        let plainAfter = after.filter { $0 != attachmentCharacter }
        return Resolved(text: plainBefore + plainAfter, charactersAfterCursor: plainAfter.count, usedClipboard: usedClipboard,
                        clipboardBlocked: blocked, unknownPlaceholders: unknown, pieces: pieces, attachmentsAfterCursor: attachmentsAfter,
                        isFormatted: isFormatted, includedSnippets: included, missingSnippets: missing, cyclicSnippets: cyclic)
    }
}

/// "Adapt case": the expansion follows how the abbreviation was typed.
public enum CaseAdapter {
    public static func apply(_ typedCase: TypedCase, toStartOf text: String) -> String {
        switch typedCase {
        case .asWritten: return text
        case .upper: return text.uppercased()
        case .capitalized:
            guard let index = text.firstIndex(where: { $0.isLetter }) else { return text }
            return text[..<index] + text[index].uppercased() + text[text.index(after: index)...]
        }
    }
}
