import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Export as Word (.docx) and Rich Text. A PDF has no paragraphs, only positioned lines, so
/// the text blocks Paper finds for editing (`TextLayout`) become paragraphs, in reading order
/// down each page, with their fonts, sizes, bold, italic, colours and alignment. Pictures are
/// placed between the paragraphs where they sit on the page, and each PDF page starts a new
/// Word page. Columns are read one block at a time; tables become plain paragraphs.
public enum OfficeExport {
    public enum Item {
        case paragraph(TextBlock, spaceAfter: CGFloat)
        case image(png: Data, size: CGSize)
    }

    /// The paragraphs and pictures of one page, top to bottom.
    public static func items(on page: PDFPage) -> [Item] {
        let blocks = TextLayout.blocks(on: page)
        let images = ContentScanner.scan(page).images.filter { $0.rect.width >= 8 && $0.rect.height >= 8 }
        enum Entry { case block(TextBlock), image(PageImage) }
        var entries: [(top: CGFloat, left: CGFloat, entry: Entry)] = blocks.map { ($0.bounds.maxY, $0.bounds.minX, .block($0)) }
        entries += images.map { ($0.rect.maxY, $0.rect.minX, .image($0)) }
        // Top to bottom; blocks on the same row left to right (a two-column page reads row by
        // row, which keeps headings with their columns better than PDFKit's own order).
        entries.sort { a, b in abs(a.top - b.top) > 4 ? a.top > b.top : a.left < b.left }
        var result: [Item] = []
        for (index, item) in entries.enumerated() {
            switch item.entry {
            case .block(let block):
                let nextTop = index + 1 < entries.count ? entries[index + 1].top : block.bounds.minY
                let gap = max(0, block.bounds.minY - nextTop)
                result.append(.paragraph(block, spaceAfter: min(gap, 36)))
            case .image(let image):
                if let png = render(image.rect, of: page) { result.append(.image(png: png, size: image.rect.size)) }
            }
        }
        return result
    }

