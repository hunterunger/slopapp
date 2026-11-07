import CryptoKit
import Foundation

/// Decodes X.509 certificates (PEM or DER, one or a chain) into readable fields.
public enum CertificateDecoder {
    public struct Decoded: Sendable, Equatable {
        public var subject: String
        public var issuer: String
        public var commonName: String?
        public var serialNumber: String
        public var version: Int
        public var signatureAlgorithm: String
        public var notBefore: Date?
        public var notAfter: Date?
        public var publicKey: String
        public var subjectAltNames: [String]
        public var keyUsage: [String]
        public var extendedKeyUsage: [String]
        public var isCA: Bool?
        public var pathLength: Int?
        public var subjectKeyID: String?
        public var authorityKeyID: String?
        public var sha256Fingerprint: String
        public var sha1Fingerprint: String
        /// The SubjectPublicKeyInfo, for JWT verification.
        public var publicKeyInfo: Data
        public var isSelfSigned: Bool { subject == issuer }
    }

    public struct DecodeError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
    }

    /// All certificates in the text: PEM blocks, or Base64 DER without headers.
    public static func decodeAll(_ text: String) throws -> [Decoded] {
        let blocks = PEM.blocks(in: text).filter { $0.label.contains("CERTIFICATE") }
        if !blocks.isEmpty { return try blocks.map { try decode(der: $0.data) } }
        let compact = text.filter { !$0.isWhitespace }
        if let data = Data(base64Encoded: compact), data.first == 0x30 {
            return [try decode(der: data)]
        }
        throw DecodeError(description: "Paste a PEM certificate (-----BEGIN CERTIFICATE-----) or Base64 DER")
    }

    public static func decode(der data: Data) throws -> Decoded {
        let fail = DecodeError(description: "This isn't a valid X.509 certificate")
        guard let root = try? DERNode.parse(data), root.tag == 0x30, root.children.count >= 3 else { throw fail }
        let tbs = root.children[0]
        guard tbs.tag == 0x30 else { throw fail }
        var fields = tbs.children[...]
        var version = 1
        if let first = fields.first, first.contextNumber == 0 {
            if let inner = first.children.first, let byte = inner.content.last { version = Int(byte) + 1 }
            fields = fields.dropFirst()
        }
        let items = Array(fields)
        guard items.count >= 6 else { throw fail }
        let serial = items[0], issuerNode = items[2], validity = items[3], subjectNode = items[4], spki = items[5]
        let signatureAlgorithm = root.children[1].children.first?.oid ?? ""

        var decoded = Decoded(
            subject: distinguishedName(subjectNode), issuer: distinguishedName(issuerNode),
            commonName: attribute("2.5.4.3", in: subjectNode),
            serialNumber: serial.integerHex, version: version,
            signatureAlgorithm: OIDNames.name(signatureAlgorithm),
            notBefore: validity.children.first?.date, notAfter: validity.children.dropFirst().first?.date,
            publicKey: describeKey(spki), subjectAltNames: [], keyUsage: [], extendedKeyUsage: [],
            isCA: nil, pathLength: nil, subjectKeyID: nil, authorityKeyID: nil,
            sha256Fingerprint: hex(Data(SHA256.hash(data: data))),
            sha1Fingerprint: hex(Data(Insecure.SHA1.hash(data: data))),
            publicKeyInfo: spki.encoded
        )
        if let extensionsWrapper = items.dropFirst(6).first(where: { $0.contextNumber == 3 }),
           let list = extensionsWrapper.children.first {
            for ext in list.children {
                guard let id = ext.children.first?.oid, let valueNode = ext.children.last, valueNode.tag == 0x04,
                      let value = try? valueNode.parseContent() else { continue }
                apply(extension: id, value: value, to: &decoded)
            }
        }
        return decoded
    }

    static func apply(extension id: String, value: DERNode, to decoded: inout Decoded) {
        switch id {
        case "2.5.29.17": // subjectAltName
            decoded.subjectAltNames = value.children.compactMap { name in
                switch name.tag {
                case 0x82: "DNS: " + String(decoding: name.content, as: UTF8.self)
                case 0x81: "Email: " + String(decoding: name.content, as: UTF8.self)
                case 0x86: "URI: " + String(decoding: name.content, as: UTF8.self)
                case 0x87: "IP: " + ipAddress(name.content)
                default: nil
                }
            }
        case "2.5.29.19": // basicConstraints
            decoded.isCA = value.children.first { $0.tag == 0x01 }.map { $0.content.first != 0 } ?? false
            if let length = value.children.first(where: { $0.tag == 0x02 }) { decoded.pathLength = Int(length.content.last ?? 0) }
        case "2.5.29.15": // keyUsage (BIT STRING)
            let bytes = [UInt8](value.content.dropFirst())
            let names = ["Digital Signature", "Non-Repudiation", "Key Encipherment", "Data Encipherment", "Key Agreement",
                         "Certificate Sign", "CRL Sign", "Encipher Only", "Decipher Only"]
            for (bit, name) in names.enumerated() {
                let byte = bit / 8
                if byte < bytes.count, bytes[byte] & (0x80 >> UInt8(bit % 8)) != 0 { decoded.keyUsage.append(name) }
            }
        case "2.5.29.37": // extKeyUsage
            decoded.extendedKeyUsage = value.children.compactMap(\.oid).map(OIDNames.name)
        case "2.5.29.14": // subjectKeyIdentifier
            decoded.subjectKeyID = hex(value.content)
        case "2.5.29.35": // authorityKeyIdentifier
            if let key = value.children.first(where: { $0.tag == 0x80 }) { decoded.authorityKeyID = hex(key.content) }
        default: break
        }
    }

    static func distinguishedName(_ name: DERNode) -> String {
        name.children.flatMap { set in
            set.children.compactMap { pair -> String? in
                guard let oid = pair.children.first?.oid, let value = pair.children.last?.string else { return nil }
                return "\(OIDNames.shortName(oid))=\(value)"
            }
        }.joined(separator: ", ")
    }

    static func attribute(_ oid: String, in name: DERNode) -> String? {
        for set in name.children {
            for pair in set.children where pair.children.first?.oid == oid { return pair.children.last?.string }
        }
        return nil
    }

    static func describeKey(_ spki: DERNode) -> String {
        guard let algorithm = spki.children.first, let oid = algorithm.children.first?.oid else { return "Unknown" }
        switch oid {
        case "1.2.840.113549.1.1.1":
            if let bitString = spki.children.last, let key = try? bitString.parseContent(skipUnusedBitsByte: true),
               let modulus = key.children.first {
                return "RSA \(modulus.integerBitLength) bits"
            }
            return "RSA"
        case "1.2.840.10045.2.1":
            let curve = algorithm.children.dropFirst().first?.oid.map(OIDNames.name) ?? "unknown curve"
            return "EC \(curve)"
        default:
            return OIDNames.name(oid)
        }
    }

    static func ipAddress(_ data: Data) -> String {
        if data.count == 4 { return data.map(String.init).joined(separator: ".") }
        if data.count == 16 {
            return stride(from: 0, to: 16, by: 2).map { String(format: "%x", Int(data[data.startIndex + $0]) << 8 | Int(data[data.startIndex + $0 + 1])) }.joined(separator: ":")
        }
        return hex(data)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    public static func looksLikeCertificate(_ text: String) -> Bool {
        text.contains("-----BEGIN CERTIFICATE-----")
    }
}

