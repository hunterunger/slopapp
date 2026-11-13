import AppKit
import CoreText
import CryptoKit
import Foundation
import PDFKit
import Security

// MARK: Signers

/// Something that can sign: a certificate chain (signer first) and its private key.
/// The real one wraps a keychain identity; tests use an in-memory key and certificate.
public protocol CMSSigning: Sendable {
    /// DER certificates, the signer's first, then any intermediates.
    var certificates: [Data] { get }
    /// The signature algorithm's OID, for the CMS `SignerInfo`.
    var signatureAlgorithmOID: String { get }
    /// Signs `message` (SHA-256 is applied by the signer).
    func sign(_ message: Data) throws -> Data
}

public enum SigningError: Error, LocalizedError, Equatable {
    case noKey
    case unsupportedKey
    case signingFailed(String)
    case unreadable
    case encrypted
    case tooLarge
    case noPage

    public var errorDescription: String? {
        switch self {
        case .noKey: "The certificate's private key isn't available."
        case .unsupportedKey: "Paper can sign with RSA and elliptic-curve keys only."
        case .signingFailed(let reason): "The signature couldn't be made: \(reason)"
        case .unreadable: "Paper couldn't read this document to sign it."
        case .encrypted: "Password-protected PDFs can't be signed with a certificate yet. Save a copy without a password, then sign that."
        case .tooLarge: "The signature was larger than the space reserved for it."
        case .noPage: "The page for the signature wasn't found."
        }
    }
}

/// Signs with a `SecKey` (a keychain identity's key, a smart card's, or one made in memory).
public struct KeySigner: CMSSigning, @unchecked Sendable {
    public let key: SecKey
    public let certificates: [Data]

    public init(key: SecKey, certificates: [Data]) {
        self.key = key
        self.certificates = certificates
    }

    public init(identity: SecIdentity) throws {
        var key: SecKey?
        var certificate: SecCertificate?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key,
              SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { throw SigningError.noKey }
        var chain: [Data] = [SecCertificateCopyData(certificate) as Data]
        // Intermediates help viewers build the chain; the root is left out (they have it).
        var trust: SecTrust?
        if SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess, let trust {
            _ = SecTrustEvaluateWithError(trust, nil)
            let certs = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
            for cert in certs.dropFirst() {
                let der = SecCertificateCopyData(cert) as Data
                if let info = CertificateInfo(der: der), Self.isSelfIssued(info) { continue }
                chain.append(der)
            }
        }
        self.init(key: key, certificates: chain)
    }

    static func isSelfIssued(_ info: CertificateInfo) -> Bool {
        guard let certificate = DER.node(in: info.der, at: 0), let tbs = DER.children(of: certificate, in: info.der).first else { return false }
        var fields = DER.children(of: tbs, in: info.der)
        if fields.first?.tag == 0xA0 { fields.removeFirst() }
        guard fields.count >= 5 else { return false }
        return DER.bytes(fields[2].range, of: info.der) == DER.bytes(fields[4].range, of: info.der)
    }

    var isRSA: Bool {
        let attributes = SecKeyCopyAttributes(key) as? [CFString: Any]
        return (attributes?[kSecAttrKeyType] as? String) == (kSecAttrKeyTypeRSA as String)
    }

    public var signatureAlgorithmOID: String {
        isRSA ? "1.2.840.113549.1.1.11" : "1.2.840.10045.4.3.2" // sha256WithRSAEncryption / ecdsa-with-SHA256
    }

    public func sign(_ message: Data) throws -> Data {
        let algorithm: SecKeyAlgorithm = isRSA ? .rsaSignatureMessagePKCS1v15SHA256 : .ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else { throw SigningError.unsupportedKey }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm, message as CFData, &error) as Data? else {
            let reason = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "unknown error"
            throw SigningError.signingFailed(reason)
        }
        return signature
    }
}

// MARK: CMS

