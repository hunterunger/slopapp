import Foundation

/// Property IDs from 7-Zip's `7zFormat.txt`.
enum SevenZipID {
    static let end: UInt8 = 0x00
    static let header: UInt8 = 0x01
    static let archiveProperties: UInt8 = 0x02
    static let additionalStreamsInfo: UInt8 = 0x03
    static let mainStreamsInfo: UInt8 = 0x04
    static let filesInfo: UInt8 = 0x05
    static let packInfo: UInt8 = 0x06
    static let unpackInfo: UInt8 = 0x07
    static let subStreamsInfo: UInt8 = 0x08
    static let size: UInt8 = 0x09
    static let crc: UInt8 = 0x0A
    static let folder: UInt8 = 0x0B
    static let codersUnpackSize: UInt8 = 0x0C
    static let numUnpackStream: UInt8 = 0x0D
    static let encodedHeader: UInt8 = 0x17
}

/// Method IDs Crate cares about.
enum SevenZipMethod {
    static let copy: [UInt8] = [0x00]
    static let aes: [UInt8] = [0x06, 0xF1, 0x07, 0x01]
    static let lzma: [UInt8] = [0x03, 0x01, 0x01]
    static let lzma2: [UInt8] = [0x21]
}

struct SevenZipCoder: Equatable {
    var method: [UInt8]
    /// Streams on the packed side (only BCJ2 has more than one).
    var inStreams: Int = 1
    /// Streams on the unpacked side.
    var outStreams: Int = 1
    var properties: [UInt8] = []

    var isAES: Bool { method == SevenZipMethod.aes }
    var isSimple: Bool { inStreams == 1 && outStreams == 1 }
}

struct SevenZipBindPair: Equatable {
    /// A coder's packed-side stream…
    var inIndex: Int
    /// …fed by another coder's unpacked-side stream.
    var outIndex: Int
}

/// A folder: a chain of coders that turns packed streams into one unpacked stream.
struct SevenZipFolder: Equatable {
    var coders: [SevenZipCoder]
    var bindPairs: [SevenZipBindPair]
    /// In-stream indices that read packed streams, in pack-stream order.
    var packedStreams: [Int]
    /// One per out stream.
    var unpackSizes: [UInt64] = []
    /// CRC of the final unpacked stream, if recorded.
    var crc: UInt32?

    var totalInStreams: Int { coders.reduce(0) { $0 + $1.inStreams } }
    var totalOutStreams: Int { coders.reduce(0) { $0 + $1.outStreams } }

    func inStart(of coder: Int) -> Int { coders[0..<coder].reduce(0) { $0 + $1.inStreams } }
    func outStart(of coder: Int) -> Int { coders[0..<coder].reduce(0) { $0 + $1.outStreams } }

    /// The out stream nothing else reads: the folder's result.
    var finalOutIndex: Int? {
        (0..<totalOutStreams).first { index in !bindPairs.contains { $0.outIndex == index } }
    }

    var unpackSize: UInt64 {
        guard let index = finalOutIndex, index < unpackSizes.count else { return 0 }
        return unpackSizes[index]
    }

    /// The coder that owns in-stream `index`.
    func coder(forInStream index: Int) -> Int? {
        var start = 0
        for (offset, coder) in coders.enumerated() {
            if index < start + coder.inStreams { return offset }
            start += coder.inStreams
        }
        return nil
    }

    /// For simple chains (every coder 1 in, 1 out, one packed stream): coder indices from
    /// the packed side to the result.
    func linearChain() throws -> [Int] {
        guard coders.allSatisfy(\.isSimple), packedStreams.count == 1 else {
            throw SevenZipError.unsupported("complex coder chain")
        }
        var chain = [packedStreams[0]]
        while let pair = bindPairs.first(where: { $0.outIndex == chain.last! }) {
            guard !chain.contains(pair.inIndex), chain.count <= coders.count else { throw SevenZipError.malformed("coder loop") }
            chain.append(pair.inIndex)
        }
        guard chain.count == coders.count else { throw SevenZipError.malformed("coder chain") }
        return chain
    }

