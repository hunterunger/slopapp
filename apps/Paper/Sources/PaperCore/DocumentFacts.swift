import Foundation
import PDFKit

/// What Paper needs to know about a document when it opens, to show the right info bars.
public struct DocumentFacts: Sendable, Equatable {
    public var pageCount = 0
    public var formFieldCount = 0
    public var hasDigitalSignature = false
    public var isPDFA = false
    public var hasXFA = false
    public var redactAnnotationCount = 0
    public var pendingMarkCount = 0
    public var hasTextLayer = true
    public var isEncrypted = false
    public var allowsCommenting = true
    public var allowsChanges = true
    public var allowsPrinting = true
    public var allowsCopying = true

    public init() {}

    public static func inspect(_ document: PDFDocument, raw: Data?) -> DocumentFacts {
        var facts = DocumentFacts()
        facts.pageCount = document.pageCount
        facts.isEncrypted = document.isEncrypted
        facts.allowsCommenting = document.allowsCommenting
        facts.allowsChanges = document.allowsDocumentChanges
        facts.allowsPrinting = document.allowsPrinting
        facts.allowsCopying = document.allowsCopying
        var fieldNames = Set<String>()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if annotation.type == "Widget" {
                    let name = annotation.fieldName ?? "\(index)-\(annotation.bounds)"
                    if annotation.widgetFieldType == .signature {
                        if annotation.value(forAnnotationKey: .widgetValue) != nil { facts.hasDigitalSignature = true }
                    } else if annotation.widgetFieldType != .button || annotation.widgetControlType != .pushButtonControl {
                        fieldNames.insert(name)
                    }
                } else if RedactionMarks.isRedactAnnotation(annotation) {
                    facts.redactAnnotationCount += 1
                } else if RedactionMarks.isMark(annotation) {
                    facts.pendingMarkCount += 1
                }
            }
        }
        facts.formFieldCount = fieldNames.count
        facts.hasTextLayer = PDFSearch.hasTextLayer(document)
        if let raw {
            facts.isPDFA = RawScan.contains("pdfaid:part", in: raw)
            facts.hasXFA = RawScan.contains("/XFA", in: raw)
            // PDFKit doesn't expose a signature field's value; a signed file has a byte range.
            if RawScan.contains("/ByteRange", in: raw) { facts.hasDigitalSignature = true }
        }
        return facts
    }

    /// The owner password restricts something (printing, copying, changes).
    public var isRestricted: Bool {
        isEncrypted && (!allowsCommenting || !allowsChanges || !allowsPrinting || !allowsCopying)
    }

    /// Paper opens restricted documents read-only: PDFKit can't write the owner password
    /// back, so any save would silently remove the restrictions.
    public var isReadOnly: Bool { isRestricted }

    /// Saving in place would break something (a digital signature, PDF/A conformance).
    public var saveBreaksSomething: Bool { hasDigitalSignature || isPDFA }
}

/// Looks for markers in the raw file without reading all of a huge document: the head and
/// tail are where catalogs, XMP metadata and AcroForm dictionaries usually live.
enum RawScan {
    static func contains(_ marker: String, in data: Data, window: Int = 4 << 20) -> Bool {
        let needle = Data(marker.utf8)
        if data.count <= window * 2 { return data.range(of: needle) != nil }
        let head = data.prefix(window)
        let tail = data.suffix(window)
        return head.range(of: needle) != nil || tail.range(of: needle) != nil
    }
}