/// Builds a detached CMS `SignedData` (RFC 5652) with the attributes PAdES baseline
/// signatures need: content type, signing time, message digest and the signing
/// certificate's hash (ESS signing-certificate-v2), so the signature can't be moved to
/// another certificate.
public enum CMS {
    static let data = "1.2.840.113549.1.7.1"
    static let signedData = "1.2.840.113549.1.7.2"
    static let sha256 = "2.16.840.1.101.3.4.2.1"
    static let contentType = "1.2.840.113549.1.9.3"
    static let messageDigest = "1.2.840.113549.1.9.4"
    static let signingTime = "1.2.840.113549.1.9.5"
    static let signingCertificateV2 = "1.2.840.113549.1.9.16.2.47"

    public static func signedData(digest: Data, signer: any CMSSigning, date: Date) throws -> Data {
        guard let certificate = signer.certificates.first, let info = CertificateInfo(der: certificate) else { throw SigningError.noKey }
        let sha256Algorithm = DER.sequence([DER.oid(sha256)])
        func attribute(_ oid: String, _ value: Data) -> Data { DER.sequence([DER.oid(oid), DER.set([value])]) }
        let certHash = Data(SHA256.hash(data: certificate))
        let essCertID = DER.sequence([DER.octetString(certHash)])
        let attributes = [
            attribute(contentType, DER.oid(data)),
            attribute(signingTime, DER.utcTime(date)),
            attribute(messageDigest, DER.octetString(digest)),
            attribute(signingCertificateV2, DER.sequence([DER.sequence([essCertID])])),
        ]
        // The signature covers the attributes encoded as a SET; in the SignerInfo they're
        // written with the [0] tag instead.
        let signedSet = DER.set(attributes)
        let signature = try signer.sign(signedSet)
        var signedAttributes = signedSet
        signedAttributes[signedAttributes.startIndex] = 0xA0
        let algorithm = signer.signatureAlgorithmOID == "1.2.840.10045.4.3.2"
            ? DER.sequence([DER.oid(signer.signatureAlgorithmOID)])
            : DER.sequence([DER.oid(signer.signatureAlgorithmOID), DER.null])
        let signerInfo = DER.sequence([
            DER.integer(1),
            DER.sequence([info.issuer, info.serial]),
            sha256Algorithm,
            signedAttributes,
            algorithm,
            DER.octetString(signature),
        ])
        let content = DER.sequence([
            DER.integer(1),
            DER.set([sha256Algorithm]),
            DER.sequence([DER.oid(data)]),
            DER.implicit(0, constructed: signer.certificates.reduce(Data(), +)),
            DER.set([signerInfo]),
        ])
        return DER.sequence([DER.oid(signedData), DER.explicit(0, content)])
    }
}

// MARK: Placing a signature

/// Where the signature goes, and what it says.
public struct SignatureRequest: Sendable {
    public enum Placement: Sendable, Equatable {
        /// A new signature field: page index (0-based) and rectangle in page space.
        case new(page: Int, rect: CGRect)
        /// An existing empty signature field, by its full name.
        case field(String)
    }

    public var placement: Placement
    public var signerName: String
    public var reason: String
    public var location: String
    public var date: Date
    /// Ink strokes (in 0…1 space, y up, width 1) shown beside the text, e.g. a saved
    /// handwritten signature. Empty for text only.
    public var ink: [[CGPoint]]
    public var inkAspect: CGFloat

    public init(placement: Placement, signerName: String, reason: String = "", location: String = "", date: Date = Date(),
                ink: [[CGPoint]] = [], inkAspect: CGFloat = 3) {
        self.placement = placement
        self.signerName = signerName
        self.reason = reason
        self.location = location
        self.date = date
        self.ink = ink
        self.inkAspect = inkAspect
    }
}

/// Signs a PDF with a byte-range signature appended as an incremental update, so the
/// bytes before it (and any earlier signatures) are untouched.
public enum PDFSigner {
    /// Space for the CMS blob. Doubled and retried if a long certificate chain needs more.
    static let initialReserve = 12_288

    public static func sign(_ pdf: Data, request: SignatureRequest, signer: any CMSSigning) throws -> Data {
        var reserve = initialReserve
        while true {
            do {
                return try sign(pdf, request: request, signer: signer, reserve: reserve)
            } catch SigningError.tooLarge where reserve < 200_000 {
                reserve *= 2
            }
        }
    }

