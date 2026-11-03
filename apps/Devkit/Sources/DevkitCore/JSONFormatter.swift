import Foundation

/// A strict JSON (RFC 8259) formatter that keeps key order and number text exactly as
/// written, so `12345678901234567890` and `1.10` survive a round trip (unlike
/// `JSONSerialization`). Works on UTF-8 bytes in one pass with an explicit stack, so deep
/// nesting can't overflow the call stack and a 50 MB document formats in well under a second.
public enum JSONFormatter {
    public enum Indent: String, CaseIterable, Sendable, Identifiable {
        case two = "2"
        case four = "4"
        case tab

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .two: "2 Spaces"
            case .four: "4 Spaces"
            case .tab: "Tab"
            }
        }

        var bytes: [UInt8] {
            switch self {
            case .two: Array("  ".utf8)
            case .four: Array("    ".utf8)
            case .tab: [UInt8(ascii: "\t")]
            }
        }
    }

    public enum Style: String, CaseIterable, Sendable, Identifiable {
        case pretty
        case minified

        public var id: String { rawValue }
        public var title: String { self == .pretty ? "Format" : "Minify" }
    }

    public struct Options: Sendable, Equatable {
        public var style: Style
        public var indent: Indent
        public var sortKeys: Bool

        public init(style: Style = .pretty, indent: Indent = .two, sortKeys: Bool = false) {
            self.style = style
            self.indent = indent
            self.sortKeys = sortKeys
        }
    }

    public struct Result: Sendable, Equatable {
        public var text: String
        /// Non-fatal findings, e.g. duplicate keys (allowed by RFC 8259 but usually a bug).
        public var warnings: [String]
        public var lineCount: Int
    }

    /// Formats (or minifies) `text`. Throws `JSONError` with a line and column for invalid
    /// JSON, or `CancellationError` when `isCancelled` returns true part way.
    public static func format(_ text: String, options: Options = Options(),
                              isCancelled: () -> Bool = { false }) throws -> Result {
        var bytes = Array(text.utf8)
        // A leading byte-order mark is common in files saved on Windows; skip it.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        let (output, warnings) = try withoutActuallyEscaping(isCancelled) { isCancelled in
            var writer = Writer(input: bytes, options: options, isCancelled: isCancelled)
            try writer.run()
            return (writer.finish(), writer.warnings)
        }
        let lines = output.reduce(into: 1) { count, byte in if byte == UInt8(ascii: "\n") { count += 1 } }
        return Result(text: String(decoding: output, as: UTF8.self), warnings: warnings, lineCount: lines)
    }

    /// True when `text` is a complete, valid JSON document.
    public static func isValid(_ text: String) -> Bool {
        (try? format(text, options: Options(style: .minified))) != nil
    }
}

