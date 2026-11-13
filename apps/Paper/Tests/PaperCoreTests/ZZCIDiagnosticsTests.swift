import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

/// Temporary: prints how this macOS's PDFKit behaves for the content-editing and form paths.
@Test func zzCIDiagnostics() throws {
    func say(_ s: String) { print("DIAG \(s)") }
    say("os \(ProcessInfo.processInfo.operatingSystemVersionString)")
    let document = doc(Fixtures.editableDocument())
    let page = document.page(at: 0)!
    say("original pageRef nil=\(page.pageRef == nil) string=\(page.string?.prefix(20) ?? "nil")")
    let copy = page.copy() as! PDFPage
    say("copy pageRef nil=\(copy.pageRef == nil) string=\(copy.string?.prefix(20) ?? "nil") doc nil=\(copy.document == nil)")
    let single = PDFDocument()
    single.insert(copy, at: 0)
    say("copy in single pageRef nil=\(copy.pageRef == nil)")
    let data = single.dataRepresentation()!
    let reopened = PDFDocument(data: data)!
    say("single written count=\(data.count) reopened string=\(reopened.page(at: 0)?.string?.replacingOccurrences(of: "\n", with: "|").prefix(80) ?? "nil")")
    let rewritten = PageRewriter.rewrite(page) { _ in }
    say("rewrite(original) nil=\(rewritten == nil) string=\(rewritten?.string?.prefix(30) ?? "nil") pageRef nil=\(rewritten?.pageRef == nil)")
    let rewrittenCopy = PageRewriter.rewrite(copy) { _ in }
    say("rewrite(copy) nil=\(rewrittenCopy == nil)")
    // Extracted pages, written: a real feature path.
    let extracted = PageOps.extract(document, pages: [0])
    let extractedData = extracted.dataRepresentation()!
    say("extract written string=\(PDFDocument(data: extractedData)?.page(at: 0)?.string?.prefix(30) ?? "nil")")
    // Redact on the document itself.
    let d2 = doc(Fixtures.editableDocument())
    let p2 = d2.page(at: 0)!
    p2.addAnnotation(PDFAnnotation(bounds: CGRect(x: 72, y: 630, width: 300, height: 30), forType: RedactionMarks.redactSubtype, withProperties: nil))
    let r2 = PDFDocument(data: d2.dataRepresentation()!)!
    say("redact in place string=\(r2.page(at: 0)?.string?.replacingOccurrences(of: "\n", with: "|").prefix(120) ?? "nil")")
    say("scan images original=\(ContentScanner.scan(page).images.map { NSStringFromRect($0.rect) }) text runs=\(ContentScanner.scan(page).text.count)")
    if let r = rewritten { say("scan images rewritten=\(ContentScanner.scan(r).images.map { NSStringFromRect($0.rect) }) runs=\(ContentScanner.scan(r).text.count)") }

    // Forms: what PDFKit writes for radios and text fields before Paper's writer.
    let form = doc(Fixtures.textDocument(pages: 1))
    let fp = form.page(at: 0)!
    for (i, o) in ["Basic", "Plus"].enumerated() {
        fp.addAnnotation(FormFieldFactory.make(.radio, in: CGRect(x: 72 + CGFloat(i) * 40, y: 300, width: 14, height: 14), name: "plan", exportValue: o))
    }
    fp.addAnnotation(FormFieldFactory.make(.text, in: CGRect(x: 72, y: 200, width: 120, height: 22), name: "name"))
    let plain = form.dataRepresentation()!
    let file = try PDFFile(data: plain)
    for n in file.entries.keys.sorted() {
        guard let o = try? file.object(n) else { continue }
        let t = String(decoding: PDFWriter.serialize(o), as: UTF8.self)
        if t.contains("Widget") || t.contains("/Kids") && t.contains("plan") || t.contains("AcroForm") { say("plain obj \(n): \(t.prefix(400))") }
    }
    let fixed = AcroFormWriter.finalize(plain, widgets: FormFields.states(in: form))
    let f2 = try PDFFile(data: fixed)
    for n in f2.entries.keys.sorted() where n >= file.size - 1 || [1,2,3].contains(n) == false {
        guard let o = try? f2.object(n) else { continue }
        let t = String(decoding: PDFWriter.serialize(o), as: UTF8.self)
        if t.contains("Widget") || t.contains("Kids") || t.contains("PaperBorder") { say("fixed obj \(n): \(t.prefix(300))") }
    }
    let back = doc(fixed).page(at: 0)!
    for a in back.annotations { say("reopened \(a.fieldName ?? "") ap keys=\(a.annotationKeyValues.keys.map { "\($0)" }.sorted())") }
}
