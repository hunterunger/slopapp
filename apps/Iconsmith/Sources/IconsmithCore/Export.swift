import CoreGraphics
import Foundation

public enum ExportFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case icns, iconset, xcode, favicons, png, ico

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .icns: ".icns File"
        case .iconset: "Iconset Folder"
        case .xcode: "Xcode App Icon"
        case .favicons: "Favicons"
        case .png: "PNG Image"
        case .ico: "Windows Icon (.ico)"
        }
    }

    public var detail: String {
        switch self {
        case .icns: "A macOS icon file with all ten sizes."
        case .iconset: "A folder of the ten macOS PNGs that iconutil turns into .icns."
        case .xcode: "AppIcon.appiconset for an Xcode asset catalog."
        case .favicons: "favicon.ico, touch and web app icons, and the HTML to use them."
        case .png: "One PNG of the icon."
        case .ico: "A Windows icon with sizes from 16 to 256 pixels."
        }
    }

    /// What the save panel suggests, never the source picture's own name (exporting
    /// logo.png as PNG next to it would otherwise offer to replace the original).
    public func suggestedName(base: String, source: String?) -> String {
        let name = suggestedName(base: base)
        return name == source ? suggestedName(base: "\(base) Icon") : name
    }

    public func suggestedName(base: String) -> String {
        switch self {
        case .icns: "\(base).icns"
        case .iconset: "\(base).iconset"
        case .xcode: "AppIcon.appiconset"
        case .favicons: "\(base) Favicons"
        case .png: "\(base).png"
        case .ico: "\(base).ico"
        }
    }

    /// The extension the output must keep (nil for a plain folder).
    public var pathExtension: String? {
        switch self {
        case .icns: "icns"
        case .iconset: "iconset"
        case .xcode: "appiconset"
        case .favicons: nil
        case .png: "png"
        case .ico: "ico"
        }
    }

    public var isFolder: Bool {
        switch self {
        case .iconset, .xcode, .favicons: true
        case .icns, .png, .ico: false
        }
    }
}

public enum XcodePlatform: String, CaseIterable, Codable, Sendable, Identifiable {
    case macOS, iOS, watchOS

    public var id: String { rawValue }
    public var title: String { rawValue }
}

public struct ExportOptions: Codable, Equatable, Sendable {
    public static let pngSizes = [256, 512, 1024, 2048]

    public var xcodePlatforms: Set<XcodePlatform> = [.macOS, .iOS]
    public var pngSize: Int = 1024

    public init(xcodePlatforms: Set<XcodePlatform> = [.macOS, .iOS], pngSize: Int = 1024) {
        self.xcodePlatforms = xcodePlatforms
        self.pngSize = pngSize
    }
}

/// One file of an export, before it's written.
public struct ExportFile: Equatable, Sendable {
    public var path: String
    public var data: Data
}

public struct ExportPlan: Sendable {
    public var files: [ExportFile]
    /// Things worth telling the user ("iOS icons were filled with white").
    public var notes: [String]
}

public enum ExportError: Error, LocalizedError, Equatable {
    case renderFailed
    case noPlatforms
    case iconutil(String)
    case write(String)

    public var errorDescription: String? {
        switch self {
        case .renderFailed: "Iconsmith couldn’t draw the icon. Try a different picture."
        case .noPlatforms: "Choose at least one platform (macOS, iOS or watchOS) for the Xcode app icon."
        case .iconutil(let message): "macOS couldn’t make the .icns file (\(message))."
        case .write(let message): "Couldn’t save the icon: \(message)"
        }
    }
}

/// Builds every export format from one renderer. Pure apart from `iconutil` for .icns.
public struct IconExporter: Sendable {
    public let renderer: IconRenderer

    public init(renderer: IconRenderer) {
        self.renderer = renderer
    }

    /// The ten images of a macOS iconset: (points, scale), named like iconutil wants them.
    public static let macSizes: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

