import Foundation
import PaperCore
import Security

/// A throwaway signing identity made in memory for tests: a fresh RSA key (never stored in
/// any keychain) and a self-signed certificate for "Paper Test Signer".
public enum TestSigner {
    public static func make(name: String = "Paper Test Signer", validDays: Double = 30) -> KeySigner? {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048,
                                           kSecAttrIsPermanent: false]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(key),
              let publicBytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }
        let algorithm = DER.sequence([DER.oid("1.2.840.113549.1.1.11"), DER.null])
        let rdn = DER.sequence([DER.set([DER.sequence([DER.oid("2.5.4.3"), DER.utf8String(name)])])])
        let now = Date()
        let validity = DER.sequence([DER.utcTime(now.addingTimeInterval(-3600)), DER.utcTime(now.addingTimeInterval(validDays * 86_400))])
        let spki = DER.sequence([DER.sequence([DER.oid("1.2.840.113549.1.1.1"), DER.null]), DER.bitString(publicBytes)])
        // Key usage: digital signature + non-repudiation.
        let keyUsage = DER.sequence([DER.oid("2.5.29.15"), Data([0x01, 0x01, 0xFF]), DER.octetString(Data([0x03, 0x02, 0x06, 0xC0]))])
        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)),
            DER.integer(unsigned: Data((0..<8).map { _ in UInt8.random(in: 1...255) })),
            algorithm, rdn, validity, rdn, spki,
            DER.explicit(3, DER.sequence([keyUsage])),
        ])
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error) as Data? else { return nil }
        let certificate = DER.sequence([tbs, algorithm, DER.bitString(signature)])
        return KeySigner(key: key, certificates: [certificate])
    }
}
