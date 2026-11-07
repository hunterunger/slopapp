import AppKit
import PDFKit

/// Since macOS 15, PDFView runs Vision on every visible page to find form fields and tables
/// in flat PDFs. It costs about 100 MB and Neural Engine time per page, it would add fields
/// Paper's undo and form tracking don't know about, and Paper's Text Box tool already covers
/// flat forms. There's no public switch, so this turns it off through PDFView's own
/// properties when they exist, and does nothing where they don't (macOS 14).
@MainActor
enum PDFViewTuning {
    static func disableAutomaticAnalysis(_ view: PDFView) {
        for key in ["documentAnalysisEnabled", "formDetectionEnabled"] {
            let setter = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            guard view.responds(to: setter) else { continue }
            view.setValue(false, forKey: key)
        }
    }
}

/// How pages sit on the canvas: on the system's under-page colour with their shadow, and the
/// same gap on every side and between pages. PDFView's own margins are 4.75 pt at the sides
/// and 4 pt between pages, and its fit-to-width leaves room for a legacy scroller even with
/// overlay scrollers, so the sides came out 6 and 8 pt (or 21 pt) against 4 pt between pages.
///
/// PDFKit scales page margins with the zoom, so the gap is in page units: 12 at 100 %, and
/// always the same on every side and between pages at any zoom.
@MainActor
enum CanvasLook {
    static func apply(to pdfView: PDFView) {
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.pageShadowsEnabled = true
        let gap = PaperMetrics.pageGap
        // The gap above each page; the scroll view's bottom inset closes the last one.
        pdfView.pageBreakMargins = NSEdgeInsets(top: gap, left: gap, bottom: 0, right: gap)
        scaleChanged(pdfView)
        // PDFView sets its scroll view up again while it lays out a new document.
        DispatchQueue.main.async { scaleChanged(pdfView) }
    }

    /// Keeps the gap under the last page equal to the others (scroll insets are in view
    /// points, page margins in page units).
    static func scaleChanged(_ pdfView: PDFView) {
        guard let scroll = pdfView.documentView?.enclosingScrollView else { return }
        // The canvas already sits below the toolbar; PDFView's own titlebar inset would hide
        // the top of the first page under it.
        scroll.automaticallyAdjustsContentInsets = false
        let bottom = (PaperMetrics.pageGap * pdfView.scaleFactor).rounded()
        if scroll.contentInsets.bottom != bottom || scroll.contentInsets.top != 0 {
            scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
        }
    }

    /// Scrolls so `page` starts one gap below the top of the canvas, the gap above it showing
    /// (PDFView's `go(to:)` puts the page's edge flush against the top and hides it).
    static func scroll(_ pdfView: PDFView, toTopOf page: PDFPage) {
        pdfView.go(to: page)
        guard let documentView = pdfView.documentView, let scroll = documentView.enclosingScrollView else { return }
        pdfView.layoutDocumentView()
        let clip = scroll.contentView
        let inView = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        let rect = documentView.convert(inView, from: pdfView)
        // The document view is in page units, like the margins.
        let gap = PaperMetrics.pageGap
        let y = documentView.isFlipped ? rect.minY - gap : rect.maxY + gap - clip.bounds.height
        let target = NSRect(origin: NSPoint(x: clip.bounds.minX, y: y), size: clip.bounds.size)
        clip.scroll(to: clip.constrainBoundsRect(target).origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// The scale that fits `page`'s width and the gap on both sides (plus a scroller only
    /// when scrollers take space).
    static func fitWidthScale(for page: PDFPage, in pdfView: PDFView) -> CGFloat {
        let bounds = page.bounds(for: pdfView.displayBox)
        var width = (page.rotation % 180 == 0 ? bounds.width : bounds.height) + 2 * PaperMetrics.pageGap
        if pdfView.displayMode == .twoUp || pdfView.displayMode == .twoUpContinuous { width *= 2 }
        var available = pdfView.bounds.width
        if NSScroller.preferredScrollerStyle == .legacy {
            available -= NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        }
        // A hair under the exact fit, so rounding never adds a horizontal scroller.
        return max(0.1, (available - 0.5) / max(width, 1))
    }
}