    /// Removes a 1-in/1-out coder that reads packed stream `slot`, so the next coder reads
    /// that stream directly. A coder whose output is the result becomes Copy instead.
    mutating func removePackedSideCoder(_ index: Int) throws {
        guard coders[index].isSimple else { throw SevenZipError.unsupported("complex encryption coder") }
        let inIndex = inStart(of: index)
        let outIndex = outStart(of: index)
        guard let slot = packedStreams.firstIndex(of: inIndex) else {
            throw SevenZipError.unsupported("encryption inside the coder chain")
        }
        guard let pairIndex = bindPairs.firstIndex(where: { $0.outIndex == outIndex }) else {
            coders[index] = SevenZipCoder(method: SevenZipMethod.copy)
            return
        }
        let target = bindPairs[pairIndex].inIndex
        bindPairs.remove(at: pairIndex)
        packedStreams[slot] = target
        coders.remove(at: index)
        if outIndex < unpackSizes.count { unpackSizes.remove(at: outIndex) }
        bindPairs = bindPairs.map {
            SevenZipBindPair(inIndex: $0.inIndex > inIndex ? $0.inIndex - 1 : $0.inIndex,
                             outIndex: $0.outIndex > outIndex ? $0.outIndex - 1 : $0.outIndex)
        }
        packedStreams = packedStreams.map { $0 > inIndex ? $0 - 1 : $0 }
    }

    /// Puts `coder` in front of a folder with one packed stream (7-Zip's layout for AES:
    /// first coder, reading the packed stream, feeding the old first coder).
    mutating func insertPackedSideCoder(_ coder: SevenZipCoder, packedSize: UInt64) throws {
        guard packedStreams.count == 1, coder.isSimple else { throw SevenZipError.unsupported("several packed streams") }
        let oldPacked = packedStreams[0]
        bindPairs = bindPairs.map { SevenZipBindPair(inIndex: $0.inIndex + 1, outIndex: $0.outIndex + 1) }
        bindPairs.append(SevenZipBindPair(inIndex: oldPacked + 1, outIndex: 0))
        coders.insert(coder, at: 0)
        packedStreams = [0]
        unpackSizes.insert(packedSize, at: 0)
    }

    // MARK: Encoding

    static func parse(_ reader: inout SevenZipReader) throws -> SevenZipFolder {
        let coderCount = try reader.count(max: 64)
        guard coderCount > 0 else { throw SevenZipError.malformed("folder without coders") }
        var coders: [SevenZipCoder] = []
        for _ in 0..<coderCount {
            let flags = try reader.byte()
            guard flags & 0xC0 == 0 else { throw SevenZipError.unsupported("alternative coder methods") }
            var coder = SevenZipCoder(method: try reader.take(Int(flags & 0x0F)))
            if flags & 0x10 != 0 {
                coder.inStreams = try reader.count(max: 64)
                coder.outStreams = try reader.count(max: 64)
            }
            if flags & 0x20 != 0 {
                coder.properties = try reader.take(try reader.count(max: 1 << 16))
            }
            coders.append(coder)
        }
        var folder = SevenZipFolder(coders: coders, bindPairs: [], packedStreams: [])
        let totalOut = folder.totalOutStreams
        let totalIn = folder.totalInStreams
        guard totalOut >= 1, totalIn >= totalOut - 1 else { throw SevenZipError.malformed("stream counts") }
        for _ in 0..<(totalOut - 1) {
            let pair = SevenZipBindPair(inIndex: try reader.count(max: 255), outIndex: try reader.count(max: 255))
            guard pair.inIndex < totalIn, pair.outIndex < totalOut else { throw SevenZipError.malformed("bind pair") }
            folder.bindPairs.append(pair)
        }
        let packedCount = totalIn - (totalOut - 1)
        if packedCount == 1 {
            guard let free = (0..<totalIn).first(where: { index in !folder.bindPairs.contains { $0.inIndex == index } }) else {
                throw SevenZipError.malformed("no packed stream")
            }
            folder.packedStreams = [free]
        } else {
            for _ in 0..<packedCount {
                let index = try reader.count(max: 255)
                guard index < totalIn else { throw SevenZipError.malformed("packed stream") }
                folder.packedStreams.append(index)
            }
        }
        return folder
    }

