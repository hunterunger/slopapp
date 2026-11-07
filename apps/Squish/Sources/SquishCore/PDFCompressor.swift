import Foundation
import PDFKit
import Quartz

/// Shrinks PDFs by downsampling and re-compressing the images inside them, through a
/// Quartz filter. Text, vectors, links, annotations and outlines are kept.
public enum PDFCompressor {
    static func compressNow(_ url: URL, settings: SquishSettings) throws -> Encoded {
        let name = url.lastPathComponent
        guard let document = PDFDocument(url: url) else { throw SquishError.unreadable(name) }
        if document.isLocked { throw SquishError.lockedPDF(name) }
        if document.isEncrypted {
            // Saving would silently drop its protection (and its permissions), so leave it.
            throw Skip(reason: "Password-protected PDFs are kept as they are, so their protection stays.")
        }
        guard document.pageCount > 0 else { throw SquishError.empty(name) }

        if settings.metadata == .removeAll {
            var attributes = document.documentAttributes ?? [:]
            for key in [PDFDocumentAttribute.authorAttribute, .creatorAttribute, .producerAttribute,
                        .keywordsAttribute, .subjectAttribute] {
                attributes.removeValue(forKey: key)
            }
            document.documentAttributes = attributes
        }

        guard let filter = QuartzFilter(properties: filterProperties(settings.pdf)) else {
            throw SquishError.encodeFailed(name)
        }
        let options: [PDFDocumentWriteOption: Any] = [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]
        guard let data = document.dataRepresentation(options: options) else {
            throw SquishError.encodeFailed(name)
        }
        return Encoded(data: data, type: .pdf)
    }

    /// A Quartz filter that re-encodes every image as JPEG at `quality`, downsampled to
    /// `resolution` dpi. Images already below that resolution aren't scaled up.
    static func filterProperties(_ pdf: PDFSettings) -> [String: Any] {
        var colorSettings: [String: Any] = [
            "ImageSettings": [
                "Compression Quality": pdf.quality,
                "ImageCompression": "ImageJPEGCompress",
                "ImageScaleSettings": [
                    "ImageResolution": pdf.resolution,
                    "ImageScaleInterpolate": true,
                    "ImageSizeMax": 0,
                    "ImageSizeMin": 0,
                ],
            ],
        ]
        var filterData: [String: Any] = [:]
        if pdf.grayscale, let profiles = grayProfiles {
            // macOS's own gray tone conversion (an abstract color profile), applied to
            // everything on the page: images, text and drawings.
            colorSettings["DocumentColorSettings"] = ["IntermediateColorSpace": 0]
            filterData["FilterProfileArray"] = profiles
        }
        filterData["ColorSettings"] = colorSettings
        return [
            "Domains": ["Applications": true],
            "FilterType": 1,
            "Name": "Squish",
            "FilterData": filterData,
        ]
    }

    /// The color profile behind macOS's "Gray Tone" Quartz filter, read from the system at
    /// run time. Nil if this macOS doesn't have it (then Grayscale is unavailable).
    static let grayProfiles: [Data]? = {
        let url = URL(fileURLWithPath: "/System/Library/Filters/Gray Tone.qfilter")
        guard let filter = NSDictionary(contentsOf: url) as? [String: Any],
              let data = filter["FilterData"] as? [String: Any],
              let profiles = data["FilterProfileArray"] as? [Data], !profiles.isEmpty else { return nil }
        return profiles
    }()

    /// Whether this Mac can turn PDFs gray.
    public static var canGrayscale: Bool { grayProfiles != nil }
}

