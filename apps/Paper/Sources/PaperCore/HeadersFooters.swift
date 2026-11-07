import AppKit
import CoreText
import PDFKit

/// Headers, footers, page numbers and Bates numbers, stamped into the page content (so they
/// print and show in every viewer). Six slots like a word processor's: left, centre and
/// right, top and bottom. Text can use tokens:
///
/// - `{page}` page number, `{pages}` page count
/// - `{bates}` Bates number (prefix + zero-padded counter)
/// - `{date}` today's date, `{name}` the document name
public struct HeaderFooter: Codable, Equatable, Sendable {
    public var topLeft = ""
    public var topCenter = ""
    public var topRight = ""
    public var bottomLeft = ""
    public var bottomCenter = ""
    public var bottomRight = ""
    public var fontSize: CGFloat = 10
    /// Distance from the visible page edge, in points.
    public var margin: CGFloat = 28
    public var batesPrefix = ""
    public var batesStart = 1
    public var batesDigits = 6

    public init() {}

    public static let pageNumbers: HeaderFooter = {
        var value = HeaderFooter()
        value.bottomCenter = "Page {page} of {pages}"
        return value
    }()

    public var isEmpty: Bool {
        [topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight].allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    public struct Context: Sendable {
        public var page: Int
        public var pageCount: Int
        /// 0-based position among the stamped pages, for Bates numbering.
        public var sequence: Int
        public var date: Date
        public var name: String

        public init(page: Int, pageCount: Int, sequence: Int, date: Date = Date(), name: String) {
            self.page = page
            self.pageCount = pageCount
            self.sequence = sequence
            self.date = date
            self.name = name
        }
    }

    public func bates(_ sequence: Int) -> String {
        let number = String(batesStart + sequence)
        let padded = String(repeating: "0", count: max(0, batesDigits - number.count)) + number
        return batesPrefix + padded
    }

    public func expand(_ template: String, _ context: Context) -> String {
        template
            .replacingOccurrences(of: "{page}", with: String(context.page))
            .replacingOccurrences(of: "{pages}", with: String(context.pageCount))
            .replacingOccurrences(of: "{bates}", with: bates(context.sequence))
            .replacingOccurrences(of: "{date}", with: context.date.formatted(date: .long, time: .omitted))
            .replacingOccurrences(of: "{name}", with: context.name)
    }

    /// The six slots' text for one page, with their positions.
    enum Slot: CaseIterable { case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight }

    func template(_ slot: Slot) -> String {
        switch slot {
        case .topLeft: topLeft
        case .topCenter: topCenter
        case .topRight: topRight
        case .bottomLeft: bottomLeft
        case .bottomCenter: bottomCenter
        case .bottomRight: bottomRight
        }
    }

    /// A copy of `page` with the headers and footers drawn on it, upright as the page is
    /// displayed (rotation and crop box respected). Annotations aren't included.
    public func stamped(_ page: PDFPage, _ context: Context) -> PDFPage? {
        let display = OCR.displaySize(of: page)
        let toPage = page.transform(for: .cropBox).inverted()
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        return PageRewriter.rewrite(page) { cg in
            cg.saveGState()
            cg.concatenate(toPage)
            cg.textMatrix = .identity
            for slot in Slot.allCases {
                let text = expand(template(slot), context).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: CGColor(gray: 0, alpha: 1),
                ]))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                let x: CGFloat
                switch slot {
                case .topLeft, .bottomLeft: x = margin
                case .topCenter, .bottomCenter: x = (display.width - width) / 2
                case .topRight, .bottomRight: x = display.width - margin - width
                }
                let top = [.topLeft, .topCenter, .topRight].contains(slot)
                let y = top ? display.height - margin - CTFontGetAscent(font) : margin
                cg.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, cg)
            }
            cg.restoreGState()
        }
    }
}
