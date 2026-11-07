import Foundation

// MARK: - CSS (also SCSS and LESS: nesting, variables and // comments)

public enum CSSFormatter {
    enum Piece {
        case prelude(String)       // followed by "{"
        case declaration(String)   // ended by ";" or "}"
        case close
        case comment(String)
    }

    /// Splits CSS into rule heads, declarations, closes and comments, respecting strings,
    /// comments and parentheses (so `url(a;b)` and `"a{b"` don't split).
    static func pieces(_ css: String) -> [Piece] {
        var result: [Piece] = []
        var buffer = ""
        var parens = 0
        let characters = Array(css)
        var index = 0
        func flushDeclaration() {
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(.declaration(text)) }
            buffer = ""
        }
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "/", next == "*" {
                var end = index + 2
                while end + 1 < characters.count, !(characters[end] == "*" && characters[end + 1] == "/") { end += 1 }
                let comment = String(characters[index..<min(end + 2, characters.count)])
                if buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.comment(comment))
                } else {
                    buffer += comment
                }
                index = end + 2
                continue
            }
            // `//` line comments (SCSS/LESS), but not inside url(http://…).
            if character == "/", next == "/", parens == 0, index == 0 || characters[index - 1] != ":" {
                var end = index
                while end < characters.count, !characters[end].isNewline { end += 1 }
                let comment = String(characters[index..<end])
                if buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.comment(comment)) } else { buffer += comment + "\n" }
                index = end
                continue
            }
            if character == "\"" || character == "'" {
                var end = index + 1
                while end < characters.count, characters[end] != character {
                    if characters[end] == "\\" { end += 1 }
                    end += 1
                }
                buffer += String(characters[index..<min(end + 1, characters.count)])
                index = end + 1
                continue
            }
            switch character {
            case "(": parens += 1; buffer.append(character)
            case ")": parens = max(0, parens - 1); buffer.append(character)
            case "{" where parens == 0:
                // `#{$var}` interpolation (SCSS) stays in the text.
                if buffer.hasSuffix("#") {
                    var end = index
                    while end < characters.count, characters[end] != "}" { end += 1 }
                    buffer += String(characters[index..<min(end + 1, characters.count)])
                    index = end + 1
                    continue
                }
                result.append(.prelude(buffer.trimmingCharacters(in: .whitespacesAndNewlines)))
                buffer = ""
            case ";" where parens == 0:
                flushDeclaration()
            case "}" where parens == 0:
                flushDeclaration()
                result.append(.close)
            default:
                buffer.append(character)
            }
            index += 1
        }
        flushDeclaration()
        return result
    }

    public static func beautify(_ css: String, indent: String = "  ") -> String {
        var lines: [String] = []
        var depth = 0
        let items = pieces(css)
        for (index, piece) in items.enumerated() {
            let pad = String(repeating: indent, count: depth)
            switch piece {
            case let .comment(text):
                lines.append(pad + text)
            case let .prelude(text):
                if depth == 0, let last = lines.last, !last.isEmpty, !last.hasPrefix("/") && !last.hasPrefix("@") || last == "}" { lines.append("") }
                lines.append(pad + selector(text) + " {")
                depth += 1
            case let .declaration(text):
                lines.append(pad + declaration(text) + ";")
            case .close:
                depth = max(0, depth - 1)
                lines.append(String(repeating: indent, count: depth) + "}")
                // A blank line after each top-level rule, except at the end.
                if depth == 0, index < items.count - 1 { lines.append("") }
            }
        }
        while lines.last == "" { lines.removeLast() }
        // Collapse runs of blank lines.
        var out: [String] = []
        for line in lines where !(line.isEmpty && out.last?.isEmpty == true) { out.append(line) }
        return out.joined(separator: "\n") + (out.isEmpty ? "" : "\n")
    }

    public static func minify(_ css: String, keepImportantComments: Bool = true) -> String {
        var out = ""
        for piece in pieces(css) {
            switch piece {
            case let .comment(text):
                if keepImportantComments && text.hasPrefix("/*!") { out += text }
            case let .prelude(text):
                out += collapse(stripComments(text)).replacingOccurrences(of: "\\s*([,>])\\s*", with: "$1", options: .regularExpression) + "{"
            case let .declaration(text):
                out += minifyDeclaration(stripComments(text)) + ";"
            case .close:
                if out.hasSuffix(";") { out.removeLast() }
                out += "}"
            }
        }
        if out.hasSuffix(";") { out.removeLast() }
        return out
    }

    static func stripComments(_ text: String) -> String {
        text.replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
    }

    static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// `a,b>c` → `a, b > c`, one space everywhere.
    static func selector(_ text: String) -> String {
        if text.hasPrefix("@") { return collapse(text) }
        var result = collapse(text)
        // Selector lists: one per line reads best for long lists; keep short ones inline.
        let parts = splitTopLevel(result, on: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        result = parts.joined(separator: parts.joined().count > 60 ? ",\n" : ", ")
        return result
    }

    static func declaration(_ text: String) -> String {
        let collapsed = collapse(text)
        // Nested-property or variable declarations: "prop: value".
        guard let colon = collapsed.firstIndex(of: ":"), !collapsed.hasPrefix("@") else { return collapsed }
        let property = collapsed[..<colon].trimmingCharacters(in: .whitespaces)
        let value = collapsed[collapsed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let tidy = splitTopLevel(value, on: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
        return property + ": " + tidy
    }

    static func minifyDeclaration(_ text: String) -> String {
        let collapsed = collapse(text)
        guard let colon = collapsed.firstIndex(of: ":"), !collapsed.hasPrefix("@") else { return collapsed }
        let property = collapsed[..<colon].trimmingCharacters(in: .whitespaces)
        var value = collapsed[collapsed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        value = splitTopLevel(value, on: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
        value = value.replacingOccurrences(of: " !important", with: "!important")
        return property + ":" + value
    }

    /// Splits outside parentheses and quotes.
    static func splitTopLevel(_ text: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
                continue
            }
            switch character {
            case "\"", "'": quote = character; current.append(character)
            case "(", "[": depth += 1; current.append(character)
            case ")", "]": depth -= 1; current.append(character)
            case separator where depth == 0: parts.append(current); current = ""
            default: current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    public static func looksLikeCSS(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("}"), !trimmed.hasPrefix("{"), !trimmed.hasPrefix("["), let open = trimmed.firstIndex(of: "{") else { return false }
        let head = trimmed[..<open]
        guard !head.contains("(") || head.hasPrefix("@"), !head.contains("="), !head.contains(";") || head.hasPrefix("@") else { return false }
        // Inside the first block: "property: value;" pairs.
        let body = trimmed[trimmed.index(after: open)...]
        return body.range(of: "^\\s*[-a-zA-Z$@]+\\s*:\\s*[^;{}]+;", options: .regularExpression) != nil
    }
}

// MARK: - SQL

public enum SQLFormatter {
    public enum KeywordCase: String, CaseIterable, Sendable, Identifiable {
        case upper, lower, preserve
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .upper: "UPPERCASE"
            case .lower: "lowercase"
            case .preserve: "As Typed"
            }
        }
    }

    enum Token: Equatable {
        case word(String)
        case string(String)
        case number(String)
        case symbol(String)
        case comment(String)
        case open, close, comma, semicolon
    }

    static let keywords: Set<String> = [
        "select", "from", "where", "and", "or", "not", "in", "is", "null", "like", "ilike", "between", "exists", "as",
        "join", "inner", "left", "right", "full", "outer", "cross", "on", "using", "group", "by", "order", "having",
        "limit", "offset", "fetch", "union", "all", "intersect", "except", "distinct", "insert", "into", "values",
        "update", "set", "delete", "create", "table", "drop", "alter", "add", "column", "index", "view", "with",
        "returning", "case", "when", "then", "else", "end", "asc", "desc", "primary", "key", "foreign", "references",
        "default", "unique", "check", "constraint", "if", "replace", "true", "false", "over", "partition", "window",
        "natural", "lateral", "recursive", "conflict", "do", "nothing", "top", "count", "sum", "avg", "min", "max",
        "coalesce", "cast", "desc", "rows", "range", "following", "preceding", "unbounded", "current", "row", "only",
        "nulls", "first", "last", "begin", "commit", "rollback", "transaction", "grant", "revoke", "truncate", "merge",
        "matched", "varchar", "integer", "int", "text", "boolean", "timestamp", "date", "serial", "bigint", "numeric",
    ]

    /// Clauses that start a new line at the statement's indent.
    static let clauses: [[String]] = [
        ["select", "distinct"], ["select"], ["from"], ["where"], ["group", "by"], ["order", "by"], ["having"], ["limit"], ["offset"],
        ["union", "all"], ["union"], ["intersect"], ["except"], ["insert", "into"], ["values"], ["update"], ["set"],
        ["delete", "from"], ["returning"], ["with", "recursive"], ["with"], ["window"], ["on", "conflict"], ["fetch"],
        ["left", "outer", "join"], ["right", "outer", "join"], ["full", "outer", "join"], ["left", "join"], ["right", "join"],
        ["full", "join"], ["inner", "join"], ["cross", "join"], ["natural", "join"], ["join"],
        ["create", "table"], ["alter", "table"], ["drop", "table"],
    ]

    static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(sql)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character.isWhitespace { index += 1; continue }
            if character == "-", next == "-" {
                var end = index
                while end < characters.count, !characters[end].isNewline { end += 1 }
                tokens.append(.comment(String(characters[index..<end])))
                index = end
                continue
            }
            if character == "/", next == "*" {
                var end = index + 2
                while end + 1 < characters.count, !(characters[end] == "*" && characters[end + 1] == "/") { end += 1 }
                tokens.append(.comment(String(characters[index..<min(end + 2, characters.count)])))
                index = end + 2
                continue
            }
            if character == "'" || character == "\"" || character == "`" || character == "[" {
                let close: Character = character == "[" ? "]" : character
                var end = index + 1
                while end < characters.count {
                    if characters[end] == close {
                        // Doubled quote is an escaped quote.
                        if end + 1 < characters.count, characters[end + 1] == close, close != "]" { end += 2; continue }
                        break
                    }
                    if characters[end] == "\\", close == "'" { end += 1 }
                    end += 1
                }
                tokens.append(.string(String(characters[index..<min(end + 1, characters.count)])))
                index = end + 1
                continue
            }
            if character.isNumber || (character == "." && next?.isNumber == true) {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." || characters[end] == "e" || characters[end] == "E" { end += 1 }
                tokens.append(.number(String(characters[index..<end])))
                index = end
                continue
            }
            if character.isLetter || character == "_" || character == "@" || character == "$" || character == "#" || (character == ":" && next?.isLetter == true) {
                var end = index + 1
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" || characters[end] == "$" || characters[end] == "." { end += 1 }
                tokens.append(.word(String(characters[index..<end])))
                index = end
                continue
            }
            switch character {
            case "(": tokens.append(.open)
            case ")": tokens.append(.close)
            case ",": tokens.append(.comma)
            case ";": tokens.append(.semicolon)
            default:
                // Multi-character operators.
                let pair = next.map { String([character, $0]) } ?? ""
                if ["<=", ">=", "<>", "!=", "||", "::", "->", "=>"].contains(pair) {
                    tokens.append(.symbol(pair))
                    index += 2
                    continue
                }
                tokens.append(.symbol(String(character)))
            }
            index += 1
        }
        return tokens
    }

    public static func format(_ sql: String, indent: String = "  ", keywordCase: KeywordCase = .upper) -> String {
        let tokens = tokenize(sql)
        var lines: [String] = []
        var line = ""
        var depth = 0
        /// Each open paren: was it a subquery (indented block) or inline (function call, list)?
        var parens: [(subquery: Bool, depth: Int)] = []
        var clause = ""
        var betweenPending = false
        var caseDepth = 0

        func pad(_ level: Int) -> String { String(repeating: indent, count: max(0, level)) }
        func newline(_ level: Int) {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
            line = pad(level)
        }
        func emit(_ text: String) {
            let hasContent = line.contains { $0 != " " && $0 != "\t" }
            if hasContent, !line.hasSuffix(" "), !line.hasSuffix("(") { line += " " }
            line += text
        }
        func word(_ text: String) -> String {
            guard keywords.contains(text.lowercased()) else { return text }
            switch keywordCase {
            case .upper: return text.uppercased()
            case .lower: return text.lowercased()
            case .preserve: return text
            }
        }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case let .word(text):
                let lower = text.lowercased()
                if let match = clauses.first(where: { phrase in
                    phrase.enumerated().allSatisfy { offset, part in
                        index + offset < tokens.count && { if case let .word(w) = tokens[index + offset] { w.lowercased() == part } else { false } }()
                    }
                }) {
                    newline(depth)
                    let words = (0..<match.count).map { offset -> String in
                        if case let .word(w) = tokens[index + offset] { return word(w) }
                        return ""
                    }
                    emit(words.joined(separator: " "))
                    clause = match.joined(separator: " ")
                    index += match.count
                    // Column lists start on the next line, indented.
                    if ["select", "select distinct", "set", "group by", "order by", "returning"].contains(clause) {
                        newline(depth + 1)
                    }
                    continue
                }
                if (lower == "and" || lower == "or"), !betweenPending, caseDepth == 0 {
                    newline(depth + 1)
                    emit(word(text))
                } else if lower == "on", clause.hasSuffix("join") {
                    newline(depth + 1)
                    emit(word(text))
                } else if lower == "case" {
                    caseDepth += 1
                    emit(word(text))
                } else if lower == "end", caseDepth > 0 {
                    caseDepth -= 1
                    emit(word(text))
                } else {
                    if lower == "between" { betweenPending = true } else if lower == "and" { betweenPending = false }
                    emit(word(text))
                }
            case let .string(text), let .number(text):
                emit(text)
            case let .symbol(text):
                if text == "." || text == "::" {
                    line += text
                } else {
                    emit(text)
                }
            case let .comment(text):
                emit(text)
                newline(depth + (clause.isEmpty ? 0 : 1))
            case .open:
                let nextIsSelect: Bool = {
                    if index + 1 < tokens.count, case let .word(w) = tokens[index + 1] { return ["select", "with"].contains(w.lowercased()) }
                    return false
                }()
                // Function calls hug their name: count(*), not count (*).
                let notCalls: Set<String> = ["in", "exists", "values", "as", "on", "and", "or", "from", "join", "using", "where", "not", "into", "over", "select", "when", "then", "else"]
                if index > 0, case let .word(previous) = tokens[index - 1], !notCalls.contains(previous.lowercased()) {
                    line += "("
                } else {
                    emit("(")
                }
                if nextIsSelect {
                    parens.append((true, depth))
                    depth += 1
                    newline(depth)
                } else {
                    parens.append((false, depth))
                }
            case .close:
                let open = parens.popLast() ?? (false, depth)
                if open.subquery {
                    depth = open.depth
                    newline(depth)
                    line += ")"
                } else {
                    line += ")"
                }
            case .comma:
                line += ","
                let inList = parens.last.map { !$0.subquery } ?? false
                if !inList, ["select", "select distinct", "set", "group by", "order by", "returning", "values", "with"].contains(clause) {
                    newline(depth + (clause == "with" || clause == "values" ? 0 : 1))
                }
            case .semicolon:
                line += ";"
                newline(0)
                lines.append("")
                depth = 0
                parens = []
                clause = ""
            }
            index += 1
        }
        newline(0)
        while lines.last == "" { lines.removeLast() }
        while lines.first == "" { lines.removeFirst() }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    public static func minify(_ sql: String) -> String {
        var out = ""
        var previous: Token?
        for token in tokenize(sql) {
            let text: String
            switch token {
            case let .word(t), let .string(t), let .number(t), let .symbol(t): text = t
            case .comment: continue
            case .open: text = "("
            case .close: text = ")"
            case .comma: text = ","
            case .semicolon: text = ";"
            }
            let needsSpace: Bool = {
                guard let previous else { return false }
                switch (previous, token) {
                case (.open, _), (_, .close), (_, .comma), (.comma, _), (_, .semicolon), (_, .open): return false
                case (.symbol("."), _), (_, .symbol(".")), (.symbol("::"), _), (_, .symbol("::")): return false
                default: return true
                }
            }()
            if case .open = token, let previous, case let .word(w) = previous, keywords.contains(w.lowercased()) { out += " " }
            if needsSpace { out += " " }
            out += text
            previous = token
        }
        return out
    }

    public static func looksLikeSQL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let starts = ["select ", "insert into ", "update ", "delete from ", "with ", "create table ", "alter table ", "select\n", "drop table "]
        guard starts.contains(where: trimmed.hasPrefix) else { return false }
        if trimmed.hasPrefix("select") {
            guard trimmed.range(of: "\\bfrom\\b", options: .regularExpression) != nil else { return false }
            // Prose like "select the best option from the menu" has none of SQL's punctuation.
            let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return original.contains { "*,=();\n.".contains($0) } || original.hasPrefix("SELECT")
        }
        if trimmed.hasPrefix("update ") { return trimmed.range(of: "\\bset\\b", options: .regularExpression) != nil }
        if trimmed.hasPrefix("with ") { return trimmed.contains(" as ") && trimmed.contains("select") }
        return true
    }
}
