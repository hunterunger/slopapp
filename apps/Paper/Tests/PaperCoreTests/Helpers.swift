import AppKit
import PDFKit
@testable import PaperCore
import PaperFixtures

func doc(_ data: Data) -> PDFDocument { PDFDocument(data: data)! }

func allText(_ document: PDFDocument) -> String {
    (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }.joined(separator: "\n")
}

func annotationCount(_ document: PDFDocument) -> Int {
    (0..<document.pageCount).reduce(0) { $0 + (document.page(at: $1)?.annotations.count ?? 0) }
}

/// Bounds of the first occurrence of `text` on `page`.
func bounds(of text: String, in document: PDFDocument, page index: Int = 0) -> CGRect {
    let page = document.page(at: index)!
    let hit = PDFSearch.hits(on: page, pageIndex: index, query: text, options: .init(caseSensitive: true)).first!
    return PDFSearch.lineRects(for: hit.range, on: page).first!.insetBy(dx: -1, dy: -1)
}

/// Adds a pending mark over the first occurrence of `text`.
@discardableResult
func mark(_ text: String, in document: PDFDocument, page index: Int = 0) -> PDFAnnotation {
    let annotation = RedactionMarks.makeMark(bounds: bounds(of: text, in: document, page: index))
    document.page(at: index)!.addAnnotation(annotation)
    return annotation
}

func pageNames(_ document: PDFDocument) -> [String] {
    (0..<document.pageCount).map { document.page(at: $0)?.string?.components(separatedBy: "\n").first ?? "" }
}
