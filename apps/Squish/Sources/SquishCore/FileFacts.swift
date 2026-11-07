import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Facts about one file for the preview's info line: "JPEG · 3840 × 2160",
/// "PDF · 12 pages · 9 images". Read from headers; images aren't decoded.
public struct FileFacts: Equatable, Sendable {
    public var typeName: String
    /// Images: the size as displayed (rotated photos have width and height swapped).
    public var pixelSize: CGSize?
    public var pageCount: Int?
    /// PDFs: images placed on the pages (each counted once per page).
    public var imageCount: Int?
    public var annotationCount: Int?

    public init(typeName: String, pixelSize: CGSize? = nil, pageCount: Int? = nil,
                imageCount: Int? = nil, annotationCount: Int? = nil) {
        self.typeName = typeName
        self.pixelSize = pixelSize
        self.pageCount = pageCount
        self.imageCount = imageCount
        self.annotationCount = annotationCount
    }

    public static func read(_ url: URL) -> FileFacts? {
        switch SquishTypes.kind(of: url) {
        case .image(let type): return image(url, type: type)
        case .pdf: return pdf(url)
        case nil: return nil
        }
    }

    static func typeName(_ type: UTType) -> String {
        if type.conforms(to: .jpeg) { return "JPEG" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIC" }
        return type.preferredFilenameExtension?.uppercased() ?? type.localizedDescription ?? "Image"
    }

    static func image(_ url: URL, type: UTType) -> FileFacts? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return FileFacts(typeName: typeName(type)) }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let size = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        return FileFacts(typeName: typeName(type), pixelSize: size)
    }

    static func pdf(_ url: URL) -> FileFacts? {
        guard let document = PDFDocument(url: url) else { return FileFacts(typeName: "PDF") }
        if document.isLocked { return FileFacts(typeName: "PDF") }
        var images = 0
        var annotations = 0
        // Big documents: count the first 200 pages only, so the info line stays instant.
        let pages = min(document.pageCount, 200)
        for index in 0..<pages {
            guard let page = document.page(at: index) else { continue }
            annotations += page.annotations.count
            if let ref = page.pageRef { images += imageCount(on: ref) }
        }
        return FileFacts(typeName: "PDF", pageCount: document.pageCount,
                         imageCount: document.pageCount > pages ? nil : images, annotationCount: annotations)
    }

    /// Image XObjects in a page's resources (not counting nested forms).
    static func imageCount(on page: CGPDFPage) -> Int {
        guard let dict = page.dictionary else { return 0 }
        var resources: CGPDFDictionaryRef?
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return 0 }
        var count = 0
        CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let streamDict = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<Int8>?
            if CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" {
                count += 1
            }
            return true
        }, nil)
        return count
    }

    /// "JPEG · 3840 × 2160" / "PDF · 12 pages · 9 images".
    public var summary: String {
        var parts = [typeName]
        if let pixelSize { parts.append("\(Int(pixelSize.width)) × \(Int(pixelSize.height))") }
        if let pageCount { parts.append(pageCount == 1 ? "1 page" : "\(pageCount) pages") }
        if let imageCount, pageCount != nil { parts.append(imageCount == 1 ? "1 image" : "\(imageCount) images") }
        return parts.joined(separator: " · ")
    }
}