    static func render(_ rect: CGRect, of page: PDFPage) -> Data? {
        let region = rect.intersection(page.bounds(for: .mediaBox))
        guard !region.isNull, let image = PageRenderer.render(page, region: region, scale: 2, annotations: false) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: Word

    public static func docx(_ document: PDFDocument, title: String? = nil) -> Data {
        var body = ""
        var media: [(String, Data)] = []
        let size = document.page(at: 0).map(OCR.displaySize) ?? CGSize(width: 612, height: 792)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if index > 0 { body += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# }
            for item in items(on: page) {
                switch item {
                case .paragraph(let block, let spaceAfter):
                    body += paragraphXML(block, spaceAfter: spaceAfter)
                case .image(let png, let imageSize):
                    media.append(("image\(media.count + 1).png", png))
                    body += imageXML(id: media.count, size: imageSize, maxWidth: size.width - 144)
                }
            }
        }
        let twips = { (points: CGFloat) in Int((points * 20).rounded()) }
        let sectPr = "<w:sectPr><w:pgSz w:w=\"\(twips(size.width))\" w:h=\"\(twips(size.height))\"/>"
            + "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr>"
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)\(sectPr)</w:body></w:document>
        """
        let relationships = media.enumerated().map { index, item in
            "<Relationship Id=\"rIdImg\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(item.0)\"/>"
        }.joined()
        let documentRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\(relationships)</Relationships>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>\
        <w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica" w:cs="Helvetica"/><w:sz w:val="22"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
        """
        let core = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(xml(title ?? ""))</dc:title></cp:coreProperties>
        """
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("docProps/core.xml", Data(core.utf8))
        zip.add("word/document.xml", Data(documentXML.utf8))
        zip.add("word/styles.xml", Data(styles.utf8))
        zip.add("word/_rels/document.xml.rels", Data(documentRels.utf8))
        for (name, data) in media { zip.add("word/media/\(name)", data) }
        return zip.finish()
    }

    static func paragraphXML(_ block: TextBlock, spaceAfter: CGFloat) -> String {
        let jc: String
        switch block.alignment {
        case .center: jc = "center"
        case .right: jc = "right"
        case .justified: jc = "both"
        default: jc = "left"
        }
        let line = Int((block.lineSpacing * 20).rounded())
        var xmlText = "<w:p><w:pPr><w:spacing w:after=\"\(Int((spaceAfter * 20).rounded()))\" w:line=\"\(max(line, 200))\" w:lineRule=\"exact\"/><w:jc w:val=\"\(jc)\"/></w:pPr>"
        let text = block.attributedText
        let fontName = block.pdfFontName
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let piece = (text.string as NSString).substring(with: range)
            let font = attributes[.font] as? NSFont
            var rPr = ""
            if let font {
                let family = wordFamily(font, pdfName: fontName)
                rPr += "<w:rFonts w:ascii=\"\(xml(family))\" w:hAnsi=\"\(xml(family))\" w:cs=\"\(xml(family))\"/>"
                let traits = NSFontManager.shared.traits(of: font)
                let name = (fontName ?? "").lowercased()
                if traits.contains(.boldFontMask) || name.contains("bold") { rPr += "<w:b/>" }
                if traits.contains(.italicFontMask) || name.contains("italic") || name.contains("oblique") { rPr += "<w:i/>" }
                rPr += "<w:sz w:val=\"\(Int((font.pointSize * 2).rounded()))\"/>"
            }
            if let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB), color.brightnessComponent > 0.08 || color.saturationComponent > 0.2 {
                rPr += "<w:color w:val=\"" + String(format: "%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255)) + "\"/>"
            }
            let lines = piece.components(separatedBy: "\n")
            for (index, part) in lines.enumerated() {
                if index > 0 { xmlText += "<w:r><w:br/></w:r>" }
                guard !part.isEmpty else { continue }
                xmlText += "<w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(xml(part))</w:t></w:r>"
            }
        }
        return xmlText + "</w:p>"
    }

    /// The family Word should use: the PDF's own font name when PDFKit had to substitute
    /// (Word may well have Calibri even if this Mac doesn't).
    static func wordFamily(_ font: NSFont, pdfName: String?) -> String {
        if font.familyName == "Helvetica", let pdfName, !pdfName.lowercased().hasPrefix("helvetica") {
            return FontMatcher.parse(ContentScanner.stripSubset(pdfName)).0
        }
        let family = font.familyName ?? "Helvetica"
        return family.hasPrefix(".") ? "Helvetica Neue" : family
    }

    static func imageXML(id: Int, size: CGSize, maxWidth: CGFloat) -> String {
        let scale = min(1, maxWidth / max(size.width, 1))
        let cx = Int(size.width * scale * 12700), cy = Int(size.height * scale * 12700)
        return """
        <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(id)" name="Picture \(id)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic><pic:nvPicPr><pic:cNvPr id="\(id)" name="image\(id).png"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="rIdImg\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
        </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    static func xml(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 forbids most control characters.
                if scalar.value < 0x20, scalar != "\t" { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: Rich text

    /// The document as styled text (paragraphs, fonts, colours, alignment), for RTF.
    public static func attributedText(_ document: PDFDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if index > 0 { result.append(NSAttributedString(string: "\u{0C}")) }
            for item in items(on: page) {
                guard case .paragraph(let block, let spaceAfter) = item else { continue }
                let style = NSMutableParagraphStyle()
                style.alignment = block.alignment
                style.paragraphSpacing = spaceAfter
                style.minimumLineHeight = block.lineSpacing
                style.maximumLineHeight = block.lineSpacing
                let text = NSMutableAttributedString(attributedString: block.attributedText)
                text.append(NSAttributedString(string: "\n"))
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
                result.append(text)
            }
        }
        return result
    }

    public static func rtf(_ document: PDFDocument) -> Data? {
        let text = attributedText(document)
        return try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}

/// A ZIP archive with stored (uncompressed) entries: what a .docx package needs, nothing more.
public struct ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    public mutating func add(_ name: String, _ content: Data) {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(content)
        let offset = UInt32(data.count)
        var local = Data()
        local.append(le32(0x04034B50)); local.append(le16(20)); local.append(le16(0x0800)); local.append(le16(0))
        local.append(le16(0)); local.append(le16(0x21)) // time, date (1980-01-01)
        local.append(le32(crc)); local.append(le32(UInt32(content.count))); local.append(le32(UInt32(content.count)))
        local.append(le16(UInt16(nameBytes.count))); local.append(le16(0))
        data.append(local); data.append(nameBytes); data.append(content)
        var entry = Data()
        entry.append(le32(0x02014B50)); entry.append(le16(20)); entry.append(le16(20)); entry.append(le16(0x0800)); entry.append(le16(0))
        entry.append(le16(0)); entry.append(le16(0x21))
        entry.append(le32(crc)); entry.append(le32(UInt32(content.count))); entry.append(le32(UInt32(content.count)))
        entry.append(le16(UInt16(nameBytes.count))); entry.append(le16(0)); entry.append(le16(0)); entry.append(le16(0)); entry.append(le16(0))
        entry.append(le32(0)); entry.append(le32(offset))
        central.append(entry); central.append(nameBytes)
        count += 1
    }

    public mutating func finish() -> Data {
        var out = data
        let start = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054B50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(count))); out.append(le16(UInt16(count)))
        out.append(le32(UInt32(central.count))); out.append(le32(start)); out.append(le16(0))
        return out
    }

    private func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private func le32(_ value: UInt32) -> Data { Data((0..<4).map { UInt8(value >> (8 * $0) & 0xFF) }) }
}

public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}
