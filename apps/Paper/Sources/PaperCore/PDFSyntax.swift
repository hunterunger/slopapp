import Foundation

/// A small reader and writer for PDF's object syntax, so Paper can add what PDFKit can't
/// write: the form's `/AcroForm` dictionary and calculation scripts (research P24, P25) and
/// certificate signatures (byte-range signatures need exact control over the bytes).
///
/// Paper only *appends* to files (incremental updates, PDF 32000 §7.5.6): the original bytes
/// stay exactly as they were, new versions of a few objects go after them, and readers use
/// the newest version. That keeps earlier signatures valid and means this code never has to
/// rewrite a whole document.
public indirect enum PDFObject: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case real(Double)
    case name(String)
    /// String bytes as stored (after unescaping). `hex` only changes how it's written.
    case string(Data, hex: Bool = false)
    case array([PDFObject])
    case dict(PDFDict)
    case ref(Int, Int)

    public static func text(_ value: String) -> PDFObject { .string(PDFText.encode(value)) }

    public var dictValue: PDFDict? { if case .dict(let d) = self { d } else { nil } }
    public var arrayValue: [PDFObject]? { if case .array(let a) = self { a } else { nil } }
    public var nameValue: String? { if case .name(let n) = self { n } else { nil } }
    public var refValue: (Int, Int)? { if case .ref(let n, let g) = self { (n, g) } else { nil } }
    public var stringValue: Data? { if case .string(let s, _) = self { s } else { nil } }
    public var textValue: String? { stringValue.map(PDFText.decode) }

    public var intValue: Int? {
        switch self {
        case .int(let i): i
        case .real(let r): Int(r)
        default: nil
        }
    }

    public var numberValue: Double? {
        switch self {
        case .int(let i): Double(i)
        case .real(let r): r
        default: nil
        }
    }
}

/// A dictionary that keeps its keys in order, so rewritten objects stay readable.
public struct PDFDict: Equatable, Sendable {
    public private(set) var entries: [(key: String, value: PDFObject)] = []

    public init(_ entries: [(String, PDFObject)] = []) {
        for (key, value) in entries { self[key] = value }
    }

    public subscript(key: String) -> PDFObject? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
            } else if let newValue {
                entries.append((key, newValue))
            }
        }
    }

    public var keys: [String] { entries.map(\.key) }

    public static func == (a: PDFDict, b: PDFDict) -> Bool {
        a.entries.count == b.entries.count && zip(a.entries, b.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}

/// PDF text strings: PDFDocEncoding (Latin-1 is close enough for what Paper writes) or
/// UTF-16BE with a byte-order mark for anything else.
public enum PDFText {
    public static func encode(_ text: String) -> Data {
        if text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F || $0 == "\n" || $0 == "\r" || $0 == "\t" }) {
            return Data(text.utf8)
        }
        var data = Data([0xFE, 0xFF])
        for unit in text.utf16 { data.append(UInt8(unit >> 8)); data.append(UInt8(unit & 0xFF)) }
        return data
    }

    public static func decode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            var units: [UInt16] = []
            var index = 2
            while index + 1 < bytes.count {
                units.append(UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
                index += 2
            }
            return String(decoding: units, as: UTF16.self)
        }
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return String(decoding: bytes.dropFirst(3), as: UTF8.self)
        }
        return String(bytes.map { Character(Unicode.Scalar($0)) })
    }
}

public enum PDFSyntaxError: Error, Equatable {
    case noStartXref
    case badXref
    case missingObject(Int)
    case unexpected(String, at: Int)
    case encrypted
}

// MARK: Lexing and parsing

/// Parses objects out of raw bytes. Works on `Data` without copying it.
struct PDFParser {
    let data: Data
    var position: Int

    init(_ data: Data, at position: Int = 0) {
        self.data = data
        self.position = data.startIndex + position
    }

    var offset: Int { position - data.startIndex }
    var atEnd: Bool { position >= data.endIndex }

    func byte(_ index: Int) -> UInt8? { index < data.endIndex && index >= data.startIndex ? data[index] : nil }
    var current: UInt8? { byte(position) }