    func write(to writer: inout SevenZipWriter) {
        writer.number(coders.count)
        for coder in coders {
            var flags = UInt8(coder.method.count)
            if !coder.isSimple { flags |= 0x10 }
            if !coder.properties.isEmpty { flags |= 0x20 }
            writer.byte(flags)
            writer.append(coder.method)
            if !coder.isSimple {
                writer.number(coder.inStreams)
                writer.number(coder.outStreams)
            }
            if !coder.properties.isEmpty {
                writer.number(coder.properties.count)
                writer.append(coder.properties)
            }
        }
        for pair in bindPairs {
            writer.number(pair.inIndex)
            writer.number(pair.outIndex)
        }
        if packedStreams.count > 1 {
            for index in packedStreams { writer.number(index) }
        }
    }
}

/// PackInfo + UnpackInfo (folders) + SubStreamsInfo.
struct SevenZipStreams: Equatable {
    /// Where the first packed stream starts, after the 32-byte signature header.
    var packPosition: UInt64 = 0
    var packSizes: [UInt64] = []
    var folders: [SevenZipFolder] = []
    /// SubStreamsInfo, kept byte for byte (it describes unpacked data, which never changes).
    var subStreams: [UInt8]?

    static func parse(_ reader: inout SevenZipReader) throws -> SevenZipStreams {
        var streams = SevenZipStreams()
        while true {
            let id = try reader.byte()
            switch id {
            case SevenZipID.end:
                return streams
            case SevenZipID.packInfo:
                streams.packPosition = try reader.number()
                let count = try reader.count()
                while true {
                    let property = try reader.byte()
                    if property == SevenZipID.end { break }
                    if property == SevenZipID.size {
                        streams.packSizes = try (0..<count).map { _ in try reader.number() }
                    } else if property == SevenZipID.crc {
                        _ = try reader.digests(count) // Recomputed by nobody; dropped on rewrite.
                    } else {
                        try reader.skip(try reader.number())
                    }
                }
                guard streams.packSizes.count == count else { throw SevenZipError.malformed("pack sizes") }
            case SevenZipID.unpackInfo:
                guard try reader.byte() == SevenZipID.folder else { throw SevenZipError.malformed("expected folders") }
                let count = try reader.count(max: 1 << 20)
                guard try reader.byte() == 0 else { throw SevenZipError.unsupported("external folders") }
                streams.folders = try (0..<count).map { _ in try SevenZipFolder.parse(&reader) }
                guard try reader.byte() == SevenZipID.codersUnpackSize else { throw SevenZipError.malformed("expected sizes") }
                for index in streams.folders.indices {
                    streams.folders[index].unpackSizes = try (0..<streams.folders[index].totalOutStreams).map { _ in try reader.number() }
                }
                while true {
                    let property = try reader.byte()
                    if property == SevenZipID.end { break }
                    if property == SevenZipID.crc {
                        let digests = try reader.digests(count)
                        for index in streams.folders.indices { streams.folders[index].crc = digests[index] }
                    } else {
                        try reader.skip(try reader.number())
                    }
                }
            case SevenZipID.subStreamsInfo:
                let start = reader.offset - 1
                try skipSubStreams(&reader, folders: streams.folders)
                streams.subStreams = Array(reader.bytes[start..<reader.offset])
            default:
                throw SevenZipError.malformed("unknown streams property \(id)")
            }
        }
    }

    /// Walks SubStreamsInfo to find where it ends.
    private static func skipSubStreams(_ reader: inout SevenZipReader, folders: [SevenZipFolder]) throws {
        var counts = Array(repeating: 1, count: folders.count)
        while true {
            let id = try reader.byte()
            switch id {
            case SevenZipID.end:
                return
            case SevenZipID.numUnpackStream:
                counts = try folders.map { _ in try reader.count() }
            case SevenZipID.size:
                for count in counts where count > 1 {
                    for _ in 0..<(count - 1) { _ = try reader.number() }
                }
            case SevenZipID.crc:
                let needed = zip(counts, folders).reduce(0) { total, pair in
                    total + (pair.0 == 1 && pair.1.crc != nil ? 0 : pair.0)
                }
                _ = try reader.digests(needed)
            default:
                try reader.skip(try reader.number())
            }
        }
    }

