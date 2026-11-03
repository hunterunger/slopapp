import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The encoded result of compressing one file, before it's written anywhere.
public struct Encoded: Sendable {
    public var data: Data
    public var type: UTType
}

/// Why a file was left alone. Not an error: the row says so calmly.
public struct Skip: Error, Equatable, Sendable {
    public let reason: String
}

public enum SquishError: LocalizedError, Equatable {
    case unreadable(String)
    case empty(String)
    case encodeFailed(String)
    case lockedPDF(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read \(name)."
        case .empty(let name): "\(name) is empty."
        case .encodeFailed(let name): "Couldn't compress \(name)."
        case .lockedPDF(let name): "\(name) is locked with a password."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unreadable: "It may be damaged or not really an image or PDF. Try opening it in Preview."
        case .empty: "There's nothing in it to compress."
        case .encodeFailed: "Try another format or quality, or open it in Preview and export a copy."
        case .lockedPDF: "Open it in Preview, enter the password and export a copy, then try that."
        }
    }
}

/// Re-encodes images with ImageIO: resize, quality, metadata, format.
public enum ImageCompressor {
    public static func compress(
        _ url: URL,
        inputType: UTType,
        settings: SquishSettings,
        capabilities: EncoderCapabilities,
        progress: (Double) -> Void = { _ in }
    ) throws -> Encoded {
        let name = url.lastPathComponent
        if inputType.conforms(to: .gif) {
            throw Skip(reason: "GIFs are kept as they are.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0
        else { throw SquishError.unreadable(name) }
        if CGImageSourceGetCount(source) > 1 {
            throw Skip(reason: "Animated and multi-image files are kept as they are.")
        }

        let outputType = try outputType(for: inputType, settings: settings, capabilities: capabilities)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1

        // Decode, downscaling while decoding when we resize (much faster and lighter).
        let resizing = settings.maxDimension.map { max(width, height) > $0 } ?? false
        let image: CGImage?
        if resizing, let maxDimension = settings.maxDimension {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        guard var image else { throw SquishError.unreadable(name) }
        progress(0.3)
        try Task.checkCancellation()

        // Thumbnails come out upright, so the orientation tag must go back to "up".
        let outOrientation: UInt32 = resizing ? 1 : orientation

        if outputType.conforms(to: .png), outOrientation == 1, case .palette(let colors) = settings.pngMode {
            if let data = palettePNG(image, colors: colors) {
                progress(0.95)
                return Encoded(data: data, type: .png)
            }
        }
        if !supportsAlpha(outputType), hasAlpha(image) {
            image = flattened(image) ?? image
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, outputType.identifier as CFString, 1, nil)
        else { throw SquishError.encodeFailed(name) }
        var options: [CFString: Any] = [kCGImagePropertyOrientation: outOrientation]
        if isLossy(outputType) {
            options[kCGImageDestinationLossyCompressionQuality] = settings.imageQuality
        }
        if !settings.stripMetadata {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                        kCGImagePropertyTIFFDictionary, kCGImagePropertyMakerAppleDictionary] {
                if let value = properties[key] { options[key] = value }
            }
            if var tiff = options[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = outOrientation
                options[kCGImagePropertyTIFFDictionary] = tiff
            }
            if resizing, var exif = options[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = image.width
                exif[kCGImagePropertyExifPixelYDimension] = image.height
                options[kCGImagePropertyExifDictionary] = exif
            }
        } else {
            // Keep resolution (DPI) so print sizes don't change; nothing that identifies anyone.
            for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
                if let value = properties[key] { options[key] = value }
            }
        }
        if outputType.conforms(to: .tiff) {
            // LZW: lossless, and what makes a TIFF smaller at all.
            var tiff = options[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = 5
            options[kCGImagePropertyTIFFDictionary] = tiff
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        // HDR gain maps (iPhone photos) keep their brightness when the size doesn't change.
        if !resizing, outputType.conforms(to: .heic) || outputType.conforms(to: .jpeg) {
            var auxTypes = [kCGImageAuxiliaryDataTypeHDRGainMap]
            if #available(macOS 15, *) { auxTypes.insert(kCGImageAuxiliaryDataTypeISOGainMap, at: 0) }
            for auxType in auxTypes {
                if let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxType) {
                    CGImageDestinationAddAuxiliaryDataInfo(destination, auxType, info)
                    break
                }
            }
        }
        progress(0.6)
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else { throw SquishError.encodeFailed(name) }
        progress(0.95)
        return Encoded(data: data as Data, type: outputType)
    }

    static func outputType(for inputType: UTType, settings: SquishSettings, capabilities: EncoderCapabilities) throws -> UTType {
        if let wanted = settings.format.type {
            guard capabilities.canWrite(wanted) else {
                throw Skip(reason: "This Mac can't save \(settings.format.title) files. Choose another format.")
            }
            return wanted
        }
        // HEIF files are written as HEIC (same container, what ImageIO writes).
        let same = inputType.conforms(to: .heif) && !capabilities.canWrite(inputType) ? UTType.heic : inputType
        guard capabilities.canWrite(same) else {
            let label = inputType.preferredFilenameExtension?.uppercased() ?? "this kind of"
            throw Skip(reason: "This Mac can't save \(label) files. To shrink it, pick JPEG, HEIC or PNG under Format.")
        }
        return same
    }

    static func isLossy(_ type: UTType) -> Bool {
        type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif)
            || type.conforms(to: .webP) || type.identifier == "public.avif" || type.identifier == "public.jpeg-2000"
    }

    static func supportsAlpha(_ type: UTType) -> Bool {
        !type.conforms(to: .jpeg) && !type.conforms(to: .bmp)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Composites onto white for formats without transparency (PNG → JPEG).
    static func flattened(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    static func palettePNG(_ image: CGImage, colors: Int) -> Data? {
        guard let rgba = RGBAImage(image) else { return nil }
        let result = PaletteQuantizer.quantize(rgba, maxColors: colors)
        return PalettePNGWriter.encode(result, width: rgba.width, height: rgba.height, colorSpace: rgba.colorSpace)
    }
}
