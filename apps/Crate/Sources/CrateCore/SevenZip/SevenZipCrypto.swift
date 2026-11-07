import CommonCrypto
import Foundation
import Security

/// 7z's AES-256 coder (method 06F10701): AES-256-CBC with a key made by hashing the salt,
/// the UTF-16LE password and a counter 2^n times with SHA-256. Written from 7-Zip's
/// format description; built on CommonCrypto.
struct SevenZipAESProperties: Equatable {
    /// log2 of the SHA-256 rounds (7-Zip uses 19: 524,288 rounds).
    var cyclesPower: Int
    var salt: [UInt8]
    /// Always 16 bytes (shorter IVs are zero-padded).
    var iv: [UInt8]

    static let maxCyclesPower = 24

    init(cyclesPower: Int, salt: [UInt8], iv: [UInt8]) {
        self.cyclesPower = cyclesPower
        self.salt = salt
        self.iv = iv + Array(repeating: 0, count: max(0, 16 - iv.count))
        storedIVLength = iv.count
    }

    /// The IV bytes as stored (7-Zip stores 16; older versions 8).
    private var storedIVLength: Int

    init(decoding props: [UInt8]) throws {
        guard let first = props.first else { throw SevenZipError.malformed("AES properties") }
        let power = Int(first & 0x3F)
        guard power <= Self.maxCyclesPower || power == 0x3F else { throw SevenZipError.unsupported("AES key rounds") }
        if first & 0xC0 == 0 {
            guard props.count == 1 else { throw SevenZipError.malformed("AES properties") }
            self.init(cyclesPower: power, salt: [], iv: [])
            return
        }
        guard props.count >= 2 else { throw SevenZipError.malformed("AES properties") }
        let second = props[1]
        let saltSize = Int((first >> 7) & 1) + Int(second >> 4)
        let ivSize = Int((first >> 6) & 1) + Int(second & 0x0F)
        guard props.count == 2 + saltSize + ivSize else { throw SevenZipError.malformed("AES properties") }
        self.init(cyclesPower: power, salt: Array(props[2..<(2 + saltSize)]),
                  iv: Array(props[(2 + saltSize)...]))
    }

    func encoded() -> [UInt8] {
        let ivBytes = Array(iv.prefix(storedIVLength))
        var first = UInt8(cyclesPower & 0x3F)
        if !salt.isEmpty { first |= 0x80 }
        if !ivBytes.isEmpty { first |= 0x40 }
        guard !salt.isEmpty || !ivBytes.isEmpty else { return [first] }
        let second = UInt8(salt.isEmpty ? 0 : (salt.count - 1) << 4) | UInt8(ivBytes.isEmpty ? 0 : ivBytes.count - 1)
        return [first, second] + salt + ivBytes
    }
}

enum SevenZipKey {
    private static let lock = NSLock()
    /// Recent keys by (password, salt, rounds) digest, so listing, checking and extracting
    /// one archive derive its key once. In memory only, like the password itself.
    nonisolated(unsafe) private static var cache: [Data: [UInt8]] = [:]
    nonisolated(unsafe) private static var order: [Data] = []

    static func passwordBytes(_ password: String) -> [UInt8] {
        password.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }
    }

    static func derive(password: String, properties: SevenZipAESProperties) -> [UInt8] {
        let passwordBytes = passwordBytes(password)
        var keyMaterial = properties.salt + passwordBytes + [UInt8(properties.cyclesPower)]
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(&keyMaterial, CC_LONG(keyMaterial.count), &digest)
        let cacheKey = Data(digest)
        keyMaterial.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) }
        if let cached = lock.withLock({ cache[cacheKey] }) { return cached }

        var key = [UInt8](repeating: 0, count: 32)
        if properties.cyclesPower == 0x3F {
            let material = Array((properties.salt + passwordBytes).prefix(32))
            key.replaceSubrange(0..<material.count, with: material)
        } else {
            var block = properties.salt + passwordBytes + [UInt8](repeating: 0, count: 8)
            let counterOffset = block.count - 8
            var context = CC_SHA256_CTX()
            CC_SHA256_Init(&context)
            let rounds = UInt64(1) << UInt64(properties.cyclesPower)
            block.withUnsafeMutableBufferPointer { buffer in
                let base = buffer.baseAddress!
                for round in 0..<rounds {
                    var counter = round.littleEndian
                    withUnsafeBytes(of: &counter) { counterBytes in
                        (base + counterOffset).withMemoryRebound(to: UInt8.self, capacity: 8) { target in
                            for index in 0..<8 { target[index] = counterBytes[index] }
                        }
                    }
                    CC_SHA256_Update(&context, base, CC_LONG(buffer.count))
                }
            }
            CC_SHA256_Final(&key, &context)
            block.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) }
        }
        lock.withLock {
            cache[cacheKey] = key
            order.append(cacheKey)
            if order.count > 16 { cache[order.removeFirst()] = nil }
        }
        return key
    }

    /// Forgets every cached key (when an archive closes).
    static func forgetAll() {
        lock.withLock {
            cache = [:]
            order = []
        }
    }

    static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "No secure random bytes")
        return bytes
    }
}

/// AES-256-CBC without padding (7z pads the last block with zeros itself).
enum AESCBC {
    static func decrypt(key: [UInt8], iv: [UInt8], _ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawPointer) throws {
        try run(CCOperation(kCCDecrypt), key: key, iv: iv, input, into: output)
    }

    static func encrypt(key: [UInt8], iv: [UInt8], _ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawPointer) throws {
        try run(CCOperation(kCCEncrypt), key: key, iv: iv, input, into: output)
    }

    static func decrypt(key: [UInt8], iv: [UInt8], _ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count)
        try input.withUnsafeBytes { inBuffer in
            try output.withUnsafeMutableBytes { try decrypt(key: key, iv: iv, inBuffer, into: $0.baseAddress!) }
        }
        return output
    }

    static func encrypt(key: [UInt8], iv: [UInt8], _ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count)
        try input.withUnsafeBytes { inBuffer in
            try output.withUnsafeMutableBytes { try encrypt(key: key, iv: iv, inBuffer, into: $0.baseAddress!) }
        }
        return output
    }

    private static func run(_ operation: CCOperation, key: [UInt8], iv: [UInt8], _ input: UnsafeRawBufferPointer,
                            into output: UnsafeMutableRawPointer) throws {
        guard input.count % kCCBlockSizeAES128 == 0, key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw SevenZipError.malformed("encrypted data isn't whole AES blocks")
        }
        if input.isEmpty { return }
        var moved = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), 0, key, key.count, iv,
                             input.baseAddress, input.count, output, input.count, &moved)
        guard status == kCCSuccess, moved == input.count else { throw SevenZipError.io("AES failed (\(status))") }
    }
}

/// A streaming AES-256-CBC encryptor for writing archives.
final class AESCBCStream {
    private var cryptor: CCCryptorRef?

    init(encryptingWith key: [UInt8], iv: [UInt8]) throws {
        let status = CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0, key, key.count, iv, &cryptor)
        guard status == kCCSuccess else { throw SevenZipError.io("AES failed (\(status))") }
    }

    deinit { CCCryptorRelease(cryptor) }

    /// `count` must be a multiple of 16.
    func update(_ input: UnsafeRawPointer, count: Int, into output: UnsafeMutableRawPointer) throws {
        var moved = 0
        let status = CCCryptorUpdate(cryptor, input, count, output, count, &moved)
        guard status == kCCSuccess, moved == count else { throw SevenZipError.io("AES failed (\(status))") }
    }
}
