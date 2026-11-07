import CLZMA
import Darwin
import Foundation

/// Random access over an archive's parts as if they were one file (`.7z.001`, `.002`…).
final class PartsReader: @unchecked Sendable {
    private struct Part {
        let fd: Int32
        let start: Int64
        let size: Int64
    }

    private let parts: [Part]
    let size: Int64

    init(_ urls: [URL]) throws {
        var parts: [Part] = []
        var start: Int64 = 0
        for url in urls {
            let fd = url.withUnsafeFileSystemRepresentation { open($0!, O_RDONLY) }
            guard fd >= 0 else {
                parts.forEach { close($0.fd) }
                throw SevenZipError.io("can't open \(url.lastPathComponent)")
            }
            var info = stat()
            fstat(fd, &info)
            parts.append(Part(fd: fd, start: start, size: Int64(info.st_size)))
            start += Int64(info.st_size)
        }
        self.parts = parts
        size = start
    }

    deinit { parts.forEach { close($0.fd) } }

    /// Reads up to `count` bytes at `offset`; fewer only at the end.
    func read(at offset: Int64, count: Int, into buffer: UnsafeMutableRawPointer) throws -> Int {
        var done = 0
        var position = offset
        while done < count, position < size {
            guard let part = parts.last(where: { $0.start <= position }) else { break }
            let within = position - part.start
            let wanted = min(count - done, Int(part.size - within))
            if wanted <= 0 { break }
            let got = pread(part.fd, buffer + done, wanted, off_t(within))
            if got < 0 { throw SevenZipError.io(String(cString: strerror(errno))) }
            if got == 0 { break }
            done += got
            position += Int64(got)
        }
        return done
    }

    /// Exactly `count` bytes, or `truncated`.
    func bytes(at offset: Int64, count: Int) throws -> [UInt8] {
        guard count >= 0 else { throw SevenZipError.malformed("negative size") }
        var result = [UInt8](repeating: 0, count: count)
        let got = try result.withUnsafeMutableBytes { try read(at: offset, count: count, into: $0.baseAddress!) }
        guard got == count else { throw SevenZipError.malformed("ends early") }
        return result
    }
}

/// A 7z archive's structure, read without libarchive (which can't decrypt): the signature,
/// the header (decoded and, given the password, decrypted), and whether data is encrypted.
struct SevenZipArchive {
    let reader: PartsReader
    let header: SevenZipHeader
    /// The header itself was encrypted (file names hidden without the password).
    let headerEncrypted: Bool

    /// Headers larger than this are refused (a hostile header can't eat memory).
    static let maxHeaderSize: UInt64 = 256 << 20

    var dataEncrypted: Bool { header.hasEncryptedData }
    var isEncrypted: Bool { headerEncrypted || dataEncrypted }

    /// True when `url` starts with 7z's signature.
    static func isSevenZip(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 6)) ?? Data()
        return Array(data) == SevenZipSignature.magic
    }

    /// Reads the structure. Without a password, an encrypted header throws
    /// `passwordRequired`; with the wrong one, `wrongPassword`.
    static func open(_ reader: PartsReader, password: String?) throws -> SevenZipArchive {
        let signature = try SevenZipSignature.parse(try reader.bytes(at: 0, count: SevenZipSignature.size))
        guard signature.nextHeaderSize > 0 else {
            // An empty archive: no header at all.
            return SevenZipArchive(reader: reader, header: SevenZipHeader(archiveProperties: nil, main: nil, tail: [SevenZipID.end]),
                                   headerEncrypted: false)
        }
        guard signature.nextHeaderSize <= maxHeaderSize else { throw SevenZipError.unsupported("huge header") }
        let (start, overflow) = UInt64(SevenZipSignature.size).addingReportingOverflow(signature.nextHeaderOffset)
        guard !overflow, start + signature.nextHeaderSize <= UInt64(reader.size) else { throw SevenZipError.malformed("ends early") }
        let raw = try reader.bytes(at: Int64(start), count: Int(signature.nextHeaderSize))
        guard CRC32.checksum(raw) == signature.nextHeaderCRC else { throw SevenZipError.malformed("header CRC") }

        guard raw.first == SevenZipID.encodedHeader else {
            return SevenZipArchive(reader: reader, header: try SevenZipHeader.parse(raw), headerEncrypted: false)
        }
        var headerReader = SevenZipReader(raw, offset: 1)
        let streams = try SevenZipStreams.parse(&headerReader)
        guard streams.folders.count == 1, let folder = streams.folders.first, streams.packSizes.count == folder.packedStreams.count else {
            throw SevenZipError.unsupported("header layout")
        }
        let encrypted = folder.coders.contains(where: \.isAES)
        if encrypted, password?.isEmpty != false { throw SevenZipError.passwordRequired }
        let packed = try reader.bytes(at: Int64(SevenZipSignature.size) + Int64(streams.packPosition),
                                      count: Int(streams.packSizes[0]))
        let decoded: [UInt8]
        do {
            decoded = try SevenZipDecoder.decode(folder, packed: packed, password: password, limit: maxHeaderSize)
        } catch let error as SevenZipError {
            switch error {
            case .unsupported, .passwordRequired, .io: throw error
            default: throw encrypted ? SevenZipError.wrongPassword : error
            }
        }
        if let crc = folder.crc, CRC32.checksum(decoded) != crc {
            throw encrypted ? SevenZipError.wrongPassword : SevenZipError.malformed("header CRC")
        }
        do {
            return SevenZipArchive(reader: reader, header: try SevenZipHeader.parse(decoded), headerEncrypted: encrypted)
        } catch let error as SevenZipError {
            if encrypted, folder.crc == nil, case .malformed = error { throw SevenZipError.wrongPassword }
            throw error
        }
    }

    /// Where pack stream `index` of the main streams starts in the (joined) file.
    func packOffsets() -> [Int64] {
        guard let main = header.main else { return [] }
        var offset = Int64(SevenZipSignature.size) + Int64(main.packPosition)
        return main.packSizes.map { size in
            defer { offset += Int64(size) }
            return offset
        }
    }
}