    func write(to writer: inout SevenZipWriter) {
        if !packSizes.isEmpty {
            writer.byte(SevenZipID.packInfo)
            writer.number(packPosition)
            writer.number(packSizes.count)
            writer.byte(SevenZipID.size)
            packSizes.forEach { writer.number($0) }
            writer.byte(SevenZipID.end)
        }
        if !folders.isEmpty {
            writer.byte(SevenZipID.unpackInfo)
            writer.byte(SevenZipID.folder)
            writer.number(folders.count)
            writer.byte(0)
            folders.forEach { $0.write(to: &writer) }
            writer.byte(SevenZipID.codersUnpackSize)
            folders.forEach { $0.unpackSizes.forEach { writer.number($0) } }
            if folders.contains(where: { $0.crc != nil }) {
                writer.byte(SevenZipID.crc)
                writer.digests(folders.map(\.crc))
            }
            writer.byte(SevenZipID.end)
        }
        if let subStreams { writer.append(subStreams) }
        writer.byte(SevenZipID.end)
    }
}

/// A decoded (plain) 7z header. Only the stream layout is parsed; the file list is kept
/// byte for byte.
struct SevenZipHeader: Equatable {
    var archiveProperties: [UInt8]?
    var main: SevenZipStreams?
    /// FilesInfo and the final kEnd.
    var tail: [UInt8]

    static func parse(_ bytes: [UInt8]) throws -> SevenZipHeader {
        var reader = SevenZipReader(bytes)
        guard try reader.byte() == SevenZipID.header else { throw SevenZipError.malformed("not a header") }
        var id = try reader.byte()
        var properties: [UInt8]?
        if id == SevenZipID.archiveProperties {
            let start = reader.offset - 1
            while try reader.byte() != 0 { try reader.skip(try reader.number()) }
            properties = Array(bytes[start..<reader.offset])
            id = try reader.byte()
        }
        if id == SevenZipID.additionalStreamsInfo { throw SevenZipError.unsupported("additional streams") }
        var main: SevenZipStreams?
        if id == SevenZipID.mainStreamsInfo {
            main = try SevenZipStreams.parse(&reader)
            id = try reader.byte()
        }
        guard id == SevenZipID.filesInfo || id == SevenZipID.end else { throw SevenZipError.malformed("header property \(id)") }
        return SevenZipHeader(archiveProperties: properties, main: main, tail: Array(bytes[(reader.offset - 1)...]))
    }

    func encoded() -> [UInt8] {
        var writer = SevenZipWriter()
        writer.byte(SevenZipID.header)
        if let archiveProperties { writer.append(archiveProperties) }
        if let main {
            writer.byte(SevenZipID.mainStreamsInfo)
            main.write(to: &writer)
        }
        writer.append(tail)
        return writer.bytes
    }

    var hasEncryptedData: Bool {
        main?.folders.contains { $0.coders.contains(where: \.isAES) } ?? false
    }
}

/// The 32-byte signature header at the start of every 7z file.
struct SevenZipSignature {
    static let magic: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
    static let size = 32

    var nextHeaderOffset: UInt64
    var nextHeaderSize: UInt64
    var nextHeaderCRC: UInt32

    static func parse(_ bytes: [UInt8]) throws -> SevenZipSignature {
        guard bytes.count >= size, Array(bytes[0..<6]) == magic else { throw SevenZipError.notSevenZip }
        var reader = SevenZipReader(bytes, offset: 8)
        let startCRC = try reader.uint32()
        guard CRC32.checksum(bytes[12..<32]) == startCRC else { throw SevenZipError.malformed("start header CRC") }
        return SevenZipSignature(nextHeaderOffset: try reader.uint64(), nextHeaderSize: try reader.uint64(),
                                 nextHeaderCRC: try reader.uint32())
    }

    func encoded() -> [UInt8] {
        var tail = SevenZipWriter()
        tail.uint64(nextHeaderOffset)
        tail.uint64(nextHeaderSize)
        tail.uint32(nextHeaderCRC)
        var writer = SevenZipWriter()
        writer.append(Self.magic)
        writer.append([0x00, 0x04])
        writer.uint32(CRC32.checksum(tail.bytes))
        writer.append(tail.bytes)
        return writer.bytes
    }
}
