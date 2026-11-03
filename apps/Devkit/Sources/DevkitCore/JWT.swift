import CryptoKit
import Foundation

/// Decodes JSON Web Tokens (RFC 7519) locally and verifies HMAC signatures (HS256/384/512).
/// Never sends anything anywhere.
public enum JWT {
    public struct Decoded: Sendable, Equatable {
        /// Pretty-printed header and payload, key order kept.
        public var header: String
        public var payload: String
        public var algorithm: String?
        public var type: String?
        public var keyID: String?
        public var claims: [Claim]
        /// The third segment as written (base64url).
        public var signature: String
        /// `header.payload`, the bytes the signature covers.
        public var signingInput: String
        public var signatureBytes: Data

        public var expiresAt: Date? { claims.first { $0.name == "exp" }?.date }
        public var notBefore: Date? { claims.first { $0.name == "nbf" }?.date }
        public var issuedAt: Date? { claims.first { $0.name == "iat" }?.date }
    }

    public struct Claim: Sendable, Equatable, Identifiable {
        public var name: String
        public var meaning: String
        /// The value as JSON text (strings keep their quotes off).
        public var value: String
        public var date: Date?
        public var id: String { name }
    }

    public enum DecodeError: Error, Equatable, Sendable, CustomStringConvertible {
        case notThreeParts(Int)
        case encrypted
        case badSegment(String)
        case notJSON(String, String)

        public var description: String {
            switch self {
            case let .notThreeParts(count):
                "A JWT has three parts separated by dots (header.payload.signature); this has \(count)."
            case .encrypted:
                "This is an encrypted token (JWE, five parts). Only signed tokens can be decoded without the key."
            case let .badSegment(part):
                "The \(part) isn't valid base64url."
            case let .notJSON(part, reason):
                "The \(part) isn't JSON: \(reason)"
            }
        }
    }

    public enum Validity: Sendable, Equatable {
        case expired(Date)
        case notYetValid(Date)
        case valid(until: Date)
        case noExpiry
    }

    public enum Verification: Sendable, Equatable {
        case verified
        case mismatch
        case unsigned
        case unsupported(String)
        case needsSecret
    }

    static let registered: [(String, String)] = [
        ("iss", "Issuer"), ("sub", "Subject"), ("aud", "Audience"), ("exp", "Expires"),
        ("nbf", "Not before"), ("iat", "Issued at"), ("jti", "Token ID"),
    ]
    static let dateClaims: Set<String> = ["exp", "nbf", "iat", "auth_time", "updated_at"]

    public static func decode(_ token: String) throws -> Decoded {
        var text = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("bearer ") { text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 5 { throw DecodeError.encrypted }
        guard parts.count == 3 else { throw DecodeError.notThreeParts(parts.count) }
        guard let headerData = try? Base64.decode(parts[0]) else { throw DecodeError.badSegment("header") }
        guard let payloadData = try? Base64.decode(parts[1]) else { throw DecodeError.badSegment("payload") }
        let signatureBytes: Data
        if parts[2].isEmpty {
            signatureBytes = Data()
        } else {
            guard let bytes = try? Base64.decode(parts[2]) else { throw DecodeError.badSegment("signature") }
            signatureBytes = bytes
        }
        let headerText = String(decoding: headerData, as: UTF8.self)
        let payloadText = String(decoding: payloadData, as: UTF8.self)
        let header: String
        let payload: String
        do { header = try JSONFormatter.format(headerText).text } catch { throw DecodeError.notJSON("header", "\(error)") }
        do { payload = try JSONFormatter.format(payloadText).text } catch { throw DecodeError.notJSON("payload", "\(error)") }

        let headerObject = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any] ?? [:]
        let payloadObject = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] ?? [:]

        var claims: [Claim] = []
        for (name, meaning) in registered {
            guard let value = payloadObject[name] else { continue }
            claims.append(Claim(name: name, meaning: meaning, value: display(value),
                                date: dateClaims.contains(name) ? numericDate(value) : nil))
        }
        for name in ["auth_time", "updated_at"] {
            if let value = payloadObject[name], let date = numericDate(value) {
                claims.append(Claim(name: name, meaning: name == "auth_time" ? "Authenticated" : "Updated", value: display(value), date: date))
            }
        }

        return Decoded(
            header: header, payload: payload,
            algorithm: headerObject["alg"] as? String, type: headerObject["typ"] as? String,
            keyID: headerObject["kid"] as? String, claims: claims,
            signature: parts[2], signingInput: parts[0] + "." + parts[1], signatureBytes: signatureBytes
        )
    }

    /// True when `text` is shaped like a JWT whose header is JSON with an `alg`.
    public static func looksLikeToken(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count >= 4, parts[1].count >= 2 else { return false }
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=")
        guard parts.allSatisfy({ $0.allSatisfy(alphabet.contains) }) else { return false }
        guard let header = try? Base64.decode(String(parts[0])),
              let object = (try? JSONSerialization.jsonObject(with: header)) as? [String: Any] else { return false }
        return object["alg"] is String
    }

    public static func validity(of token: Decoded, now: Date) -> Validity {
        if let notBefore = token.notBefore, now < notBefore { return .notYetValid(notBefore) }
        guard let expires = token.expiresAt else { return .noExpiry }
        return now >= expires ? .expired(expires) : .valid(until: expires)
    }

    /// Checks an HMAC signature. `secret` is the raw key bytes.
    public static func verify(_ token: Decoded, secret: Data) -> Verification {
        guard let algorithm = token.algorithm else { return .unsupported("missing") }
        if algorithm.lowercased() == "none" { return .unsigned }
        guard algorithm.hasPrefix("HS") else { return .unsupported(algorithm) }
        guard !secret.isEmpty else { return .needsSecret }
        let key = SymmetricKey(data: secret)
        let message = Data(token.signingInput.utf8)
        let expected: Data
        switch algorithm {
        case "HS256": expected = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case "HS384": expected = Data(HMAC<SHA384>.authenticationCode(for: message, using: key))
        case "HS512": expected = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        default: return .unsupported(algorithm)
        }
        return constantTimeEqual(expected, token.signatureBytes) ? .verified : .mismatch
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    static func numericDate(_ value: Any) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }

    static func display(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) {
            return String(decoding: data, as: UTF8.self)
        }
        return "\(value)"
    }
}
