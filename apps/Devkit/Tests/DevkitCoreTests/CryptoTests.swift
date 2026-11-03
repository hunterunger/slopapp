import Foundation
import Testing
@testable import DevkitCore

@Suite struct HashingTests {
    @Test func nistAndRFCVectors() {
        let abc = Hashing.digests(of: Data("abc".utf8))
        // RFC 1321 and NIST FIPS 180 examples.
        #expect(HexDump.hex(abc[.md5]!) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(HexDump.hex(abc[.sha1]!) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(HexDump.hex(abc[.sha256]!) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(HexDump.hex(abc[.sha384]!) == "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
        #expect(HexDump.hex(abc[.sha512]!) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        let empty = Hashing.digests(of: Data())
        #expect(HexDump.hex(empty[.md5]!) == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(HexDump.hex(empty[.sha256]!) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let twoBlock = Hashing.digests(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
        #expect(HexDump.hex(twoBlock[.sha256]!) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    @Test func hmacRFC4231Case2() {
        let digests = Hashing.digests(of: Data("what do ya want for nothing?".utf8), hmacKey: Data("Jefe".utf8))
        #expect(HexDump.hex(digests[.sha256]!) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        #expect(HexDump.hex(digests[.sha512]!) == "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737")
    }

    struct FakeSource: ChunkSource {
        var remaining: [Data]
        var totalBytes: Int64?
        mutating func next(maxLength: Int) throws -> Data? { remaining.isEmpty ? nil : remaining.removeFirst() }
    }

    @Test func streamsChunksWithProgress() throws {
        var source = FakeSource(remaining: [Data("ab".utf8), Data("c".utf8)], totalBytes: 3)
        var progress: [Double] = []
        let digests = try Hashing.digests(of: &source, progress: { progress.append($0) })
        #expect(HexDump.hex(digests[.sha1]!) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(progress.last == 1)
        var cancelled = FakeSource(remaining: [Data("a".utf8)], totalBytes: 1)
        #expect(throws: CancellationError.self) { try Hashing.digests(of: &cancelled, isCancelled: { true }) }
    }

    @Test func matchesPastedChecksum() {
        let digests = Hashing.digests(of: Data("abc".utf8))
        #expect(Hashing.match("BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", in: digests) == .sha256)
        #expect(Hashing.match("sha1:a9993e364706816aba3e25717850c26c9cd0d89d", in: digests) == .sha1)
        #expect(Hashing.match("deadbeef", in: digests) == nil)
    }

    @Test func encodings() {
        #expect(DigestEncoding.base64.encode([0xFF, 0x00]) == "/wA=")
        #expect(DigestEncoding.hexUppercase.encode([0xAB]) == "AB")
    }
}

@Suite struct JWTTests {
    // RFC 7519 §3.1 example, signed with the RFC 7515 Appendix A.1 key.
    static let token = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    static let key = "AyM1SysPpbyDfgZld3umj1qzKObwVMkoqQ-EstJQLr_T-1qS0gZH75aKtMN3Yj0iPS4hcgUuTwjAzZr1Z9CAow"

    @Test func decodesRFC7519Example() throws {
        let jwt = try JWT.decode(Self.token)
        #expect(jwt.algorithm == "HS256")
        #expect(jwt.type == "JWT")
        #expect(jwt.payload == "{\n  \"iss\": \"joe\",\n  \"exp\": 1300819380,\n  \"http://example.com/is_root\": true\n}")
        #expect(jwt.claims.map(\.name) == ["iss", "exp"])
        #expect(jwt.expiresAt == Date(timeIntervalSince1970: 1_300_819_380))
    }

    @Test func verifiesHMAC() throws {
        let jwt = try JWT.decode(Self.token)
        #expect(JWT.verify(jwt, secret: try Base64.decode(Self.key)) == .verified)
        #expect(JWT.verify(jwt, secret: Data("wrong".utf8)) == .mismatch)
        #expect(JWT.verify(jwt, secret: Data()) == .needsSecret)
    }

    @Test func validity() throws {
        let jwt = try JWT.decode(Self.token)
        let exp = Date(timeIntervalSince1970: 1_300_819_380)
        #expect(JWT.validity(of: jwt, now: exp.addingTimeInterval(-10)) == .valid(until: exp))
        #expect(JWT.validity(of: jwt, now: exp) == .expired(exp))
    }

    @Test func acceptsBearerPrefixAndUnsigned() throws {
        let header = Base64.encode(#"{"alg":"none"}"#, options: .init(urlSafe: true, padding: false))
        let payload = Base64.encode(#"{"sub":"1","nbf":2000000000}"#, options: .init(urlSafe: true, padding: false))
        let jwt = try JWT.decode("Bearer \(header).\(payload).")
        #expect(JWT.verify(jwt, secret: Data("x".utf8)) == .unsigned)
        #expect(JWT.validity(of: jwt, now: Date(timeIntervalSince1970: 0)) == .notYetValid(Date(timeIntervalSince1970: 2_000_000_000)))
    }

    @Test func errors() {
        #expect(throws: JWT.DecodeError.notThreeParts(2)) { try JWT.decode("abc.def") }
        #expect(throws: JWT.DecodeError.encrypted) { try JWT.decode("a.b.c.d.e") }
        #expect(throws: JWT.DecodeError.badSegment("header")) { try JWT.decode("$$$.e30.x") }
        let notJSON = Base64.encode("hello", options: .init(urlSafe: true, padding: false))
        #expect(throws: (any Error).self) { try JWT.decode("\(notJSON).e30.") }
    }
}
