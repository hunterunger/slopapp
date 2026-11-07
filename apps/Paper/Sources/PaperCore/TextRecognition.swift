import AppKit
import CoreText
import PDFKit
import Vision

/// One line of recognized text. `box` is normalized (0...1, origin bottom-left) in the page
/// image as it's displayed, rotation included.
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// Reads text in an image. The real one is Vision; tests use fakes.
public protocol TextRecognizing: Sendable {
    func recognize(_ image: CGImage) throws -> [RecognizedLine]
}

/// Vision's accurate recognizer with automatic language detection. Everything runs on this
/// Mac; nothing is sent anywhere. The first call in a process is slow (macOS prepares the
/// model, about 30 s on first use, research P9); later pages take well under a second.
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognize(_ image: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text, box: observation.boundingBox)
        }
    }
}

/// Makes scanned pages searchable: recognizes the text on each page image and writes it as
/// an invisible text layer over the unchanged page (the way scanners' OCR layers work).
public enum OCR {
    /// Pixels per point for recognition. 2× (144 dpi) reads body text reliably.
    public static let scale: CGFloat = 2.5

    /// Whether a page has no text at all (a scan or a photo).
    public static func needsText(_ page: PDFPage) -> Bool {
        (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The page as it's displayed (crop box, rotation applied), content only.
    public static func displayImage(of page: PDFPage, scale: CGFloat = OCR.scale) -> CGImage? {
        let size = displaySize(of: page)
        // Cap very large pages so a poster doesn't allocate gigabytes.
        let scale = min(scale, 8000 / max(size.width, size.height, 1))
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let pageRef = page.pageRef,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.transform(for: .cropBox))
        context.drawPDFPage(pageRef)
        return context.makeImage()
    }

    /// Width and height as displayed (crop box, rotated).
    public static func displaySize(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// Recognized text, top to bottom, one line per line. For Copy Text from Page.
    public static func text(of page: PDFPage, recognizer: any TextRecognizing) throws -> String {
        guard let image = displayImage(of: page) else { return "" }
        return readingOrder(try recognizer.recognize(image)).map(\.text).joined(separator: "\n")
    }

    /// Lines sorted top to bottom, then left to right.
    public static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        lines.sorted { a, b in
            if abs(a.box.midY - b.box.midY) > min(a.box.height, b.box.height) / 2 { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }
    }

    /// A copy of `page` with `lines` added as invisible text. The page's content is copied
    /// as it is (vector stays vector); annotations are not included (move them yourself).
    public static func page(byAdding lines: [RecognizedLine], to page: PDFPage) -> PDFPage? {
        guard let pageRef = page.pageRef else { return nil }
        let display = displaySize(of: page)
        let toPage = page.transform(for: .cropBox).inverted()
        return PageRewriter.rewrite(page, pageRef: pageRef) { context in
            context.saveGState()
            context.concatenate(toPage)
            context.setTextDrawingMode(.invisible)
            context.textMatrix = .identity
            for line in lines {
                let box = CGRect(x: line.box.minX * display.width, y: line.box.minY * display.height,
                                 width: line.box.width * display.width, height: line.box.height * display.height)
                draw(line.text, fitting: box, in: context)
            }
            context.restoreGState()
        }
    }

    /// Draws `text` on one baseline so it spans `box` (in the context's current space).
    static func draw(_ text: String, fitting box: CGRect, in context: CGContext) {
        guard box.width > 0.5, box.height > 0.5 else { return }
        let size = box.height * 0.9
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard width > 0 else { return }
        context.saveGState()
        // Vision's box covers ascenders to descenders; sit the baseline a descent above the bottom.
        context.translateBy(x: box.minX, y: box.minY + CTFontGetDescent(font) * 0.8)
        context.scaleBy(x: box.width / CGFloat(width), y: 1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// Rebuilds a page as a new one-page PDF: the original content stream drawn as a form, plus
/// whatever `overlay` draws on top (an OCR text layer, headers and footers). Keeps the media
/// box, crop box and rotation. Annotations aren't copied; callers move them across.
public enum PageRewriter {
    public static func rewrite(_ page: PDFPage, pageRef: CGPDFPage? = nil, overlay: (CGContext) -> Void) -> PDFPage? {
        guard let pageRef = pageRef ?? page.pageRef else { return nil }
        var media = page.bounds(for: .mediaBox)
        let crop = page.bounds(for: .cropBox)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { return nil }
        let pageInfo: [CFString: Any] = [
            kCGPDFContextMediaBox: NSValue(rect: media) as Any,
            kCGPDFContextCropBox: NSValue(rect: crop) as Any,
        ]
        context.beginPDFPage(pageInfo as CFDictionary)
        // drawPDFPage draws in the page's own space (media box coordinates, unrotated).
        context.drawPDFPage(pageRef)
        overlay(context)
        context.endPDFPage()
        context.closePDF()
        // A copy, so the page isn't tied to the temporary document it was read from.
        guard let document = PDFDocument(data: data as Data), let newPage = document.page(at: 0)?.copy() as? PDFPage else { return nil }
        newPage.setBounds(media, for: .mediaBox)
        newPage.setBounds(crop, for: .cropBox)
        newPage.rotation = page.rotation
        return newPage
    }

    /// Moves every annotation from one page to another (same page space).
    public static func moveAnnotations(from source: PDFPage, to target: PDFPage) {
        for annotation in source.annotations {
            let tag = AnnotationTags.tag(of: annotation)
            source.removeAnnotation(annotation)
            target.addAnnotation(annotation)
            if let tag { AnnotationTags.tag(annotation, as: tag) }
        }
    }
}