    static let byteRangePlaceholder: PDFObject = .array([.int(0), .int(1_111_111_111), .int(2_222_222_222), .int(3_333_333_333)])

    static func sign(_ pdf: Data, request: SignatureRequest, signer: any CMSSigning, reserve: Int) throws -> Data {
        let file: PDFFile
        do { file = try PDFFile(data: pdf) } catch { throw SigningError.unreadable }
        guard !file.isEncrypted else { throw SigningError.encrypted }
        guard let root = file.rootRef, var catalog = try? file.object(root.0).dictValue else { throw SigningError.unreadable }
        var update = IncrementalUpdate(file)

        // The signature dictionary.
        var signature = PDFDict()
        signature["Type"] = .name("Sig")
        signature["Filter"] = .name("Adobe.PPKLite")
        signature["SubFilter"] = .name("ETSI.CAdES.detached")
        signature["ByteRange"] = byteRangePlaceholder
        signature["Contents"] = .string(Data(count: reserve), hex: true)
        signature["M"] = .string(Data(PDFDate.string(request.date).utf8))
        signature["Name"] = .text(request.signerName)
        if !request.reason.isEmpty { signature["Reason"] = .text(request.reason) }
        if !request.location.isEmpty { signature["Location"] = .text(request.location) }
        signature["Prop_Build"] = .dict(PDFDict([("App", .dict(PDFDict([("Name", .name("Paper"))])))]))
        let signatureRef = update.add(.dict(signature))

        // The form.
        var form = file.dict(catalog["AcroForm"]) ?? PDFDict()
        var fields = form["Fields"].flatMap { try? file.resolve($0).arrayValue } ?? []
        let pages = file.pageRefs()

        let widgetNumber: Int
        let rect: CGRect
        switch request.placement {
        case .field(let name):
            guard let (number, dict) = findField(named: name, in: fields, file: file), let fieldRect = AcroFormWriter.rect(dict["Rect"]) else {
                throw SigningError.noPage
            }
            var widget = dict
            widget["V"] = signatureRef
            widget["F"] = .int(132) // print + locked
            rect = fieldRect
            let appearance = StreamFilters.deflate(SignatureAppearance.stream(request, size: rect.size)) ?? Data()
            widget["AP"] = .dict(PDFDict([("N", update.add(appearanceDict(rect.size), stream: appearance))]))
            update.replace(number, with: .dict(widget))
            widgetNumber = number
        case .new(let pageIndex, let placementRect):
            guard pages.indices.contains(pageIndex), var page = file.dict(.ref(pages[pageIndex].0, pages[pageIndex].1)) else { throw SigningError.noPage }
            rect = placementRect.standardized
            let existingNames = Set(fields.compactMap { file.dict($0)?["T"]?.textValue })
            var number = 1
            while existingNames.contains("Signature \(number)") { number += 1 }
            let appearance = StreamFilters.deflate(SignatureAppearance.stream(request, size: rect.size)) ?? Data()
            let apRef = update.add(appearanceDict(rect.size), stream: appearance)
            let widget = PDFDict([
                ("Type", .name("Annot")), ("Subtype", .name("Widget")), ("FT", .name("Sig")),
                ("T", .text("Signature \(number)")), ("V", signatureRef),
                ("Rect", .array([rect.minX, rect.minY, rect.maxX, rect.maxY].map { .real(Double($0)) })),
                ("F", .int(132)), ("P", .ref(pages[pageIndex].0, pages[pageIndex].1)),
                ("AP", .dict(PDFDict([("N", apRef)]))),
            ])
            let widgetRef = update.add(.dict(widget))
            guard case .ref(let n, _) = widgetRef else { throw SigningError.unreadable }
            widgetNumber = n
            fields.append(widgetRef)
            // Add the widget to the page's annotations.
            var annots = page["Annots"].flatMap { try? file.resolve($0).arrayValue } ?? []
            annots.append(widgetRef)
            if case .ref(let annotsNumber, _) = page["Annots"] {
                update.replace(annotsNumber, with: .array(annots))
            } else {
                page["Annots"] = .array(annots)
                update.replace(pages[pageIndex].0, with: .dict(page))
            }
        }
        _ = widgetNumber
        _ = rect

        form["Fields"] = .array(fields)
        form["SigFlags"] = .int(3)
        if case .ref(let formNumber, _) = catalog["AcroForm"] {
            update.replace(formNumber, with: .dict(form))
        } else {
            catalog["AcroForm"] = update.add(.dict(form))
            update.replace(root.0, with: .dict(catalog))
        }

        // Write, then fill in the byte range and the signature.
        var output = update.write()
        let appended = pdf.count..<output.count
        let placeholderText = Data(PDFWriter.serialize(byteRangePlaceholder))
        guard let rangeSpot = output.range(of: placeholderText, in: appended),
              let contentsStart = output.range(of: Data("/Contents <".utf8), in: rangeSpot.upperBound..<output.count)
                ?? output.range(of: Data("/Contents <".utf8), in: appended) else { throw SigningError.unreadable }
        let hexStart = contentsStart.upperBound - 1 // the "<"
        let hexEnd = hexStart + 2 + reserve * 2      // after the ">"
        let ranges = [0, hexStart, hexEnd, output.count - hexEnd]
        var rangeText = "[" + ranges.map(String.init).joined(separator: " ") + "]"
        guard rangeText.utf8.count <= placeholderText.count else { throw SigningError.unreadable }
        rangeText += String(repeating: " ", count: placeholderText.count - rangeText.utf8.count)
        output.replaceSubrange(rangeSpot, with: Data(rangeText.utf8))

        var hasher = SHA256()
        hasher.update(data: output.subdata(in: 0..<hexStart))
        hasher.update(data: output.subdata(in: hexEnd..<output.count))
        let digest = Data(hasher.finalize())
        let cms = try CMS.signedData(digest: digest, signer: signer, date: request.date)
        guard cms.count <= reserve else { throw SigningError.tooLarge }
        let hex = cms.map { String(format: "%02X", $0) }.joined() + String(repeating: "0", count: (reserve - cms.count) * 2)
        output.replaceSubrange((hexStart + 1)..<(hexEnd - 1), with: Data(hex.utf8))
        return output
    }

