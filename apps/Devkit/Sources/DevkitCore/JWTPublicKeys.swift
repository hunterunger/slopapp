import CryptoKit
import Foundation
import Security

/// RS/PS/ES signature checks for JWTs, with the public key as PEM (SPKI or PKCS#1), a
/// certificate, a JWK or a JWK Set.
extension JWT {
    public enum PublicKey: Sendable, Equatable {
        case rsa(pkcs1: Data)
        case ec(curve: String, x963: Data)

        public var summary: String {
            switch self {
            case let .rsa(pkcs1):
                let bits = (try? DERNode.parse(pkcs1))?.children.first?.integerBitLength ?? 0
                return "RSA \(bits) bits"
            case let .ec(curve, _): return "EC \(curve)"
            }
        }
    }

    public struct KeyError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
    }

    public static func isAsymmetric(_ algorithm: String?) -> Bool {
        guard let algorithm else { return false }
        return ["RS", "PS", "ES"].contains { algorithm.hasPrefix($0) }
    }

    /// Reads a public key from PEM, a certificate, a JWK or a JWK Set (picking `kid` when it matches).
    public static func publicKey(from text: String, keyID: String? = nil) throws -> PublicKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
                throw KeyError(description: "The JWK isn't valid JSON")
            }
            if let keys = object["keys"] as? [[String: Any]] {
                let chosen = keys.first { keyID != nil && $0["kid"] as? String == keyID } ?? keys.first
                guard let chosen else { throw KeyError(description: "The JWK Set has no keys") }
                return try jwk(chosen)
            }
            return try jwk(object)
        }
        let blocks = PEM.blocks(in: trimmed)
        guard let block = blocks.first else {
            throw KeyError(description: "Paste a public key: PEM (-----BEGIN PUBLIC KEY-----), a certificate or a JWK")
        }
        switch block.label {
        case "RSA PUBLIC KEY":
            return .rsa(pkcs1: block.data)
        case "PUBLIC KEY":
            return try subjectPublicKeyInfo(block.data)
        case "CERTIFICATE":
            let certificate = try CertificateDecoder.decode(der: block.data)
            return try subjectPublicKeyInfo(certificate.publicKeyInfo)
        case let label where label.contains("PRIVATE"):
            throw KeyError(description: "That's a private key. Paste the public key; Devkit never needs the private one to verify")
        default:
            throw KeyError(description: "Unsupported PEM type “\(block.label)”")
        }
    }

    static func subjectPublicKeyInfo(_ data: Data) throws -> PublicKey {
        guard let spki = try? DERNode.parse(data), let algorithm = spki.children.first, let bits = spki.children.last,
              let oid = algorithm.children.first?.oid else { throw KeyError(description: "The public key isn't valid") }
        let key = Data(bits.content.dropFirst())
        switch oid {
        case "1.2.840.113549.1.1.1": return .rsa(pkcs1: key)
        case "1.2.840.10045.2.1":
            let curve = algorithm.children.dropFirst().first?.oid.map(OIDNames.name) ?? ""
            return .ec(curve: curve, x963: key)
        default: throw KeyError(description: "Unsupported key type \(OIDNames.name(oid))")
        }
    }

    static func jwk(_ object: [String: Any]) throws -> PublicKey {
        let field = { (name: String) throws -> Data in
            guard let text = object[name] as? String, let data = try? Base64.decode(text) else {
                throw KeyError(description: "The JWK is missing “\(name)”")
            }
            return data
        }
        switch object["kty"] as? String {
        case "RSA":
            let modulus = try field("n"), exponent = try field("e")
            let sequence = DERNode.encodeUnsignedInteger([UInt8](modulus)) + DERNode.encodeUnsignedInteger([UInt8](exponent))
            return .rsa(pkcs1: Data(DERNode.encode(tag: 0x30, sequence)))
        case "EC":
            let curve = object["crv"] as? String ?? ""
            return .ec(curve: curve, x963: Data([0x04]) + (try field("x")) + (try field("y")))
        case let other:
            throw KeyError(description: "Unsupported JWK type \(other ?? "(none)")")
        }
    }

    public static func verify(_ token: Decoded, publicKey text: String) -> Verification {
        guard let algorithm = token.algorithm else { return .unsupported("missing") }
        guard isAsymmetric(algorithm) else { return .unsupported(algorithm) }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .needsSecret }
        let key: PublicKey
        do { key = try publicKey(from: text, keyID: token.keyID) } catch { return .badKey("\(error)") }
        return verify(signingInput: Data(token.signingInput.utf8), signature: token.signatureBytes, algorithm: algorithm, key: key)
    }

    static func verify(signingInput: Data, signature: Data, algorithm: String, key: PublicKey) -> Verification {
        switch (algorithm.prefix(2), key) {
        case ("RS", .rsa(let pkcs1)), ("PS", .rsa(let pkcs1)):
            let pss = algorithm.hasPrefix("PS")
            let secAlgorithm: SecKeyAlgorithm
            switch (algorithm.dropFirst(2), pss) {
            case ("256", false): secAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
            case ("384", false): secAlgorithm = .rsaSignatureMessagePKCS1v15SHA384
            case ("512", false): secAlgorithm = .rsaSignatureMessagePKCS1v15SHA512
            case ("256", true): secAlgorithm = .rsaSignatureMessagePSSSHA256
            case ("384", true): secAlgorithm = .rsaSignatureMessagePSSSHA384
            case ("512", true): secAlgorithm = .rsaSignatureMessagePSSSHA512
            default: return .unsupported(algorithm)
            }
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
            guard let secKey = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else {
                return .badKey("The RSA key couldn't be read")
            }
            let valid = SecKeyVerifySignature(secKey, secAlgorithm, signingInput as CFData, signature as CFData, nil)
            return valid ? .verified : .mismatch
        case ("ES", .ec(let curve, let point)):
            do {
                switch algorithm {
                case "ES256":
                    guard ["P-256", ""].contains(curve) else { return .badKey("ES256 needs a P-256 key; this one is \(curve)") }
                    let key = try P256.Signing.PublicKey(x963Representation: point)
                    let signature = try P256.Signing.ECDSASignature(rawRepresentation: signature)
                    return key.isValidSignature(signature, for: signingInput) ? .verified : .mismatch
                case "ES384":
                    guard ["P-384", ""].contains(curve) else { return .badKey("ES384 needs a P-384 key; this one is \(curve)") }
                    let key = try P384.Signing.PublicKey(x963Representation: point)
                    let signature = try P384.Signing.ECDSASignature(rawRepresentation: signature)
                    return key.isValidSignature(signature, for: signingInput) ? .verified : .mismatch
                case "ES512":
                    guard ["P-521", ""].contains(curve) else { return .badKey("ES512 needs a P-521 key; this one is \(curve)") }
                    let key = try P521.Signing.PublicKey(x963Representation: point)
                    let signature = try P521.Signing.ECDSASignature(rawRepresentation: signature)
                    return key.isValidSignature(signature, for: signingInput) ? .verified : .mismatch
                default:
                    return .unsupported(algorithm)
                }
            } catch {
                // A malformed signature (wrong length) can't match.
                return signature.isEmpty ? .unsigned : .mismatch
            }
        case ("RS", _), ("PS", _):
            return .badKey("\(algorithm) needs an RSA public key")
        case ("ES", _):
            return .badKey("\(algorithm) needs an EC public key")
        default:
            return .unsupported(algorithm)
        }
    }
}
