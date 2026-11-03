import AppKit
import PDFKit

/// Removes content under rectangles and writes the result. The real one uses PDFKit's
/// `Redact` annotation (research P1); tests swap in fakes to drive the fallback path.
public protocol ContentRemover: Sendable {
    /// Writes `document` with the content under `rects` removed. Must leave `document` as it
    /// found it (any annotations it adds are removed again).
    func removeContent(in document: PDFDocument, rects: [Int: [CGRect]]) -> Data?
}

public struct PDFKitContentRemover: ContentRemover {
    public init() {}

    public func removeContent(in document: PDFDocument, rects: [Int: [CGRect]]) -> Data? {
        var added: [(PDFPage, PDFAnnotation)] = []
        for (index, pageRects) in rects {
            guard let page = document.page(at: index) else { continue }
            for rect in pageRects {
                let redact = PDFAnnotation(bounds: rect, forType: RedactionMarks.redactSubtype, withProperties: nil)
                redact.interiorColor = .black
                page.addAnnotation(redact)
                added.append((page, redact))
            }
        }
        let data = document.dataRepresentation()
        for (page, annotation) in added { page.removeAnnotation(annotation) }
        return data
    }
}

/// Turns a page into an image with black boxes (the fallback). A protocol so tests can
/// prove that a fallback which doesn't work leads to an error, never to a false success.
public protocol PageRasterizing: Sendable {
    func rasterize(_ page: PDFPage, blackRects: [CGRect], dpi: CGFloat) -> PDFPage?
}

public struct ImagePageRasterizer: PageRasterizing {
    public init() {}
    public func rasterize(_ page: PDFPage, blackRects: [CGRect], dpi: CGFloat) -> PDFPage? {
        PageRenderer.rasterizedPage(from: page, blackRects: blackRects, dpi: dpi)
    }
}

public struct RedactionOptions: Sendable, Equatable {
    public var removeMetadata: Bool
    public var rasterDPI: CGFloat

    public init(removeMetadata: Bool = true, rasterDPI: CGFloat = 300) {
        self.removeMetadata = removeMetadata
        self.rasterDPI = rasterDPI
    }
}

public struct RedactionReport: Sendable, Equatable {
    public var areaCount: Int
    public var pageCount: Int
    /// 0-based indexes of pages that had to be turned into images.
    public var rasterizedPages: [Int]
    public var removedAnnotations: Int
    public var metadataCleared: Bool
    /// The outline (table of contents) was dropped because a title held redacted text.
    public var outlineRemoved: Bool = false

    public var summary: String {
        let areas = areaCount == 1 ? "1 area" : "\(areaCount) areas"
        let pages = pageCount == 1 ? "1 page" : "\(pageCount) pages"
        return "Removed \(areas) on \(pages)."
    }

    public var verificationLine: String {
        "Checked: none of the redacted text can be found in the new file."
    }

    public var outlineLine: String? {
        outlineRemoved ? "The table of contents was removed because its titles included redacted text." : nil
    }

    /// "Page 4 was converted to an image…", or nil when no page needed it.
    public var rasterizedLine: String? {
        guard !rasterizedPages.isEmpty else { return nil }
        let numbers = rasterizedPages.map { String($0 + 1) }
        let list: String
        if numbers.count == 1 {
            return "Page \(numbers[0]) was converted to an image to make sure its content is gone. Its text can no longer be selected."
        } else if numbers.count == 2 {
            list = "\(numbers[0]) and \(numbers[1])"
        } else {
            list = numbers.dropLast().joined(separator: ", ") + " and " + numbers.last!
        }
        return "Pages \(list) were converted to images to make sure their content is gone. Their text can no longer be selected."
    }
}

public enum RedactionError: Error, LocalizedError, Equatable {
    case unreadable
    case noMarks
    case writeFailed
    case verificationFailed(pages: [Int])

    public var errorDescription: String? {
        switch self {
        case .unreadable: "Paper couldn't read this document to redact it."
        case .noMarks: "There's nothing marked for redaction."
        case .writeFailed: "Paper couldn't write the redacted file."
        case .verificationFailed(let pages) where pages.isEmpty:
            "Redaction couldn't be verified, so no file was written."
        case .verificationFailed(let pages):
            "Redaction couldn't be verified on page \(pages.map { String($0 + 1) }.joined(separator: ", ")), so no file was written."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .verificationFailed: "Your document hasn't changed. Try marking a larger area, or export the pages as images."
        case .noMarks: "Use the Redact tool or Find and Redact to mark text first."
        default: "Your document hasn't changed."
        }
    }
}

