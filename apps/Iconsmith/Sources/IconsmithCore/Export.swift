import CoreGraphics
import Foundation

public enum ExportFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    // In the order the export panel shows them: Finder first, then developer formats.
    case folder, icns, xcode, android, favicons, iconset, ico, png, jpg

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .folder: "Folder with Icon"
        case .icns: ".icns File"
        case .iconset: "Iconset Folder"
        case .xcode: "Xcode App Icon"
        case .android: "Android Icons"
        case .favicons: "Favicons"
        case .png: "PNG Image"
        case .jpg: "JPEG Image"
        case .ico: "Windows Icon (.ico)"
        }
    }

    /// The label on the export panel's tile.
    public var shortTitle: String {
        switch self {
        case .folder: "Folder"
        case .icns: "ICNS"
        case .iconset: "Iconset"
        case .xcode: "Xcode"
        case .android: "Android"
        case .favicons: "Favicon"
        case .png: "PNG"
        case .jpg: "JPEG"
        case .ico: "ICO"
        }
    }

    /// SF Symbol for the export panel.
    public var systemImage: String {
        switch self {
        case .folder: "folder"
        case .icns: "app.dashed"
        case .iconset: "square.grid.3x3"
        case .xcode: "hammer"
        case .android: "smartphone"
        case .favicons: "globe"
        case .png: "photo"
        case .jpg: "photo.artframe"
        case .ico: "pc"
        }
    }

    public var detail: String {
        switch self {
        case .folder: "A new folder that already has this icon. Copy it from Get Info, or keep things in it."
        case .icns: "A macOS icon file with all ten sizes."
        case .iconset: "A folder of the ten macOS PNGs that iconutil turns into .icns."
        case .xcode: "AppIcon.appiconset for an Xcode asset catalog."
        case .android: "Launcher icons for every density, round and adaptive icons, and the 512 px Play Store icon."
        case .favicons: "favicon.ico, touch and web app icons, and the HTML to use them."
        case .png: "One PNG of the icon."
        case .jpg: "One JPEG of the icon. JPEG can’t be transparent, so see-through parts become white."
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
        case .folder: base
        case .icns: "\(base).icns"
        case .iconset: "\(base).iconset"
        case .xcode: "AppIcon.appiconset"
        case .android: "\(base) Android"
        case .favicons: "\(base) Favicons"
        case .png: "\(base).png"
        case .jpg: "\(base).jpg"
        case .ico: "\(base).ico"
        }
    }

    /// The name of one picture's output in a batch export (all go in one folder, so the
    /// Xcode icon is named after its picture).
    public func batchName(base: String) -> String {
        self == .xcode ? "\(base).appiconset" : suggestedName(base: base)
    }

    /// The extension the output must keep (nil for a plain folder).
    public var pathExtension: String? {
        switch self {
        case .icns: "icns"
        case .iconset: "iconset"
        case .xcode: "appiconset"
        case .folder, .android, .favicons: nil
        case .png: "png"
        case .jpg: "jpg"
        case .ico: "ico"
        }
    }

    public var isFolder: Bool {
        switch self {
        case .folder, .iconset, .xcode, .android, .favicons: true
        case .icns, .png, .jpg, .ico: false
        }
    }

    /// Single-image formats have a size option.
    public var hasImageSize: Bool { self == .png || self == .jpg }
}

public enum XcodePlatform: String, CaseIterable, Codable, Sendable, Identifiable {
    case macOS, iOS, watchOS

    public var id: String { rawValue }
    public var title: String { rawValue }
}

public struct ExportOptions: Codable, Equatable, Sendable {
    public static let pngSizes = [256, 512, 1024, 2048]

    public var xcodePlatforms: Set<XcodePlatform> = [.macOS, .iOS]
    /// iOS 18 dark and tinted variants alongside the iOS icon.
    public var xcodeAppearances = false
    /// PNG and JPEG size in pixels.
    public var pngSize: Int = 1024

    public init(xcodePlatforms: Set<XcodePlatform> = [.macOS, .iOS], xcodeAppearances: Bool = false, pngSize: Int = 1024) {
        self.xcodePlatforms = xcodePlatforms
        self.xcodeAppearances = xcodeAppearances
        self.pngSize = pngSize
    }

    public init(from decoder: Decoder) throws {
        // Every field optional, so adding one later never resets the rest.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportOptions()
        xcodePlatforms = (try? c.decode(Set<XcodePlatform>.self, forKey: .xcodePlatforms)) ?? d.xcodePlatforms
        xcodeAppearances = (try? c.decode(Bool.self, forKey: .xcodeAppearances)) ?? d.xcodeAppearances
        pngSize = (try? c.decode(Int.self, forKey: .pngSize)) ?? d.pngSize
    }
}

/// Names for batch exports: every picture's output in one folder, never overwriting.
public enum BatchNaming {
    /// One unique name per base name, skipping `existing` and each other ("logo 2.icns").
    public static func names(for bases: [String], format: ExportFormat, existing: Set<String>) -> [String] {
        var taken = Set(existing.map { $0.lowercased() })
        return bases.map { base in
            var name = format.batchName(base: base)
            var n = 2
            while taken.contains(name.lowercased()) {
                name = format.batchName(base: "\(base) \(n)")
                n += 1
            }
            taken.insert(name.lowercased())
            return name
        }
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

    func png(_ style: IconStyle, pixels: Int, opaque: Bool = false, parts: RenderParts = .all) throws -> Data {
        guard let image = renderer.render(style, pixels: pixels, opaque: opaque, parts: parts),
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
        case .jpg:
            return ExportPlan(files: [ExportFile(path: "", data: try jpeg(style, pixels: options.pngSize))],
                              notes: style.shape == .square && !renderer.opaqueNeedsFill(style)
                                ? [] : ["JPEG can’t be transparent, so see-through parts are white."])
        case .xcode:
            return try xcode(style, platforms: options.xcodePlatforms, appearances: options.xcodeAppearances)
        case .favicons:
            return try favicons(style)
        case .android:
            return try android(style)
        case .folder:
            // An empty folder; the app gives it the icon once it's in place.
            return ExportPlan(files: [], notes: [])
        }
    }

