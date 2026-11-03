import CryptoKit
import Foundation

public enum HashAlgorithm: String, CaseIterable, Sendable, Identifiable {
    case md5, sha1, sha256, sha384, sha512

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .md5: "MD5"
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        case .sha384: "SHA-384"
        case .sha512: "SHA-512"
        }
    }

    /// MD5 and SHA-1 are broken for security; fine for checksums.
    public var isInsecure: Bool { self == .md5 || self == .sha1 }
}

public enum DigestEncoding: String, CaseIterable, Sendable, Identifiable {
    case hex, hexUppercase, base64
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hex: "Hex"
        case .hexUppercase: "HEX"
        case .base64: "Base64"
        }
    }

    public func encode(_ digest: [UInt8]) -> String {
        switch self {
        case .hex: HexDump.hex(digest)
        case .hexUppercase: HexDump.hex(digest, uppercase: true)
        case .base64: Data(digest).base64EncodedString()
        }
    }
}

/// Feeds the same bytes to every algorithm at once, so a file is read only once.
public struct MultiHasher {
    var md5 = Insecure.MD5()
    var sha1 = Insecure.SHA1()
    var sha256 = SHA256()
    var sha384 = SHA384()
    var sha512 = SHA512()
    var hmacs: (HMAC<Insecure.MD5>, HMAC<Insecure.SHA1>, HMAC<SHA256>, HMAC<SHA384>, HMAC<SHA512>)?

    public init(hmacKey: Data? = nil) {
        if let hmacKey, !hmacKey.isEmpty {
            let key = SymmetricKey(data: hmacKey)
            hmacs = (HMAC(key: key), HMAC(key: key), HMAC(key: key), HMAC(key: key), HMAC(key: key))
        }
    }

    public mutating func update(_ data: some DataProtocol) {
        if hmacs != nil {
            hmacs!.0.update(data: data)
            hmacs!.1.update(data: data)
            hmacs!.2.update(data: data)
            hmacs!.3.update(data: data)
            hmacs!.4.update(data: data)
        } else {
            md5.update(data: data)
            sha1.update(data: data)
            sha256.update(data: data)
            sha384.update(data: data)
            sha512.update(data: data)
        }
    }

    public func finalize() -> [HashAlgorithm: [UInt8]] {
        if let hmacs {
            return [
                .md5: Array(hmacs.0.finalize()), .sha1: Array(hmacs.1.finalize()),
                .sha256: Array(hmacs.2.finalize()), .sha384: Array(hmacs.3.finalize()),
                .sha512: Array(hmacs.4.finalize()),
            ]
        }
        return [
            .md5: Array(md5.finalize()), .sha1: Array(sha1.finalize()),
            .sha256: Array(sha256.finalize()), .sha384: Array(sha384.finalize()),
            .sha512: Array(sha512.finalize()),
        ]
    }
}

/// Something that hands out a file's bytes in chunks. `FileHandle` in the app; fakes in tests.
public protocol ChunkSource {
    var totalBytes: Int64? { get }
    /// Next chunk, or nil at the end.
    mutating func next(maxLength: Int) throws -> Data?
}

public enum Hashing {
    public static func digests(of data: some DataProtocol, hmacKey: Data? = nil) -> [HashAlgorithm: [UInt8]] {
        var hasher = MultiHasher(hmacKey: hmacKey)
        hasher.update(data)
        return hasher.finalize()
    }

    /// Streams `source` through every algorithm, 1 MB at a time.
    public static func digests(of source: inout some ChunkSource, hmacKey: Data? = nil,
                               progress: (Double) -> Void = { _ in },
                               isCancelled: () -> Bool = { false }) throws -> [HashAlgorithm: [UInt8]] {
        var hasher = MultiHasher(hmacKey: hmacKey)
        var done: Int64 = 0
        while true {
            // File reads hand back autoreleased buffers; drain them per chunk so memory
            // stays at one chunk instead of the whole file.
            let more = try autoreleasepool { () throws -> Bool in
                guard let chunk = try source.next(maxLength: 1 << 20) else { return false }
                if isCancelled() { throw CancellationError() }
                hasher.update(chunk)
                done += Int64(chunk.count)
                if let total = source.totalBytes, total > 0 { progress(min(1, Double(done) / Double(total))) }
                return true
            }
            if !more { break }
        }
        return hasher.finalize()
    }

    /// Which algorithm (if any) produced `expected`, ignoring case, spaces and a
    /// `sha256:`-style prefix. Lets people paste a published checksum to compare.
    public static func match(_ expected: String, in digests: [HashAlgorithm: [UInt8]]) -> HashAlgorithm? {
        var cleaned = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = cleaned.firstIndex(of: ":"), cleaned.distance(from: cleaned.startIndex, to: colon) <= 8 {
            cleaned = String(cleaned[cleaned.index(after: colon)...])
        }
        cleaned = cleaned.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        for algorithm in HashAlgorithm.allCases {
            guard let digest = digests[algorithm] else { continue }
            if HexDump.hex(digest) == cleaned.lowercased() || Data(digest).base64EncodedString() == cleaned {
                return algorithm
            }
        }
        return nil
    }
}
