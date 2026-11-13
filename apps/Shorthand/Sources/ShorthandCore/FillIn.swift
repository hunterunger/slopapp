import Foundation

/// One control in the fill-in form. Fields with the same name (in the snippet or the
/// snippets it includes) are one control, filled once.
public struct FillField: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case text(defaultValue: String)
        case choice(options: [String])
        /// An optional section: included or not.
        case section(defaultOn: Bool)
    }

    /// As first written.
    public var name: String
    public var kind: Kind
    /// The section this field only appears inside (its key), so the form can dim it when
    /// that section is off. Nil when it also appears outside.
    public var onlyInSection: String?

    public var id: String { key }
    /// Names match ignoring case and accents: `Name` and `name` are one field.
    public var key: String { FillValues.key(name) }

    public init(name: String, kind: Kind, onlyInSection: String? = nil) {
        self.name = name
        self.kind = kind
        self.onlyInSection = onlyInSection
    }

    public var defaultValue: FillValue {
        switch kind {
        case .text(let value): .text(value)
        case .choice(let options): .text(options.first ?? "")
        case .section(let on): .flag(on)
        }
    }
}

public enum FillValue: Sendable, Equatable {
    case text(String)
    case flag(Bool)
}

/// What the person filled in, by field name. Only ever in memory, never stored.
public struct FillValues: Sendable, Equatable {
    public var values: [String: FillValue] = [:]

    public init(_ values: [String: FillValue] = [:]) {
        self.values = [:]
        for (name, value) in values { self.values[Self.key(name)] = value }
    }

    public static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public subscript(name: String) -> FillValue? {
        get { values[Self.key(name)] }
        set { values[Self.key(name)] = newValue }
    }

    public func text(_ name: String) -> String? {
        if case .text(let value)? = values[Self.key(name)] { return value }
        return nil
    }

    public func flag(_ name: String) -> Bool? {
        if case .flag(let value)? = values[Self.key(name)] { return value }
        return nil
    }

    /// Every field at its default.
    public static func defaults(_ fields: [FillField]) -> FillValues {
        var values = FillValues()
        for field in fields { values.values[field.key] = field.defaultValue }
        return values
    }
}

/// Walks a snippet's tokens and the snippets it includes, depth first, each snippet at most
/// once per path (cycles stop), at most `PlaceholderResolver.nestingLimit` deep.
enum TemplateWalker {
    /// `visit(token, sections)`: sections = the keys of the optional sections open around it.
    static func walk(_ snippet: Snippet, lookup: (String) -> Snippet?, visit: (Token, [String]) -> Void) {
        var path: [UUID] = [snippet.id]
        walk(snippet.content, lookup: lookup, path: &path, outerSections: [], visit: visit)
    }

    private static func walk(_ content: String, lookup: (String) -> Snippet?, path: inout [UUID], outerSections: [String],
                             visit: (Token, [String]) -> Void) {
        var sections = outerSections
        for token in PlaceholderParser.tokens(content) {
            switch token.segment {
            case .placeholder(.optionalStart(let name, _), _):
                visit(token, sections)
                sections.append(FillValues.key(name))
            case .placeholder(.optionalEnd, _):
                if sections.count > outerSections.count { sections.removeLast() }
                visit(token, sections)
            case .placeholder(.snippet(let abbreviation), _):
                visit(token, sections)
                guard let nested = lookup(abbreviation), !path.contains(nested.id),
                      path.count < PlaceholderResolver.nestingLimit else { continue }
                path.append(nested.id)
                walk(nested.content, lookup: lookup, path: &path, outerSections: sections, visit: visit)
                path.removeLast()
            default:
                visit(token, sections)
            }
        }
    }
}

