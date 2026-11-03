import Foundation
import PDFKit

/// One search result: where it is and a line of context for the results list.
public struct TextHit: Sendable, Hashable, Identifiable {
    public var pageIndex: Int
    public var range: NSRange
    public var matched: String
    public var context: String

    public var id: String { "\(pageIndex):\(range.location):\(range.length)" }

    public init(pageIndex: Int, range: NSRange, matched: String, context: String) {
        self.pageIndex = pageIndex
        self.range = range
        self.matched = matched
        self.context = context
    }
}

public enum PDFSearch {
    /// Hits on one page, in reading order.
    public static func hits(on page: PDFPage, pageIndex: Int, query: String, options: MatchOptions) -> [TextHit] {
        guard let text = page.string, !text.isEmpty else { return [] }
        return TextMatcher.ranges(of: query, in: text, options: options).map { range in
            TextHit(
                pageIndex: pageIndex,
                range: range,
                matched: (text as NSString).substring(with: range),
                context: TextMatcher.context(for: range, in: text)
            )
        }
    }

    /// All hits in a document. The app runs its own page loop so it can show progress and
    /// cancel; this is the simple version for tests and small documents.
    public static func hits(in document: PDFDocument, query: String, options: MatchOptions) -> [TextHit] {
        (0..<document.pageCount).flatMap { index -> [TextHit] in
            guard let page = document.page(at: index) else { return [] }
            return hits(on: page, pageIndex: index, query: query, options: options)
        }
    }

    /// Whether the document has any text to search. Samples the first pages so a
    /// 1,000-page scan doesn't get read in full. A scan with no OCR layer returns false.
    public static func hasTextLayer(_ document: PDFDocument, samplePages: Int = 8) -> Bool {
        let count = min(document.pageCount, samplePages)
        for index in 0..<count {
            if let text = document.page(at: index)?.string,
               text.contains(where: { !$0.isWhitespace }) {
                return true
            }
        }
        return false
    }

    /// The selection rectangles of a hit, one per line, in page space.
    public static func lineRects(for range: NSRange, on page: PDFPage) -> [CGRect] {
        guard let selection = page.selection(for: range) else { return [] }
        return lineRects(for: selection, on: page)
    }

    public static func lineRects(for selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        let lines = selection.selectionsByLine()
        let rects = lines.map { $0.bounds(for: page) }.filter { !$0.isEmpty && $0.width > 0.5 }
        if rects.isEmpty {
            let whole = selection.bounds(for: page)
            return whole.isEmpty ? [] : [whole]
        }
        return rects
    }
}
