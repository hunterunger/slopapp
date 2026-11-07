import Foundation
import Yams

/// YAML ⇄ JSON. Parsing uses libyaml (through Yams) with the YAML 1.2 core schema, so
/// `no` and `on` stay strings (the "Norway problem"); emitting is our own, so key order and
/// number text are kept exactly.
public enum YAMLConverter {
    public struct ConversionError: Error, Equatable, Sendable, CustomStringConvertible {
        public var message: String
        public var line: Int?
        public var column: Int?
        public var description: String {
            if let line, let column { return "Line \(line), column \(column): \(message)" }
            return message
        }
    }

    // MARK: YAML → JSON

    /// The YAML 1.2 core schema (what js-yaml and most tools use today).
    static let resolver: Resolver = {
        // Patterns are constants; a bad one is a programming error caught by the tests.
        let rules: [Resolver.Rule] = [
            try! Resolver.Rule(.null, "^(?:~|null|Null|NULL|)$"),
            try! Resolver.Rule(.bool, "^(?:true|True|TRUE|false|False|FALSE)$"),
            try! Resolver.Rule(.int, "^(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$"),
            try! Resolver.Rule(.float, "^(?:[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$"),
            try! Resolver.Rule(.merge, "^(?:<<)$"),
        ]
        return rules.reduce(Resolver.basic) { $0.appending($1) }
    }()

    /// Converts YAML to a JSON value. Several documents (`---`) become an array.
    public static func parse(_ yaml: String) throws -> JSONValue {
        do {
            var documents: [JSONValue] = []
            var sequence = try compose_all(yaml: yaml, resolver)
            while let node = sequence.next() {
                documents.append(try value(of: node, depth: 0))
            }
            if let error = sequence.error { throw error }
            switch documents.count {
            case 0: return .null
            case 1: return documents[0]
            default: return .array(documents)
            }
        } catch let error as ConversionError {
            throw error
        } catch let error as YamlError {
            throw describe(error)
        }
    }

    public static func toJSON(_ yaml: String, indent: String = "  ") throws -> String {
        JSONTree.serialize(try parse(yaml), pretty: true, indent: indent)
    }

