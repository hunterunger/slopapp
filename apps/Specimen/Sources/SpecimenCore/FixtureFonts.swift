import Foundation

/// Test fonts with new names: a copy of the OFL fixture (Silkscreen) whose `name` table says
/// another family, style and PostScript name. Unit tests and `specimen-fixture library` use
/// it to make many distinct fonts (a big library, project folders, duplicates) without
/// copying anyone's fonts. The copies are made at test time and never committed.
public enum FixtureFonts {
    public enum Failure: Error { case notAFont }

    /// `data` with its naming replaced. Other names (copyright, licence) are kept.
    public static func renamed(_ data: Data, family: String, style: String = "Regular", postScriptName: String? = nil) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 12 else { throw Failure.notAFont }
        let count = Int(read16(bytes, 4))
        guard bytes.count >= 12 + count * 16 else { throw Failure.notAFont }
        var tables: [(tag: UInt32, data: [UInt8])] = []
        for index in 0..<count {
            let record = 12 + index * 16
            let tag = read32(bytes, record), offset = Int(read32(bytes, record + 8)), length = Int(read32(bytes, record + 12))
            guard offset + length <= bytes.count else { throw Failure.notAFont }
            tables.append((tag, Array(bytes[offset..<offset + length])))
        }
        let nameTag = tagValue("name")
        let postScript = postScriptName ?? (family + "-" + style).filter { !$0.isWhitespace }
        let kept = tables.first { $0.tag == nameTag }.map { keptNames($0.data) } ?? []
        let full = style == "Regular" ? family : "\(family) \(style)"
        let names: [(UInt16, String)] = [(1, family), (2, style), (3, "Specimen test: \(postScript)"), (4, full), (6, postScript), (16, family), (17, style)]
        let table = nameTable(names, kept: kept)
        if let index = tables.firstIndex(where: { $0.tag == nameTag }) { tables[index].data = table } else { tables.append((nameTag, table)) }
        return Data(assemble(sfntVersion: read32(bytes, 0), tables: tables))
    }

    /// Writes `count` renamed copies of `source` into `folder`: "<prefix> 1.ttf" … (family
    /// "<prefix> 1" …). Returns the files.
    @discardableResult
    public static func makeLibrary(from source: URL, into folder: URL, prefix: String, count: Int, style: String = "Regular") throws -> [URL] {
        let data = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try (1...max(count, 1)).map { number in
            let family = "\(prefix) \(number)"
            let url = folder.appendingPathComponent("\(family) \(style).ttf")
            try renamed(data, family: family, style: style).write(to: url)
            return url
        }
    }

    // MARK: sfnt plumbing

    static func tagValue(_ tag: String) -> UInt32 { tag.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    static func read16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i + 1]) }
    static func read32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }
    static func append16(_ b: inout [UInt8], _ v: UInt16) { b += [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func append32(_ b: inout [UInt8], _ v: UInt32) { b += [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    struct NameRecord {
        var platform: UInt16, encoding: UInt16, language: UInt16, nameID: UInt16
        var string: [UInt8]
    }

    /// Records from the old table other than the ones we replace.
    static func keptNames(_ table: [UInt8]) -> [NameRecord] {
        guard table.count >= 6 else { return [] }
        let count = Int(read16(table, 2)), storage = Int(read16(table, 4))
        let replaced: Set<UInt16> = [1, 2, 3, 4, 6, 16, 17]
        var result: [NameRecord] = []
        for index in 0..<count {
            let r = 6 + index * 12
            guard r + 12 <= table.count else { break }
            let nameID = read16(table, r + 6), length = Int(read16(table, r + 8)), offset = Int(read16(table, r + 10))
            guard !replaced.contains(nameID), storage + offset + length <= table.count else { continue }
            result.append(NameRecord(platform: read16(table, r), encoding: read16(table, r + 2), language: read16(table, r + 4),
                                     nameID: nameID, string: Array(table[(storage + offset)..<(storage + offset + length)])))
        }
        return result
    }

    static func nameTable(_ names: [(UInt16, String)], kept: [NameRecord]) -> [UInt8] {
        var records = kept
        for (id, value) in names {
            records.append(NameRecord(platform: 1, encoding: 0, language: 0, nameID: id, string: Array(value.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : 0x3F })))
            records.append(NameRecord(platform: 3, encoding: 1, language: 0x409, nameID: id, string: value.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }))
        }
        records.sort { ($0.platform, $0.encoding, $0.language, $0.nameID) < ($1.platform, $1.encoding, $1.language, $1.nameID) }
        var header: [UInt8] = [], storage: [UInt8] = []
        append16(&header, 0)
        append16(&header, UInt16(records.count))
        append16(&header, UInt16(6 + records.count * 12))
        for record in records {
            for value in [record.platform, record.encoding, record.language, record.nameID, UInt16(record.string.count), UInt16(storage.count)] {
                append16(&header, value)
            }
            storage += record.string
        }
        return header + storage
    }

    static func checksum(_ data: [UInt8]) -> UInt32 {
        var sum: UInt32 = 0
        var index = 0
        while index < data.count {
            var word: UInt32 = 0
            for byte in 0..<4 { word = word << 8 | UInt32(index + byte < data.count ? data[index + byte] : 0) }
            sum = sum &+ word
            index += 4
        }
        return sum
    }

    static func assemble(sfntVersion: UInt32, tables unsorted: [(tag: UInt32, data: [UInt8])]) -> [UInt8] {
        var tables = unsorted.sorted { $0.tag < $1.tag }
        let headTag = tagValue("head")
        // checkSumAdjustment is zero while summing.
        if let head = tables.firstIndex(where: { $0.tag == headTag }), tables[head].data.count >= 12 {
            tables[head].data.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        }
        let count = tables.count
        var power = 1, exponent = 0
        while power * 2 <= count { power *= 2; exponent += 1 }
        var out: [UInt8] = []
        append32(&out, sfntVersion)
        append16(&out, UInt16(count))
        append16(&out, UInt16(power * 16))
        append16(&out, UInt16(exponent))
        append16(&out, UInt16(count * 16 - power * 16))
        var offset = 12 + count * 16
        var body: [UInt8] = []
        var headOffset: Int?
        for table in tables {
            append32(&out, table.tag)
            append32(&out, checksum(table.data))
            append32(&out, UInt32(offset))
            append32(&out, UInt32(table.data.count))
            if table.tag == headTag { headOffset = offset }
            var padded = table.data
            while padded.count % 4 != 0 { padded.append(0) }
            body += padded
            offset += padded.count
        }
        out += body
        if let headOffset, headOffset + 12 <= out.count {
            let adjustment = 0xB1B0_AFBA &- checksum(out)
            out.replaceSubrange((headOffset + 8)..<(headOffset + 12), with: [UInt8(adjustment >> 24), UInt8(adjustment >> 16 & 0xFF), UInt8(adjustment >> 8 & 0xFF), UInt8(adjustment & 0xFF)])
        }
        return out
    }
}
