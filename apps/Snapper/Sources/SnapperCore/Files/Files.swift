import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The file format captures are saved in.
public enum ImageFormat: String, Sendable, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    /// The format a file extension stands for ("jpeg" and "jpg" are both JPEG).
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "heic": self = .heic
        default: return nil
        }
    }
}

/// Names for saved captures: "Screenshot 2026-11-02 at 14.03.22.png", like macOS's own,
/// with " 2", " 3"… when the name is taken.
public enum FileNaming {
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        return "Screenshot \(c.year ?? 0)-\(two(c.month))-\(two(c.day)) at \(two(c.hour)).\(two(c.minute)).\(two(c.second))"
    }

    /// The default template: "Screenshot 2026-11-02 at 14.03.22".
    public static let defaultTemplate = "{type} {date} at {time}"

    /// Tokens a template can use, for the Settings help line.
    public static let tokens = ["{type}", "{date}", "{time}", "{year}", "{month}", "{day}", "{hour}", "{minute}", "{second}"]

    /// A file name from a template such as "{type} {date} at {time}". `type` is "Screenshot"
    /// or "Recording". Characters Finder can't take ("/" and ":") become "-"; an empty
    /// result falls back to the default template.
    public static func baseName(template: String, type: String = "Screenshot", date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        let values: [String: String] = [
            "{type}": type,
            "{date}": "\(c.year ?? 0)-\(two(c.month))-\(two(c.day))",
            "{time}": "\(two(c.hour)).\(two(c.minute)).\(two(c.second))",
            "{year}": "\(c.year ?? 0)", "{month}": two(c.month), "{day}": two(c.day),
            "{hour}": two(c.hour), "{minute}": two(c.minute), "{second}": two(c.second),
        ]
        var name = template
        for (token, value) in values { name = name.replacingOccurrences(of: token, with: value) }
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { return baseName(template: defaultTemplate, type: type, date: date, timeZone: timeZone) }
        return name
    }

    /// The first free file name in a folder. `exists` reports whether a name is taken.
    public static func uniqueName(base: String, fileExtension: String, exists: (String) -> Bool) -> String {
        let first = "\(base).\(fileExtension)"
        if !exists(first) { return first }
        var n = 2
        while exists("\(base) \(n).\(fileExtension)") { n += 1 }
        return "\(base) \(n).\(fileExtension)"
    }
}

/// Where Save puts captures.
public enum SaveLocation {
    /// In order: the test override (`SNAPPER_SAVE_DIR`), the folder chosen in Settings,
    /// the folder macOS's own screenshots go to, then the Desktop.
    public static func resolve(override: String?, chosen: String?, systemScreenshotFolder: String?, home: URL) -> URL {
        for candidate in [override, chosen, systemScreenshotFolder] {
            if let path = candidate?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }
}

/// Encodes captures to file data.
public enum ImageEncoder {
    public enum Failure: Error, Equatable {
        case encodingFailed
    }

    public static func data(for image: CGImage, format: ImageFormat, jpegQuality: Double = 0.9) throws -> Data {

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        var options: [CFString: Any] = [:]
        if format != .png { options[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        // JPEG has no alpha: flatten transparent window shadows onto white first.
        let source = format == .jpeg && image.hasAlpha ? (image.flattened() ?? image) : image
        CGImageDestinationAddImage(destination, source, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }

    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Writes the image to `folder` with a unique name. Returns the file's URL.
    ///
    /// `replacing`: where this same capture was saved before. If that file is still there,
    /// in this folder and format, it's overwritten instead of making "… 2", so saving again
    /// after more edits updates the one file.
    public static func save(_ image: CGImage, format: ImageFormat, to folder: URL, date: Date = Date(), baseName: String? = nil,
                            replacing previous: URL? = nil, fileManager: FileManager = .default) throws -> URL {
        if let previous, previous.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
           ImageFormat(fileExtension: previous.pathExtension) == format, fileManager.fileExists(atPath: previous.path) {
            try data(for: image, format: format).write(to: previous, options: .atomic)
            return previous
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = FileNaming.uniqueName(base: baseName ?? FileNaming.baseName(for: date), fileExtension: format.fileExtension) {
            fileManager.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let url = folder.appendingPathComponent(name)
        try data(for: image, format: format).write(to: url, options: .withoutOverwriting)
        return url
    }
}

extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// The image drawn on white, without alpha.
    func flattened() -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