    static func describe(_ error: YamlError) -> ConversionError {
        switch error {
        case let .scanner(context, problem, mark, _), let .parser(context, problem, mark, _), let .composer(context, problem, mark, _):
            let detail = [context?.text, problem].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return ConversionError(message: capitalized(detail), line: mark.line, column: mark.column)
        case let .duplicatedKeysInMapping(duplicates, context):
            return ConversionError(message: "Duplicate key \(duplicates.joined(separator: ", "))", line: context.mark.line, column: context.mark.column)
        default:
            return ConversionError(message: capitalized("\(error)"), line: nil, column: nil)
        }
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    static func value(of node: Node, depth: Int) throws -> JSONValue {
        guard depth < 256 else { throw ConversionError(message: "Nested too deeply", line: node.mark?.line, column: node.mark?.column) }
        switch node {
        case let .scalar(scalar):
            return scalarValue(scalar, tag: Tag.Name(rawValue: node.tag.rawValue))
        case let .sequence(sequence):
            return .array(try sequence.map { try value(of: $0, depth: depth + 1) })
        case let .mapping(mapping):
            var pairs: [(String, JSONValue)] = []
            var merged: [(String, JSONValue)] = []
            for (keyNode, valueNode) in mapping {
                if case .scalar = keyNode, Tag.Name(rawValue: keyNode.tag.rawValue) == .merge {
                    // `<<: *base` or `<<: [*a, *b]`: earlier sources win, explicit keys win over all.
                    let sources: [Node] = valueNode.sequence.map { Array($0) } ?? [valueNode]
                    for source in sources {
                        if case let .object(inherited) = try value(of: source, depth: depth + 1) {
                            for (key, item) in inherited where !merged.contains(where: { $0.0 == key }) {
                                merged.append((key, item))
                            }
                        }
                    }
                    continue
                }
                let key: String
                switch keyNode {
                case let .scalar(scalar): key = scalar.string
                default: key = JSONTree.serialize(try value(of: keyNode, depth: depth + 1), pretty: false)
                }
                let item = try value(of: valueNode, depth: depth + 1)
                if let index = pairs.firstIndex(where: { $0.0 == key }) {
                    pairs[index].1 = item
                } else {
                    pairs.append((key, item))
                }
            }
            for (key, item) in merged where !pairs.contains(where: { $0.0 == key }) {
                pairs.append((key, item))
            }
            return .object(pairs)
        case let .alias(alias):
            throw ConversionError(message: "Unknown alias *\(alias.anchor.rawValue)", line: alias.mark?.line, column: alias.mark?.column)
        }
    }

    static func scalarValue(_ scalar: Node.Scalar, tag: Tag.Name) -> JSONValue {
        let text = scalar.string
        switch tag {
        case .null: return .null
        case .bool: return .bool(text.lowercased() == "true")
        case .int:
            var digits = text
            var negative = false
            if digits.hasPrefix("+") { digits.removeFirst() } else if digits.hasPrefix("-") { negative = true; digits.removeFirst() }
            if digits.hasPrefix("0x") || digits.hasPrefix("0o") {
                let radix = digits.hasPrefix("0x") ? 16 : 8
                if let number = UInt64(digits.dropFirst(2), radix: radix) { return .number((negative ? "-" : "") + String(number)) }
                return .string(text)
            }
            let trimmed = String(digits.drop { $0 == "0" })
            let normalized = trimmed.isEmpty ? "0" : trimmed
            return .number((negative && normalized != "0" ? "-" : "") + normalized)
        case .float:
            if JSONTree.isNumberLiteral(text) { return .number(text) }
            var candidate = text
            if candidate.hasPrefix("+") { candidate.removeFirst() }
            if candidate.hasPrefix(".") && !candidate.lowercased().contains("inf") && !candidate.lowercased().contains("nan") { candidate = "0" + candidate }
            if candidate.hasPrefix("-.") && !candidate.lowercased().contains("inf") { candidate = "-0" + candidate.dropFirst() }
            candidate = candidate.replacingOccurrences(of: ".e", with: ".0e").replacingOccurrences(of: ".E", with: ".0E")
            if candidate.hasSuffix(".") { candidate += "0" }
            if JSONTree.isNumberLiteral(candidate) { return .number(candidate) }
            // .inf and .nan have no JSON form; keep them readable as strings.
            return .string(text)
        default:
            return .string(text)
        }
    }

    // MARK: JSON → YAML

    public static func fromJSON(_ json: String, indent: Int = 2) throws -> String {
        emit(try JSONTree.parse(json), indent: indent)
    }

    /// Block-style YAML that parses back to the same value.
    public static func emit(_ value: JSONValue, indent: Int = 2) -> String {
        var lines: [String] = []
        let unit = String(repeating: " ", count: max(1, indent))
        switch value {
        case .array(let items) where !items.isEmpty:
            emitSequence(items, level: 0, unit: unit, into: &lines)
        case .object(let pairs) where !pairs.isEmpty:
            emitMapping(pairs, level: 0, unit: unit, into: &lines)
        default:
            lines.append(inline(value, level: 0, unit: unit))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func pad(_ level: Int, _ unit: String) -> String { String(repeating: unit, count: level) }

    private static func emitMapping(_ pairs: [(String, JSONValue)], level: Int, unit: String, into lines: inout [String], firstPrefix: String? = nil) {
        for (index, (key, item)) in pairs.enumerated() {
            let prefix = index == 0 && firstPrefix != nil ? firstPrefix! : pad(level, unit)
            let head = prefix + scalarText(key, isKey: true) + ":"
            switch item {
            case .object(let inner) where !inner.isEmpty:
                lines.append(head)
                emitMapping(inner, level: level + 1, unit: unit, into: &lines)
            case .array(let inner) where !inner.isEmpty:
                lines.append(head)
                // Sequences inside a mapping sit at the key's indent, the common style.
                emitSequence(inner, level: level, unit: unit, into: &lines)
            default:
                appendScalar(item, head: head, level: level + 1, unit: unit, into: &lines)
            }
        }
    }

    private static func emitSequence(_ items: [JSONValue], level: Int, unit: String, into lines: inout [String]) {
        // "-" padded to the indent width, so a mapping's first key ("- key: 1") lines up with
        // the keys after it, which are written one level deeper.
        let dash = pad(level, unit) + "-" + String(repeating: " ", count: unit.count - 1)
        for item in items {
            switch item {
            case .object(let pairs) where !pairs.isEmpty:
                emitMapping(pairs, level: level + 1, unit: unit, into: &lines, firstPrefix: dash)
            case .array(let inner) where !inner.isEmpty:
                lines.append(pad(level, unit) + "-")
                emitSequence(inner, level: level + 1, unit: unit, into: &lines)
            default:
                appendScalar(item, head: pad(level, unit) + "-", level: level + 1, unit: unit, into: &lines)
            }
        }
    }

    private static func appendScalar(_ value: JSONValue, head: String, level: Int, unit: String, into lines: inout [String]) {
        if case let .string(text) = value, let block = literalBlock(text, level: level, unit: unit) {
            lines.append(head + " " + block.header)
            lines.append(contentsOf: block.lines)
        } else {
            lines.append(head + " " + inline(value, level: level, unit: unit))
        }
    }

    private static func inline(_ value: JSONValue, level: Int, unit: String) -> String {
        switch value {
        case .null: "null"
        case let .bool(flag): flag ? "true" : "false"
        case let .number(text): text
        case let .string(text): scalarText(text, isKey: false)
        case .array: "[]"
        case .object: "{}"
        }
    }

    /// Multi-line strings as `|` blocks when that's lossless.
    private static func literalBlock(_ text: String, level: Int, unit: String) -> (header: String, lines: [String])? {
        guard text.contains("\n"), !text.contains("\r"), !text.hasPrefix(" "), !text.hasPrefix("\n"),
              !text.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" }) else { return nil }
        var body = text
        var chomp = "-"
        if body.hasSuffix("\n") {
            body.removeLast()
            chomp = body.hasSuffix("\n") ? "+" : ""
            if chomp == "+" {
                // Keep trailing blank lines: the "+" indicator preserves them.
                let parts = text.components(separatedBy: "\n")
                let content = parts.dropLast()
                return ("|+", content.map { $0.isEmpty ? "" : pad(level, unit) + $0 })
            }
        }
        let lines = body.components(separatedBy: "\n")
        // Trailing spaces on a line are kept by YAML, but a line with only spaces at the
        // start of the block would change the detected indentation.
        if let first = lines.first, first.allSatisfy({ $0 == " " }) { return nil }
        return ("|" + chomp, lines.map { $0.isEmpty ? "" : pad(level, unit) + $0 })
    }

    static let reservedWords: Set<String> = [
        "true", "false", "yes", "no", "on", "off", "y", "n", "null", "~",
    ]

    /// Plain when safe under both YAML 1.1 and 1.2 readers, double-quoted otherwise.
    static func scalarText(_ text: String, isKey: Bool) -> String {
        needsQuotes(text) ? JSONTree.quote(text) : text
    }

    static func needsQuotes(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else { return true }
        if reservedWords.contains(text.lowercased()) { return true }
        if first == " " || last == " " || first == "\t" { return true }
        if "-?:,[]{}#&*!|>'\"%@`".contains(first) {
            // "-foo" and ":foo" are fine plain only when not followed by a space; keep it simple.
            return true
        }
        if text.contains(": ") || text.contains(" #") || text.hasSuffix(":") { return true }
        if text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0 == "\u{FEFF}" }) { return true }
        // Anything a reader could take as a number, date or special float.
        if looksNumeric(text) { return true }
        return false
    }

    private static func looksNumeric(_ text: String) -> Bool {
        let numeric = (try? NSRegularExpression(pattern: "^[-+]?(?:[0-9][0-9_]*(?:\\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\\.[0-9]+(?:[eE][-+]?[0-9]+)?|0x[0-9a-fA-F_]+|0o?[0-7_]+|0b[01_]+|\\.(?:inf|Inf|INF|nan|NaN|NAN)|[0-9][0-9_]*(?::[0-5]?[0-9])+(?:\\.[0-9_]*)?)$"))!
        let date = (try? NSRegularExpression(pattern: "^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}"))!
        let range = NSRange(text.startIndex..., in: text)
        return numeric.firstMatch(in: text, range: range) != nil || date.firstMatch(in: text, range: range) != nil
    }

    /// For the detector: text that parses as a YAML mapping or sequence and isn't JSON.
    public static func looksLikeYAML(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        guard lines.count >= 2 || text.hasPrefix("---") else { return false }
        // Keys look like identifiers ("max_retries", "app.name") or are quoted; prose ("Dear team:") isn't.
        let keyLine = try! NSRegularExpression(pattern: "^\\s*(?:- )?(?:[A-Za-z_][A-Za-z0-9_.-]*|\"[^\"]*\"|'[^']*'):(?:\\s|$)")
        let itemLine = try! NSRegularExpression(pattern: "^\\s*- ")
        let structured = lines.filter { line in
            let range = NSRange(line.startIndex..., in: line)
            return keyLine.firstMatch(in: line, range: range) != nil || itemLine.firstMatch(in: line, range: range) != nil
                || line.hasPrefix("---") || line.hasPrefix("  ")
        }
        guard Double(structured.count) / Double(lines.count) >= 0.8,
              lines.contains(where: { line in keyLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }) else { return false }
        guard let value = try? parse(text) else { return false }
        switch value {
        case .object, .array: return true
        default: return false
        }
    }
}
