import Foundation

/// CSV ⇄ JSON (RFC 4180: quoted fields, doubled quotes, line breaks inside quotes).
public enum CSVConverter {
    public enum Delimiter: String, CaseIterable, Sendable, Identifiable {
        case auto, comma, semicolon, tab, pipe
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .auto: "Detect"
            case .comma: "Comma"
            case .semicolon: "Semicolon"
            case .tab: "Tab"
            case .pipe: "Pipe"
            }
        }
        var character: Character? {
            switch self {
            case .auto: nil
            case .comma: ","
            case .semicolon: ";"
            case .tab: "\t"
            case .pipe: "|"
            }
        }
    }

    public struct ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        public var message: String
        public var line: Int
        public var description: String { "Line \(line): \(message)" }
    }

    /// Splits CSV into rows of fields.
    public static func parse(_ text: String, delimiter: Delimiter = .auto) throws -> [[String]] {
        let separator = delimiter.character ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false
        var line = 1
        var quoteLine = 1
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()
        // Skip a byte order mark.
        if pending == "\u{FEFF}" { pending = iterator.next() }
        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    if character.isNewline { line += 1 }
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty && !fieldWasQuoted:
                inQuotes = true
                fieldWasQuoted = true
                quoteLine = line
            case separator:
                row.append(field)
                field = ""
                fieldWasQuoted = false
            case "\r\n", "\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                fieldWasQuoted = false
                line += 1
            default:
                field.append(character)
            }
        }
        if inQuotes { throw ParseError(message: "A quoted field is never closed", line: quoteLine) }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted {
            row.append(field)
            rows.append(row)
        }
        // Ignore blank lines (a lone empty field).
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// The delimiter that splits the first lines most consistently.
    static func detectDelimiter(_ text: String) -> Character {
        let sample = text.split(whereSeparator: \.isNewline).prefix(10).map(String.init)
        var best: Character = ","
        var bestScore = 0
        for candidate in [",", ";", "\t", "|"] as [Character] {
            let counts = sample.map { line in line.filter { $0 == candidate }.count }
            guard let first = counts.first, first > 0 else { continue }
            let consistent = counts.filter { $0 == first }.count
            let score = consistent * 100 + first
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    public struct ToJSONOptions: Sendable, Equatable {
        /// First row holds the keys; otherwise each row becomes an array.
        public var headerRow: Bool
        /// Turn `42`, `true`, `null` into JSON numbers, booleans and null.
        public var inferTypes: Bool
        public var delimiter: Delimiter
        public init(headerRow: Bool = true, inferTypes: Bool = true, delimiter: Delimiter = .auto) {
            self.headerRow = headerRow
            self.inferTypes = inferTypes
            self.delimiter = delimiter
        }
    }

    public static func toJSONValue(_ csv: String, options: ToJSONOptions = ToJSONOptions()) throws -> JSONValue {
        let rows = try parse(csv, delimiter: options.delimiter)
        let cell = { (text: String) -> JSONValue in options.inferTypes ? infer(text) : .string(text) }
        guard options.headerRow, let header = rows.first else {
            return .array(rows.map { .array($0.map(cell)) })
        }
        // Blank or repeated header names still need distinct keys.
        var keys: [String] = []
        for (index, name) in header.enumerated() {
            var key = name.isEmpty ? "column\(index + 1)" : name
            var suffix = 2
            while keys.contains(key) { key = "\(name.isEmpty ? "column\(index + 1)" : name)_\(suffix)"; suffix += 1 }
            keys.append(key)
        }
        return .array(rows.dropFirst().map { row in
            var pairs: [(String, JSONValue)] = []
            for (index, key) in keys.enumerated() {
                pairs.append((key, index < row.count ? cell(row[index]) : .null))
            }
            if row.count > keys.count {
                for index in keys.count..<row.count { pairs.append(("column\(index + 1)", cell(row[index]))) }
            }
            return .object(pairs)
        })
    }

    public static func toJSON(_ csv: String, options: ToJSONOptions = ToJSONOptions(), indent: String = "  ") throws -> String {
        JSONTree.serialize(try toJSONValue(csv, options: options), pretty: true, indent: indent)
    }

    static func infer(_ text: String) -> JSONValue {
        switch text {
        case "": return .string("")
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default:
            // Leading zeros (ZIP codes, IDs) stay strings.
            if JSONTree.isNumberLiteral(text), !(text.count > 1 && text.hasPrefix("0") && !text.hasPrefix("0.")),
               !(text.hasPrefix("-0") && text.count > 2 && !text.hasPrefix("-0.")) {
                return .number(text)
            }
            return .string(text)
        }
    }

    // MARK: JSON → CSV

    public struct ToCSVOptions: Sendable, Equatable {
        public var delimiter: Delimiter
        /// Nested objects become `parent.child` columns; otherwise they're written as JSON.
        public var flatten: Bool
        public var header: Bool
        public init(delimiter: Delimiter = .comma, flatten: Bool = true, header: Bool = true) {
            self.delimiter = delimiter
            self.flatten = flatten
            self.header = header
        }
    }

    public enum ToCSVError: Error, Equatable, Sendable, CustomStringConvertible {
        case notArray
        public var description: String { "Expected an array of objects (or of arrays), or a single object" }
    }

    public static func fromJSON(_ json: String, options: ToCSVOptions = ToCSVOptions()) throws -> String {
        let value = try JSONTree.parse(json)
        let separator = String(options.delimiter.character ?? ",")
        let items: [JSONValue]
        switch value {
        case let .array(array): items = array
        case .object: items = [value]
        default: throw ToCSVError.notArray
        }
        var lines: [String] = []
        if items.allSatisfy({ if case .array = $0 { true } else { false } }), !items.isEmpty {
            for item in items {
                guard case let .array(cells) = item else { continue }
                lines.append(cells.map { escape(cellText($0), separator: separator) }.joined(separator: separator))
            }
            return lines.joined(separator: "\n") + "\n"
        }
        // Columns in first-seen order across all rows.
        var columns: [String] = []
        var seen = Set<String>()
        var rows: [[(String, JSONValue)]] = []
        for item in items {
            let pairs: [(String, JSONValue)]
            switch item {
            case let .object(object): pairs = options.flatten ? flatten(object, prefix: "") : object
            default: pairs = [("value", item)]
            }
            for (key, _) in pairs where seen.insert(key).inserted { columns.append(key) }
            rows.append(pairs)
        }
        if options.header {
            lines.append(columns.map { escape($0, separator: separator) }.joined(separator: separator))
        }
        for pairs in rows {
            let lookup = Dictionary(pairs.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
            lines.append(columns.map { escape(lookup[$0].map(cellText) ?? "", separator: separator) }.joined(separator: separator))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func flatten(_ pairs: [(String, JSONValue)], prefix: String) -> [(String, JSONValue)] {
        var out: [(String, JSONValue)] = []
        for (key, value) in pairs {
            let name = prefix.isEmpty ? key : prefix + "." + key
            if case let .object(inner) = value, !inner.isEmpty {
                out.append(contentsOf: flatten(inner, prefix: name))
            } else {
                out.append((name, value))
            }
        }
        return out
    }

    static func cellText(_ value: JSONValue) -> String { value.plainText }

    static func escape(_ field: String, separator: String) -> String {
        let needsQuotes = field.contains(separator) || field.contains("\"") || field.contains("\n") || field.contains("\r")
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// For the detector: several lines with the same number (≥ 2) of delimited fields.
    public static func looksLikeCSV(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).prefix(20)
        guard lines.count >= 2 else { return false }
        let separator = detectDelimiter(text)
        guard let rows = try? parse(lines.joined(separator: "\n"), delimiter: Delimiter.allCases.first { $0.character == separator } ?? .comma),
              let width = rows.first?.count, width >= 2 else { return false }
        return rows.allSatisfy { $0.count == width }
    }
}