    static func isWhitespace(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32].contains(byte) }
    static func isDelimiter(_ byte: UInt8) -> Bool { "()<>[]{}/%".utf8.contains(byte) }
    static func isRegular(_ byte: UInt8) -> Bool { !isWhitespace(byte) && !isDelimiter(byte) }

    mutating func skipWhitespace() {
        while let byte = current {
            if Self.isWhitespace(byte) {
                position += 1
            } else if byte == UInt8(ascii: "%") {
                while let next = current, next != 10, next != 13 { position += 1 }
            } else {
                return
            }
        }
    }

    /// The next run of regular characters (a keyword or number), without consuming it.
    func peekToken() -> String {
        var index = position
        var bytes: [UInt8] = []
        while let byte = byte(index), Self.isRegular(byte) { bytes.append(byte); index += 1 }
        return String(decoding: bytes, as: UTF8.self)
    }

    mutating func readToken() -> String {
        let token = peekToken()
        position += token.utf8.count
        return token
    }

    mutating func expect(_ keyword: String) throws {
        skipWhitespace()
        guard readToken() == keyword else { throw PDFSyntaxError.unexpected(keyword, at: offset) }
    }

    mutating func parseObject() throws -> PDFObject {
        skipWhitespace()
        guard let first = current else { throw PDFSyntaxError.unexpected("object", at: offset) }
        switch first {
        case UInt8(ascii: "/"):
            position += 1
            return .name(readName())
        case UInt8(ascii: "("):
            return .string(try readLiteralString())
        case UInt8(ascii: "<"):
            if self.byte(position + 1) == UInt8(ascii: "<") {
                position += 2
                var dict = PDFDict()
                while true {
                    skipWhitespace()
                    guard let next = current else { throw PDFSyntaxError.unexpected(">>", at: offset) }
                    if next == UInt8(ascii: ">") {
                        position += 2
                        return .dict(dict)
                    }
                    guard next == UInt8(ascii: "/") else { throw PDFSyntaxError.unexpected("name", at: offset) }
                    position += 1
                    let key = readName()
                    dict[key] = try parseObject()
                }
            }
            return .string(try readHexString(), hex: true)
        case UInt8(ascii: "["):
            position += 1
            var items: [PDFObject] = []
            while true {
                skipWhitespace()
                guard let next = current else { throw PDFSyntaxError.unexpected("]", at: offset) }
                if next == UInt8(ascii: "]") {
                    position += 1
                    return .array(items)
                }
                items.append(try parseObject())
            }
        default:
            let token = readToken()
            switch token {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            case "": throw PDFSyntaxError.unexpected("object", at: offset)
            default:
                if let int = Int(token) {
                    // `n g R` is a reference.
                    let saved = position
                    skipWhitespace()
                    let generation = peekToken()
                    if let gen = Int(generation), !generation.contains(".") {
                        position += generation.utf8.count
                        skipWhitespace()
                        if peekToken() == "R" {
                            position += 1
                            return .ref(int, gen)
                        }
                    }
                    position = saved
                    return .int(int)
                }
                if let real = Double(token) { return .real(real) }
                throw PDFSyntaxError.unexpected("object", at: offset)
            }
        }
    }

    mutating func readName() -> String {
        var bytes: [UInt8] = []
        while let byte = current, Self.isRegular(byte) {
            if byte == UInt8(ascii: "#"), let hi = self.byte(position + 1).flatMap(Self.hexValue), let lo = self.byte(position + 2).flatMap(Self.hexValue) {
                bytes.append(hi << 4 | lo)
                position += 3
            } else {
                bytes.append(byte)
                position += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    mutating func readLiteralString() throws -> Data {
        position += 1
        var depth = 1
        var out = Data()
        while let byte = current {
            position += 1
            switch byte {
            case UInt8(ascii: "\\"):
                guard let next = current else { break }
                position += 1
                switch next {
                case UInt8(ascii: "n"): out.append(10)
                case UInt8(ascii: "r"): out.append(13)
                case UInt8(ascii: "t"): out.append(9)
                case UInt8(ascii: "b"): out.append(8)
                case UInt8(ascii: "f"): out.append(12)
                case 10: break
                case 13: if current == 10 { position += 1 }
                case 48...55:
                    var value = Int(next - 48)
                    for _ in 0..<2 {
                        guard let digit = current, (48...55).contains(digit) else { break }
                        value = value * 8 + Int(digit - 48)
                        position += 1
                    }
                    out.append(UInt8(value & 0xFF))
                default: out.append(next)
                }
            case UInt8(ascii: "("):
                depth += 1
                out.append(byte)
            case UInt8(ascii: ")"):
                depth -= 1
                if depth == 0 { return out }
                out.append(byte)
            default:
                out.append(byte)
            }
        }
        throw PDFSyntaxError.unexpected(")", at: offset)
    }

    mutating func readHexString() throws -> Data {
        position += 1
        var out = Data()
        var high: UInt8?
        while let byte = current {
            position += 1
            if byte == UInt8(ascii: ">") {
                if let high { out.append(high << 4) }
                return out
            }
            guard let value = Self.hexValue(byte) else { continue }
            if let h = high { out.append(h << 4 | value); high = nil } else { high = value }
        }
        throw PDFSyntaxError.unexpected(">", at: offset)
    }
}

// MARK: Serializing

public enum PDFWriter {
    public static func serialize(_ object: PDFObject) -> Data {
        var out = Data()
        write(object, into: &out)
        return out
    }

    static func write(_ object: PDFObject, into out: inout Data) {
        switch object {
        case .null: out.append(contentsOf: Array("null".utf8))
        case .bool(let value): out.append(contentsOf: Array((value ? "true" : "false").utf8))
        case .int(let value): out.append(contentsOf: Array(String(value).utf8))
        case .real(let value): out.append(contentsOf: Array(number(value).utf8))
        case .name(let name): out.append(contentsOf: Array(("/" + escapeName(name)).utf8))
        case .string(let data, let hex):
            if hex {
                out.append(UInt8(ascii: "<"))
                out.append(contentsOf: Array(data.map { String(format: "%02X", $0) }.joined().utf8))
                out.append(UInt8(ascii: ">"))
            } else {
                out.append(UInt8(ascii: "("))
                for byte in data {
                    switch byte {
                    case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\\"):
                        out.append(UInt8(ascii: "\\")); out.append(byte)
                    case 10: out.append(contentsOf: Array("\\n".utf8))
                    case 13: out.append(contentsOf: Array("\\r".utf8))
                    case 32..<127: out.append(byte)
                    default: out.append(contentsOf: Array(String(format: "\\%03o", byte).utf8))
                    }
                }
                out.append(UInt8(ascii: ")"))
            }
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (index, item) in items.enumerated() {
                if index > 0 { out.append(UInt8(ascii: " ")) }
                write(item, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .dict(let dict):
            out.append(contentsOf: Array("<<".utf8))
            for entry in dict.entries {
                out.append(contentsOf: Array((" /" + escapeName(entry.key) + " ").utf8))
                write(entry.value, into: &out)
            }
            out.append(contentsOf: Array(" >>".utf8))
        case .ref(let number, let generation):
            out.append(contentsOf: Array("\(number) \(generation) R".utf8))
        }
    }

    /// Plain decimal notation (PDF has no exponents), at most 4 decimals.
    static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    static func escapeName(_ name: String) -> String {
        var out = ""
        for byte in name.utf8 {
            if byte > 32, byte < 127, PDFParser.isRegular(byte), byte != UInt8(ascii: "#") {
                out.append(Character(Unicode.Scalar(byte)))
            } else {
                out += String(format: "#%02X", byte)
            }
        }
        return out
    }
}

// MARK: Files

/// A PDF file's cross-reference information and objects, read lazily from its bytes.
public final class PDFFile: @unchecked Sendable {
    public enum Entry: Equatable, Sendable {
        case offset(Int, generation: Int)
        case compressed(stream: Int, index: Int)
        case free
    }

    public let data: Data
    /// Newest entry for each object number.
    public private(set) var entries: [Int: Entry] = [:]
    /// The newest trailer (for cross-reference streams, the stream's dictionary).
    public private(set) var trailer = PDFDict()
    /// Byte offset of the newest cross-reference section.
    public private(set) var startXref = 0
    /// Whether the newest section is a cross-reference stream (updates then use one too).
    public private(set) var usesXrefStream = false
    private var objectStreamCache: [Int: [Int: PDFObject]] = [:]

    public init(data: Data) throws {
        self.data = data
        startXref = try Self.findStartXref(data)
        var seen = Set<Int>()
        var next: Int? = startXref
        var first = true
        while let offset = next, !seen.contains(offset) {
            seen.insert(offset)
            let (sectionTrailer, isStream) = try readSection(at: offset)
            if first {
                trailer = sectionTrailer
                usesXrefStream = isStream
                first = false
            }
            // A hybrid file's table points at a stream with more entries.
            if let extra = sectionTrailer["XRefStm"]?.intValue, !seen.contains(extra) {
                seen.insert(extra)
                _ = try? readSection(at: extra)
            }
            next = sectionTrailer["Prev"]?.intValue
        }
    }

    public var isEncrypted: Bool { trailer["Encrypt"] != nil }
    public var size: Int { trailer["Size"]?.intValue ?? ((entries.keys.max() ?? 0) + 1) }
    public var rootRef: (Int, Int)? { trailer["Root"]?.refValue }

    static func findStartXref(_ data: Data) throws -> Int {
        let tail = data.suffix(2048)
        guard let range = tail.range(of: Data("startxref".utf8), options: .backwards) else { throw PDFSyntaxError.noStartXref }
        var parser = PDFParser(data, at: range.upperBound - data.startIndex)
        parser.skipWhitespace()
        guard let offset = Int(parser.readToken()), offset >= 0, offset < data.count else { throw PDFSyntaxError.noStartXref }
        return offset
    }

    /// Reads one cross-reference section (table or stream). Older entries never overwrite
    /// newer ones, since sections are read newest first.
    private func readSection(at offset: Int) throws -> (PDFDict, Bool) {
        var parser = PDFParser(data, at: offset)
        parser.skipWhitespace()
        if parser.peekToken() == "xref" {
            _ = parser.readToken()
            while true {
                parser.skipWhitespace()
                let token = parser.peekToken()
                if token == "trailer" {
                    _ = parser.readToken()
                    guard case .dict(let dict) = try parser.parseObject() else { throw PDFSyntaxError.badXref }
                    return (dict, false)
                }
                guard let start = Int(parser.readToken()) else { throw PDFSyntaxError.badXref }
                parser.skipWhitespace()
                guard let count = Int(parser.readToken()) else { throw PDFSyntaxError.badXref }
                for index in 0..<count {
                    parser.skipWhitespace()
                    guard let position = Int(parser.readToken()) else { throw PDFSyntaxError.badXref }
                    parser.skipWhitespace()
                    let generation = Int(parser.readToken()) ?? 0
                    parser.skipWhitespace()
                    let kind = parser.readToken()
                    let number = start + index
                    guard entries[number] == nil else { continue }
                    entries[number] = kind == "n" ? .offset(position, generation: generation) : .free
                }
            }
        }
        // A cross-reference stream: `n g obj << /Type /XRef … >> stream … endstream`.
        let (object, stream) = try readIndirect(at: offset)
        guard case .dict(let dict) = object, let stream, dict["Type"]?.nameValue == "XRef" else { throw PDFSyntaxError.badXref }
        let decoded = try StreamFilters.decode(stream, dict: dict)
        let widths = (dict["W"]?.arrayValue ?? []).compactMap(\.intValue)
        guard widths.count == 3 else { throw PDFSyntaxError.badXref }
        let rowLength = widths.reduce(0, +)
        let size = dict["Size"]?.intValue ?? 0
        let index = (dict["Index"]?.arrayValue ?? [.int(0), .int(size)]).compactMap(\.intValue)
        var row = 0
        let bytes = [UInt8](decoded)
        func field(_ start: Int, _ width: Int) -> Int {
            var value = 0
            for i in 0..<width { value = value << 8 | Int(bytes[start + i]) }
            return value
        }
        for pair in stride(from: 0, to: index.count - 1, by: 2) {
            for number in index[pair]..<(index[pair] + index[pair + 1]) {
                let base = row * rowLength
                row += 1
                guard base + rowLength <= bytes.count else { break }
                guard entries[number] == nil else { continue }
                let type = widths[0] == 0 ? 1 : field(base, widths[0])
                let second = field(base + widths[0], widths[1])
                let third = field(base + widths[0] + widths[1], widths[2])
                switch type {
                case 1: entries[number] = .offset(second, generation: third)
                case 2: entries[number] = .compressed(stream: second, index: third)
                default: entries[number] = .free
                }
            }
        }
        return (dict, true)
    }

    /// The object (and raw stream bytes, still encoded) starting at `offset`.
    public func readIndirect(at offset: Int) throws -> (PDFObject, Data?) {
        var parser = PDFParser(data, at: offset)
        parser.skipWhitespace()
        guard Int(parser.readToken()) != nil else { throw PDFSyntaxError.unexpected("object number", at: offset) }
        parser.skipWhitespace()
        guard Int(parser.readToken()) != nil else { throw PDFSyntaxError.unexpected("generation", at: offset) }
        try parser.expect("obj")
        let object = try parser.parseObject()
        parser.skipWhitespace()
        guard parser.peekToken() == "stream", case .dict(let dict) = object else { return (object, nil) }
        _ = parser.readToken()
        if parser.current == 13 { parser.position += 1 }
        if parser.current == 10 { parser.position += 1 }
        let start = parser.position
        var length = dict["Length"].flatMap { try? resolve($0).intValue } ?? -1
        if length < 0 || start + length > data.endIndex {
            // A wrong /Length: look for the end marker instead.
            let end = data.range(of: Data("endstream".utf8), in: start..<data.endIndex)?.lowerBound ?? data.endIndex
            length = end - start
        }
        return (object, data.subdata(in: start..<(start + length)))
    }

    public func object(_ number: Int) throws -> PDFObject {
        try objectWithStream(number).0
    }

    public func objectWithStream(_ number: Int) throws -> (PDFObject, Data?) {
        switch entries[number] {
        case .offset(let offset, _):
            return try readIndirect(at: offset)
        case .compressed(let stream, let index):
            if let cached = objectStreamCache[stream]?[index] { return (cached, nil) }
            let objects = try readObjectStream(stream)
            guard let object = objects[index] else { throw PDFSyntaxError.missingObject(number) }
            return (object, nil)
        default:
            throw PDFSyntaxError.missingObject(number)
        }
    }

    private func readObjectStream(_ number: Int) throws -> [Int: PDFObject] {
        let (object, raw) = try objectWithStream(number)
        guard case .dict(let dict) = object, let raw else { throw PDFSyntaxError.missingObject(number) }
        let decoded = try StreamFilters.decode(raw, dict: dict)
        let count = dict["N"]?.intValue ?? 0
        let first = dict["First"]?.intValue ?? 0
        var header = PDFParser(decoded)
        var offsets: [Int] = []
        for _ in 0..<count {
            header.skipWhitespace(); _ = header.readToken()
            header.skipWhitespace(); offsets.append(Int(header.readToken()) ?? 0)
        }
        var result: [Int: PDFObject] = [:]
        for (index, offset) in offsets.enumerated() {
            var parser = PDFParser(decoded, at: first + offset)
            result[index] = try? parser.parseObject()
        }
        objectStreamCache[number] = result
        return result
    }

    /// Follows references until it reaches a direct object.
    public func resolve(_ object: PDFObject) throws -> PDFObject {
        var current = object
        var hops = 0
        while case .ref(let number, _) = current, hops < 32 {
            current = try self.object(number)
            hops += 1
        }
        return current
    }

    public func dict(_ object: PDFObject?) -> PDFDict? {
        guard let object else { return nil }
        return (try? resolve(object))?.dictValue
    }

    /// Page object references in page order.
    public func pageRefs() -> [(Int, Int)] {
        guard let root = rootRef, let catalog = try? object(root.0).dictValue, let pages = catalog["Pages"]?.refValue else { return [] }
        var result: [(Int, Int)] = []
        var visited = Set<Int>()
        func walk(_ ref: (Int, Int)) {
            guard !visited.contains(ref.0), let node = try? object(ref.0).dictValue else { return }
            visited.insert(ref.0)
            if node["Type"]?.nameValue == "Page" || node["Kids"] == nil {
                result.append(ref)
                return
            }
            for kid in node["Kids"].flatMap({ try? resolve($0).arrayValue }) ?? [] {
                if let kidRef = kid.refValue { walk(kidRef) }
            }
        }
        walk(pages)
        return result
    }
}

/// The stream filters Paper needs to read cross-reference and object streams.
public enum StreamFilters {
    public static func decode(_ data: Data, dict: PDFDict) throws -> Data {
        let filters: [String]
        switch dict["Filter"] {
        case .name(let name): filters = [name]
        case .array(let items): filters = items.compactMap(\.nameValue)
        default: filters = []
        }
        var result = data
        for filter in filters {
            guard filter == "FlateDecode" || filter == "Fl" else { throw PDFSyntaxError.unexpected("filter \(filter)", at: 0) }
            result = try inflate(result)
        }
        if let parms = dict["DecodeParms"]?.dictValue ?? dict["DecodeParms"]?.arrayValue?.first?.dictValue,
           let predictor = parms["Predictor"]?.intValue, predictor >= 10 {
            result = undoPNGPredictor(result, columns: parms["Columns"]?.intValue ?? 1, colors: parms["Colors"]?.intValue ?? 1,
                                      bits: parms["BitsPerComponent"]?.intValue ?? 8)
        }
        return result
    }

    /// zlib data (FlateDecode) to bytes. Foundation's zlib codec wants raw deflate, so the
    /// two-byte zlib header is skipped.
    public static func inflate(_ data: Data) throws -> Data {
        guard data.count > 2 else { return Data() }
        let body = data.subdata(in: (data.startIndex + 2)..<data.endIndex)
        guard let output = try? (body as NSData).decompressed(using: .zlib) as Data else {
            throw PDFSyntaxError.unexpected("deflate data", at: 0)
        }
        return output
    }

    /// zlib-wrapped deflate, for streams Paper writes.
    public static func deflate(_ data: Data) -> Data? {
        guard let raw = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }
        var out = Data([0x78, 0x9C])
        out.append(raw)
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = b << 16 | a
        out.append(contentsOf: [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)])
        return out
    }

    static func undoPNGPredictor(_ data: Data, columns: Int, colors: Int, bits: Int) -> Data {
        let bpp = max(1, colors * bits / 8)
        let rowLength = (columns * colors * bits + 7) / 8
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        var previous = [UInt8](repeating: 0, count: rowLength)
        var index = 0
        while index + rowLength < bytes.count + 1, index < bytes.count {
            let type = bytes[index]
            index += 1
            var row = Array(bytes[index..<min(index + rowLength, bytes.count)])
            if row.count < rowLength { row += [UInt8](repeating: 0, count: rowLength - row.count) }
            index += rowLength
            for i in 0..<rowLength {
                let left = i >= bpp ? Int(row[i - bpp]) : 0
                let up = Int(previous[i])
                let upLeft = i >= bpp ? Int(previous[i - bpp]) : 0
                let value: Int
                switch type {
                case 1: value = Int(row[i]) + left
                case 2: value = Int(row[i]) + up
                case 3: value = Int(row[i]) + (left + up) / 2
                case 4:
                    let p = left + up - upLeft
                    let pa = abs(p - left), pb = abs(p - up), pc = abs(p - upLeft)
                    value = Int(row[i]) + (pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft)
                default: value = Int(row[i])
                }
                row[i] = UInt8(value & 0xFF)
            }
            out += row
            previous = row
        }
        return Data(out)
    }
}

// MARK: Incremental updates

/// New versions of objects appended after a file's bytes, with their own cross-reference
/// section and trailer (`/Prev` points at the previous one).
public struct IncrementalUpdate {
    public let file: PDFFile
    private var nextNumber: Int
    private var objects: [(number: Int, generation: Int, object: PDFObject, stream: Data?)] = []

    public init(_ file: PDFFile) {
        self.file = file
        nextNumber = max(file.size, (file.entries.keys.max() ?? 0) + 1)
    }

    /// A new object; returns its reference.
    public mutating func add(_ object: PDFObject, stream: Data? = nil) -> PDFObject {
        let number = nextNumber
        nextNumber += 1
        objects.append((number, 0, object, stream))
        return .ref(number, 0)
    }

    /// A new version of an existing object.
    public mutating func replace(_ number: Int, with object: PDFObject, stream: Data? = nil) {
        let generation: Int
        if case .offset(_, let g) = file.entries[number] { generation = g } else { generation = 0 }
        objects.removeAll { $0.number == number }
        objects.append((number, generation, object, stream))
    }

    /// The pending version of an object, or the file's.
    public func current(_ number: Int) -> PDFObject? {
        if let pending = objects.last(where: { $0.number == number }) { return pending.object }
        return try? file.object(number)
    }

    public var isEmpty: Bool { objects.isEmpty }

    /// The original bytes followed by the update. `placeholder` marks bytes the caller will
    /// overwrite later (a signature's `/Contents`); its range in the output is returned.
    public func write(trailerExtras: [(String, PDFObject)] = []) -> Data {
        var out = file.data
        if out.last != 10 { out.append(10) }
        var offsets: [(number: Int, generation: Int, offset: Int)] = []
        for item in objects.sorted(by: { $0.number < $1.number }) {
            offsets.append((item.number, item.generation, out.count))
            out.append(contentsOf: Array("\(item.number) \(item.generation) obj\n".utf8))
            if let stream = item.stream, case .dict(var dict) = item.object {
                dict["Length"] = .int(stream.count)
                out.append(PDFWriter.serialize(.dict(dict)))
                out.append(contentsOf: Array("\nstream\n".utf8))
                out.append(stream)
                out.append(contentsOf: Array("\nendstream".utf8))
            } else {
                out.append(PDFWriter.serialize(item.object))
            }
            out.append(contentsOf: Array("\nendobj\n".utf8))
        }
        var trailer = PDFDict()
        trailer["Size"] = .int(nextNumber)
        if let root = file.trailer["Root"] { trailer["Root"] = root }
        if let info = file.trailer["Info"] { trailer["Info"] = info }
        if let id = file.trailer["ID"] { trailer["ID"] = id }
        for (key, value) in trailerExtras { trailer[key] = value }
        trailer["Prev"] = .int(file.startXref)
        let xrefOffset = out.count
        if file.usesXrefStream {
            // Rows: type (1 byte), offset (4 bytes), generation (2 bytes). Uncompressed.
            let number = nextNumber
            var rows = Data()
            var index: [PDFObject] = []
            let all = offsets + [(number, 0, xrefOffset)]
            for group in Self.runs(all.map(\.number)) {
                index += [.int(group.lowerBound), .int(group.count)]
                for n in group {
                    let entry = all.first { $0.number == n }!
                    rows.append(1)
                    rows.append(contentsOf: [UInt8(entry.offset >> 24 & 0xFF), UInt8(entry.offset >> 16 & 0xFF), UInt8(entry.offset >> 8 & 0xFF), UInt8(entry.offset & 0xFF)])
                    rows.append(contentsOf: [UInt8(entry.generation >> 8 & 0xFF), UInt8(entry.generation & 0xFF)])
                }
            }
            trailer["Size"] = .int(number + 1)
            trailer["Type"] = .name("XRef")
            trailer["W"] = .array([.int(1), .int(4), .int(2)])
            trailer["Index"] = .array(index)
            trailer["Length"] = .int(rows.count)
            out.append(contentsOf: Array("\(number) 0 obj\n".utf8))
            out.append(PDFWriter.serialize(.dict(trailer)))
            out.append(contentsOf: Array("\nstream\n".utf8))
            out.append(rows)
            out.append(contentsOf: Array("\nendstream\nendobj\n".utf8))
        } else {
            out.append(contentsOf: Array("xref\n".utf8))
            for group in Self.runs(offsets.map(\.number)) {
                out.append(contentsOf: Array("\(group.lowerBound) \(group.count)\n".utf8))
                for n in group {
                    let entry = offsets.first { $0.number == n }!
                    out.append(contentsOf: Array(String(format: "%010d %05d n \n", entry.offset, entry.generation).utf8))
                }
            }
            out.append(contentsOf: Array("trailer\n".utf8))
            out.append(PDFWriter.serialize(.dict(trailer)))
            out.append(10)
        }
        out.append(contentsOf: Array("startxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return out
    }

    /// Consecutive runs of sorted numbers, for cross-reference subsections.
    static func runs(_ numbers: [Int]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for number in numbers.sorted() {
            if let last = result.last, last.upperBound + 1 == number {
                result[result.count - 1] = last.lowerBound...number
            } else {
                result.append(number...number)
            }
        }
        return result
    }
}