public enum FillIn {
    /// The form's controls, in the order they first appear (included snippets too). Empty:
    /// the snippet expands straight away.
    public static func fields(for snippet: Snippet, lookup: (String) -> Snippet?) -> [FillField] {
        var fields: [FillField] = []
        var index: [String: Int] = [:]
        TemplateWalker.walk(snippet, lookup: lookup) { token, sections in
            let field: FillField
            switch token.segment {
            case .placeholder(.field(let name, let defaultValue), _):
                field = FillField(name: name, kind: .text(defaultValue: defaultValue), onlyInSection: sections.last)
            case .placeholder(.choice(let name, let options), _):
                field = FillField(name: name, kind: .choice(options: options), onlyInSection: sections.last)
            case .placeholder(.optionalStart(let name, let defaultOn), _):
                field = FillField(name: name, kind: .section(defaultOn: defaultOn), onlyInSection: sections.last)
            default:
                return
            }
            if let existing = index[field.key] {
                // Seen outside any section now: never dim it.
                if fields[existing].onlyInSection != field.onlyInSection { fields[existing].onlyInSection = nil }
                return
            }
            index[field.key] = fields.count
            fields.append(field)
        }
        // A field inside a section that is itself the field's own key can't dim itself.
        for i in fields.indices where fields[i].onlyInSection == fields[i].key { fields[i].onlyInSection = nil }
        return fields
    }

    public static func hasFields(_ snippet: Snippet, lookup: (String) -> Snippet?) -> Bool {
        !fields(for: snippet, lookup: lookup).isEmpty
    }
}

/// Problems in a snippet's placeholders the editor points out.
public enum TemplateNote: Sendable, Equatable, Hashable {
    /// `{snippet:x}` but no snippet has the abbreviation x.
    case missingSnippet(String)
    /// `{snippet:x}` would include itself, directly or through others.
    case cycle(String)
    /// `{/optional}` with no section open.
    case strayEnd
    /// `{optional:x}` never closed: runs to the end of the snippet.
    case unclosed(String)
    /// The same name used for different kinds of fill-in (the first one wins).
    case nameClash(String)

    public var message: String {
        switch self {
        case .missingSnippet(let abbreviation): "No snippet has the abbreviation “\(abbreviation)”, so nothing goes there."
        case .cycle(let abbreviation): "“\(abbreviation)” would include itself, so it's left out there."
        case .strayEnd: "There's a {/optional} with no {optional:…} before it."
        case .unclosed(let name): "The optional section “\(name)” has no {/optional}, so it runs to the end."
        case .nameClash(let name): "“\(name)” names two kinds of fill-in; the form shows the first one."
        }
    }
}

public enum TemplateCheck {
    public static func notes(for snippet: Snippet, lookup: (String) -> Snippet?) -> [TemplateNote] {
        var notes: [TemplateNote] = []
        func add(_ note: TemplateNote) { if !notes.contains(note) { notes.append(note) } }
        // Sections and references in this snippet's own text.
        var open: [String] = []
        for token in PlaceholderParser.tokens(snippet.content) {
            switch token.segment {
            case .placeholder(.optionalStart(let name, _), _): open.append(name)
            case .placeholder(.optionalEnd, _): if open.isEmpty { add(.strayEnd) } else { open.removeLast() }
            case .placeholder(.snippet(let abbreviation), _):
                guard let nested = lookup(abbreviation) else { add(.missingSnippet(abbreviation)); continue }
                if nested.id == snippet.id || reaches(nested, target: snippet.id, lookup: lookup) { add(.cycle(abbreviation)) }
            default: break
            }
        }
        for name in open { add(.unclosed(name)) }
        // The same name for two kinds, anywhere in what it includes.
        var kinds: [String: (name: String, kind: Int)] = [:]
        TemplateWalker.walk(snippet, lookup: lookup) { token, _ in
            let entry: (String, Int)
            switch token.segment {
            case .placeholder(.field(let name, _), _): entry = (name, 0)
            case .placeholder(.choice(let name, _), _): entry = (name, 1)
            case .placeholder(.optionalStart(let name, _), _): entry = (name, 2)
            default: return
            }
            let key = FillValues.key(entry.0)
            if let seen = kinds[key] {
                if seen.kind != entry.1 { add(.nameClash(seen.name)) }
            } else {
                kinds[key] = entry
            }
        }
        return notes
    }

    /// Whether `snippet` includes `target`, directly or through others.
    static func reaches(_ snippet: Snippet, target: UUID, lookup: (String) -> Snippet?) -> Bool {
        var seen: Set<UUID> = [snippet.id]
        var stack = [snippet]
        while let next = stack.popLast() {
            for token in PlaceholderParser.tokens(next.content) {
                guard case .placeholder(.snippet(let abbreviation), _) = token.segment, let nested = lookup(abbreviation) else { continue }
                if nested.id == target { return true }
                if seen.insert(nested.id).inserted { stack.append(nested) }
            }
        }
        return false
    }
}