    func jpeg(_ style: IconStyle, pixels: Int) throws -> Data {
        guard let image = renderer.render(style, pixels: pixels),
              let flat = IconRenderer.flattened(image, on: .white),
              let data = Bitmap.jpegData(flat) else { throw ExportError.renderFailed }
        return data
    }

    func xcode(_ style: IconStyle, platforms: Set<XcodePlatform>, appearances: Bool = false) throws -> ExportPlan {
        guard !platforms.isEmpty else { throw ExportError.noPlatforms }
        var files: [ExportFile] = []
        var images: [[String: Any]] = []
        var notes: [String] = []
        if platforms.contains(.iOS) || platforms.contains(.watchOS) {
            let data = try png(style, pixels: 1024, opaque: true)
            for platform in [XcodePlatform.iOS, .watchOS] where platforms.contains(platform) {
                let name = "AppIcon-\(platform.rawValue)-1024.png"
                files.append(ExportFile(path: name, data: data))
                images.append(["filename": name, "idiom": "universal", "platform": platform.rawValue.lowercased(), "size": "1024x1024"])
                if platform == .iOS && appearances {
                    let (dark, tinted) = try iOSAppearances(style)
                    files.append(ExportFile(path: "AppIcon-iOS-Dark-1024.png", data: dark))
                    files.append(ExportFile(path: "AppIcon-iOS-Tinted-1024.png", data: tinted))
                    for (value, file) in [("dark", "AppIcon-iOS-Dark-1024.png"), ("tinted", "AppIcon-iOS-Tinted-1024.png")] {
                        images.append(["appearances": [["appearance": "luminosity", "value": value]], "filename": file,
                                       "idiom": "universal", "platform": "ios", "size": "1024x1024"])
                    }
                }
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

    /// iOS 18 variants. Dark: the picture on transparency (the system draws the dark
    /// background); tinted: its greyscale on black (the system adds the tint).
    func iOSAppearances(_ style: IconStyle) throws -> (dark: Data, tinted: Data) {
        var art = style
        art.shape = .square
        art.background = .none
        guard let dark = renderer.render(art, pixels: 1024),
              let gray = IconRenderer.grayscale(dark),
              let tinted = IconRenderer.flattened(gray, on: .black),
              let darkData = Bitmap.pngData(dark), let tintedData = Bitmap.pngData(tinted) else { throw ExportError.renderFailed }
        return (darkData, tintedData)
    }

    /// Android densities: (folder suffix, legacy launcher px, adaptive layer px).
    public static let androidDensities: [(name: String, launcher: Int, layer: Int)] = [
        ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
    ]

    /// An Android `res` folder (legacy, round and adaptive launcher icons) plus the Play
    /// Store icon. Adaptive layers: a logo goes in the foreground inside the 66 dp safe zone
    /// on a solid background; a photo becomes the background, with any text in front.
    func android(_ style: IconStyle) throws -> ExportPlan {
        var files: [ExportFile] = []
        var round = style
        round.shape = .circle
        let logo = renderer.source.edges.isTransparent
        var layer = style
        layer.shape = .square
        layer.background = .none
        // The art fills 76% of a square at 100%; the adaptive safe zone is 66 of 108 dp.
        layer.scale = style.scale * 0.8
        layer.offset = CGPoint(x: style.offset.x * 0.8, y: style.offset.y * 0.8)
        var backdrop = style
        backdrop.shape = .square
        for density in Self.androidDensities {
            let folder = "res/mipmap-\(density.name)/"
            files.append(ExportFile(path: folder + "ic_launcher.png", data: try png(style, pixels: density.launcher)))
            files.append(ExportFile(path: folder + "ic_launcher_round.png", data: try png(round, pixels: density.launcher)))
            files.append(ExportFile(path: folder + "ic_launcher_foreground.png",
                                    data: try png(layer, pixels: density.layer, parts: logo ? .all : .text)))
            files.append(ExportFile(path: folder + "ic_launcher_background.png",
                                    data: try png(backdrop, pixels: density.layer, opaque: true, parts: logo ? [] : .picture)))
        }
        let xml = Self.adaptiveXML(monochrome: logo)
        files.append(ExportFile(path: "res/mipmap-anydpi-v26/ic_launcher.xml", data: Data(xml.utf8)))
        files.append(ExportFile(path: "res/mipmap-anydpi-v26/ic_launcher_round.xml", data: Data(xml.utf8)))
        files.append(ExportFile(path: "playstore-icon.png", data: try png(style, pixels: 512, opaque: true)))
        var notes = ["Copy the res folder into your app’s src/main folder."]
        if renderer.opaqueNeedsFill(style) {
            notes.append("The Play Store and background icons can’t be transparent, so their background is white.")
        }
        return ExportPlan(files: files, notes: notes)
    }

    static func adaptiveXML(monochrome: Bool) -> String {
        var xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
            <background android:drawable="@mipmap/ic_launcher_background"/>
            <foreground android:drawable="@mipmap/ic_launcher_foreground"/>

        """
        if monochrome { xml += "    <monochrome android:drawable=\"@mipmap/ic_launcher_foreground\"/>\n" }
        xml += "</adaptive-icon>\n"
        return xml
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
        var square = style
        square.shape = .square
        let background = renderer.background(for: square)
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
