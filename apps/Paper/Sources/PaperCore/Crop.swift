import CoreGraphics
import PDFKit

/// Cropping sets a page's crop box (what viewers show and print). The media box and the
/// content outside the crop are kept, so a crop can always be undone or removed later.
public enum PageCrop {
    /// The crop rectangle clamped to the page's media box, or nil when too small to keep.
    public static func clamped(_ rect: CGRect, to page: PDFPage) -> CGRect? {
        let result = rect.standardized.intersection(page.bounds(for: .mediaBox))
        guard !result.isNull, result.width >= 18, result.height >= 18 else { return nil }
        return result.integral
    }

    /// Applies `rect` (page space of `reference`) to `pages`. Pages of another size get the
    /// same margins, measured from the reference page's media box. Returns the old crop boxes.
    @discardableResult
    public static func apply(_ rect: CGRect, from reference: PDFPage, to pages: [PDFPage]) -> [(PDFPage, CGRect)] {
        let media = reference.bounds(for: .mediaBox)
        let left = rect.minX - media.minX, bottom = rect.minY - media.minY
        let right = media.maxX - rect.maxX, top = media.maxY - rect.maxY
        var old: [(PDFPage, CGRect)] = []
        for page in pages {
            old.append((page, page.bounds(for: .cropBox)))
            let box = page.bounds(for: .mediaBox)
            let crop = page === reference ? rect
                : CGRect(x: box.minX + left, y: box.minY + bottom, width: box.width - left - right, height: box.height - bottom - top)
            if let crop = clamped(crop, to: page) { page.setBounds(crop, for: .cropBox) }
        }
        return old
    }

    public static func isCropped(_ page: PDFPage) -> Bool {
        !page.bounds(for: .cropBox).isClose(to: page.bounds(for: .mediaBox), tolerance: 0.5)
    }

    /// The crop box set back to the whole page.
    @discardableResult
    public static func remove(from pages: [PDFPage]) -> [(PDFPage, CGRect)] {
        pages.map { page in
            let old = page.bounds(for: .cropBox)
            page.setBounds(page.bounds(for: .mediaBox), for: .cropBox)
            return (page, old)
        }
    }
}
