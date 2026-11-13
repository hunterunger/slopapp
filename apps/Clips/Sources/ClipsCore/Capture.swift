import CryptoKit
import Foundation
import ImageIO

/// What was on the pasteboard, reduced to the types Clips stores. Built by the app from
/// NSPasteboard, or by tests directly.
public struct PasteboardSnapshot: Sendable, Equatable {
    public var items: [[Representation]]

    public init(items: [[Representation]]) {
        self.items = items
    }

    public init(text: String) {
        self.items = [[Representation(type: PasteboardType.string, data: Data(text.utf8))]]
    }

    func first(_ type: String) -> Data? {
        for item in items {
            if let rep = item.first(where: { $0.type == type }) { return rep.data }
        }
        return nil
    }
}

/// The user's recording settings, as the capture policy sees them.
public struct CaptureSettings: Sendable, Equatable {
    public var isPaused: Bool
    public var ignoredBundleIDs: Set<String>
    /// Larger clips are skipped (huge images, giant documents).
    public var maxBytes: Int

    public init(isPaused: Bool = false, ignoredBundleIDs: Set<String> = [], maxBytes: Int = 50_000_000) {
        self.isPaused = isPaused
        self.ignoredBundleIDs = ignoredBundleIDs
        self.maxBytes = maxBytes
    }
}

public enum SkipReason: Error, Equatable, Sendable {
    case paused
    case marked(String)
    case ignoredApp(String)
    case empty
    case tooLarge
}

public enum CaptureDecision: Equatable, Sendable {
    case record
    case skip(SkipReason)
}

/// Decides whether a pasteboard change is recorded. Runs on the types alone, before any data
/// is read, so concealed passwords are never even loaded into memory.
public enum CapturePolicy {
    public static func decide(types: Set<String>, sourceBundleID: String?, settings: CaptureSettings) -> CaptureDecision {
        if settings.isPaused { return .skip(.paused) }
        if let marker = PasteboardType.skipMarkers.first(where: types.contains) { return .skip(.marked(marker)) }
        if let source = sourceBundleID, settings.ignoredBundleIDs.contains(source) { return .skip(.ignoredApp(source)) }
        if types.isDisjoint(with: PasteboardType.stored) { return .skip(.empty) }
        return .record
    }
}

/// Trims a rich text representation (RTF or RTFD) the same way as its plain text. Returns
/// nil when it can't, and the rich version is then dropped. Lives in the app (it needs AppKit).
public typealias RichTextTrimmer = @Sendable (Representation) -> Representation?

/// Turns a pasteboard snapshot into a clip and the payload to store.
public enum ClipBuilder {
    /// Rich text larger than this is dropped (the plain text is kept).
    static let richTextLimit = 10_000_000

    /// `trimWhitespace` removes spaces, tabs and line breaks from both ends of copied text.
    /// RTF goes through `trimRichText`; HTML is kept as is, since it doesn't show whitespace at its ends.
    public static func build(
        _ snapshot: PasteboardSnapshot, sourceBundleID: String?, sourceName: String?,
        now: Date, maxBytes: Int = 50_000_000,
        trimWhitespace: Bool = false, trimRichText: RichTextTrimmer? = nil
    ) -> Result<(Clip, ClipPayload), SkipReason> {
        func clip(_ kind: ClipKind, text: String, payload: ClipPayload, fingerprint: String,
                  width: Int = 0, height: Int = 0, rich: Bool = false, title: String? = nil) -> Result<(Clip, ClipPayload), SkipReason> {
            guard payload.byteCount <= maxBytes else { return .failure(.tooLarge) }
            let clip = Clip(kind: kind, text: text, imageWidth: width, imageHeight: height,
                            byteCount: payload.byteCount, hasRichText: rich,
                            sourceBundleID: sourceBundleID, sourceName: sourceName, title: title,
                            created: now, fingerprint: fingerprint)
            return .success((clip, payload))
        }

        // Files (Finder copies): one pasteboard item per file.
        let fileItems = snapshot.items.compactMap { item -> (String, Representation)? in
            guard let rep = item.first(where: { $0.type == PasteboardType.fileURL }),
                  let string = String(data: rep.data, encoding: .utf8),
                  let url = URL(string: string), url.isFileURL else { return nil }
            return (url.path, rep)
        }
        if !fileItems.isEmpty {
            let paths = fileItems.map(\.0)
            let payload = ClipPayload(items: fileItems.map { [$0.1] })
            return clip(.file, text: paths.joined(separator: "\n"), payload: payload,
                        fingerprint: "file:" + digest(Data(paths.joined(separator: "\n").utf8)))
        }

        // Text, with rich representations from the same item.
        if let item = snapshot.items.first(where: { item in
            item.contains { $0.type == PasteboardType.string || $0.type == PasteboardType.url }
        }) {
            let raw = item.first(where: { $0.type == PasteboardType.string })?.data
                ?? item.first(where: { $0.type == PasteboardType.url })?.data ?? Data()
            let copied = String(decoding: raw, as: UTF8.self)
            let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let trims = trimWhitespace && trimmed != copied
                let text = trims ? trimmed : copied
                var reps = [Representation(type: PasteboardType.string, data: Data(text.utf8))]
                var rich = false
                for type in PasteboardType.richTextTypes + [PasteboardType.url, PasteboardType.urlName] {
                    guard var rep = item.first(where: { $0.type == type }), rep.data.count <= richTextLimit else { continue }
                    if trims, type == PasteboardType.rtf || type == PasteboardType.rtfd {
                        guard let cleaned = trimRichText?(rep) else { continue }
                        rep = cleaned
                    }
                    reps.append(rep)
                    if PasteboardType.richTextTypes.contains(type) { rich = true }
                }
                let kind: ClipKind = LinkDetector.isLink(trimmed) ? .link
                    : (ColorValue(hex: trimmed) != nil ? .color : .text)
                let title = kind == .link ? LinkTitle.from(item: item, url: trimmed) : nil
                return clip(kind, text: text, payload: ClipPayload(items: [reps]),
                            fingerprint: "text:" + digest(Data(text.utf8)), rich: rich, title: title)
            }
        }

