import Foundation
import Testing
@testable import CrateCore

/// Encrypted 7z: decrypting (py7zr fixtures, password "secret") and encrypting (our own
/// writer, read back by our reader and checked structurally).
@Suite struct SevenZipCryptoTests {
    static let data = ArchiveSource(file: TestFolder.fixture("encrypted_data.7z"))
    static let header = ArchiveSource(file: TestFolder.fixture("encrypted_header.7z"))

    @Test func numbersRoundTrip() throws {
        for value: UInt64 in [0, 1, 0x7F, 0x80, 0x3FFF, 0x4000, 0x1F_FFFF, 0x20_0000, 1 << 35, 1 << 56, .max] {
            var writer = SevenZipWriter()
            writer.number(value)
            var reader = SevenZipReader(writer.bytes)
            #expect(try reader.number() == value)
            #expect(reader.isAtEnd)
        }
    }

    @Test func keyDerivationMatchesKnownVector() {
        // 7-Zip's KDF: SHA-256 over (salt + UTF-16LE password + 8-byte counter), 2^n times.
        // With n = 0x3F the key is just salt + password (zero padded).
        let raw = SevenZipKey.derive(password: "ab", properties: SevenZipAESProperties(cyclesPower: 0x3F, salt: [1, 2], iv: []))
        #expect(Array(raw.prefix(6)) == [1, 2, 0x61, 0, 0x62, 0])
        // One round (n = 0) is SHA-256("a\0" + 8 zero bytes).
        let one = SevenZipKey.derive(password: "a", properties: SevenZipAESProperties(cyclesPower: 0, salt: [], iv: []))
        #expect(one.map { String(format: "%02x", $0) }.joined() == SevenZipCryptoTests.sha256Hex([0x61, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    }

    @Test func propertiesRoundTrip() throws {
        let properties = SevenZipAESProperties(cyclesPower: 19, salt: Array(1...16), iv: Array(100...115))
        #expect(try SevenZipAESProperties(decoding: properties.encoded()) == properties)
        let saltless = SevenZipAESProperties(cyclesPower: 19, salt: [], iv: Array(1...16))
        #expect(saltless.encoded().count == 18)
        #expect(throws: SevenZipError.unsupported("AES key rounds")) { try SevenZipAESProperties(decoding: [30]) }
    }

    @Test func dataOnlyEncryptionListsThenAsks() throws {
        let listing = try ArchiveReader.list(Self.data)
        #expect(listing.hasEncryptedEntries)
        #expect(!listing.encryptionUnsupported)
        #expect(!listing.entries.isEmpty)
        let out = TestFolder.make()
        #expect(throws: CrateError.passwordRequired(name: "encrypted_data.7z")) {
            try Extractor().extract(Self.data, to: out)
        }
        #expect(TestFolder.tree(out).isEmpty)
    }

    @Test func decryptsDataOnlyEncryption() throws {
        #expect(try ArchiveReader.checkPassword("secret", for: Self.data))
        #expect(try !ArchiveReader.checkPassword("wrong", for: Self.data))
        let out = TestFolder.make()
        let result = try Extractor().extract(Self.data, to: out, options: .init(password: "secret"))
        #expect(result.fileCount >= 1)
        #expect(result.skipped.isEmpty)
        let listing = try ArchiveReader.list(Self.data)
        let file = try #require(listing.entries.first { $0.kind == .file })
        let written = try Data(contentsOf: try #require(result.primary).deletingLastPathComponent().appendingPathComponent(file.path))
        #expect(Int64(written.count) == file.size)
    }

    @Test func headerEncryptionHidesNamesUntilUnlocked() throws {
        #expect(SevenZipDecryptedView.hidesNames(Self.header))
        #expect(!SevenZipDecryptedView.hidesNames(Self.data))
        #expect(throws: CrateError.passwordRequired(name: "encrypted_header.7z")) { try ArchiveReader.list(Self.header) }
        #expect(throws: CrateError.wrongPassword(name: "encrypted_header.7z")) {
            try ArchiveReader.list(Self.header, password: "nope")
        }
        #expect(try !ArchiveReader.checkPassword("nope", for: Self.header))
        #expect(try ArchiveReader.checkPassword("secret", for: Self.header))
        let listing = try ArchiveReader.list(Self.header, password: "secret")
        #expect(!listing.entries.isEmpty)
        let out = TestFolder.make()
        let result = try Extractor().extract(Self.header, to: out, options: .init(password: "secret"))
        #expect(result.fileCount == listing.entries.filter { $0.kind == .file }.count)
    }

