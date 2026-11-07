import Darwin
import Foundation

/// Turns a plain 7z (as libarchive writes it) into an AES-256 encrypted one, the way 7-Zip
/// lays them out: each folder gets an AES coder in front (reading the packed stream), and
/// with `hideNames` the header is encrypted too, so the file list needs the password.
/// Compression is untouched; only the packed bytes and the header are rewritten.
enum SevenZipEncryptor {
    /// 2^19 SHA-256 rounds, as 7-Zip uses.
    static let cyclesPower = 19

    static func encrypt(_ input: URL, to output: URL, password: String, hideNames: Bool,
                        progress: ((Double) -> Void)? = nil) throws {
        guard !password.isEmpty else { throw SevenZipError.passwordRequired }
        // Precomposed, as Windows and Mac text fields type it.
        let password = password.precomposedStringWithCanonicalMapping
        let reader = try PartsReader([input])
        let archive = try SevenZipArchive.open(reader, password: nil)
        guard !archive.isEncrypted else { throw SevenZipError.unsupported("already encrypted") }

        let salt = SevenZipKey.randomBytes(16)
        let key = SevenZipKey.derive(password: password, properties: SevenZipAESProperties(cyclesPower: cyclesPower, salt: salt, iv: []))
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o644]) else {
            throw SevenZipError.io("can't create the archive")
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data(count: SevenZipSignature.size))

        var header = archive.header
        var written: Int64 = 0
        if var main = header.main {
            let offsets = archive.packOffsets()
            guard main.folders.allSatisfy({ $0.packedStreams.count == 1 }), main.packSizes.count == main.folders.count else {
                throw SevenZipError.unsupported("several packed streams")
            }
            let total = max(1, main.packSizes.reduce(0, +))
            var done: UInt64 = 0
            var newSizes: [UInt64] = []
            for index in main.folders.indices {
                let properties = SevenZipAESProperties(cyclesPower: cyclesPower, salt: salt, iv: SevenZipKey.randomBytes(16))
                let size = main.packSizes[index]
                let encryptedSize = try copyEncrypted(from: reader, offset: offsets[index], length: Int64(size), to: handle,
                                                      key: key, iv: properties.iv) { bytes in
                    progress?(Double(done + bytes) / Double(total))
                }
                done += size
                written += encryptedSize
                newSizes.append(UInt64(encryptedSize))
                try main.folders[index].insertPackedSideCoder(SevenZipCoder(method: SevenZipMethod.aes, properties: properties.encoded()),
                                                              packedSize: size)
            }
            main.packPosition = 0
            main.packSizes = newSizes
            header.main = main
        }

        let plainHeader = header.encoded()
        var nextHeader = plainHeader
        if hideNames {
            // The header as one AES-only folder (py7zr and 7-Zip with -mhc=off write the same).
            let properties = SevenZipAESProperties(cyclesPower: cyclesPower, salt: salt, iv: SevenZipKey.randomBytes(16))
            let padded = plainHeader + [UInt8](repeating: 0, count: (16 - plainHeader.count % 16) % 16)
            let encrypted = try AESCBC.encrypt(key: key, iv: properties.iv, padded)
            try handle.write(contentsOf: Data(encrypted))
            var folder = SevenZipFolder(coders: [SevenZipCoder(method: SevenZipMethod.aes, properties: properties.encoded())],
                                        bindPairs: [], packedStreams: [0])
            folder.unpackSizes = [UInt64(plainHeader.count)]
            folder.crc = CRC32.checksum(plainHeader)
            let streams = SevenZipStreams(packPosition: UInt64(written), packSizes: [UInt64(encrypted.count)], folders: [folder])
            var writer = SevenZipWriter()
            writer.byte(SevenZipID.encodedHeader)
            streams.write(to: &writer)
            nextHeader = writer.bytes
            written += Int64(encrypted.count)
        }
        try handle.write(contentsOf: Data(nextHeader))
        let signature = SevenZipSignature(nextHeaderOffset: UInt64(written), nextHeaderSize: UInt64(nextHeader.count),
                                          nextHeaderCRC: CRC32.checksum(nextHeader))
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(signature.encoded()))
        try handle.synchronize()
    }

    /// Encrypts `length` bytes, zero-padding the last block. Returns the bytes written.
    private static func copyEncrypted(from reader: PartsReader, offset: Int64, length: Int64, to handle: FileHandle,
                                      key: [UInt8], iv: [UInt8], progress: (UInt64) -> Void) throws -> Int64 {
        let stream = try AESCBCStream(encryptingWith: key, iv: iv)
        let chunk = 1 << 20
        let input = UnsafeMutableRawPointer.allocate(byteCount: chunk + 16, alignment: 16)
        let output = UnsafeMutableRawPointer.allocate(byteCount: chunk + 16, alignment: 16)
        defer {
            input.deallocate()
            output.deallocate()
        }
        var position: Int64 = 0
        var written: Int64 = 0
        while position < length {
            try Task.checkCancellation()
            let wanted = Int(min(Int64(chunk), length - position))
            let got = try reader.read(at: offset + position, count: wanted, into: input)
            guard got == wanted else { throw SevenZipError.malformed("ends early") }
            position += Int64(got)
            var count = got
            if position == length, count % 16 != 0 {
                let padding = 16 - count % 16
                (input + count).initializeMemory(as: UInt8.self, repeating: 0, count: padding)
                count += padding
            }
            try stream.update(input, count: count, into: output)
            try handle.write(contentsOf: Data(bytesNoCopy: output, count: count, deallocator: .none))
            written += Int64(count)
            progress(UInt64(position))
        }
        return written
    }
}
