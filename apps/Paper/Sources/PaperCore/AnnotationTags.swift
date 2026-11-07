import CoreGraphics
import Foundation
import ObjectiveC
import PDFKit

/// What Paper made an annotation for, when that matters after reopening a file.
public enum PaperTag: String, Sendable, CaseIterable {
    /// A pending redaction mark (a plain Square, never a `Redact` annotation; research P4).
    case redactionMark = "paper.redaction"
    /// A placed signature (an Ink annotation).
    case signature = "paper.signature"

    /// The `/NM` prefix Paper has always written (`paper.redaction.<UUID>`).
    var namePrefix: String { rawValue + "." }

    /// `/Subj`: the standard "what kind of comment is this" entry (PDF 1.5 markup
    /// annotations). Acrobat shows it as the comment's subject, so it's human-readable.
    public var subject: String {
        switch self {
        case .redactionMark: "Pending Redaction"
        case .signature: "Signature"
        }
    }

    /// The PDF subtype a tagged annotation must have.
    var subtype: String {
        switch self {
        case .redactionMark: "Square"
        case .signature: "Ink"
        }
    }
}

/// Stores and finds Paper's tags on annotations in a way that survives save + reopen on
/// every macOS from 14 on (research P20).
///
/// Paper used to rely on `/NM` alone, read back through `PDFAnnotation.value(forAnnotationKey:
/// .name)`. On macOS 26 that came back empty after a write/reopen, so pending marks vanished
/// (and with them Apply Redactions, and flattening baked the red boxes in). PDFKit's *reader*
/// only surfaces the keys it models, and which keys it models changes between releases (on
/// macOS 27 a custom `/PaperMark` key is written to the file but never read back). So tags are:
///
/// 1. **Written redundantly** into standard entries every PDF writer keeps: `/NM`, `/Subj`
///    and, for marks, `/Contents` ("Pending redaction", which files saved by Paper 0.1 already
///    carry).
/// 2. **Read from the file itself** with CoreGraphics' low-level `CGPDFDocument` parser, which
///    hands back the raw annotation dictionaries whatever PDFKit's model does with them. A
///    PDFKit annotation is matched to its raw dictionary by page, subtype and `/Rect`.
/// 3. **Kept in memory** on the annotation object (an associated value), so a tag never
///    depends on PDFKit echoing a key back between edits.
///
/// Any one signal is enough. `restore(in:from:)` re-tags a freshly opened document, which
/// is also the migration: the next save writes the full set of keys.
public enum AnnotationTags {
    /// The `/Contents` Paper 0.1 wrote on marks; still written, and still recognized on a
    /// Square, so marks saved where `/NM` was lost come back.
    public static let legacyMarkContents = "Pending redaction"

    // MARK: Writing

    public static func tag(_ annotation: PDFAnnotation, as tag: PaperTag) {
        setMemoryTag(tag, on: annotation)
        let name = annotation.value(forAnnotationKey: .name) as? String
        if name?.hasPrefix(tag.namePrefix) != true {
            annotation.setValue(tag.namePrefix + UUID().uuidString, forAnnotationKey: .name)
        }
        annotation.setValue(tag.subject, forAnnotationKey: subjectKey)
        if tag == .redactionMark { annotation.contents = legacyMarkContents }
    }

    // MARK: Reading

    /// The tag of an annotation in memory: the associated value, then the keys PDFKit shows.
    public static func tag(of annotation: PDFAnnotation) -> PaperTag? {
        if let tag = memoryTag(of: annotation) { return tag }
        let type = normalized(annotation.type)
        let name = annotation.value(forAnnotationKey: .name) as? String
        let subject = annotation.value(forAnnotationKey: subjectKey) as? String
        return classify(subtype: type, name: name, subject: subject, contents: annotation.contents)
    }

    public static func has(_ tag: PaperTag, _ annotation: PDFAnnotation) -> Bool {
        self.tag(of: annotation) == tag
    }

    /// Decides a tag from an annotation's entries, wherever they were read from.
    static func classify(subtype: String, name: String?, subject: String?, contents: String?) -> PaperTag? {
        for tag in PaperTag.allCases where subtype == tag.subtype {
            if let name, name.hasPrefix(tag.namePrefix) { return tag }
            if let subject, subject == tag.subject { return tag }
            if tag == .redactionMark, contents == legacyMarkContents { return tag }
        }
        return nil
    }

    // MARK: Restoring after open

    /// Opens PDF data and restores Paper's tags. Use this instead of `PDFDocument(data:)`
    /// anywhere Paper reads back a file it may have written.
    public static func open(_ data: Data, password: String? = nil) -> PDFDocument? {
        guard let document = PDFDocument(data: data) else { return nil }
        if document.isLocked, let password { document.unlock(withPassword: password) }
        if !document.isLocked { restore(in: document, from: data, password: password) }
        return document
    }