    static func findField(named name: String, in fields: [PDFObject], file: PDFFile) -> (Int, PDFDict)? {
        var visited = Set<Int>()
        func visit(_ object: PDFObject, prefix: String) -> (Int, PDFDict)? {
            guard let ref = object.refValue, !visited.contains(ref.0), let dict = file.dict(object) else { return nil }
            visited.insert(ref.0)
            let full = [prefix, dict["T"]?.textValue ?? ""].filter { !$0.isEmpty }.joined(separator: ".")
            if full == name, dict["Subtype"]?.nameValue == "Widget" { return (ref.0, dict) }
            for kid in dict["Kids"].flatMap({ try? file.resolve($0).arrayValue }) ?? [] {
                if let found = visit(kid, prefix: full) { return found }
            }
            return nil
        }
        for field in fields { if let found = visit(field, prefix: "") { return found } }
        return nil
    }

    static func appearanceDict(_ size: CGSize) -> PDFObject {
        .dict(PDFDict([("Type", .name("XObject")), ("Subtype", .name("Form")),
                       ("BBox", .array([.int(0), .int(0), .real(Double(size.width)), .real(Double(size.height))])),
                       ("Resources", .dict(PDFDict([("Font", .dict(PDFDict([("Helv", .dict(PDFDict([
                           ("Type", .name("Font")), ("Subtype", .name("Type1")), ("BaseFont", .name("Helvetica")),
                           ("Encoding", .name("WinAnsiEncoding"))])))])))]))),
                       ("Filter", .name("FlateDecode"))]))
    }
}

