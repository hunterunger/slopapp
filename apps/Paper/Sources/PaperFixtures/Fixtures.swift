import AppKit
import PDFKit

/// Generated PDFs for tests and walkthroughs. Never real documents.
public enum Fixtures {
    public static let secret = "SECRET-4417"
    public static let hidden = "HIDDENOCR-777"

    static func font(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black]
    }

    /// Draws pages with CoreGraphics into PDF data.
    public static func pdf(pages: Int, size: CGSize = CGSize(width: 612, height: 792),
                           info: [CFString: Any] = [:], draw: (Int, CGContext) -> Void) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }
        for index in 0..<pages {
            context.beginPDFPage(nil)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            draw(index, context)
            NSGraphicsContext.current = previous
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    static func text(_ string: String, at point: CGPoint, size: CGFloat = 18) {
        (string as NSString).draw(at: point, withAttributes: font(size))
    }

    /// A gradient bitmap, so redaction can check pixels really changed.
    public static func gradientImage(width: Int = 200, height: Int = 100) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<width {
            context.setFillColor(CGColor(red: CGFloat(x) / CGFloat(width), green: 0.5, blue: CGFloat(width - x) / CGFloat(width), alpha: 1)) // lint:allow fixture page content
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return context.makeImage()!
    }

    /// 3 pages: a title, a secret line, a public line, a blue box and a gradient image.
    public static func textDocument(pages: Int = 3, title: String = "Paper test document", author: String = "Test Author") -> Data {
        pdf(pages: pages, info: [kCGPDFContextTitle: title, kCGPDFContextAuthor: author, kCGPDFContextKeywords: "fixture"]) { index, context in
            text("Paper test page \(index + 1)", at: CGPoint(x: 72, y: 700))
            text("Account number \(secret)-\(index + 1) belongs to nobody.", at: CGPoint(x: 72, y: 650))
            text("This public sentence should survive redaction.", at: CGPoint(x: 72, y: 600))
            text("Contact jane@example.com about the Example project.", at: CGPoint(x: 72, y: 560), size: 14)
            context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1)) // lint:allow fixture page content
            context.fill(CGRect(x: 72, y: 400, width: 200, height: 120))
            context.draw(gradientImage(), in: CGRect(x: 320, y: 400, width: 200, height: 100))
        }
    }

    /// One page of image only, like a scanner makes. No text layer.
    public static func scanDocument(withHiddenText: Bool = false) -> Data {
        let width = 1275, height = 1650 // 150 dpi letter
        let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 0.97, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        text("Scanned invoice number 55821", at: CGPoint(x: 150, y: 1400), size: 44)
        text("Total due forty dollars", at: CGPoint(x: 150, y: 1300), size: 44)
        NSGraphicsContext.current = previous
        let image = bitmap.makeImage()!
        return pdf(pages: 1) { _, context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: 612, height: 792))
            if withHiddenText {
                context.setTextDrawingMode(.invisible)
                text("Scanned invoice number 55821 \(hidden)", at: CGPoint(x: 72, y: 672), size: 21)
                context.setTextDrawingMode(.fill)
            }
        }
    }

    /// One page with a text field, a checkbox, two radio buttons and a dropdown.
    public static func formDocument() -> Data {
        let base = pdf(pages: 1) { _, _ in
            text("Application form", at: CGPoint(x: 72, y: 720), size: 22)
            text("Full name", at: CGPoint(x: 72, y: 664), size: 12)
            text("I agree to the terms", at: CGPoint(x: 100, y: 604), size: 12)
            text("Plan: Basic / Plus", at: CGPoint(x: 72, y: 564), size: 12)
            text("Color", at: CGPoint(x: 72, y: 524), size: 12)
        }
        let document = PDFDocument(data: base)!
        let page = document.page(at: 0)!
        let name = PDFAnnotation(bounds: CGRect(x: 150, y: 656, width: 250, height: 24), forType: .widget, withProperties: nil)
        name.widgetFieldType = .text
        name.fieldName = "fullName"
        name.backgroundColor = NSColor(white: 0.95, alpha: 1)
        label(name, "Full name")
        page.addAnnotation(name)
        let agree = PDFAnnotation(bounds: CGRect(x: 72, y: 600, width: 18, height: 18), forType: .widget, withProperties: nil)
        agree.widgetFieldType = .button
        agree.widgetControlType = .checkBoxControl
        agree.fieldName = "agree"
        label(agree, "I agree to the terms")
        page.addAnnotation(agree)
        for (offset, option) in ["Basic", "Plus"].enumerated() {
            let radio = PDFAnnotation(bounds: CGRect(x: 200 + CGFloat(offset) * 60, y: 560, width: 16, height: 16), forType: .widget, withProperties: nil)
            radio.widgetFieldType = .button
            radio.widgetControlType = .radioButtonControl
            radio.fieldName = "plan"
            radio.buttonWidgetStateString = option
            label(radio, "Plan \(option)")
            page.addAnnotation(radio)
        }
        let color = PDFAnnotation(bounds: CGRect(x: 150, y: 518, width: 150, height: 22), forType: .widget, withProperties: nil)
        color.widgetFieldType = .choice
        color.isListChoice = false
        color.choices = ["Red", "Green", "Blue"]
        color.fieldName = "color"
        label(color, "Color")
        page.addAnnotation(color)
        return document.dataRepresentation()!
    }

    /// A visible border and an accessible name (`/TU`), like a well-made form.
    static func label(_ widget: PDFAnnotation, _ name: String) {
        widget.setValue(name, forAnnotationKey: PDFAnnotationKey(rawValue: "/TU"))
        let border = PDFBorder()
        border.lineWidth = 1
        widget.border = border
        widget.color = NSColor(white: 0.45, alpha: 1)
        if widget.backgroundColor == nil { widget.backgroundColor = .white }
    }

    /// `count` pages with a top-level outline entry every `chapterEvery` pages. Built with
    /// CoreGraphics: PDFKit (macOS 27) doesn't write outlines it creates itself.
    public static func outlineDocument(pages count: Int = 6, chapterEvery: Int = 2) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for index in 0..<count {
            context.beginPDFPage(nil)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            text("Chapter \(index / chapterEvery + 1), page \(index + 1)", at: CGPoint(x: 72, y: 700))
            NSGraphicsContext.current = previous
            context.endPDFPage()
        }
        let children: [[String: Any]] = stride(from: 0, to: count, by: chapterEvery).enumerated().map { offset, start in
            [kCGPDFOutlineTitle as String: "Chapter \(offset + 1)",
             kCGPDFOutlineDestination as String: start + 1]
        }
        CGPDFContextSetOutline(context, [kCGPDFOutlineChildren as String: children] as CFDictionary)
        context.closePDF()
        return data as Data
    }

    /// Many simple text pages, for performance checks.
    public static func longDocument(pages count: Int) -> Data {
        pdf(pages: count) { index, context in
            text("Long document page \(index + 1)", at: CGPoint(x: 72, y: 700))
            for line in 0..<30 {
                text("Line \(line + 1) of page \(index + 1): the quick brown fox jumps over the lazy dog.", at: CGPoint(x: 72, y: 660 - CGFloat(line) * 18), size: 11)
            }
            context.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 1)) // lint:allow fixture page content
            context.fill(CGRect(x: 72, y: 72, width: 100, height: 20))
        }
    }

    /// A page turned 90° with a secret on it.
    public static func rotatedDocument() -> Data {
        let document = PDFDocument(data: textDocument(pages: 1))!
        document.page(at: 0)!.rotation = 90
        return document.dataRepresentation()!
    }

    /// A document that already has an unapplied `Redact` annotation from "another app".
    /// Written by hand: PDFKit would apply the annotation if it wrote the file (research P4).
    public static func foreignRedactDocument() -> Data {
        let content = "BT /F1 18 Tf 72 700 Td (Account \(secret)-1 belongs to nobody.) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R] >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Annot /Subtype /Redact /Rect [140 694 260 716] /QuadPoints [140 716 260 716 140 694 260 694] /IC [0 0 0] /NM (other-app-1) >>",
        ]
        var out = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { out += String(format: "%010d 00000 n \n", offset) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }

    /// A page with an external link and a link to page 2.
    public static func linksDocument() -> Data {
        let base = pdf(pages: 2) { index, _ in
            text(index == 0 ? "Visit example.com or go to page 2" : "This is page 2", at: CGPoint(x: 72, y: 700))
        }
        let document = PDFDocument(data: base)!
        let page = document.page(at: 0)!
        let web = PDFAnnotation(bounds: CGRect(x: 110, y: 696, width: 100, height: 24), forType: .link, withProperties: nil)
        web.url = URL(string: "https://example.com")
        page.addAnnotation(web)
        let jump = PDFAnnotation(bounds: CGRect(x: 260, y: 696, width: 90, height: 24), forType: .link, withProperties: nil)
        jump.destination = PDFDestination(page: document.page(at: 1)!, at: CGPoint(x: 0, y: 792))
        page.addAnnotation(jump)
        return document.dataRepresentation()!
    }

    public static func encryptedDocument(password: String = "paper") -> Data {
        let document = PDFDocument(data: textDocument(pages: 1))!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paper-enc-\(UUID().uuidString).pdf")
        document.write(to: url, withOptions: [.userPasswordOption: password, .ownerPasswordOption: password + "-owner"])
        defer { try? FileManager.default.removeItem(at: url) }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    /// Opens without a password, but the owner forbids changes, annotations and printing.
    public static func restrictedDocument() -> Data {
        pdf(pages: 1, info: [kCGPDFContextOwnerPassword: "owner", kCGPDFContextUserPassword: "",
                             kCGPDFContextAllowsPrinting: false, kCGPDFContextAllowsCopying: false]) { _, _ in
            text("Restricted document", at: CGPoint(x: 72, y: 700))
        }
    }

    public static func cjkDocument() -> Data {
        pdf(pages: 1) { _, _ in
            text("口座番号は東京支店です。", at: CGPoint(x: 72, y: 700))
            text("Café déjà vu, Ünïcode naïve.", at: CGPoint(x: 72, y: 650))
        }
    }

    public static func landscapeA4() -> Data {
        pdf(pages: 1, size: CGSize(width: 842, height: 595)) { _, _ in
            text("Landscape A4 page", at: CGPoint(x: 72, y: 500))
        }
    }

    public static func pngData(width: Int = 400, height: Int = 300) -> Data {
        let rep = NSBitmapImageRep(cgImage: gradientImage(width: width, height: height))
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Writes every fixture into `directory`. Returns the file names written.
    @discardableResult
    public static func writeAll(to directory: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files: [(String, Data)] = [
            ("text.pdf", textDocument()),
            ("form.pdf", formDocument()),
            ("scan.pdf", scanDocument()),
            ("ocr-layer.pdf", scanDocument(withHiddenText: true)),
            ("outline.pdf", outlineDocument()),
            ("rotated.pdf", rotatedDocument()),
            ("links.pdf", linksDocument()),
            ("encrypted.pdf", encryptedDocument()),
            ("restricted.pdf", restrictedDocument()),
            ("cjk.pdf", cjkDocument()),
            ("landscape-a4.pdf", landscapeA4()),
            ("long-100.pdf", longDocument(pages: 100)),
            ("picture.png", pngData()),
            ("damaged.pdf", textDocument().prefix(900)),
            ("not-a-pdf.pdf", Data("This is plain text, not a PDF.\n".utf8)),
            ("foreign-redact.pdf", foreignRedactDocument()),
        ]
        for (name, data) in files {
            try data.write(to: directory.appendingPathComponent(name))
        }
        return files.map(\.0)
    }
}
