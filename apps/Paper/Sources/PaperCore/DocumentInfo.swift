import AppKit
import PDFKit

/// Title, author, subject and keywords (editable), plus what Paper can tell about the file.
/// Shown in the inspector's Document tab.
public struct DocumentInfo: Equatable, Sendable {
    public var title = ""
    public var author = ""
    public var subject = ""
    /// Comma-separated, as people type them.
    public var keywords = ""

    public init(title: String = "", author: String = "", subject: String = "", keywords: String = "") {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
    }

    public init(_ document: PDFDocument) {
        let attributes = document.documentAttributes ?? [:]
        func string(_ key: PDFDocumentAttribute) -> String { (attributes[key] as? String) ?? "" }
        title = string(.titleAttribute)
        author = string(.authorAttribute)
        subject = string(.subjectAttribute)
        switch attributes[PDFDocumentAttribute.keywordsAttribute] {
        case let list as [String]: keywords = list.joined(separator: ", ")
        case let text as String: keywords = text
        default: keywords = ""
        }
    }

    public var keywordList: [String] {
        keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Writes the four editable fields into `document`, keeping every other attribute.
    public func apply(to document: PDFDocument) {
        var attributes = document.documentAttributes ?? [:]
        func set(_ key: PDFDocumentAttribute, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            attributes[key] = trimmed.isEmpty ? nil : trimmed
        }
        set(.titleAttribute, title)
        set(.authorAttribute, author)
        set(.subjectAttribute, subject)
        attributes[PDFDocumentAttribute.keywordsAttribute] = keywordList.isEmpty ? nil : keywordList
        document.documentAttributes = attributes
    }
}

/// Read-only facts for the inspector.
public struct FileFacts: Equatable, Sendable {
    public var creator: String?
    public var producer: String?
    public var created: Date?
    public var modified: Date?
    public var pageCount: Int
    public var pageSize: String?
    public var version: String
    public var fileSize: Int64?
    public var isEncrypted: Bool

    public init(_ document: PDFDocument, fileURL: URL?) {
        let attributes = document.documentAttributes ?? [:]
        creator = (attributes[PDFDocumentAttribute.creatorAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
        producer = (attributes[PDFDocumentAttribute.producerAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
        created = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        modified = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date
        pageCount = document.pageCount
        pageSize = document.page(at: 0).map { Self.describe($0.bounds(for: .cropBox).size, rotation: $0.rotation) }
        version = "\(document.majorVersion).\(document.minorVersion)"
        fileSize = fileURL.flatMap { (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }.map(Int64.init)
        isEncrypted = document.isEncrypted
    }

    /// "8.5 × 11 in (Letter)" or "210 × 297 mm (A4)", following the Mac's measurement system.
    public static func describe(_ size: CGSize, rotation: Int, metric: Bool = Locale.current.measurementSystem != .us) -> String {
        let shown = rotation % 180 == 0 ? size : CGSize(width: size.height, height: size.width)
        let name = paperName(shown)
        let dimensions: String
        if metric {
            dimensions = "\(Int((shown.width / 72 * 25.4).rounded())) × \(Int((shown.height / 72 * 25.4).rounded())) mm"
        } else {
            func inches(_ points: CGFloat) -> String {
                let value = (points / 72 * 100).rounded() / 100
                return value == value.rounded() ? "\(Int(value))" : String(format: "%g", value)
            }
            dimensions = "\(inches(shown.width)) × \(inches(shown.height)) in"
        }
        return name.map { "\(dimensions) (\($0))" } ?? dimensions
    }

    static func paperName(_ size: CGSize) -> String? {
        let known: [(String, CGSize)] = [
            ("Letter", CGSize(width: 612, height: 792)), ("Legal", CGSize(width: 612, height: 1008)),
            ("Tabloid", CGSize(width: 792, height: 1224)), ("A3", CGSize(width: 842, height: 1191)),
            ("A4", CGSize(width: 595, height: 842)), ("A5", CGSize(width: 420, height: 595)),
        ]
        for (name, paper) in known {
            if abs(size.width - paper.width) < 2, abs(size.height - paper.height) < 2 { return name }
            if abs(size.width - paper.height) < 2, abs(size.height - paper.width) < 2 { return "\(name), landscape" }
        }
        return nil
    }
}

/// Markup that follows text: highlight every search result, remove markup from a selection.
public enum TextMarkup {
    /// One markup annotation per hit (multi-line hits get one annotation with a quad per line).
    public static func annotations(for hits: [TextHit], in document: PDFDocument, style: MarkupStyle, color: NSColor,
                                   factory: AnnotationFactory) -> [(page: PDFPage, annotation: PDFAnnotation)] {
        hits.compactMap { hit in
            guard let page = document.page(at: hit.pageIndex) else { return nil }
            let rects = PDFSearch.lineRects(for: hit.range, on: page)
            guard let annotation = factory.markup(style, color: color, lineRects: rects) else { return nil }
            return (page, annotation)
        }
    }

    /// Highlight, underline and strike-through annotations that overlap `rects` on `page`.
    public static func markup(on page: PDFPage, overlapping rects: [CGRect]) -> [PDFAnnotation] {
        page.annotations.filter { annotation in
            AnnotationGeometry.isMarkup(annotation) && rects.contains { rect in
                let overlap = rect.intersection(annotation.bounds)
                return !overlap.isNull && overlap.width > 1 && overlap.height > 1
            }
        }
    }
}