        // Images (screenshots, "Copy Image" in a browser).
        for type in PasteboardType.imageTypes {
            if let data = snapshot.first(type) {
                guard data.count <= maxBytes else { return .failure(.tooLarge) }
                let size = ImageInfo.pixelSize(of: data)
                return clip(.image, text: "", payload: ClipPayload(items: [[Representation(type: type, data: data)]]),
                            fingerprint: "image:" + digest(data), width: size.width, height: size.height)
            }
        }
        return .failure(.empty)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A link's title, from what the copying app put next to it. Never fetched.
public enum LinkTitle {
    /// `public.url-name` (Safari, Mail…), else the text of a single `<a>` in the HTML (a
    /// link copied from a web page). Nil when there's nothing better than the URL itself.
    public static func from(item: [Representation], url: String) -> String? {
        if let data = item.first(where: { $0.type == PasteboardType.urlName })?.data,
           let title = clean(String(decoding: data, as: UTF8.self), url: url) {
            return title
        }
        if let data = item.first(where: { $0.type == PasteboardType.html })?.data, data.count <= 8_000 {
            return anchorText(String(decoding: data, as: UTF8.self), url: url)
        }
        return nil
    }

    /// The text inside the only `<a …>…</a>` of a small HTML fragment.
    static func anchorText(_ html: String, url: String) -> String? {
        let lower = html.lowercased()
        guard let open = lower.range(of: "<a "), lower.range(of: "<a ", range: open.upperBound..<lower.endIndex) == nil,
              let close = lower.range(of: "</a>", range: open.upperBound..<lower.endIndex),
              let tagEnd = lower.range(of: ">", range: open.upperBound..<close.lowerBound) else { return nil }
        let inner = String(html[tagEnd.upperBound..<close.lowerBound])
        return clean(stripTags(inner), url: url)
    }

    static func stripTags(_ html: String) -> String {
        var result = ""
        var inTag = false
        for character in html {
            if character == "<" { inTag = true } else if character == ">" { inTag = false } else if !inTag { result.append(character) }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func clean(_ raw: String, url: String) -> String? {
        let title = ClipText.oneLine(raw, limit: 300)
        guard !title.isEmpty, title != url, !LinkDetector.isLink(title) else { return nil }
        return title
    }
}

public enum LinkDetector {
    /// A single web or mail link with nothing else around it.
    public static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }), text.count < 4_000 else { return false }
        if text.lowercased().hasPrefix("www."), text.contains(".") { return true }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https", "ftp": return url.host?.isEmpty == false
        case "mailto": return text.count > 7
        default: return false
        }
    }
}

/// A `#RGB`, `#RRGGBB` or `#RRGGBBAA` color, so color clips can show a swatch.
public struct ColorValue: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        var digits = String(hex.dropFirst())
        guard [3, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit),
              let _ = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        if digits.count == 6 { digits += "ff" }
        guard let value = UInt64(digits, radix: 16) else { return nil }
        red = Double((value >> 24) & 0xFF) / 255
        green = Double((value >> 16) & 0xFF) / 255
        blue = Double((value >> 8) & 0xFF) / 255
        alpha = Double(value & 0xFF) / 255
    }
}

/// Image facts and thumbnails through ImageIO (no AppKit, safe off the main thread).
public enum ImageInfo {
    public static func pixelSize(of data: Data) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// A downscaled CGImage, at most `maxPixelSize` on its longer side.
    public static func thumbnail(of data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension ImageInfo {
    /// A small PNG preview for list rows, stored with the clip so rows never decode full images.
    public static func thumbnailPNG(of data: Data, maxPixelSize: Int = 128) -> Data? {
        guard let image = thumbnail(of: data, maxPixelSize: maxPixelSize) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