enum OIDNames {
    static let names: [String: String] = [
        "1.2.840.113549.1.1.1": "RSA", "1.2.840.113549.1.1.5": "SHA-1 with RSA", "1.2.840.113549.1.1.11": "SHA-256 with RSA",
        "1.2.840.113549.1.1.12": "SHA-384 with RSA", "1.2.840.113549.1.1.13": "SHA-512 with RSA", "1.2.840.113549.1.1.10": "RSASSA-PSS",
        "1.2.840.10045.2.1": "EC", "1.2.840.10045.4.3.2": "ECDSA with SHA-256", "1.2.840.10045.4.3.3": "ECDSA with SHA-384",
        "1.2.840.10045.4.3.4": "ECDSA with SHA-512", "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384", "1.3.132.0.35": "P-521",
        "1.3.101.112": "Ed25519", "1.3.101.113": "Ed448",
        "1.3.6.1.5.5.7.3.1": "Server Authentication", "1.3.6.1.5.5.7.3.2": "Client Authentication",
        "1.3.6.1.5.5.7.3.3": "Code Signing", "1.3.6.1.5.5.7.3.4": "Email Protection", "1.3.6.1.5.5.7.3.8": "Time Stamping",
        "1.3.6.1.5.5.7.3.9": "OCSP Signing",
    ]
    static let short: [String: String] = [
        "2.5.4.3": "CN", "2.5.4.6": "C", "2.5.4.7": "L", "2.5.4.8": "ST", "2.5.4.10": "O", "2.5.4.11": "OU",
        "2.5.4.5": "serialNumber", "1.2.840.113549.1.9.1": "emailAddress", "0.9.2342.19200300.100.1.25": "DC",
        "2.5.4.9": "street", "2.5.4.17": "postalCode", "2.5.4.97": "organizationIdentifier",
    ]
    static func name(_ oid: String) -> String { names[oid] ?? oid }
    static func shortName(_ oid: String) -> String { short[oid] ?? oid }
}
