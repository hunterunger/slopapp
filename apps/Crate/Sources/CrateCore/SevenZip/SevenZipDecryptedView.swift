import Foundation

/// An encrypted 7z archive presented as the same archive without encryption, decrypted on
/// the fly as it's read. Nothing decrypted is written to disk: libarchive reads this view
/// (through callbacks) and does the decompression, listing and safe extraction as usual.
///
/// The view is: a new signature header, the packed streams (AES removed, everything else
/// byte for byte), and a rewritten plain header without the AES coders.
final class SevenZipDecryptedView: @unchecked Sendable {
    private enum Source {
        case memory([UInt8])
        case plain(offset: Int64)
        /// AES-256-CBC data at `offset` (`cipherLength` bytes, whole blocks).
        case decrypted(offset: Int64, cipherLength: Int64, key: [UInt8], iv: [UInt8])
    }

    private struct Piece {
        let start: Int64
        let length: Int64
        let source: Source
    }

    private let reader: PartsReader
    private let pieces: [Piece]
    let size: Int64

    /// Builds the view, checking the password: against the header's CRC when the header is
    /// encrypted, and by test-decoding the start of each encrypted stream.
    init(archive: SevenZipArchive, password: String) throws {
        reader = archive.reader
        var header = archive.header
        var sources: [Source] = []
        var lengths: [Int64] = []
        if var main = header.main {
            let offsets = archive.packOffsets()
            guard offsets.count == main.packSizes.count else { throw SevenZipError.malformed("pack streams") }
            sources = offsets.map { .plain(offset: $0) }
            lengths = main.packSizes.map { Int64($0) }
            var firstPack = 0
            for folderIndex in main.folders.indices {
                var folder = main.folders[folderIndex]
                let packCount = folder.packedStreams.count
                guard firstPack + packCount <= offsets.count else { throw SevenZipError.malformed("pack streams") }
                while let aesIndex = folder.coders.firstIndex(where: \.isAES) {
                    let inIndex = folder.inStart(of: aesIndex)
                    let outIndex = folder.outStart(of: aesIndex)
                    guard let slot = folder.packedStreams.firstIndex(of: inIndex), outIndex < folder.unpackSizes.count else {
                        throw SevenZipError.unsupported("encryption inside the coder chain")
                    }
                    let pack = firstPack + slot
                    let cipherLength = lengths[pack]
                    let plainLength = Int64(folder.unpackSizes[outIndex])
                    guard cipherLength % 16 == 0, plainLength <= cipherLength, case .plain(let offset) = sources[pack] else {
                        throw SevenZipError.malformed("encrypted stream size")
                    }
                    let properties = try SevenZipAESProperties(decoding: folder.coders[aesIndex].properties)
                    let key = SevenZipKey.derive(password: password, properties: properties)
                    sources[pack] = .decrypted(offset: offset, cipherLength: cipherLength, key: key, iv: properties.iv)
                    lengths[pack] = plainLength
                    try folder.removePackedSideCoder(aesIndex)
                    try Self.checkPassword(folder: folder, slot: slot, reader: reader, offset: offset,
                                           cipherLength: cipherLength, plainLength: plainLength, key: key, iv: properties.iv)
                }
                main.folders[folderIndex] = folder
                firstPack += packCount
            }
            main.packPosition = 0
            main.packSizes = lengths.map { UInt64($0) }
            header.main = main
        }
        let headerBytes = header.encoded()
        let packTotal = lengths.reduce(0, +)
        let signature = SevenZipSignature(nextHeaderOffset: UInt64(packTotal), nextHeaderSize: UInt64(headerBytes.count),
                                          nextHeaderCRC: CRC32.checksum(headerBytes))
        var pieces = [Piece(start: 0, length: Int64(SevenZipSignature.size), source: .memory(signature.encoded()))]
        var position = Int64(SevenZipSignature.size)
        for (source, length) in zip(sources, lengths) {
            pieces.append(Piece(start: position, length: length, source: source))
            position += length
        }
        pieces.append(Piece(start: position, length: Int64(headerBytes.count), source: .memory(headerBytes)))
        self.pieces = pieces
        size = position + Int64(headerBytes.count)
    }

    /// Opens `source` if it's an encrypted 7z and a password is given. Nil when it isn't a
    /// 7z, isn't encrypted, or no password was given for data-only encryption (libarchive
    /// can list those, and asks for the password at extraction).
    static func open(_ source: ArchiveSource, password: String?) throws -> SevenZipDecryptedView? {
        guard SevenZipArchive.isSevenZip(source.parts[0]) else { return nil }
        // Keys hash the password's UTF-16, so "ö" typed precomposed (as Mac and Windows text
        // fields do) and decomposed (as some Mac tools pass it) are different passwords.
        // Try the other form before calling it wrong.
        guard let password, password.unicodeScalars.contains(where: { !$0.isASCII }) else {
            return try openExactly(source, password: password)
        }
        var variants = [password]
        for form in [password.precomposedStringWithCanonicalMapping, password.decomposedStringWithCanonicalMapping]
            where !variants.contains(where: { Array($0.utf16) == Array(form.utf16) }) {
            variants.append(form)
        }
        for (index, variant) in variants.enumerated() {
            do {
                return try openExactly(source, password: variant)
            } catch CrateError.wrongPassword(let name) where index < variants.count - 1 {
                _ = name
                continue
            }
        }
        return nil
    }