public enum PDFDate {
    /// `D:20261110154500-06'00'`
    public static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMddHHmmss"
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        return "D:" + formatter.string(from: date) + String(format: "%@%02d'%02d'", sign, hours, minutes)
    }

    public static func parse(_ text: String) -> Date? {
        var digits = text.hasPrefix("D:") ? String(text.dropFirst(2)) : text
        let zone = digits.dropFirst(14)
        digits = String(digits.prefix(14))
        guard digits.count >= 8 else { return nil }
        digits += String("00000101000000".suffix(14 - digits.count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        var offset = 0
        if let first = zone.first, first == "+" || first == "-" {
            let parts = zone.dropFirst().split(separator: "'").compactMap { Int($0) }
            offset = ((parts.first ?? 0) * 3600 + (parts.dropFirst().first ?? 0) * 60) * (first == "-" ? -1 : 1)
        }
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        return formatter.date(from: digits)
    }
}

/// The visible part of a signature: the signer's handwritten ink (if any) or name, and the
/// details beside it. Text is drawn as outlines, so it shows in every viewer and any
/// script without embedding a font.
public enum SignatureAppearance {
    public static func lines(_ request: SignatureRequest) -> [String] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var lines = ["Digitally signed by \(request.signerName)", "Date: \(formatter.string(from: request.date))"]
        if !request.reason.isEmpty { lines.append("Reason: \(request.reason)") }
        if !request.location.isEmpty { lines.append("Location: \(request.location)") }
        return lines
    }

    public static func stream(_ request: SignatureRequest, size: CGSize) -> Data {
        var ops: [String] = ["q 0.1 0.15 0.35 rg 0.1 0.15 0.35 RG"]
        let width = size.width, height = size.height
        let wide = width > height * 2.2
        let left = wide ? CGRect(x: 4, y: 4, width: width * 0.45 - 8, height: height - 8)
            : CGRect(x: 4, y: height * 0.45, width: width - 8, height: height * 0.55 - 4)
        let right = wide ? CGRect(x: width * 0.45 + 2, y: 4, width: width * 0.55 - 6, height: height - 8)
            : CGRect(x: 4, y: 4, width: width - 8, height: height * 0.45 - 6)
        if !request.ink.isEmpty {
            let fit = Signature.fitted(aspect: request.inkAspect, in: left)
            let lineWidth = max(0.8, min(2.2, fit.width / 90))
            ops.append("\(PDFWriter.number(Double(lineWidth))) w 1 J 1 j")
            for stroke in request.ink where stroke.count > 1 {
                let points = stroke.map { CGPoint(x: fit.minX + $0.x * fit.width, y: fit.minY + $0.y * fit.width) }
                ops.append(pathOps(InkSmoothing.path(through: points, lineWidth: lineWidth).cgPath) + " S")
            }
        } else {
            ops.append(textOps(request.signerName, in: left, font: "Snell Roundhand", maxSize: left.height * 0.7))
        }
        let lines = lines(request)
        let lineHeight = min(right.height / CGFloat(lines.count), 11)
        for (index, line) in lines.enumerated() {
            let box = CGRect(x: right.minX, y: right.maxY - lineHeight * CGFloat(index + 1), width: right.width, height: lineHeight)
            ops.append(standardTextOps(line, in: box, maxSize: lineHeight * 0.85)
                ?? textOps(line, in: box, font: "Helvetica", maxSize: lineHeight * 0.85))
        }
        ops.append("Q")
        return Data(ops.joined(separator: "\n").utf8)
    }

    /// Text in the standard Helvetica font (nothing embedded), when every character is in
    /// WinAnsi. Nil otherwise, and the text is drawn as outlines instead.
    static func standardTextOps(_ text: String, in box: CGRect, maxSize: CGFloat) -> String? {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F || ($0.value >= 0xA0 && $0.value <= 0xFF) }) else { return nil }
        var size = max(4, maxSize)
        let measure = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: measure])), nil, nil, nil)
        if width > box.width { size = max(3, size * box.width / width) }
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let baseline = box.minY + (box.height - CTFontGetAscent(font) - CTFontGetDescent(font)) / 2 + CTFontGetDescent(font)
        let bytes = Data(text.unicodeScalars.map { UInt8($0.value) })
        let literal = String(decoding: PDFWriter.serialize(.string(bytes)), as: UTF8.self)
        func n(_ value: CGFloat) -> String { PDFWriter.number((Double(value) * 100).rounded() / 100) }
        return "BT /Helv \(n(size)) Tf \(n(box.minX)) \(n(baseline)) Td \(literal) Tj ET"
    }

    /// Text as filled outlines, shrunk to fit `box`, left-aligned on its baseline.
    static func textOps(_ text: String, in box: CGRect, font name: String, maxSize: CGFloat) -> String {
        guard !text.isEmpty, box.width > 1, box.height > 1 else { return "" }
        var size = max(4, maxSize)
        var font = CTFontCreateWithName(name as CFString, size, nil)
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        if width > box.width {
            size = max(3, size * box.width / width)
            font = CTFontCreateWithName(name as CFString, size, nil)
            line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        }
        let path = CGMutablePath()
        let baseline = box.minY + (box.height - CTFontGetAscent(font) - CTFontGetDescent(font)) / 2 + CTFontGetDescent(font)
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attributes[kCTFontAttributeName] as! CTFont?) ?? font
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                path.addPath(glyph, transform: CGAffineTransform(translationX: box.minX + positions[index].x, y: baseline + positions[index].y))
            }
        }
        return pathOps(path) + " f"
    }

    static func pathOps(_ path: CGPath) -> String {
        var ops: [String] = []
        var current = CGPoint.zero
        // Hundredths of a point are far below what any printer resolves.
        func n(_ value: CGFloat) -> String { PDFWriter.number((Double(value) * 100).rounded() / 100) }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                let p = element.points[0]
                ops.append("\(n(p.x)) \(n(p.y)) m")
                current = p
            case .addLineToPoint:
                let p = element.points[0]
                ops.append("\(n(p.x)) \(n(p.y)) l")
                current = p
            case .addQuadCurveToPoint:
                let c = element.points[0], p = element.points[1]
                let c1 = CGPoint(x: current.x + 2 / 3 * (c.x - current.x), y: current.y + 2 / 3 * (c.y - current.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
                ops.append("\(n(c1.x)) \(n(c1.y)) \(n(c2.x)) \(n(c2.y)) \(n(p.x)) \(n(p.y)) c")
                current = p
            case .addCurveToPoint:
                let c1 = element.points[0], c2 = element.points[1], p = element.points[2]
                ops.append("\(n(c1.x)) \(n(c1.y)) \(n(c2.x)) \(n(c2.y)) \(n(p.x)) \(n(p.y)) c")
                current = p
            case .closeSubpath:
                ops.append("h")
            @unknown default:
                break
            }
        }
        return ops.joined(separator: " ")
    }
}