/// Applies Paper's pending redaction marks to a copy of a document, then proves the result.
///
/// 1. Reads the marks and records what text sits under each one.
/// 2. Drops the marks and any annotation or form field that overlaps them; scrubs the
///    removed words from other notes, field values and outline titles.
/// 3. Pass 1: writes with `Redact` annotations, which removes text (also invisible OCR text),
///    image pixels and vector art inside the areas.
/// 4. Pass 2: paints black boxes and flattens everything (so nothing can be peeled off).
/// 5. Verifies every page; any page that fails is rasterized with black boxes and checked
///    again. If a page still fails, nothing is returned.
public struct Redactor: Sendable {
    public var remover: any ContentRemover
    public var rasterizer: any PageRasterizing
    public var options: RedactionOptions

    public init(remover: any ContentRemover = PDFKitContentRemover(),
                rasterizer: any PageRasterizing = ImagePageRasterizer(),
                options: RedactionOptions = .init()) {
        self.remover = remover
        self.rasterizer = rasterizer
        self.options = options
    }

    public func apply(to source: Data) throws -> (data: Data, report: RedactionReport) {
        guard let work = PDFDocument(data: source), !work.isLocked else { throw RedactionError.unreadable }
        RedactionMarks.convertRedactAnnotations(in: work)
        let marks = RedactionMarks.marks(in: work)
        guard !marks.isEmpty else { throw RedactionError.noMarks }

        var rects: [Int: [CGRect]] = [:]
        for mark in marks { rects[mark.pageIndex, default: []].append(mark.annotation.bounds) }
        let originalAttributes = work.documentAttributes ?? [:]

        // What's under the marks, for scrubbing and verification.
        var secrets = Set<String>()
        for (index, pageRects) in rects {
            guard let page = work.page(at: index) else { continue }
            for rect in pageRects {
                let text = RedactionVerifier.characters(on: page, in: [rect])
                if text.count >= 3 { secrets.insert(text) }
                for word in RedactionVerifier.tokens(text) where word.count >= 3 { secrets.insert(word) }
            }
        }

        // Step 2: drop marks and overlapping annotations, scrub the rest.
        var removed = 0
        for mark in marks { work.page(at: mark.pageIndex)?.removeAnnotation(mark.annotation) }
        for (index, pageRects) in rects {
            guard let page = work.page(at: index) else { continue }
            for annotation in page.annotations where pageRects.contains(where: { $0.intersects(annotation.bounds) }) {
                page.removeAnnotation(annotation)
                removed += 1
            }
        }
        Scrubber.scrub(work, removing: secrets)

        // Step 3: pass 1 removes content.
        guard let removedData = remover.removeContent(in: work, rects: rects),
              let pass1 = PDFDocument(data: removedData) else { throw RedactionError.writeFailed }
        for item in RedactionMarks.redactAnnotations(in: pass1) {
            pass1.page(at: item.pageIndex)?.removeAnnotation(item.annotation)
        }
        var failing = Set<Int>()
        for (index, pageRects) in rects {
            guard let page = pass1.page(at: index), let before = work.page(at: index) else { failing.insert(index); continue }
            if !RedactionVerifier.regionsAreBlank(original: before, redacted: page, rects: pageRects) { failing.insert(index) }
        }

        // Step 4: pass 2 paints boxes and flattens.
        for (index, pageRects) in rects {
            guard let page = pass1.page(at: index) else { continue }
            for rect in pageRects { page.addAnnotation(Self.blackBox(rect)) }
        }
        guard let flatData = pass1.dataRepresentation(options: [PDFDocumentWriteOption.burnInAnnotationsOption: true]),
              var result = PDFDocument(data: flatData) else { throw RedactionError.writeFailed }

        // Step 5: verify, rasterize what fails, verify again.
        failing.formUnion(Self.failingPages(original: work, redacted: result, rects: rects))
        var rasterized: [Int] = []
        for index in failing.sorted() {
            guard let source = work.page(at: index),
                  let image = rasterizer.rasterize(source, blackRects: rects[index] ?? [], dpi: options.rasterDPI)
            else { throw RedactionError.verificationFailed(pages: [index]) }
            result.removePage(at: index)
            result.insert(image, at: index)
            rasterized.append(index)
        }

        // PDFKit (macOS 27) writes the original outline whatever we change, so an outline
        // with redacted words in its titles can only be dropped, by rebuilding the document.
        var outlineRemoved = false
        if Self.outlineMentions(secrets, in: result) {
            result = PageOps.extract(result, pages: IndexSet(integersIn: 0..<result.pageCount))
            outlineRemoved = true
        }

        if options.removeMetadata {
            result.documentAttributes = [:]
        } else {
            var kept = originalAttributes
            kept.removeValue(forKey: PDFDocumentAttribute.modificationDateAttribute)
            result.documentAttributes = kept
        }
        guard let output = result.dataRepresentation(), let reopened = PDFDocument(data: output) else {
            throw RedactionError.writeFailed
        }
        let stillFailing = Self.failingPages(original: work, redacted: reopened, rects: rects)
            .union(rasterized.filter { !(reopened.page(at: $0)?.string ?? "").isEmpty })
        guard stillFailing.isEmpty else { throw RedactionError.verificationFailed(pages: stillFailing.sorted()) }
        guard !Self.outlineMentions(secrets, in: reopened) else { throw RedactionError.verificationFailed(pages: []) }

        let report = RedactionReport(
            areaCount: marks.count,
            pageCount: rects.count,
            rasterizedPages: rasterized,
            removedAnnotations: removed,
            metadataCleared: options.removeMetadata,
            outlineRemoved: outlineRemoved
        )
        return (output, report)
    }