    public static func iconsetName(points: Int, scale: Int) -> String {
        "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    }

    public static let icoSizes = [16, 24, 32, 48, 64, 128, 256]
    public static let faviconICOSizes = [16, 32, 48]

    func png(_ style: IconStyle, pixels: Int, opaque: Bool = false) throws -> Data {
        guard let image = renderer.render(style, pixels: pixels, opaque: opaque),
              let data = Bitmap.pngData(image) else { throw ExportError.renderFailed }
        return data
    }

    func macIconset(_ style: IconStyle) throws -> [ExportFile] {
        try Self.macSizes.map { size in
            ExportFile(path: Self.iconsetName(points: size.points, scale: size.scale),
                       data: try png(style, pixels: size.points * size.scale))
        }
    }

    func ico(_ style: IconStyle, sizes: [Int]) throws -> Data {
        try ICOEncoder.encode(sizes.map { (pixels: $0, png: try png(style, pixels: $0)) })
    }

    /// Everything a format writes, as relative paths inside the output (or the output
    /// file itself for single-file formats, path "").
    public func plan(_ format: ExportFormat, style: IconStyle, options: ExportOptions) throws -> ExportPlan {
        switch format {
        case .iconset:
            return ExportPlan(files: try macIconset(style), notes: [])
        case .icns:
            return ExportPlan(files: try macIconset(style), notes: []) // compiled by write()
        case .png:
            return ExportPlan(files: [ExportFile(path: "", data: try png(style, pixels: options.pngSize))], notes: [])
        case .ico:
            return ExportPlan(files: [ExportFile(path: "", data: try ico(style, sizes: Self.icoSizes))], notes: [])
        case .xcode:
            return try xcode(style, platforms: options.xcodePlatforms)
        case .favicons:
            return try favicons(style)
        }
    }

    func xcode(_ style: IconStyle, platforms: Set<XcodePlatform>) throws -> ExportPlan {
        guard !platforms.isEmpty else { throw ExportError.noPlatforms }
        var files: [ExportFile] = []
        var images: [[String: String]] = []
        var notes: [String] = []
        if platforms.contains(.iOS) || platforms.contains(.watchOS) {
            let data = try png(style, pixels: 1024, opaque: true)
            for platform in [XcodePlatform.iOS, .watchOS] where platforms.contains(platform) {
                let name = "AppIcon-\(platform.rawValue)-1024.png"
                files.append(ExportFile(path: name, data: data))
                images.append(["filename": name, "idiom": "universal", "platform": platform.rawValue.lowercased(), "size": "1024x1024"])
            }
            if renderer.opaqueNeedsFill(style) {
                notes.append("iOS and watchOS icons can’t be transparent, so their background was filled with white.")
            }
        }
        if platforms.contains(.macOS) {
            for size in Self.macSizes {
                let name = Self.iconsetName(points: size.points, scale: size.scale)
                files.append(ExportFile(path: name, data: try png(style, pixels: size.points * size.scale)))
                images.append(["filename": name, "idiom": "mac", "scale": "\(size.scale)x", "size": "\(size.points)x\(size.points)"])
            }
        }
        let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        files.append(ExportFile(path: "Contents.json", data: try Self.json(contents)))
        return ExportPlan(files: files, notes: notes)
    }

    func favicons(_ style: IconStyle) throws -> ExportPlan {
        var files = [
            ExportFile(path: "favicon.ico", data: try ico(style, sizes: Self.faviconICOSizes)),
            ExportFile(path: "icon-192.png", data: try png(style, pixels: 192)),
            ExportFile(path: "icon-512.png", data: try png(style, pixels: 512)),
            ExportFile(path: "apple-touch-icon.png", data: try png(style, pixels: 180, opaque: true)),
        ]
        // Maskable icons get cropped to a circle by Android: keep the picture inside the
        // central 80% safe zone.
        var maskable = style
        maskable.scale = style.scale * 0.8
        maskable.offset = CGPoint(x: style.offset.x * 0.8, y: style.offset.y * 0.8)
        files.append(ExportFile(path: "icon-maskable-512.png", data: try png(maskable, pixels: 512, opaque: true)))
        let background = renderer.background(for: IconStyle(shape: .square, background: style.background, color: style.color))
        let hex = (background ?? .white).opaque.hex
        let manifest: [String: Any] = [
            "name": renderer.source.name,
            "short_name": renderer.source.name,
            "theme_color": hex,
            "background_color": hex,
            "display": "standalone",
            "icons": [
            ["src": "/icon-192.png", "type": "image/png", "sizes": "192x192"],
            ["src": "/icon-512.png", "type": "image/png", "sizes": "512x512"],
            ["src": "/icon-maskable-512.png", "type": "image/png", "sizes": "512x512", "purpose": "maskable"],
        ]]
        files.append(ExportFile(path: "manifest.webmanifest", data: try Self.json(manifest)))
        files.append(ExportFile(path: "head.html", data: Data(Self.faviconHTML.utf8)))
        var notes: [String] = []
        if renderer.opaqueNeedsFill(style) {
            notes.append("The touch and maskable icons can’t be transparent, so their background was filled with white.")
        }
        return ExportPlan(files: files, notes: notes)
    }

    public static let faviconHTML = """
    <link rel="icon" href="/favicon.ico" sizes="32x32">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <link rel="manifest" href="/manifest.webmanifest">

    """

    static func json(_ object: Any) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}

/// Windows .ico with PNG-compressed images (supported by Windows Vista+ and every browser).
public enum ICOEncoder {
    public static func encode(_ images: [(pixels: Int, png: Data)]) throws -> Data {
        var data = Data()
        func le16(_ v: Int) { data.append(UInt8(v & 0xFF)); data.append(UInt8((v >> 8) & 0xFF)) }
        func le32(_ v: Int) { le16(v & 0xFFFF); le16((v >> 16) & 0xFFFF) }
        le16(0); le16(1); le16(images.count)
        var offset = 6 + 16 * images.count
        for image in images {
            let side = image.pixels >= 256 ? 0 : image.pixels // 0 means 256
            data.append(UInt8(side)); data.append(UInt8(side))
            data.append(0); data.append(0) // palette size, reserved
            le16(1); le16(32)             // planes, bits per pixel
            le32(image.png.count); le32(offset)
            offset += image.png.count
        }
        for image in images { data.append(image.png) }
        return data
    }
}