    static func sha256Hex(_ bytes: [UInt8]) -> String {
        var data = bytes
        var digest = [UInt8](repeating: 0, count: 32)
        CommonCryptoShim.sha256(&data, &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@Suite struct SevenZipWriteTests {
    func makeSource(_ folder: URL) -> URL {
        let src = folder.appendingPathComponent("Secret Project")
        TestFolder.write("hello", to: src.appendingPathComponent("hello.txt"))
        TestFolder.write("emoji", to: src.appendingPathComponent("sub/📦 box.txt"))
        TestFolder.write(String(repeating: "compressible line\n", count: 200_000), to: src.appendingPathComponent("big.txt"))
        var random = [UInt8](repeating: 0, count: 3 << 20)
        for index in random.indices { random[index] = UInt8(truncatingIfNeeded: index &* 2_654_435_761 >> 13) }
        try! Data(random).write(to: src.appendingPathComponent("noise.bin"))
        try! FileManager.default.createDirectory(at: src.appendingPathComponent("empty"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src.appendingPathComponent("zero.txt").path, contents: Data())
        try! FileManager.default.createSymbolicLink(atPath: src.appendingPathComponent("link").path, withDestinationPath: "hello.txt")
        return src
    }

    @Test func encryptedRoundTripWithHiddenNames() throws {
        let folder = TestFolder.make()
        let src = makeSource(folder)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "vault", format: .sevenZip,
                                                                level: .fast, password: "pässwörd 🔑"))
        let archive = try #require(result.primary)
        let source = ArchiveSource(file: archive)
        // Nothing readable without the password, not even names.
        #expect(SevenZipDecryptedView.hidesNames(source))
        #expect(throws: CrateError.passwordRequired(name: "vault.7z")) { try ArchiveReader.list(source) }
        #expect(throws: CrateError.wrongPassword(name: "vault.7z")) { try ArchiveReader.list(source, password: "password") }
        let raw = try Data(contentsOf: archive)
        #expect(raw.range(of: Data("hello.txt".utf8)) == nil)
        #expect(raw.range(of: Data("compressible".utf8)) == nil)

        let listing = try ArchiveReader.list(source, password: "pässwörd 🔑")
        #expect(listing.formatName == "7z")
        #expect(Set(listing.entries.map(\.path)).isSuperset(of: ["Secret Project/hello.txt", "Secret Project/sub/📦 box.txt",
                                                                  "Secret Project/noise.bin", "Secret Project/empty",
                                                                  "Secret Project/zero.txt", "Secret Project/link"]))
        let out = TestFolder.make("out")
        let extracted = try Extractor().extract(source, to: out, options: .init(password: "pässwörd 🔑"))
        #expect(TestFolder.tree(out) == TestFolder.tree(folder.appendingPathComponent("Secret Project")).map { "Secret Project/" + $0 } + ["Secret Project/"]
            || extracted.outputs.count == 1)
        let root = try #require(extracted.primary)
        for name in ["hello.txt", "sub/📦 box.txt", "big.txt", "noise.bin", "zero.txt"] {
            #expect(try Data(contentsOf: root.appendingPathComponent(name)) == Data(contentsOf: src.appendingPathComponent(name)), "\(name)")
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("link").path) == "hello.txt")
    }

    @Test func encryptedWithVisibleNames() throws {
        let folder = TestFolder.make()
        let src = folder.appendingPathComponent("a.txt")
        TestFolder.write(String(repeating: "abc", count: 10_000), to: src)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "names", format: .sevenZip,
                                                                password: "pw", hideNames: false))
        let source = ArchiveSource(file: try #require(result.primary))
        #expect(!SevenZipDecryptedView.hidesNames(source))
        let listing = try ArchiveReader.list(source)
        #expect(listing.entries.map(\.path) == ["a.txt"])
        #expect(listing.hasEncryptedEntries && !listing.encryptionUnsupported)
        #expect(throws: CrateError.passwordRequired(name: "names.7z")) { try Extractor().extract(source, to: TestFolder.make("o1")) }
        #expect(throws: CrateError.wrongPassword(name: "names.7z")) {
            try Extractor().extract(source, to: TestFolder.make("o2"), options: .init(password: "nope"))
        }
        #expect(try !ArchiveReader.checkPassword("nope", for: source))
        #expect(try ArchiveReader.checkPassword("pw", for: source))
        let out = try Extractor().extract(source, to: TestFolder.make("o3"), options: .init(password: "pw"))
        #expect(try String(contentsOf: try #require(out.primary), encoding: .utf8).count == 30_000)
    }

    @Test func layoutMatches7Zip() throws {
        let folder = TestFolder.make()
        let src = folder.appendingPathComponent("a.txt")
        TestFolder.write("layout", to: src)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "l", format: .sevenZip,
                                                                password: "pw", hideNames: true))
        let archive = try SevenZipArchive.open(try PartsReader([try #require(result.primary)]), password: "pw")
        #expect(archive.headerEncrypted)
        let folderInfo = try #require(archive.header.main?.folders.first)
        // AES first, reading the packed stream, feeding LZMA2 (7-Zip's own layout).
        #expect(folderInfo.coders.map(\.method) == [SevenZipMethod.aes, SevenZipMethod.lzma2])
        #expect(folderInfo.packedStreams == [0])
        #expect(folderInfo.bindPairs == [SevenZipBindPair(inIndex: 1, outIndex: 0)])
        let properties = try SevenZipAESProperties(decoding: folderInfo.coders[0].properties)
        #expect(properties.cyclesPower == 19 && properties.salt.count == 16)
    }

    @Test func encryptedSplitSetReopens() throws {
        let folder = TestFolder.make()
        let src = folder.appendingPathComponent("noise.bin")
        var bytes = [UInt8](repeating: 0, count: 2_500_000)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in bytes.indices {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            bytes[index] = UInt8(truncatingIfNeeded: state)
        }
        try Data(bytes).write(to: src)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "parts", format: .sevenZip,
                                                                level: .fast, password: "pw", partSize: 1_000_000))
        try #require(result.outputs.count >= 2)
        let source = try VolumeSet.resolve(result.outputs[1])
        #expect(source.parts.count == result.outputs.count)
        #expect(throws: CrateError.passwordRequired(name: "parts.7z.001")) { try ArchiveReader.list(source) }
        let out = try Extractor().extract(source, to: TestFolder.make("o"), options: .init(password: "pw"))
        #expect(try Data(contentsOf: try #require(out.primary)) == Data(bytes))
    }

    /// Hostile entries stay contained when they arrive encrypted.
    @Test func hostileEntriesInsideEncryption() throws {
        let root = TestFolder.make()
        let folder = root.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let plain = folder.appendingPathComponent("plain.7z")
        RawArchive.write(plain, format: .sevenZip, entries: [
            .text("../escaped.txt", "bad"),
            .text("/tmp/crate-test/absolute-7z.txt", "bad"),
            .init("link", .symlink("../../outside")),
            .text("safe.txt", "good"),
        ])
        let evil = folder.appendingPathComponent("evil.7z")
        try SevenZipEncryptor.encrypt(plain, to: evil, password: "pw", hideNames: true)
        let source = ArchiveSource(file: evil)
        let listing = try ArchiveReader.list(source, password: "pw")
        #expect(listing.entries.map(\.path) == ["safe.txt"])
        #expect(listing.unsafeEntries.count == 3)
        let result = try Extractor().extract(source, to: folder, options: .init(password: "pw"))
        #expect(result.skipped.count == 3)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/crate-test/absolute-7z.txt"))
        #expect(try String(contentsOf: try #require(result.primary), encoding: .utf8) == "good")
    }

    @Test func bombInsideEncryptionIsStopped() throws {
        let folder = TestFolder.make()
        let plain = folder.appendingPathComponent("plain.7z")
        RawArchive.write(plain, format: .sevenZip, entries: [.init("zeros.bin", .zeros(64 << 20))])
        let bomb = folder.appendingPathComponent("bomb.7z")
        try SevenZipEncryptor.encrypt(plain, to: bomb, password: "pw", hideNames: false)
        try FileManager.default.removeItem(at: plain)
        let limits = ExtractionLimits(maxRatio: 100, ratioFloor: 1 << 20, reserve: 0)
        #expect(throws: CrateError.self) {
            try Extractor().extract(ArchiveSource(file: bomb), to: folder, options: .init(password: "pw", limits: limits))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["bomb.7z"])
    }

    @Test func damagedAndTruncatedEncryptedArchivesFailCleanly() throws {
        let folder = TestFolder.make()
        let src = folder.appendingPathComponent("a.txt")
        TestFolder.write(String(repeating: "data ", count: 50_000), to: src)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "d", format: .sevenZip,
                                                                password: "pw", hideNames: false))
        let archive = try #require(result.primary)
        let original = try Data(contentsOf: archive)
        // Truncated.
        let cut = folder.appendingPathComponent("cut.7z")
        try original.prefix(original.count / 2).write(to: cut)
        #expect(throws: CrateError.self) {
            try Extractor().extract(ArchiveSource(file: cut), to: TestFolder.make("t"), options: .init(password: "pw"))
        }
        // Random damage anywhere: errors, never a crash or stray output.
        var generator = SystemRandomNumberGenerator()
        for round in 0..<150 {
            var bytes = [UInt8](original)
            for _ in 0..<(1 + round % 4) {
                let index = Int.random(in: 0..<bytes.count, using: &generator)
                bytes[index] ^= UInt8.random(in: 1...255, using: &generator)
            }
            let damaged = folder.appendingPathComponent("damaged.7z")
            try Data(bytes).write(to: damaged)
            let out = TestFolder.make("f")
            _ = try? ArchiveReader.list(ArchiveSource(file: damaged), password: "pw")
            if (try? Extractor().extract(ArchiveSource(file: damaged), to: out, options: .init(password: "pw"))) == nil {
                #expect(TestFolder.tree(out).isEmpty)
            }
        }
    }
}
