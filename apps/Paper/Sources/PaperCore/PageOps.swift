import AppKit
import PDFKit

/// Page surgery on a `PDFDocument`. Each mutating call returns what's needed to undo it.
public enum PageOps {
    /// Puts pages in `order` (`order[new] == old`). Undo with `PageOrder.inverse(order)`.
    public static func reorder(_ document: PDFDocument, to order: [Int]) {
        let count = document.pageCount
        guard order.count == count, Set(order) == Set(0..<count) else { return }
        let pages = (0..<count).compactMap { document.page(at: $0) }
        guard pages.count == count else { return }
        var current = pages
        for target in 0..<count {
            let wanted = pages[order[target]]
            guard let from = current.firstIndex(where: { $0 === wanted }), from != target else { continue }
            document.exchangePage(at: target, withPageAt: from)
            current.swapAt(target, from)
        }
    }

    public static func rotate(_ document: PDFDocument, pages indices: IndexSet, by degrees: Int) {
        for index in indices {
            guard let page = document.page(at: index) else { continue }
            page.rotation = normalizedRotation(page.rotation + degrees)
        }
    }

    public static func normalizedRotation(_ degrees: Int) -> Int {
        let snapped = Int((Double(degrees) / 90).rounded()) * 90
        return ((snapped % 360) + 360) % 360
    }

    /// Removes pages and returns them with their old indexes, ascending, for `insert`.
    @discardableResult
    public static func remove(_ document: PDFDocument, pages indices: IndexSet) -> [(index: Int, page: PDFPage)] {
        var removed: [(Int, PDFPage)] = []
        for index in indices.sorted(by: >) where index < document.pageCount {
            guard let page = document.page(at: index) else { continue }
            document.removePage(at: index)
            removed.append((index, page))
        }
        return removed.reversed()
    }

    /// Inserts pages at their indexes, ascending (the inverse of `remove`).
    public static func insert(_ document: PDFDocument, pages: [(index: Int, page: PDFPage)]) {
        for item in pages.sorted(by: { $0.index < $1.index }) {
            document.insert(item.page, at: min(item.index, document.pageCount))
        }
    }

    /// Copies of the pages, in order, in a new document. The source is unchanged.
    public static func extract(_ document: PDFDocument, pages indices: IndexSet) -> PDFDocument {
        let output = PDFDocument()
        for index in indices.sorted() {
            guard let copy = document.page(at: index)?.copy() as? PDFPage else { continue }
            output.insert(copy, at: output.pageCount)
        }
        return output
    }

    /// Copies of every page of `documents`, one after another, or front/back interleaved
    /// (two documents, the second reversed) for one-sided duplex scans.
    public static func combine(_ documents: [PDFDocument], interleave: Bool = false) -> PDFDocument {
        let output = PDFDocument()
        func append(_ document: PDFDocument, _ index: Int) {
            guard let copy = document.page(at: index)?.copy() as? PDFPage else { return }
            output.insert(copy, at: output.pageCount)
        }
        if interleave, documents.count == 2 {
            for item in PageOrder.interleave(frontCount: documents[0].pageCount, backCount: documents[1].pageCount) {
                append(documents[item.document], item.page)
            }
        } else {
            for document in documents {
                for index in 0..<document.pageCount { append(document, index) }
            }
        }
        return output
    }

    public static func split(_ document: PDFDocument, into ranges: [Range<Int>]) -> [PDFDocument] {
        ranges.map { extract(document, pages: IndexSet(integersIn: $0)) }
    }

    /// A blank page the same size (and rotation) as `page`, or US Letter.
    public static func blankPage(like page: PDFPage?) -> PDFPage {
        let blank = PDFPage()
        let size = page?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        blank.setBounds(size, for: .mediaBox)
        blank.setBounds(page?.bounds(for: .cropBox) ?? size, for: .cropBox)
        blank.rotation = page?.rotation ?? 0
        return blank
    }

    /// Top-level outline entries with the page they point to, for "split at chapters".
    public static func topLevelOutline(_ document: PDFDocument) -> [(title: String, pageIndex: Int)] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [(String, Int)] = []
        for index in 0..<root.numberOfChildren {
            guard let child = root.child(at: index), let page = child.destination?.page else { continue }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            entries.append((child.label ?? "Part \(entries.count + 1)", pageIndex))
        }
        return entries
    }

    /// Form field names that appear in more than one of `documents`. Combined, such fields
    /// would share one value (filling one fills the other).
    public static func collidingFieldNames(_ documents: [PDFDocument]) -> [String] {
        var seen: [String: Int] = [:]
        for (offset, document) in documents.enumerated() {
            var names = Set<String>()
            for index in 0..<document.pageCount {
                for annotation in document.page(at: index)?.annotations ?? [] {
                    if let name = annotation.fieldName, !name.isEmpty { names.insert(name) }
                }
            }
            for name in names { seen[name, default: 0] |= 1 << min(offset, 62) }
        }
        return seen.filter { $0.value.nonzeroBitCount > 1 }.map(\.key).sorted()
    }
}

/// Turning images into pages.
public enum ImagePages {
    static let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE", "PR", "GT", "CR", "PA", "DO", "SV", "NI", "BO"]

    /// Letter in North America and a few other places, A4 elsewhere.
    public static func paperSize(for region: String?) -> CGSize {
        letterRegions.contains(region ?? "") ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    /// The page box for an image: the paper size, turned to match the image's orientation.
    public static func pageBox(forImageSize size: CGSize, region: String?) -> CGRect {
        let paper = paperSize(for: region)
        let landscape = size.width > size.height
        return CGRect(x: 0, y: 0,
                      width: landscape ? paper.height : paper.width,
                      height: landscape ? paper.width : paper.height)
    }

    public static func page(for image: NSImage, region: String? = Locale.current.region?.identifier) -> PDFPage? {
        let box = pageBox(forImageSize: image.size, region: region)
        return PDFPage(image: image, options: [.mediaBox: box, .upscaleIfSmaller: true])
    }
}
