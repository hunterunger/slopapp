import AppKit
import PDFKit

/// Pending redaction marks.
///
/// A mark is a plain **Square** annotation whose `/NM` starts with `paper.redaction.`.
/// It is never a `Redact` annotation: PDFKit applies `Redact` annotations on every write
/// (research P1/P4), so storing marks that way would let autosave destroy content in the
/// original before the person chose Apply. A Square changes nothing on save and shows up in
/// other viewers as a red dashed box over intact content.
public enum RedactionMarks {
    public static let namePrefix = "paper.redaction."
    /// PDFKit's subtype string for a real (content-removing) redaction annotation.
    public static let redactSubtype = PDFAnnotationSubtype(rawValue: "Redact")

    public static func isMark(_ annotation: PDFAnnotation) -> Bool {
        guard let name = annotation.value(forAnnotationKey: .name) as? String else { return false }
        return name.hasPrefix(namePrefix)
    }

    /// A `Redact` annotation that came from another app (or anywhere else).
    public static func isRedactAnnotation(_ annotation: PDFAnnotation) -> Bool {
        let type = annotation.type ?? ""
        return type == "Redact" || type == "/Redact"
    }

    public static func makeMark(bounds: CGRect) -> PDFAnnotation {
        let mark = PDFAnnotation(bounds: bounds.standardized, forType: .square, withProperties: nil)
        mark.setValue(namePrefix + UUID().uuidString, forAnnotationKey: .name)
        mark.color = NSColor.systemRed
        mark.interiorColor = NSColor.systemRed.withAlphaComponent(0.18)
        let border = PDFBorder()
        border.lineWidth = 1
        border.style = .dashed
        border.dashPattern = [3, 2]
        mark.border = border
        mark.contents = "Pending redaction"
        return mark
    }

    public struct Located {
        public var pageIndex: Int
        public var annotation: PDFAnnotation
    }

    public static func marks(in document: PDFDocument) -> [Located] {
        annotations(in: document, where: isMark)
    }

    public static func redactAnnotations(in document: PDFDocument) -> [Located] {
        annotations(in: document, where: isRedactAnnotation)
    }

    static func annotations(in document: PDFDocument, where match: (PDFAnnotation) -> Bool) -> [Located] {
        var found: [Located] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where match(annotation) {
                found.append(Located(pageIndex: index, annotation: annotation))
            }
        }
        return found
    }

    /// Replaces `Redact` annotations from another app with Paper's pending marks, so no save
    /// can apply them. Content stays exactly as it is. Returns how many were converted.
    @discardableResult
    public static func convertRedactAnnotations(in document: PDFDocument) -> Int {
        let foreign = redactAnnotations(in: document)
        for item in foreign {
            guard let page = document.page(at: item.pageIndex) else { continue }
            let rects = quadRects(of: item.annotation)
            page.removeAnnotation(item.annotation)
            for rect in rects { page.addAnnotation(makeMark(bounds: rect)) }
        }
        return foreign.count
    }

    /// A `Redact` annotation can cover several lines with `/QuadPoints`. Falls back to bounds.
    static func quadRects(of annotation: PDFAnnotation) -> [CGRect] {
        let points = annotation.quadrilateralPoints?.map(\.pointValue) ?? []
        guard points.count >= 4, points.count % 4 == 0 else { return [annotation.bounds] }
        let origin = annotation.bounds.origin
        return stride(from: 0, to: points.count, by: 4).map { start in
            let quad = points[start..<start + 4]
            let xs = quad.map(\.x), ys = quad.map(\.y)
            return CGRect(x: xs.min()! + origin.x, y: ys.min()! + origin.y,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }
}

/// "7 marks on 3 pages".
public struct MarkSummary: Sendable, Equatable {
    public var markCount: Int
    public var pageCount: Int

    public init(markCount: Int, pageCount: Int) {
        self.markCount = markCount
        self.pageCount = pageCount
    }

    public init(pageIndexes: [Int]) {
        self.init(markCount: pageIndexes.count, pageCount: Set(pageIndexes).count)
    }

    public var text: String {
        let marks = markCount == 1 ? "1 mark" : "\(markCount) marks"
        let pages = pageCount == 1 ? "1 page" : "\(pageCount) pages"
        return "\(marks) on \(pages)"
    }
}