// MARK: Validation

/// What Paper found out about one signature in a document.
public struct SignatureStatus: Sendable, Equatable, Identifiable {
    public enum Integrity: Sendable, Equatable {
        /// The signed bytes are unchanged.
        case intact
        /// The signature doesn't match the bytes it covers: the document was altered.
        case altered
        /// Paper can't check this kind of signature.
        case unsupported(String)
        /// The signature data is damaged.
        case malformed
    }

    public var id: Int { index }
    public var index: Int
    public var fieldName: String
    public var signerName: String
    public var date: Date?
    public var reason: String?
    public var location: String?
    public var integrity: Integrity
    /// The signer's certificate chains to a root this Mac trusts.
    public var trusted: Bool
    public var trustProblem: String?
    /// The signature covers the whole file as it is now (nothing was added after it).
    public var coversWholeFile: Bool
    public var certificate: Data?
    public var issuerName: String?

    public var isValid: Bool { integrity == .intact }

    /// One line for the info bar and the inspector.
    public var summary: String {
        switch integrity {
        case .altered: return "The document was changed after \(signerName) signed it. This signature is no longer valid."
        case .malformed: return "This signature is damaged and can't be checked."
        case .unsupported(let kind): return "Paper can't check this kind of signature (\(kind))."
        case .intact:
            var text = "Signed by \(signerName)"
            if let date { text += " on \(date.formatted(date: .abbreviated, time: .shortened))" }
            text += "."
            if !coversWholeFile { text += " Changes were added to the file after this signature." }
            else { text += " The document hasn't changed since." }
            if !trusted { text += " The certificate isn't from an authority this Mac trusts." }
            return text
        }
    }
}

