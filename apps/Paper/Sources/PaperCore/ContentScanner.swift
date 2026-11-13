import CoreGraphics
import Foundation
import PDFKit

/// What a page's content stream draws, read with CoreGraphics' scanner: where text runs
/// start (with the PDF's own font names, which PDFKit hides when a font isn't installed,
/// research P27) and where images are placed. Form XObjects are followed, so pages Paper has
/// rebuilt (whose old content is wrapped in a form) still scan.
public struct ScannedText: Equatable, Sendable {
    /// The `/BaseFont`, without a subset prefix ("ABCDEF+Calibri-Bold" → "Calibri-Bold").
    public var fontName: String
    public var fontSize: CGFloat
    /// Baseline origin in page space.
    public var origin: CGPoint
    /// The run is drawn horizontally (not rotated or vertical).
    public var isHorizontal: Bool
}

public struct PageImage: Equatable, Sendable {
    /// Where the image sits on the page (its unit square transformed, as a bounding box).
    public var rect: CGRect
    /// The image's own transform is a plain scale and offset (not rotated or skewed).
    public var isAxisAligned: Bool
    public var pixelSize: CGSize
}

public enum ContentScanner {
    public struct Result: Sendable {
        public var text: [ScannedText] = []
        public var images: [PageImage] = []
    }

    final class State {
        var ctm: [CGAffineTransform] = [.identity]
        var textMatrix = CGAffineTransform.identity
        var lineMatrix = CGAffineTransform.identity
        var leading: CGFloat = 0
        var fontName = ""
        var fontSize: CGFloat = 0
        var result = Result()
        var depth = 0
        /// Rectangles of the path being built (`re`); nil once it has other segments.
        var pathRects: [CGRect]? = []
        let table: CGPDFOperatorTableRef
        init(table: CGPDFOperatorTableRef) { self.table = table }
    }

    public static func scan(_ page: PDFPage) -> Result {
        guard let pageRef = page.pageRef else { return Result() }
        return scan(pageRef)
    }

    public static func scan(_ pageRef: CGPDFPage) -> Result {
        guard let table = CGPDFOperatorTableCreate() else { return Result() }
        install(table)
        let state = State(table: table)
        let stream = CGPDFContentStreamCreateWithPage(pageRef)
        run(stream, state)
        return state.result
    }

    static func run(_ stream: CGPDFContentStreamRef, _ state: State) {
        let scanner = CGPDFScannerCreate(stream, state.table, Unmanaged.passUnretained(state).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
    }

    static func state(_ info: UnsafeMutableRawPointer?) -> State { Unmanaged<State>.fromOpaque(info!).takeUnretainedValue() }

    static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for index in (0..<count).reversed() {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
            values[index] = value
        }
        return values
    }

    static func recordShow(_ state: State) {
        let full = state.textMatrix.concatenating(state.ctm.last ?? .identity)
        let origin = CGPoint.zero.applying(full)
        let scaleY = hypot(full.c, full.d)
        let horizontal = abs(full.b) < 0.01 * max(abs(full.a), 0.001) && abs(full.c) < 0.01 * max(abs(full.d), 0.001) && full.a > 0
        state.result.text.append(ScannedText(fontName: state.fontName, fontSize: state.fontSize * scaleY, origin: origin, isHorizontal: horizontal))
    }

    static func nextLine(_ state: State, tx: CGFloat, ty: CGFloat) {
        state.lineMatrix = CGAffineTransform(translationX: tx, y: ty).concatenating(state.lineMatrix)
        state.textMatrix = state.lineMatrix
    }