    static func outlineMentions(_ secrets: Set<String>, in document: PDFDocument) -> Bool {
        guard !secrets.isEmpty, let root = document.outlineRoot else { return false }
        func visit(_ outline: PDFOutline) -> Bool {
            if let label = outline.label, secrets.contains(where: { label.localizedCaseInsensitiveContains($0) }) { return true }
            return (0..<outline.numberOfChildren).contains { outline.child(at: $0).map(visit) ?? false }
        }
        return visit(root)
    }

    static func blackBox(_ rect: CGRect) -> PDFAnnotation {
        let box = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        box.color = .black
        box.interiorColor = .black
        let border = PDFBorder()
        border.lineWidth = 0
        box.border = border
        return box
    }

    /// Pages where text survives under a mark, or where an annotation other than a link is
    /// left (the output is flattened, so there should be none, and certainly no `Redact` ones).
    static func failingPages(original: PDFDocument, redacted: PDFDocument, rects: [Int: [CGRect]]) -> Set<Int> {
        var failing = Set<Int>()
        guard redacted.pageCount == original.pageCount else { return Set(rects.keys) }
        for index in 0..<redacted.pageCount {
            guard let page = redacted.page(at: index) else { failing.insert(index); continue }
            if page.annotations.contains(where: { $0.type != PDFAnnotationSubtype.link.rawValue && $0.type != "Link" }) {
                failing.insert(index)
            }
            guard let pageRects = rects[index], let before = original.page(at: index) else { continue }
            if !RedactionVerifier.check(original: before, redacted: page, rects: pageRects).passed {
                failing.insert(index)
            }
        }
        return failing
    }
}

/// Removes redacted words from places the page content doesn't cover: notes, text box
/// contents and form field values. (Outline titles are handled by dropping the outline.)
enum Scrubber {
    static let replacement = "█████"

    static func scrub(_ document: PDFDocument, removing secrets: Set<String>) {
        let ordered = secrets.sorted { $0.count > $1.count }
        guard !ordered.isEmpty else { return }
        func clean(_ text: String) -> String {
            var result = text
            for secret in ordered {
                result = result.replacingOccurrences(of: secret, with: replacement, options: .caseInsensitive)
            }
            return result
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if let contents = annotation.contents, clean(contents) != contents {
                    annotation.contents = clean(contents)
                }
                if annotation.type == PDFAnnotationSubtype.widget.rawValue || annotation.type == "Widget",
                   let value = annotation.widgetStringValue, clean(value) != value {
                    annotation.widgetStringValue = clean(value)
                }
            }
        }
    }
}