public enum SignatureValidator {
    /// Every signature in a PDF, in signing order, with its status.
    public static func validate(_ data: Data) -> [SignatureStatus] {
        guard let file = try? PDFFile(data: data), let root = file.rootRef,
              let catalog = try? file.object(root.0).dictValue, let form = file.dict(catalog["AcroForm"]) else { return [] }
        var found: [(String, PDFDict)] = []
        var visited = Set<Int>()
        func visit(_ object: PDFObject, prefix: String) {
            guard let ref = object.refValue, !visited.contains(ref.0), let dict = file.dict(object) else { return }
            visited.insert(ref.0)
            let name = [prefix, dict["T"]?.textValue ?? ""].filter { !$0.isEmpty }.joined(separator: ".")
            let type = dict["FT"]?.nameValue
            if type == "Sig" || (type == nil && dict["V"] != nil && file.dict(dict["V"])?["ByteRange"] != nil),
               let value = file.dict(dict["V"]), value["ByteRange"] != nil {
                found.append((name, value))
            }
            for kid in dict["Kids"].flatMap({ try? file.resolve($0).arrayValue }) ?? [] { visit(kid, prefix: name) }
        }
        for field in form["Fields"].flatMap({ try? file.resolve($0).arrayValue }) ?? [] { visit(field, prefix: "") }
        let statuses = found.enumerated().map { index, item in status(index: index, field: item.0, signature: item.1, data: data) }
        // Signing order: by where each signature's covered range ends.
        return statuses.sorted { ($0.coversWholeFile ? 1 : 0, $0.index) < ($1.coversWholeFile ? 1 : 0, $1.index) }
    }

    static func status(index: Int, field: String, signature: PDFDict, data: Data) -> SignatureStatus {
        var result = SignatureStatus(index: index, fieldName: field, signerName: signature["Name"]?.textValue ?? "Unknown signer",
                                     date: signature["M"]?.textValue.flatMap(PDFDate.parse),
                                     reason: signature["Reason"]?.textValue, location: signature["Location"]?.textValue,
                                     integrity: .malformed, trusted: false, trustProblem: nil, coversWholeFile: false)
        let ranges = (signature["ByteRange"]?.arrayValue ?? []).compactMap(\.intValue)
        guard ranges.count == 4, ranges[0] == 0, ranges[1] >= 0, ranges[2] >= ranges[1], ranges[2] + ranges[3] <= data.count,
              let contents = signature["Contents"]?.stringValue else { return result }
        result.coversWholeFile = ranges[2] + ranges[3] == data.count
        let subFilter = signature["SubFilter"]?.nameValue ?? ""
        guard ["adbe.pkcs7.detached", "ETSI.CAdES.detached"].contains(subFilter) else {
            result.integrity = .unsupported(subFilter.isEmpty ? "unknown" : subFilter)
            return result
        }
        // The hex string is padded with zeros after the DER blob.
        guard let outer = DER.node(in: contents, at: 0) else { return result }
        let cms = DER.bytes(outer.range, of: contents)
        var signed = data.subdata(in: (data.startIndex + ranges[0])..<(data.startIndex + ranges[1]))
        signed.append(data.subdata(in: (data.startIndex + ranges[2])..<(data.startIndex + ranges[2] + ranges[3])))

        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { return result }
        let status = cms.withUnsafeBytes { CMSDecoderUpdateMessage(decoder, $0.baseAddress!, cms.count) }
        guard status == errSecSuccess, CMSDecoderSetDetachedContent(decoder, signed as CFData) == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return result }
        var signerCount = 0
        CMSDecoderGetNumSigners(decoder, &signerCount)
        guard signerCount > 0 else { return result }
        var signerStatus = CMSSignerStatus.unsigned
        var trust: SecTrust?
        var verifyCode: OSStatus = 0
        CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &signerStatus, &trust, &verifyCode)
        switch signerStatus {
        case .valid: result.integrity = .intact
        case .invalidSignature, .invalidCert: result.integrity = .altered
        default: result.integrity = .malformed
        }
        var signingTime = CFAbsoluteTime()
        if CMSDecoderCopySignerSigningTime(decoder, 0, &signingTime) == errSecSuccess {
            result.date = Date(timeIntervalSinceReferenceDate: signingTime)
        }
        var certificate: SecCertificate?
        if CMSDecoderCopySignerCert(decoder, 0, &certificate) == errSecSuccess, let certificate {
            result.certificate = SecCertificateCopyData(certificate) as Data
            if let summary = SecCertificateCopySubjectSummary(certificate) as String? { result.signerName = summary }
        }
        if let trust {
            var error: CFError?
            result.trusted = SecTrustEvaluateWithError(trust, &error)
            if !result.trusted { result.trustProblem = error.map { CFErrorCopyDescription($0) as String } }
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count > 1 {
                result.issuerName = SecCertificateCopySubjectSummary(chain[1]) as String?
            }
        }
        return result
    }
}