    public static func open(url: URL) -> PDFDocument? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return open(data)
    }

    /// Tags annotations PDFKit loaded without the keys that identify them, using the raw
    /// dictionaries in `data` (the bytes `document` was read from). Returns how many were
    /// re-tagged. Never marks anything as edited: the next save just writes complete tags.
    @discardableResult
    public static func restore(in document: PDFDocument, from data: Data, password: String? = nil) -> Int {
        // Only look at the file when PDFKit left something unexplained (a Square or Ink
        // annotation without a tag), so ordinary documents never pay for the raw parse.
        var candidates: [Int: [PDFAnnotation]] = [:]
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if let tag = tag(of: annotation) {
                    // Visible through PDFKit: still pin it in memory and complete the keys.
                    self.tag(annotation, as: tag)
                    continue
                }
                let type = normalized(annotation.type)
                if PaperTag.allCases.contains(where: { $0.subtype == type }) {
                    candidates[index, default: []].append(annotation)
                }
            }
        }
        guard !candidates.isEmpty else { return 0 }
        let raw = RawAnnotationReader.read(data, pages: Set(candidates.keys), password: password)
        var restored = 0
        for (index, annotations) in candidates {
            var available = raw[index] ?? []
            for annotation in annotations {
                let type = normalized(annotation.type)
                guard let match = available.firstIndex(where: { $0.subtype == type && $0.rect.isClose(to: annotation.bounds) })
                else { continue }
                let entry = available.remove(at: match)
                if let tag = entry.tag {
                    self.tag(annotation, as: tag)
                    restored += 1
                }
            }
        }
        return restored
    }

    /// A copy of `page` with Paper's tags carried over (`PDFPage.copy()` doesn't copy the
    /// in-memory tag, and on some macOS versions not every key either).
    public static func copy(_ page: PDFPage) -> PDFPage? {
        guard let copy = page.copy() as? PDFPage else { return nil }
        var available = page.annotations.compactMap { annotation in tag(of: annotation).map { (annotation, $0) } }
        guard !available.isEmpty else { return copy }
        for annotation in copy.annotations {
            let type = normalized(annotation.type)
            guard let match = available.firstIndex(where: {
                normalized($0.0.type) == type && $0.0.bounds.isClose(to: annotation.bounds)
            }) else { continue }
            tag(annotation, as: available.remove(at: match).1)
        }
        return copy
    }

    // MARK: Internals

    static let subjectKey = PDFAnnotationKey(rawValue: "/Subj")

    static func normalized(_ type: String?) -> String {
        guard let type else { return "" }
        return type.hasPrefix("/") ? String(type.dropFirst()) : type
    }

    nonisolated(unsafe) private static let memoryKey: UnsafeRawPointer = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    static func memoryTag(of annotation: PDFAnnotation) -> PaperTag? {
        (objc_getAssociatedObject(annotation, memoryKey) as? String).flatMap(PaperTag.init(rawValue:))
    }

    static func setMemoryTag(_ tag: PaperTag?, on annotation: PDFAnnotation) {
        objc_setAssociatedObject(annotation, memoryKey, tag?.rawValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
    }
}

/// One annotation dictionary as it is in the file.
struct RawAnnotation: Equatable {
    var subtype: String
    var rect: CGRect
    var name: String?
    var subject: String?
    var contents: String?

    var tag: PaperTag? { AnnotationTags.classify(subtype: subtype, name: name, subject: subject, contents: contents) }
}

/// Reads annotation dictionaries straight from the PDF with CoreGraphics (independent of
/// what PDFKit's annotation model exposes on a given macOS).
enum RawAnnotationReader {
    static func read(_ data: Data, pages: Set<Int>? = nil, password: String? = nil) -> [Int: [RawAnnotation]] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return [:] }
        if document.isEncrypted, !document.isUnlocked {
            if !document.unlockWithPassword(""), let password { _ = document.unlockWithPassword(password) }
            guard document.isUnlocked else { return [:] }
        }
        var result: [Int: [RawAnnotation]] = [:]
        let indexes = pages.map { $0.sorted() } ?? Array(0..<document.numberOfPages)
        for index in indexes where index < document.numberOfPages {
            guard let dictionary = document.page(at: index + 1)?.dictionary else { continue }
            var annots: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dictionary, "Annots", &annots), let annots else { continue }
            for item in 0..<CGPDFArrayGetCount(annots) {
                var entry: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(annots, item, &entry), let entry,
                      let subtype = name(entry, "Subtype"), let rect = rect(entry, "Rect") else { continue }
                result[index, default: []].append(RawAnnotation(
                    subtype: subtype, rect: rect,
                    name: string(entry, "NM"), subject: string(entry, "Subj"), contents: string(entry, "Contents")
                ))
            }
        }
        return result
    }

    static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }

    static func string(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dictionary, key, &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }

    static func rect(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGRect? {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, key, &array), let array, CGPDFArrayGetCount(array) == 4 else { return nil }
        var numbers: [CGFloat] = []
        for index in 0..<4 {
            var number: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &number) else { return nil }
            numbers.append(number)
        }
        return CGRect(x: min(numbers[0], numbers[2]), y: min(numbers[1], numbers[3]),
                      width: abs(numbers[2] - numbers[0]), height: abs(numbers[3] - numbers[1]))
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(maxX - other.maxX) <= tolerance && abs(maxY - other.maxY) <= tolerance
    }
}