/// Decodes small streams in memory (headers, and the first bytes of data to check a
/// password): AES, Copy, and LZMA/LZMA2/BCJ/Delta through the system liblzma.
enum SevenZipDecoder {
    static func decode(_ folder: SevenZipFolder, packed: [UInt8], password: String?, limit: UInt64) throws -> [UInt8] {
        let chain = try folder.linearChain()
        var data = packed
        var pending: [(coder: SevenZipCoder, outIndex: Int)] = []

        func flush() throws {
            guard let last = pending.last else { return }
            let size = folder.unpackSizes[last.outIndex]
            guard size <= limit else { throw SevenZipError.unsupported("huge header") }
            // liblzma wants filters in encoding order: the packed side last.
            data = try lzma(data, filters: pending.reversed().map(\.coder), outputSize: Int(size), partial: false)
            pending = []
        }

        for index in chain {
            let coder = folder.coders[index]
            let outIndex = folder.outStart(of: index)
            guard outIndex < folder.unpackSizes.count else { throw SevenZipError.malformed("sizes") }
            let size = folder.unpackSizes[outIndex]
            switch coder.method {
            case SevenZipMethod.aes:
                try flush()
                guard let password, !password.isEmpty else { throw SevenZipError.passwordRequired }
                let properties = try SevenZipAESProperties(decoding: coder.properties)
                let key = SevenZipKey.derive(password: password, properties: properties)
                let whole = data.count - data.count % 16
                data = try AESCBC.decrypt(key: key, iv: properties.iv, Array(data.prefix(whole)))
                guard UInt64(data.count) >= size else { throw SevenZipError.malformed("short encrypted stream") }
                data = Array(data.prefix(Int(size)))
            case SevenZipMethod.copy:
                try flush()
                guard UInt64(data.count) >= size else { throw SevenZipError.malformed("short stream") }
                data = Array(data.prefix(Int(size)))
            default:
                guard lzmaFilterID(coder.method) != nil else { throw SevenZipError.unsupported("header method") }
                pending.append((coder, outIndex))
            }
        }
        try flush()
        return data
    }

    static func lzmaFilterID(_ method: [UInt8]) -> UInt64? {
        switch method {
        case SevenZipMethod.lzma: LZMA_FILTER_LZMA1
        case SevenZipMethod.lzma2: LZMA_FILTER_LZMA2
        case [0x03]: LZMA_FILTER_DELTA
        case [0x03, 0x03, 0x01, 0x03], [0x04]: LZMA_FILTER_X86
        case [0x03, 0x03, 0x02, 0x05]: LZMA_FILTER_POWERPC
        case [0x03, 0x03, 0x04, 0x01]: LZMA_FILTER_IA64
        case [0x03, 0x03, 0x05, 0x01]: LZMA_FILTER_ARM
        case [0x03, 0x03, 0x07, 0x01]: LZMA_FILTER_ARMTHUMB
        case [0x03, 0x03, 0x08, 0x05]: LZMA_FILTER_SPARC
        default: nil
        }
    }

    /// Raw liblzma decoding. `partial`: the input may stop early (password checks); returns
    /// what decoded cleanly, throwing only on invalid data.
    static func lzma(_ input: [UInt8], filters coders: [SevenZipCoder], outputSize: Int, partial: Bool) throws -> [UInt8] {
        var filters: [lzma_filter] = []
        defer { filters.forEach { free($0.options) } }
        for coder in coders {
            guard let id = lzmaFilterID(coder.method) else { throw SevenZipError.unsupported("method") }
            var filter = lzma_filter(id: id, options: nil)
            let status = coder.properties.withUnsafeBufferPointer {
                lzma_properties_decode(&filter, nil, $0.baseAddress, $0.count)
            }
            guard status == LZMA_OK else { throw SevenZipError.malformed("coder properties") }
            filters.append(filter)
        }
        filters.append(lzma_filter(id: LZMA_VLI_UNKNOWN, options: nil))
        var stream = lzma_stream()
        guard lzma_raw_decoder(&stream, filters) == LZMA_OK else { throw SevenZipError.unsupported("decoder") }
        defer { lzma_end(&stream) }
        var output = [UInt8](repeating: 0, count: outputSize)
        let produced: Int = try input.withUnsafeBufferPointer { inBuffer in
            try output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = inBuffer.count
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = outBuffer.count
                while stream.avail_out > 0 {
                    let before = (stream.avail_in, stream.avail_out)
                    let status = lzma_code(&stream, partial ? LZMA_RUN : LZMA_FINISH)
                    if status == LZMA_STREAM_END { break }
                    if status == LZMA_BUF_ERROR || (status == LZMA_OK && before == (stream.avail_in, stream.avail_out)) {
                        if partial { break }
                        throw SevenZipError.malformed("compressed data ends early")
                    }
                    guard status == LZMA_OK else { throw SevenZipError.malformed("compressed data is invalid") }
                    if partial, stream.avail_in == 0 { break }
                }
                return outBuffer.count - stream.avail_out
            }
        }
        if !partial, produced != outputSize { throw SevenZipError.malformed("compressed data ends early") }
        return Array(output.prefix(produced))
    }
}