// MARK: Identities

/// A certificate with a private key, ready to sign.
public struct SigningIdentity: Identifiable, @unchecked Sendable {
    public var id: Data { certificate }
    public let identity: SecIdentity
    public let certificate: Data
    public let name: String
    public let issuer: String?
    public let expires: Date?
    public let email: String?

    public var isExpired: Bool { (expires ?? .distantFuture) < Date() }

    public init(identity: SecIdentity) throws {
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { throw SigningError.noKey }
        self.identity = identity
        certificate = SecCertificateCopyData(cert) as Data
        name = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Certificate"
        var emails: CFArray?
        SecCertificateCopyEmailAddresses(cert, &emails)
        email = (emails as? [String])?.first
        let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotAfter, kSecOIDX509V1IssuerName] as CFArray, nil) as? [CFString: Any]
        if let notAfter = values?[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any], let value = notAfter[kSecPropertyKeyValue] as? NSNumber {
            expires = Date(timeIntervalSinceReferenceDate: value.doubleValue)
        } else {
            expires = nil
        }
        if let issuerValue = values?[kSecOIDX509V1IssuerName] as? [CFString: Any],
           let parts = issuerValue[kSecPropertyKeyValue] as? [[CFString: Any]],
           let cn = parts.first(where: { ($0[kSecPropertyKeyLabel] as? String) == (kSecOIDCommonName as String) })?[kSecPropertyKeyValue] as? String {
            issuer = cn
        } else {
            issuer = nil
        }
    }

    /// Certificates only usable for code signing (developer identities) aren't offered.
    static func isCodeSigningOnly(_ cert: SecCertificate) -> Bool {
        guard let values = SecCertificateCopyValues(cert, [kSecOIDExtendedKeyUsage] as CFArray, nil) as? [CFString: Any],
              let usage = values[kSecOIDExtendedKeyUsage] as? [CFString: Any],
              let list = usage[kSecPropertyKeyValue] as? [Data] else { return false }
        let codeSigning = DER.oid("1.3.6.1.5.5.7.3.3").dropFirst(2)
        return !list.isEmpty && list.allSatisfy { $0 == Data(codeSigning) }
    }
}

/// Lists the identities Paper can sign with. The real one asks the keychain; tests can point
/// it at a separate keychain file (`PAPER_SIGNING_KEYCHAIN`) so the login keychain is never
/// touched.
public enum IdentityStore {
    public static func identities(keychainPath: String? = ProcessInfo.processInfo.environment["PAPER_SIGNING_KEYCHAIN"]) -> [SigningIdentity] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnRef: true,
        ]
        if let keychainPath {
            var keychain: SecKeychain?
            guard SecKeychainOpen(keychainPath, &keychain) == errSecSuccess, let keychain else { return [] }
            query[kSecMatchSearchList] = [keychain]
        }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [SecIdentity] else { return [] }
        return items.compactMap { identity in
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert, !SigningIdentity.isCodeSigningOnly(cert) else { return nil }
            return try? SigningIdentity(identity: identity)
        }
        .sorted { ($0.isExpired ? 1 : 0, $0.name) < ($1.isExpired ? 1 : 0, $1.name) }
    }
}