    static func baseFont(_ scanner: CGPDFScannerRef, _ resource: String) -> String {
        let stream = CGPDFScannerGetContentStream(scanner)
        guard let object = CGPDFContentStreamGetResource(stream, "Font", resource) else { return resource }
        var dict: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return resource }
        var name: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, "BaseFont", &name), let name else { return resource }
        return stripSubset(String(cString: name))
    }

    public static func stripSubset(_ name: String) -> String {
        let parts = name.split(separator: "+", maxSplits: 1)
        if parts.count == 2, parts[0].count == 6, parts[0].allSatisfy({ $0.isUppercase }) { return String(parts[1]) }
        return name
    }

    static func install(_ table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q") { _, info in let s = ContentScanner.state(info); s.ctm.append(s.ctm.last ?? .identity) }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in let s = ContentScanner.state(info); if s.ctm.count > 1 { s.ctm.removeLast() } }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = ContentScanner.state(info)
            guard let v = ContentScanner.numbers(scanner, 6) else { return }
            s.ctm[s.ctm.count - 1] = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]).concatenating(s.ctm.last ?? .identity)
        }
        // An opaque rectangle filled over an image hides it: that's how Paper's edits cover
        // the zeroed remains of a removed image (and how other tools hide one), so it no
        // longer counts as an image on the page.
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            let s = ContentScanner.state(info)
            guard let v = ContentScanner.numbers(scanner, 4) else { return }
            s.pathRects?.append(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]).standardized.applying(s.ctm.last ?? .identity))
        }
        for op in ["m", "l", "c", "v", "y", "h"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in ContentScanner.state(info).pathRects = nil }
        }
        // Ending a path without filling it (no-op paint or a stroke) forgets it. Clipping
        // (W, W*) keeps it for the painting operator that follows.
        for op in ["n", "S", "s"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in ContentScanner.state(info).pathRects = [] }
        }
        for op in ["f", "F", "f*", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                let s = ContentScanner.state(info)
                if let rects = s.pathRects {
                    s.result.images.removeAll { image in rects.contains { $0.insetBy(dx: -1, dy: -1).contains(image.rect) } }
                }
                s.pathRects = []
            }
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in let s = ContentScanner.state(info); s.textMatrix = .identity; s.lineMatrix = .identity }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let s = ContentScanner.state(info)
            var size: CGPDFReal = 0
            CGPDFScannerPopNumber(scanner, &size)
            var name: UnsafePointer<CChar>?
            if CGPDFScannerPopName(scanner, &name), let name { s.fontName = ContentScanner.baseFont(scanner, String(cString: name)) }
            s.fontSize = size
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            var value: CGPDFReal = 0
            if CGPDFScannerPopNumber(scanner, &value) { ContentScanner.state(info).leading = value }
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            guard let v = ContentScanner.numbers(scanner, 2) else { return }
            ContentScanner.nextLine(ContentScanner.state(info), tx: v[0], ty: v[1])
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            guard let v = ContentScanner.numbers(scanner, 2) else { return }
            let s = ContentScanner.state(info)
            s.leading = -v[1]
            ContentScanner.nextLine(s, tx: v[0], ty: v[1])
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            guard let v = ContentScanner.numbers(scanner, 6) else { return }
            let s = ContentScanner.state(info)
            s.lineMatrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            s.textMatrix = s.lineMatrix
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in let s = ContentScanner.state(info); ContentScanner.nextLine(s, tx: 0, ty: -s.leading) }
        for op in ["Tj", "TJ"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in ContentScanner.recordShow(ContentScanner.state(info)) }
        }
        CGPDFOperatorTableSetCallback(table, "'") { _, info in let s = ContentScanner.state(info); ContentScanner.nextLine(s, tx: 0, ty: -s.leading); ContentScanner.recordShow(s) }
        CGPDFOperatorTableSetCallback(table, "\"") { _, info in let s = ContentScanner.state(info); ContentScanner.nextLine(s, tx: 0, ty: -s.leading); ContentScanner.recordShow(s) }
        CGPDFOperatorTableSetCallback(table, "EI") { _, info in
            let s = ContentScanner.state(info)
            let ctm = s.ctm.last ?? .identity
            s.result.images.append(PageImage(rect: CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctm),
                                             isAxisAligned: abs(ctm.b) < 0.001 && abs(ctm.c) < 0.001, pixelSize: .zero))
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = ContentScanner.state(info)
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            let stream = CGPDFScannerGetContentStream(scanner)
            guard let object = CGPDFContentStreamGetResource(stream, "XObject", name) else { return }
            var xobject: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &xobject), let xobject, let dict = CGPDFStreamGetDictionary(xobject) else { return }
            var subtype: UnsafePointer<CChar>?
            CGPDFDictionaryGetName(dict, "Subtype", &subtype)
            let kind = subtype.map { String(cString: $0) } ?? ""
            let ctm = s.ctm.last ?? .identity
            if kind == "Image" {
                var width: CGPDFInteger = 0, height: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(dict, "Width", &width)
                CGPDFDictionaryGetInteger(dict, "Height", &height)
                s.result.images.append(PageImage(rect: CGRect(x: 0, y: 0, width: 1, height: 1).applying(ctm),
                                                 isAxisAligned: abs(ctm.b) < 0.001 && abs(ctm.c) < 0.001,
                                                 pixelSize: CGSize(width: Int(width), height: Int(height))))
            } else if kind == "Form", s.depth < 12 {
                var matrix = CGAffineTransform.identity
                var array: CGPDFArrayRef?
                if CGPDFDictionaryGetArray(dict, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 {
                    var v = [CGFloat](repeating: 0, count: 6)
                    for index in 0..<6 { var n: CGPDFReal = 0; CGPDFArrayGetNumber(array, index, &n); v[index] = n }
                    matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
                }
                var resources: CGPDFDictionaryRef?
                CGPDFDictionaryGetDictionary(dict, "Resources", &resources)
                let inner = CGPDFContentStreamCreateWithStream(xobject, resources ?? dict, stream)
                let savedText = (s.textMatrix, s.lineMatrix)
                s.ctm.append(matrix.concatenating(ctm))
                s.depth += 1
                ContentScanner.run(inner, s)
                s.depth -= 1
                s.ctm.removeLast()
                (s.textMatrix, s.lineMatrix) = savedText
            }
        }
    }
}
