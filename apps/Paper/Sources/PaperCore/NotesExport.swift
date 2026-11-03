import Foundation
import PDFKit

/// "Copy Highlights & Notes": the document's markup as Markdown, in page order.
public enum NotesExport {
    public struct Item: Equatable, Sendable {
        public enum Kind: String, Sendable { case highlight, underline, strikeOut, note, textBox }
        public var pageIndex: Int
        public var kind: Kind
        public var quote: String?
        public var note: String?
    }

    public static func items(in document: PDFDocument) -> [Item] {
        var items: [Item] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let sorted = page.annotations.sorted { $0.bounds.maxY > $1.bounds.maxY }
            for annotation in sorted where !RedactionMarks.isMark(annotation) {
                let note = annotation.contents.flatMap { $0.isEmpty ? nil : $0 }
                switch annotation.type ?? "" {
                case "Highlight", "Underline", "StrikeOut":
                    let kind: Item.Kind = annotation.type == "Highlight" ? .highlight : annotation.type == "Underline" ? .underline : .strikeOut
                    items.append(Item(pageIndex: index, kind: kind, quote: quotedText(annotation, on: page), note: note))
                case "Text":
                    if let note { items.append(Item(pageIndex: index, kind: .note, quote: nil, note: note)) }
                case "FreeText":
                    if let note { items.append(Item(pageIndex: index, kind: .textBox, quote: nil, note: note)) }
                default:
                    continue
                }
            }
        }
        return items
    }

    /// The text under a markup annotation's quads.
    public static func quotedText(_ annotation: PDFAnnotation, on page: PDFPage) -> String? {
        let rects = RedactionMarks.quadRects(of: annotation)
        let parts = rects.compactMap { rect -> String? in
            page.selection(for: rect.insetBy(dx: 0.5, dy: rect.height * 0.2))?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    public static func markdown(title: String, items: [Item]) -> String {
        var lines = ["# \(title)", ""]
        var currentPage = -1
        for item in items {
            if item.pageIndex != currentPage {
                currentPage = item.pageIndex
                lines.append("## Page \(currentPage + 1)")
                lines.append("")
            }
            if let quote = item.quote {
                let marker = item.kind == .strikeOut ? "~~\(quote)~~" : quote
                lines.append("> \(marker)")
                if let note = item.note { lines.append(""); lines.append(note) }
            } else if let note = item.note {
                lines.append(item.kind == .note ? "Note: \(note)" : note)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