/// Where and why a JSON document is invalid. Line and column are 1-based; the column counts
/// characters (not bytes). `offset` is a UTF-8 byte offset into the input.
public struct JSONError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var line: Int
    public var column: Int
    public var offset: Int

    public var description: String { "Line \(line), column \(column): \(message)" }

    static func at(_ offset: Int, in bytes: [UInt8], _ message: String) -> JSONError {
        var line = 1
        var lineStart = 0
        let end = min(offset, bytes.count)
        var index = 0
        while index < end {
            if bytes[index] == UInt8(ascii: "\n") {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        // Count characters, not bytes: skip UTF-8 continuation bytes.
        var column = 1
        index = lineStart
        while index < end {
            if bytes[index] & 0xC0 != 0x80 { column += 1 }
            index += 1
        }
        return JSONError(message: message, line: line, column: column, offset: offset)
    }
}

// MARK: - Writer

private struct Writer {
    enum Container { case object, array }

    /// One open object or array. Objects being sorted collect their members separately and
    /// write them out in key order when they close.
    struct Frame {
        var kind: Container
        var count = 0
        var sorting = false
        var members: [(key: String, text: [UInt8])] = []
        var currentKey: String?
        var current: [UInt8] = []
        var keys: Set<String>? = nil
    }

    enum Expect { case value, keyOrEnd, key, colon, commaOrEnd, valueOrEnd }

    let input: [UInt8]
    let options: JSONFormatter.Options
    let isCancelled: () -> Bool
    let pretty: Bool
    let indentUnit: [UInt8]
    let colon: [UInt8]

    var position = 0
    var out: [UInt8] = []
    var stack: [Frame] = []
    var expect: Expect = .value
    var sawValue = false
    var warnings: [String] = []
    var steps = 0
    /// Byte offset of the last comma, to point "trailing comma" errors at it.
    var lastComma = 0

    init(input: [UInt8], options: JSONFormatter.Options, isCancelled: @escaping () -> Bool) {
        self.input = input
        self.options = options
        self.isCancelled = isCancelled
        pretty = options.style == .pretty
        indentUnit = options.indent.bytes
        colon = pretty ? Array(": ".utf8) : [UInt8(ascii: ":")]
        out.reserveCapacity(pretty ? input.count + input.count / 2 : input.count)
    }

    func error(_ message: String, at offset: Int? = nil) -> JSONError {
        JSONError.at(offset ?? position, in: input, message)
    }

    // MARK: Output

    @inline(__always)
    mutating func emit(_ bytes: [UInt8]) {
        if sortingFrames.isEmpty {
            out.append(contentsOf: bytes)
        } else if let index = sortingIndex {
            stack[index].current.append(contentsOf: bytes)
        } else {
            out.append(contentsOf: bytes)
        }
    }

    @inline(__always)
    mutating func emit(_ slice: ArraySlice<UInt8>) {
        if sortingFrames.isEmpty {
            out.append(contentsOf: slice)
        } else if let index = sortingIndex {
            stack[index].current.append(contentsOf: slice)
        } else {
            out.append(contentsOf: slice)
        }
    }

    @inline(__always)
    mutating func emit(_ byte: UInt8) {
        if sortingFrames.isEmpty {
            out.append(byte)
        } else if let index = sortingIndex {
            stack[index].current.append(byte)
        } else {
            out.append(byte)
        }
    }

    /// The innermost sorting object: everything inside it is buffered per member.
    var sortingIndex: Int? { sortingFrames.last }
    /// Stack indices of open sorting objects, innermost last.
    var sortingFrames: [Int] = []

    mutating func newline(depth: Int) {
        guard pretty else { return }
        emit(UInt8(ascii: "\n"))
        for _ in 0..<depth { emit(indentUnit) }
    }

    func newlineBytes(depth: Int) -> [UInt8] {
        guard pretty else { return [] }
        var bytes: [UInt8] = [UInt8(ascii: "\n")]
        for _ in 0..<depth { bytes.append(contentsOf: indentUnit) }
        return bytes
    }

    mutating func finish() -> [UInt8] { out }

    // MARK: Parse loop

    mutating func run() throws {
        skipWhitespace()
        if position >= input.count { throw error("The input is empty. Paste some JSON.") }
        while true {
            steps += 1
            if steps & 0xFFFF == 0, isCancelled() { throw CancellationError() }
            skipWhitespace()
            guard position < input.count else {
                if stack.isEmpty, sawValue { return }
                throw error(stack.last?.kind == .object ? "The object isn't closed. Add a }." : "The array isn't closed. Add a ].")
            }
            if stack.isEmpty, sawValue {
                throw error("Unexpected text after the JSON value.")
            }
            let byte = input[position]
            switch expect {
            case .value, .valueOrEnd:
                if expect == .valueOrEnd, byte == UInt8(ascii: "]") {
                    try close(.array)
                } else if byte == UInt8(ascii: "]") || byte == UInt8(ascii: "}") {
                    let afterComma = stack.last?.kind == .array && (stack.last?.count ?? 0) > 0
                    if afterComma { throw error("Trailing comma before ]. Remove the comma.", at: lastComma) }
                    throw error("Expected a value.")
                } else {
                    try value()
                }
            case .keyOrEnd, .key:
                if byte == UInt8(ascii: "}") {
                    if expect == .key { throw error("Trailing comma before }. Remove the comma.", at: lastComma) }
                    try close(.object)
                } else if byte == UInt8(ascii: "\"") {
                    try key()
                } else if byte == UInt8(ascii: "'") {
                    throw error("Keys need double quotes, not single quotes.")
                } else if byte == UInt8(ascii: "/") {
                    throw error("Comments aren't allowed in JSON.")
                } else {
                    throw error("Expected a key in double quotes.")
                }
            case .colon:
                guard byte == UInt8(ascii: ":") else { throw error("Expected : after the key.") }
                position += 1
                emit(colon)
                expect = .value
            case .commaOrEnd:
                guard let frame = stack.last else { return }
                if byte == UInt8(ascii: ",") {
                    lastComma = position
                    position += 1
                    expect = frame.kind == .object ? .key : .value
                } else if byte == UInt8(ascii: "}"), frame.kind == .object {
                    try close(.object)
                } else if byte == UInt8(ascii: "]"), frame.kind == .array {
                    try close(.array)
                } else if byte == UInt8(ascii: "/") {
                    throw error("Comments aren't allowed in JSON.")
                } else {
                    throw error(frame.kind == .object ? "Expected , or } after the value." : "Expected , or ] after the value.")
                }
            }
        }
    }

    /// Writes the separator before an array element or object member. Sorting objects
    /// join their members when they close instead.
    mutating func beginItem() {
        guard let last = stack.indices.last else { return }
        if !stack[last].sorting {
            if stack[last].count > 0 { emit(UInt8(ascii: ",")) }
            newline(depth: stack.count)
        }
        stack[last].count += 1
    }

    mutating func key() throws {
        let start = position
        let decoded = try scanString(decode: true) ?? ""
        beginItem()
        let last = stack.count - 1
        if stack[last].sorting {
            if let previous = stack[last].currentKey {
                stack[last].members.append((key: previous, text: stack[last].current))
                stack[last].current = []
            }
            stack[last].currentKey = decoded
        }
        if stack[last].keys?.insert(decoded).inserted == false, warnings.count < 20 {
            let location = JSONError.at(start, in: input, "")
            warnings.append("Duplicate key “\(decoded)” at line \(location.line), column \(location.column).")
        }
        emit(input[start..<position])
        expect = .colon
    }

    mutating func value() throws {
        let byte = input[position]
        let inObject = stack.last?.kind == .object
        if !inObject { beginItem() }
        switch byte {
        case UInt8(ascii: "{"):
            position += 1
            var frame = Frame(kind: .object)
            frame.sorting = options.sortKeys
            frame.keys = []
            emit(UInt8(ascii: "{"))
            if frame.sorting { sortingFrames.append(stack.count) }
            stack.append(frame)
            expect = .keyOrEnd
            return
        case UInt8(ascii: "["):
            position += 1
            emit(UInt8(ascii: "["))
            stack.append(Frame(kind: .array))
            expect = .valueOrEnd
            return
        case UInt8(ascii: "\""):
            let start = position
            _ = try scanString(decode: false)
            emit(input[start..<position])
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            let start = position
            try scanNumber()
            emit(input[start..<position])
        case UInt8(ascii: "t"): try literal("true")
        case UInt8(ascii: "f"): try literal("false")
        case UInt8(ascii: "n"): try literal("null")
        case UInt8(ascii: "N"):
            throw error(startsWith("NaN") ? "NaN isn't valid JSON. Use null or a string." : "Expected a value.")
        case UInt8(ascii: "I"):
            throw error(startsWith("Infinity") ? "Infinity isn't valid JSON. Use null or a string." : "Expected a value.")
        case UInt8(ascii: "'"):
            throw error("Strings need double quotes, not single quotes.")
        case UInt8(ascii: "/"):
            throw error("Comments aren't allowed in JSON.")
        default:
            throw error("Expected a value.")
        }
        afterValue()
    }

    mutating func afterValue() {
        if stack.isEmpty {
            sawValue = true
            expect = .value
        } else {
            expect = .commaOrEnd
        }
    }

    mutating func close(_ kind: Writer.Container) throws {
        position += 1
        guard var frame = stack.popLast() else { throw error("Unexpected closing bracket.") }
        if frame.kind != kind { throw error("Mismatched bracket.") }
        if frame.sorting { sortingFrames.removeLast() }
        let depth = stack.count
        let closing = UInt8(ascii: kind == .object ? "}" : "]")
        if frame.sorting {
            // `{` was already written to the parent's buffer; write the sorted members after it.
            if let key = frame.currentKey { frame.members.append((key: key, text: frame.current)) }
            frame.members.sort { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
            var bytes: [UInt8] = []
            for (index, member) in frame.members.enumerated() {
                if index > 0 { bytes.append(UInt8(ascii: ",")) }
                bytes.append(contentsOf: newlineBytes(depth: depth + 1))
                bytes.append(contentsOf: member.text)
            }
            if !frame.members.isEmpty { bytes.append(contentsOf: newlineBytes(depth: depth)) }
            bytes.append(closing)
            emit(bytes)
        } else {
            if frame.count > 0 { newline(depth: depth) }
            emit(closing)
        }
        afterValue()
    }

    // MARK: Scanning

    mutating func skipWhitespace() {
        while position < input.count {
            switch input[position] {
            case 0x20, 0x09, 0x0A, 0x0D: position += 1
            default: return
            }
        }
    }

    func startsWith(_ word: StaticString) -> Bool {
        let count = word.utf8CodeUnitCount
        guard position + count <= input.count else { return false }
        let pointer = word.utf8Start
        for offset in 0..<count where input[position + offset] != pointer[offset] { return false }
        return true
    }

    mutating func literal(_ word: StaticString) throws {
        guard startsWith(word) else {
            throw error(word.utf8CodeUnitCount != 4 || input[position] == UInt8(ascii: "t") ? "Expected true or false." : "Expected a value.")
        }
        emit(input[position..<position + word.utf8CodeUnitCount])
        position += word.utf8CodeUnitCount
    }

    mutating func scanNumber() throws {
        let start = position
        if input[position] == UInt8(ascii: "-") { position += 1 }
        guard position < input.count, isDigit(input[position]) else {
            if position < input.count, input[position] == UInt8(ascii: "I") {
                throw error("Infinity isn't valid JSON. Use null or a string.", at: start)
            }
            throw error("Expected a digit.")
        }
        if input[position] == UInt8(ascii: "0") {
            position += 1
            if position < input.count, isDigit(input[position]) {
                throw error("Numbers can't have leading zeros.", at: start)
            }
        } else {
            while position < input.count, isDigit(input[position]) { position += 1 }
        }
        if position < input.count, input[position] == UInt8(ascii: ".") {
            position += 1
            guard position < input.count, isDigit(input[position]) else { throw error("Expected a digit after the decimal point.") }
            while position < input.count, isDigit(input[position]) { position += 1 }
        }
        if position < input.count, input[position] == UInt8(ascii: "e") || input[position] == UInt8(ascii: "E") {
            position += 1
            if position < input.count, input[position] == UInt8(ascii: "+") || input[position] == UInt8(ascii: "-") { position += 1 }
            guard position < input.count, isDigit(input[position]) else { throw error("Expected a digit in the exponent.") }
            while position < input.count, isDigit(input[position]) { position += 1 }
        }
    }

    func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    /// Scans a string starting at the opening quote. Returns the decoded value when asked.
    mutating func scanString(decode: Bool) throws -> String? {
        let start = position
        position += 1
        var decoded: [UInt8]? = decode ? [] : nil
        var runStart = position
        while true {
            guard position < input.count else { throw error("The string isn't closed. Add a \".", at: start) }
            let byte = input[position]
            if byte == UInt8(ascii: "\"") {
                decoded?.append(contentsOf: input[runStart..<position])
                position += 1
                return decoded.map { String(decoding: $0, as: UTF8.self) }
            }
            if byte < 0x20 {
                throw error(byte == 0x0A ? "The string isn't closed before the end of the line." : "Strings can't contain control characters. Escape them, e.g. \\n or \\t.")
            }
            if byte == UInt8(ascii: "\\") {
                decoded?.append(contentsOf: input[runStart..<position])
                position += 1
                guard position < input.count else { throw error("The string isn't closed. Add a \".", at: start) }
                let escape = input[position]
                switch escape {
                case UInt8(ascii: "\""): decoded?.append(escape)
                case UInt8(ascii: "\\"): decoded?.append(escape)
                case UInt8(ascii: "/"): decoded?.append(escape)
                case UInt8(ascii: "b"): decoded?.append(0x08)
                case UInt8(ascii: "f"): decoded?.append(0x0C)
                case UInt8(ascii: "n"): decoded?.append(0x0A)
                case UInt8(ascii: "r"): decoded?.append(0x0D)
                case UInt8(ascii: "t"): decoded?.append(0x09)
                case UInt8(ascii: "u"):
                    let unit = try hex4(at: position + 1)
                    position += 4
                    if decoded != nil {
                        var scalar: UnicodeScalar?
                        if (0xD800...0xDBFF).contains(unit), position + 6 < input.count,
                           input[position + 1] == UInt8(ascii: "\\"), input[position + 2] == UInt8(ascii: "u"),
                           let low = try? hex4(at: position + 3), (0xDC00...0xDFFF).contains(low) {
                            scalar = UnicodeScalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
                            position += 6
                        } else {
                            scalar = UnicodeScalar(unit)
                        }
                        decoded?.append(contentsOf: Array(String(scalar ?? "\u{FFFD}").utf8))
                    }
                default:
                    throw error("Unknown escape \\\(Character(UnicodeScalar(escape))). Use \\\\ for a backslash.", at: position - 1)
                }
                position += 1
                runStart = position
                continue
            }
            position += 1
        }
    }

    func hex4(at index: Int) throws -> UInt32 {
        guard index + 4 <= input.count else { throw error("Expected four hex digits after \\u.") }
        var value: UInt32 = 0
        for offset in 0..<4 {
            let byte = input[index + offset]
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
            default: throw error("Expected four hex digits after \\u.", at: index + offset)
            }
            value = value << 4 | digit
        }
        return value
    }
}
