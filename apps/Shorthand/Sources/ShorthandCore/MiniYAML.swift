import Foundation

/// A YAML value. Scalars stay strings (`true`, `42` included); readers interpret them.
public indirect enum YAMLValue: Sendable, Equatable {
    case string(String)
    case list([YAMLValue])
    case map([YAMLPair])
    case null

    public subscript(key: String) -> YAMLValue? {
        guard case .map(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var list: [YAMLValue]? {
        if case .list(let value) = self { return value }
        return nil
    }

    public var pairs: [YAMLPair]? {
        if case .map(let value) = self { return value }
        return nil
    }

    /// `true`/`yes`/`on` (YAML 1.1 and 1.2 spellings).
    public var bool: Bool? {
        guard let string = string?.lowercased() else { return nil }
        if ["true", "yes", "on"].contains(string) { return true }
        if ["false", "no", "off"].contains(string) { return false }
        return nil
    }
}

public struct YAMLPair: Sendable, Equatable {
    public var key: String
    public var value: YAMLValue

    public init(_ key: String, _ value: YAMLValue) {
        self.key = key
        self.value = value
    }
}

/// The part of YAML that snippet files use: block mappings and sequences (including a
/// sequence at its key's indentation), plain, single- and double-quoted scalars (multi-line
/// too), literal and folded block scalars with chomping, flow `[…]` and `{…}`, comments,
/// document markers, and simple anchors and aliases. Not a general YAML parser: tags are
/// ignored, merge keys and complex keys aren't supported.
public enum MiniYAML {
    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public var line: Int
        public var message: String
        public var description: String { "Line \(line): \(message)" }
    }

    public static func parse(_ text: String) throws -> YAMLValue {
        var parser = Parser(text: text)
        return try parser.document()
    }

    struct Parser {
        var lines: [String]
        var index = 0
        var anchors: [String: YAMLValue] = [:]

        init(text: String) {
            var lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\t", with: "    ").components(separatedBy: "\n")
            if let first = lines.first, first.hasPrefix("\u{FEFF}") { lines[0] = String(first.dropFirst()) }
            self.lines = lines
        }

        func error(_ message: String) -> ParseError { ParseError(line: index + 1, message: message) }

        static func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }

        /// Blank, comment-only or a document marker.
        static func isSkippable(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" || trimmed == "..." || trimmed.hasPrefix("%YAML")
                || trimmed.hasPrefix("--- ")
        }

        mutating func skipBlank() {
            while index < lines.count, Self.isSkippable(lines[index]) { index += 1 }
        }

        mutating func document() throws -> YAMLValue {
            skipBlank()
            guard index < lines.count else { return .null }
            let value = try block(minIndent: 0)
            skipBlank()
            if index < lines.count { throw error("Unexpected text") }
            return value
        }

        /// A node starting at the next non-blank line, indented at least `minIndent`.
        mutating func block(minIndent: Int) throws -> YAMLValue {
            skipBlank()
            guard index < lines.count else { return .null }
            let line = lines[index]
            let indent = Self.indent(line)
            guard indent >= minIndent else { return .null }
            let text = String(line.dropFirst(indent))
            if Self.isSequenceItem(text) { return try sequence(indent: indent) }
            if Self.mappingKeyEnd(text) != nil { return try mapping(indent: indent) }
            // A scalar on its own lines.
            index += 1
            return try scalar(text, parentIndent: indent - 1)
        }

        static func isSequenceItem(_ text: String) -> Bool { text == "-" || text.hasPrefix("- ") }

        /// Where a `key:` ends (the colon), if `text` starts a mapping entry.
        static func mappingKeyEnd(_ text: String) -> String.Index? {
            guard let first = text.first, first != "[", first != "{", first != "#", first != "|", first != ">" else { return nil }
            var i = text.startIndex
            if first == "\"" || first == "'" {
                i = text.index(after: i)
                while i < text.endIndex {
                    if text[i] == "\\" && first == "\"" { i = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex; continue }
                    if text[i] == first {
                        if first == "'", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "'" {
                            i = text.index(i, offsetBy: 2); continue
                        }
                        break
                    }
                    i = text.index(after: i)
                }
                guard i < text.endIndex else { return nil }
                let after = text.index(after: i)
                let rest = text[after...].drop { $0 == " " }
                guard rest.first == ":" else { return nil }
                let colon = rest.startIndex
                let next = text.index(after: colon)
                return next == text.endIndex || text[next] == " " ? colon : nil
            }
            while i < text.endIndex {
                if text[i] == ":" {
                    let next = text.index(after: i)
                    if next == text.endIndex || text[next] == " " { return i }
                }
                if text[i] == "#", i > text.startIndex, text[text.index(before: i)] == " " { return nil }
                i = text.index(after: i)
            }
            return nil
        }

        mutating func mapping(indent: Int) throws -> YAMLValue {
            var pairs: [YAMLPair] = []
            while true {
                skipBlank()
                guard index < lines.count else { break }
                let line = lines[index]
                guard Self.indent(line) == indent else {
                    if Self.indent(line) > indent { throw error("Unexpected indentation") }
                    break
                }
                let text = String(line.dropFirst(indent))
                guard !Self.isSequenceItem(text), let colon = Self.mappingKeyEnd(text) else {
                    throw error("Expected “key: value”")
                }
                let key = Self.unquoteKey(String(text[..<colon]).trimmingCharacters(in: .whitespaces))
                let rest = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                index += 1
                pairs.append(YAMLPair(key, try value(rest, parentIndent: indent, allowSequenceAtParent: true)))
            }
            return .map(pairs)
        }

        mutating func sequence(indent: Int) throws -> YAMLValue {
            var items: [YAMLValue] = []
            while true {
                skipBlank()
                guard index < lines.count else { break }
                let line = lines[index]
                guard Self.indent(line) == indent else {
                    if Self.indent(line) > indent { throw error("Unexpected indentation") }
                    break
                }
                let text = String(line.dropFirst(indent))
                guard Self.isSequenceItem(text) else { break }
                let content = String(text.dropFirst(1)).drop { $0 == " " }
                let column = indent + (text.count - content.count)
                if content.isEmpty {
                    index += 1
                    items.append(try nestedBlock(parentIndent: indent, allowSequenceAtParent: false))
                } else if Self.isSequenceItem(String(content)) || Self.mappingKeyEnd(String(content)) != nil,
                          !content.hasPrefix("&"), !content.hasPrefix("*") {
                    // `- key: value` / `- - x`: the item is a block starting at the content's column.
                    lines[index] = String(repeating: " ", count: column) + content
                    items.append(try block(minIndent: column))
                } else {
                    index += 1
                    items.append(try value(String(content), parentIndent: indent, allowSequenceAtParent: false))
                }
            }
            return .list(items)
        }

        /// The value after `key:` or `- ` (`rest` is what's left on that line).
        mutating func value(_ rest: String, parentIndent: Int, allowSequenceAtParent: Bool) throws -> YAMLValue {
            var rest = rest
            var anchor: String?
            if rest.hasPrefix("&") {
                let name = rest.dropFirst().prefix { $0 != " " }
                anchor = String(name)
                rest = String(rest.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
            }
            if rest.hasPrefix("!") { rest = String(rest.drop { $0 != " " }).trimmingCharacters(in: .whitespaces) }
            let result: YAMLValue
            if rest.isEmpty || rest.hasPrefix("#") {
                result = try nestedBlock(parentIndent: parentIndent, allowSequenceAtParent: allowSequenceAtParent)
            } else if rest.hasPrefix("*") {
                let name = String(rest.dropFirst().prefix { $0 != " " })
                result = anchors[name] ?? .null
            } else {
                result = try scalar(rest, parentIndent: parentIndent)
            }
            if let anchor { anchors[anchor] = result }
            return result
        }

        /// A block under a key or dash: more indented, or (for keys) a sequence at the key's own indent.
        mutating func nestedBlock(parentIndent: Int, allowSequenceAtParent: Bool) throws -> YAMLValue {
            skipBlank()
            guard index < lines.count else { return .null }
            let line = lines[index]
            let indent = Self.indent(line)
            if indent > parentIndent { return try block(minIndent: parentIndent + 1) }
            if allowSequenceAtParent, indent == parentIndent, Self.isSequenceItem(String(line.dropFirst(indent))) {
                return try sequence(indent: indent)
            }
            return .null
        }

        /// A scalar or flow collection starting with `text`; may continue on following lines
        /// indented more than `parentIndent`.
        mutating func scalar(_ text: String, parentIndent: Int) throws -> YAMLValue {
            guard let first = text.first else { return .string("") }
            switch first {
            case "|", ">":
                return .string(blockScalar(header: text, parentIndent: parentIndent))
            case "\"", "'":
                return .string(try quoted(text, quote: first, parentIndent: parentIndent))
            case "[", "{":
                var source = text
                while !Self.balanced(source), index < lines.count {
                    source += " " + lines[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                }
                var flow = FlowParser(text: source, anchors: anchors)
                let value = try flow.value()
                guard flow.atEnd else { throw error("Unexpected text after a list or map") }
                return value
            default:
                var value = Self.stripComment(text)
                // Continuation lines of a plain scalar.
                while index < lines.count {
                    let line = lines[index]
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        // A blank line inside a plain scalar is a line break, if more follows.
                        var look = index + 1
                        while look < lines.count, lines[look].trimmingCharacters(in: .whitespaces).isEmpty { look += 1 }
                        guard look < lines.count, Self.indent(lines[look]) > parentIndent, !Self.isStructural(lines[look]) else { break }
                        value += "\n"
                        index += 1
                        continue
                    }
                    guard Self.indent(line) > parentIndent, !trimmed.hasPrefix("#"), !Self.isStructural(line) else { break }
                    value += (value.hasSuffix("\n") ? "" : " ") + Self.stripComment(trimmed)
                    index += 1
                }
                return .string(value)
            }
        }

        /// A line that starts a new entry (so it can't continue a plain scalar).
        static func isStructural(_ line: String) -> Bool {
            let text = String(line.dropFirst(indent(line)))
            return isSequenceItem(text) || mappingKeyEnd(text) != nil
        }

        static func stripComment(_ text: String) -> String {
            var previous: Character = " "
            for (offset, character) in text.enumerated() {
                if character == "#" && previous == " " {
                    return String(text.prefix(offset)).trimmingCharacters(in: .whitespaces)
                }
                previous = character
            }
            return text.trimmingCharacters(in: .whitespaces)
        }

        static func balanced(_ text: String) -> Bool {
            var depth = 0
            var quote: Character?
            var escaped = false
            for character in text {
                if let q = quote {
                    if escaped { escaped = false; continue }
                    if character == "\\" && q == "\"" { escaped = true; continue }
                    if character == q { quote = nil }
                    continue
                }
                switch character {
                case "\"", "'": quote = character
                case "[", "{": depth += 1
                case "]", "}": depth -= 1
                default: break
                }
            }
            return depth <= 0 && quote == nil
        }

        static func unquoteKey(_ key: String) -> String {
            if key.count >= 2, let first = key.first, first == "\"" || first == "'", key.last == first {
                let inner = String(key.dropFirst().dropLast())
                return first == "'" ? inner.replacingOccurrences(of: "''", with: "'") : unescape(inner)
            }
            return key
        }

        mutating func blockScalar(header: String, parentIndent: Int) -> String {
            let folded = header.first == ">"
            var chomp: Character = "c"
            var explicitIndent: Int?
            for character in Self.stripComment(header).dropFirst() {
                if character == "-" || character == "+" { chomp = character }
                if let digit = character.wholeNumberValue { explicitIndent = digit }
            }
            var raw: [String] = []
            var contentIndent = explicitIndent.map { max(parentIndent, 0) + $0 }
            while index < lines.count {
                let line = lines[index]
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    raw.append("")
                    index += 1
                    continue
                }
                let indent = Self.indent(line)
                if contentIndent == nil {
                    guard indent > parentIndent else { break }
                    contentIndent = indent
                }
                guard let content = contentIndent, indent >= content else { break }
                raw.append(String(line.dropFirst(content)))
                index += 1
            }
            // Trailing blank lines belong to chomping.
            var trailing = 0
            while let last = raw.last, last.isEmpty { raw.removeLast(); trailing += 1 }
            var body = ""
            if folded {
                // One break between two plain lines is a space; blank lines are breaks;
                // more-indented lines keep their breaks.
                var blanks = 0
                var previous: String?
                for line in raw {
                    if line.isEmpty { blanks += 1; continue }
                    if let previous {
                        let keepsBreak = previous.hasPrefix(" ") || line.hasPrefix(" ")
                        if blanks > 0 {
                            body += String(repeating: "\n", count: blanks) + (keepsBreak ? "\n" : "")
                        } else {
                            body += keepsBreak ? "\n" : " "
                        }
                    } else {
                        body += String(repeating: "\n", count: blanks)
                    }
                    body += line
                    blanks = 0
                    previous = line
                }
            } else {
                body = raw.joined(separator: "\n")
            }
            switch chomp {
            case "-": return body
            case "+": return body + String(repeating: "\n", count: raw.isEmpty ? trailing : trailing + 1)
            default: return raw.isEmpty ? "" : body + "\n"
            }
        }

        mutating func quoted(_ text: String, quote: Character, parentIndent: Int) throws -> String {
            var source = text
            func closed(_ s: String) -> String.Index? {
                var i = s.index(after: s.startIndex)
                while i < s.endIndex {
                    if quote == "\"" && s[i] == "\\" {
                        i = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                        continue
                    }
                    if s[i] == quote {
                        let next = s.index(after: i)
                        if quote == "'", next < s.endIndex, s[next] == "'" { i = s.index(after: next); continue }
                        return i
                    }
                    i = s.index(after: i)
                }
                return nil
            }
            while closed(source) == nil {
                guard index < lines.count else { throw error("A quoted value never ends") }
                source += "\n" + lines[index]
                index += 1
            }
            let end = closed(source)!
            var inner = String(source[source.index(after: source.startIndex)..<end])
            // Fold line breaks: one break is a space, blank lines are breaks.
            if inner.contains("\n") {
                let parts = inner.components(separatedBy: "\n")
                var folded = parts[0].replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                var pendingBreaks = 0
                for part in parts.dropFirst() {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { pendingBreaks += 1; continue }
                    if quote == "\"" && folded.hasSuffix("\\") {
                        folded.removeLast()
                    } else {
                        folded += pendingBreaks > 0 ? String(repeating: "\n", count: pendingBreaks) : " "
                    }
                    pendingBreaks = 0
                    folded += trimmed
                }
                inner = folded
            }
            return quote == "'" ? inner.replacingOccurrences(of: "''", with: "'") : Self.unescape(inner)
        }

        static func unescape(_ text: String) -> String {
            guard text.contains("\\") else { return text }
            var result = ""
            var iterator = Array(text)
            var i = 0
            func hex(_ count: Int) -> Character? {
                guard i + count < iterator.count else { return nil }
                let digits = String(iterator[(i + 1)...(i + count)])
                guard let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
                i += count
                return Character(scalar)
            }
            while i < iterator.count {
                let character = iterator[i]
                if character == "\\", i + 1 < iterator.count {
                    i += 1
                    switch iterator[i] {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "0": result.append("\0")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "/": result.append("/")
                    case " ": result.append(" ")
                    case "x": if let c = hex(2) { result.append(c) }
                    case "u": if let c = hex(4) { result.append(c) }
                    case "U": if let c = hex(8) { result.append(c) }
                    default: result.append("\\"); result.append(iterator[i])
                    }
                } else {
                    result.append(character)
                }
                i += 1
            }
            iterator.removeAll()
            return result
        }
    }

    /// `[a, "b", {c: d}]` and `{a: b}` on one (joined) line.
    struct FlowParser {
        let characters: [Character]
        var position = 0
        let anchors: [String: YAMLValue]

        init(text: String, anchors: [String: YAMLValue]) {
            characters = Array(text)
            self.anchors = anchors
        }

        var atEnd: Bool {
            var p = position
            while p < characters.count, characters[p] == " " { p += 1 }
            return p >= characters.count || characters[p] == "#"
        }

        mutating func skipSpaces() { while position < characters.count, characters[position] == " " { position += 1 } }

        func fail(_ message: String) -> ParseError { ParseError(line: 0, message: message) }

        mutating func value() throws -> YAMLValue {
            skipSpaces()
            guard position < characters.count else { return .null }
            switch characters[position] {
            case "[":
                position += 1
                var items: [YAMLValue] = []
                while true {
                    skipSpaces()
                    guard position < characters.count else { throw fail("A list never ends") }
                    if characters[position] == "]" { position += 1; break }
                    items.append(try value())
                    skipSpaces()
                    if position < characters.count, characters[position] == "," { position += 1 }
                }
                return .list(items)
            case "{":
                position += 1
                var pairs: [YAMLPair] = []
                while true {
                    skipSpaces()
                    guard position < characters.count else { throw fail("A map never ends") }
                    if characters[position] == "}" { position += 1; break }
                    let key = try scalarText(stopAtColon: true)
                    skipSpaces()
                    var item = YAMLValue.null
                    if position < characters.count, characters[position] == ":" {
                        position += 1
                        item = try value()
                    }
                    pairs.append(YAMLPair(key, item))
                    skipSpaces()
                    if position < characters.count, characters[position] == "," { position += 1 }
                }
                return .map(pairs)
            case "*":
                position += 1
                var name = ""
                while position < characters.count, !",]} ".contains(characters[position]) { name.append(characters[position]); position += 1 }
                return anchors[name] ?? .null
            default:
                return .string(try scalarText(stopAtColon: false))
            }
        }

        mutating func scalarText(stopAtColon: Bool) throws -> String {
            skipSpaces()
            guard position < characters.count else { return "" }
            let first = characters[position]
            if first == "\"" || first == "'" {
                position += 1
                var raw = ""
                while position < characters.count {
                    let c = characters[position]
                    if first == "\"" && c == "\\" && position + 1 < characters.count {
                        raw.append(c); raw.append(characters[position + 1]); position += 2; continue
                    }
                    if c == first {
                        if first == "'", position + 1 < characters.count, characters[position + 1] == "'" {
                            raw.append("'"); position += 2; continue
                        }
                        position += 1
                        return first == "\"" ? Parser.unescape(raw) : raw
                    }
                    raw.append(c)
                    position += 1
                }
                throw fail("A quoted value never ends")
            }
            var raw = ""
            while position < characters.count {
                let c = characters[position]
                if c == "," || c == "]" || c == "}" { break }
                if stopAtColon, c == ":", position + 1 >= characters.count || characters[position + 1] == " " { break }
                raw.append(c)
                position += 1
            }
            return raw.trimmingCharacters(in: .whitespaces)
        }
    }
}
