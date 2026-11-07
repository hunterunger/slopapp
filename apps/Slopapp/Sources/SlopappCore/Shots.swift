import Foundation

/// One store screenshot from the feed (docs/screenshots.md): a light and a dark image at
/// 2880 × 1800, each with a 1440 × 900 copy, plus a title and a one-line caption drawn as
/// real text. URLs may be relative to the feed.
public struct FeedShot: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var caption: String
    public var light: URL
    public var dark: URL
    public var light1x: URL?
    public var dark1x: URL?

    public init(id: String, title: String, caption: String, light: URL, dark: URL, light1x: URL? = nil, dark1x: URL? = nil) {
        self.id = id
        self.title = title
        self.caption = caption
        self.light = light
        self.dark = dark
        self.light1x = light1x
        self.dark1x = dark1x
    }

    enum CodingKeys: String, CodingKey { case id, title, caption, light, dark, light1x, dark1x }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = decoder.userInfo[FeedParser.baseURLKey] as? URL
        func url(_ key: CodingKeys) throws -> URL? {
            try c.decodeIfPresent(String.self, forKey: key).flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
        }
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        guard let light = try url(.light), let dark = try url(.dark) else {
            throw DecodingError.dataCorruptedError(forKey: .light, in: c, debugDescription: "a shot needs light and dark images")
        }
        self.light = light
        self.dark = dark
        light1x = try url(.light1x)
        dark1x = try url(.dark1x)
    }

    public enum Appearance: String, Sendable { case light, dark }

    /// The page shows the 1440-wide copy (enough for the gallery's width on Retina); the
    /// full-size viewer shows the 2880 master.
    public enum Size: String, Sendable { case page, full }

    public func url(_ appearance: Appearance, _ size: Size) -> URL {
        switch (appearance, size) {
        case (.light, .page): light1x ?? light
        case (.dark, .page): dark1x ?? dark
        case (.light, .full): light
        case (.dark, .full): dark
        }
    }

    /// Something to show for VoiceOver and as the image's description.
    public var accessibilityText: String {
        caption.isEmpty ? title : "\(title). \(caption)"
    }
}

/// Decodes a list of shots, dropping malformed entries instead of failing the app.
struct LossyShots: Decodable {
    var shots: [FeedShot]

    init(from decoder: any Decoder) throws {
        var list = try decoder.unkeyedContainer()
        var shots: [FeedShot] = []
        var ids = Set<String>()
        while !list.isAtEnd {
            if let shot = try? list.decode(FeedShot.self) {
                if ids.insert(shot.id).inserted { shots.append(shot) }
            } else {
                _ = try? list.decode(Skip.self)
            }
        }
        self.shots = shots
    }

    private struct Skip: Decodable {}
}

/// The gallery's paging: which shot is showing, and where the arrows and keys go. Arrows
/// stop at the ends (no wrapping), like the App Store's.
public struct GalleryPaging: Equatable, Sendable {
    public private(set) var index: Int
    public let count: Int

    public init(count: Int, index: Int = 0) {
        self.count = max(0, count)
        self.index = Self.clamp(index, count: max(0, count))
    }

    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < count - 1 }

    public mutating func goBack() { index = Self.clamp(index - 1, count: count) }
    public mutating func goForward() { index = Self.clamp(index + 1, count: count) }
    public mutating func go(to newIndex: Int) { index = Self.clamp(newIndex, count: count) }

    /// "2 of 5", for VoiceOver and the page dots' label.
    public var position: String { count == 0 ? "" : "\(index + 1) of \(count)" }

    /// The shots worth loading now: the visible one and its neighbours (the next one peeks in).
    public var prefetch: [Int] {
        guard count > 0 else { return [] }
        return [index, index + 1, index - 1].filter { (0..<count).contains($0) }
    }

    static func clamp(_ value: Int, count: Int) -> Int {
        count == 0 ? 0 : min(max(value, 0), count - 1)
    }
}

/// Where shots are cached: `<caches>/shots/<slug>/<set version>/<file>`. A new set (another
/// version) gets a new folder and the old one is removed.
public enum ShotCache {
    public static func file(in caches: URL, slug: String, version: String?, url: URL) -> URL {
        folder(in: caches, slug: slug, version: version).appendingPathComponent(safe(url.lastPathComponent))
    }

    public static func folder(in caches: URL, slug: String, version: String?) -> URL {
        caches.appendingPathComponent(safe(slug), isDirectory: true)
            .appendingPathComponent(safe(version ?? "0"), isDirectory: true)
    }

    /// Folders of older sets of this app, to delete.
    public static func stale(in caches: URL, slug: String, version: String?, existing: [String]) -> [URL] {
        let keep = safe(version ?? "0")
        return existing.filter { $0 != keep }.map {
            caches.appendingPathComponent(safe(slug), isDirectory: true).appendingPathComponent($0, isDirectory: true)
        }
    }

    /// A file-name-safe version of a feed string (no "/", "..", or leading dots).
    static func safe(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.@"))
        var result = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        while result.hasPrefix(".") { result.removeFirst() }
        return result.isEmpty ? "_" : String(result.prefix(120))
    }
}