    private static func openExactly(_ source: ArchiveSource, password: String?) throws -> SevenZipDecryptedView? {
        let reader: PartsReader
        do { reader = try PartsReader(source.parts) } catch { return nil }
        let archive: SevenZipArchive
        do {
            archive = try SevenZipArchive.open(reader, password: password)
        } catch let error as SevenZipError {
            switch error {
            case .passwordRequired: throw CrateError.passwordRequired(name: source.fileName)
            case .wrongPassword: throw CrateError.wrongPassword(name: source.fileName)
            default: return nil // Let libarchive read it and report (see ErrorMapping).
            }
        }
        guard archive.isEncrypted, let password, !password.isEmpty else { return nil }
        do {
            return try SevenZipDecryptedView(archive: archive, password: password)
        } catch let error as SevenZipError {
            switch error {
            case .wrongPassword: throw CrateError.wrongPassword(name: source.fileName)
            case .unsupported: throw CrateError.unsupportedEncryption(name: source.fileName, format: "7z")
            default: throw CrateError.damaged(name: source.fileName, detail: "")
            }
        }
    }

    /// Whether `source` is a 7z whose names are hidden until a password is given.
    static func hidesNames(_ source: ArchiveSource) -> Bool {
        guard SevenZipArchive.isSevenZip(source.parts[0]), let reader = try? PartsReader(source.parts) else { return false }
        if case SevenZipError.passwordRequired? = Result(catching: { try SevenZipArchive.open(reader, password: nil) }).failure {
            return true
        }
        return false
    }

    // MARK: Checking the password

    /// Decrypts the start of a stream and test-decodes it with the coder that reads it.
    /// LZMA and LZMA2 reject random bytes within a few hundred bytes; a CRC check at
    /// extraction catches the rest.
    private static func checkPassword(folder: SevenZipFolder, slot: Int, reader: PartsReader, offset: Int64,
                                      cipherLength: Int64, plainLength: Int64, key: [UInt8], iv: [UInt8]) throws {
        guard plainLength > 0, let coderIndex = folder.coder(forInStream: folder.packedStreams[slot]) else { return }
        let coder = folder.coders[coderIndex]
        guard coder.method == SevenZipMethod.lzma || coder.method == SevenZipMethod.lzma2 else { return }
        let sample = Int(min(cipherLength, 64 * 1024))
        let decrypted = try AESCBC.decrypt(key: key, iv: iv, try reader.bytes(at: offset, count: sample))
        let input = Array(decrypted.prefix(Int(min(plainLength, Int64(sample)))))
        if coder.method == SevenZipMethod.lzma, input.first != 0 { throw SevenZipError.wrongPassword }
        if coder.method == SevenZipMethod.lzma2, let control = input.first, control != 0x01, control < 0xE0 {
            throw SevenZipError.wrongPassword
        }
        let outIndex = folder.outStart(of: coderIndex)
        let expected = outIndex < folder.unpackSizes.count ? Int(min(folder.unpackSizes[outIndex], 256 * 1024)) : 256 * 1024
        do {
            _ = try SevenZipDecoder.lzma(input, filters: [coder], outputSize: expected, partial: true)
        } catch {
            throw SevenZipError.wrongPassword
        }
    }

    // MARK: Reading

    /// Reads up to `count` bytes at `offset` into `buffer`. Returns 0 at the end.
    func read(at offset: Int64, count: Int, into buffer: UnsafeMutableRawPointer) throws -> Int {
        var done = 0
        var position = offset
        while done < count, position < size {
            guard let piece = pieces.last(where: { $0.start <= position }) else { break }
            let within = position - piece.start
            let wanted = Int(min(Int64(count - done), piece.length - within))
            if wanted <= 0 { break }
            let got: Int
            switch piece.source {
            case .memory(let bytes):
                bytes.withUnsafeBytes { source in
                    (buffer + done).copyMemory(from: source.baseAddress! + Int(within), byteCount: wanted)
                }
                got = wanted
            case .plain(let start):
                got = try reader.read(at: start + within, count: wanted, into: buffer + done)
                if got == 0 { throw SevenZipError.malformed("ends early") }
            case .decrypted(let start, let cipherLength, let key, let iv):
                got = try decrypt(start: start, cipherLength: cipherLength, key: key, iv: iv,
                                  from: within, count: wanted, into: buffer + done)
            }
            done += got
            position += Int64(got)
        }
        return done
    }

    /// CBC decrypts any block on its own: its IV is the ciphertext block before it.
    private func decrypt(start: Int64, cipherLength: Int64, key: [UInt8], iv: [UInt8], from within: Int64, count: Int,
                         into output: UnsafeMutableRawPointer) throws -> Int {
        let blockStart = within & ~15
        let blockEnd = min((within + Int64(count) + 15) & ~15, cipherLength)
        let blockIV = blockStart == 0 ? iv : try reader.bytes(at: start + blockStart - 16, count: 16)
        let cipher = try reader.bytes(at: start + blockStart, count: Int(blockEnd - blockStart))
        let plain = try AESCBC.decrypt(key: key, iv: blockIV, cipher)
        let skip = Int(within - blockStart)
        let available = min(count, plain.count - skip)
        guard available > 0 else { throw SevenZipError.malformed("ends early") }
        plain.withUnsafeBytes { output.copyMemory(from: $0.baseAddress! + skip, byteCount: available) }
        return available
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
