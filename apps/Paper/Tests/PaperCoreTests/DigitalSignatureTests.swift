import AppKit
import CryptoKit
import PDFKit
import Security
import Testing
@testable import PaperCore
import PaperFixtures

@Suite("Certificate signatures")
struct DigitalSignatureTests {
    static let signer = TestSigner.make()!

    static func source() -> Data {
        PDFDocument(data: Fixtures.textDocument(pages: 2))!.dataRepresentation()!
    }

    static func signed(_ data: Data = source(), placement: SignatureRequest.Placement = .new(page: 0, rect: CGRect(x: 320, y: 80, width: 220, height: 60)),
                       name: String = "Paper Test Signer") throws -> Data {
        let request = SignatureRequest(placement: placement, signerName: name, reason: "I approve", location: "Testing",
                                       date: Date(timeIntervalSince1970: 1_800_000_000))
        return try PDFSigner.sign(data, request: request, signer: signer)
    }

    @Test func certificateParses() throws {
        let der = try #require(Self.signer.certificates.first)
        #expect(SecCertificateCreateWithData(nil, der as CFData) != nil)
        let info = try #require(CertificateInfo(der: der))
        #expect(info.issuer.first == DER.Tag.sequence)
        #expect(info.serial.first == DER.Tag.integer)
    }

    @Test func signsAndVerifies() throws {
        let original = Self.source()
        let data = try Self.signed(original)
        // The original bytes are untouched: an incremental update.
        #expect(data.prefix(original.count) == original)
        let statuses = SignatureValidator.validate(data)
        let status = try #require(statuses.first)
        #expect(statuses.count == 1)
        #expect(status.integrity == .intact)
        #expect(status.coversWholeFile)
        #expect(status.signerName == "Paper Test Signer")
        #expect(status.reason == "I approve")
        // Self-signed, so not trusted, and the summary says so.
        #expect(!status.trusted)
        #expect(status.summary.contains("isn't from an authority"))
        // Still a normal PDF with a signature widget on page 1.
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        let widget = try #require(document.page(at: 0)?.annotations.first { $0.widgetFieldType == .signature })
        #expect(widget.bounds.isClose(to: CGRect(x: 320, y: 80, width: 220, height: 60)))
        #expect(DocumentFacts.inspect(document, raw: data).hasDigitalSignature)
    }

    @Test func detectsTampering() throws {
        var data = try Self.signed()
        // Change one byte inside the signed range: in the first (compressed) stream.
        let target = try #require(data.range(of: Data("stream\n".utf8)))
        data[target.upperBound + 10] ^= 0xFF
        let status = try #require(SignatureValidator.validate(data).first)
        #expect(status.integrity == .altered)
        #expect(status.summary.contains("no longer valid"))
    }

    @Test func noticesLaterChanges() throws {
        let data = try Self.signed()
        // Anything appended after signing (here a harmless update) leaves the signature
        // intact but no longer covering the whole file.
        let file = try PDFFile(data: data)
        var update = IncrementalUpdate(file)
        _ = update.add(.dict(PDFDict([("Note", .text("added later"))])))
        let later = update.write()
        let status = try #require(SignatureValidator.validate(later).first)
        #expect(status.integrity == .intact)
        #expect(!status.coversWholeFile)
        #expect(status.summary.contains("Changes were added"))
    }

    @Test func secondSignatureKeepsTheFirstValid() throws {
        let once = try Self.signed()
        let twice = try Self.signed(once, placement: .new(page: 1, rect: CGRect(x: 72, y: 80, width: 200, height: 50)), name: "Second Signer")
        let statuses = SignatureValidator.validate(twice)
        #expect(statuses.count == 2)
        #expect(statuses.allSatisfy { $0.integrity == .intact })
        #expect(statuses.filter(\.coversWholeFile).count == 1)
    }

    @Test func signsAnExistingEmptyField() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        document.page(at: 0)!.addAnnotation(FormFieldFactory.make(.signature, in: CGRect(x: 72, y: 100, width: 200, height: 50), name: "Approver"))
        let prepared = AcroFormWriter.finalize(document.dataRepresentation()!, widgets: FormFields.states(in: document))
        let data = try Self.signed(prepared, placement: .field("Approver"))
        let status = try #require(SignatureValidator.validate(data).first)
        #expect(status.fieldName == "Approver")
        #expect(status.integrity == .intact)
        let reopened = try #require(PDFDocument(data: data))
        #expect(reopened.page(at: 0)!.annotations.filter { $0.widgetFieldType == .signature }.count == 1)
    }

    @Test func appearanceHasTheSignerAndDate() {
        let request = SignatureRequest(placement: .new(page: 0, rect: .zero), signerName: "Zoë Example", reason: "Agreed", date: Date())
        let lines = SignatureAppearance.lines(request)
        #expect(lines.first == "Digitally signed by Zoë Example")
        #expect(lines.contains("Reason: Agreed"))
        let stream = String(decoding: SignatureAppearance.stream(request, size: CGSize(width: 220, height: 60)), as: UTF8.self)
        // The name ("ë" is outside ASCII but in WinAnsi) uses the standard font; the name
        // in the script face is outlines.
        #expect(stream.contains(" f"))
        #expect(stream.contains("/Helv"))
        let cjk = SignatureRequest(placement: .new(page: 0, rect: .zero), signerName: "山田太郎")
        let cjkStream = String(decoding: SignatureAppearance.stream(cjk, size: CGSize(width: 220, height: 60)), as: UTF8.self)
        #expect(!cjkStream.contains("(Digitally signed by"))
    }

    @Test func pdfDates() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let text = PDFDate.string(date, timeZone: TimeZone(secondsFromGMT: -6 * 3600)!)
        #expect(text.hasPrefix("D:2027") && text.hasSuffix("-06'00'") && text.count == 23)
        let parsed = try #require(PDFDate.parse(text))
        #expect(abs(parsed.timeIntervalSince(date)) < 1)
    }

    @Test func emptyKeychainListsNothing() {
        #expect(IdentityStore.identities(keychainPath: "/tmp/paper-test/does-not-exist.keychain-db").isEmpty)
    }
}
