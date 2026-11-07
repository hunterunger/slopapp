import CoreGraphics
import Foundation

/// `apps/<Name>/showcase.json`: an app's shot list. See docs/screenshots.md.
public struct ShowcaseFile: Codable, Equatable, Sendable {
    /// Bumped when the set should be retaken (recorded in the manifest).
    public var version: Int
    /// Extra environment for every scene (the app's test-data hooks). `{data}` becomes the
    /// scene's scratch folder, where the app's `showcase/` fixtures are copied.
    public var env: [String: String]
    public var shots: [Shot]

    public init(version: Int, env: [String: String] = [:], shots: [Shot]) {
        self.version = version
        self.env = env
        self.shots = shots
    }

    enum CodingKeys: String, CodingKey { case version, env, shots }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        shots = try c.decode([Shot].self, forKey: .shots)
    }

    public static func load(_ url: URL) throws -> ShowcaseFile {
        let file = try JSONDecoder().decode(ShowcaseFile.self, from: Data(contentsOf: url))
        try file.validate()
        return file
    }

    public struct Invalid: Error, CustomStringConvertible {
        public var description: String
    }

    /// 3 to 5 shots (1 or more is accepted with a warning by the script), unique ids that
    /// are safe file names, a title and caption each, sizes that parse.
    public func validate() throws {
        guard !shots.isEmpty else { throw Invalid(description: "showcase.json has no shots") }
        guard shots.count <= 5 else { throw Invalid(description: "showcase.json has \(shots.count) shots; a set is 3 to 5") }
        var seen = Set<String>()
        for shot in shots {
            guard shot.id.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
                throw Invalid(description: "shot id \"\(shot.id)\" must be lowercase letters, digits and dashes")
            }
            guard seen.insert(shot.id).inserted else { throw Invalid(description: "duplicate shot id \"\(shot.id)\"") }
            guard !shot.title.isEmpty, !shot.caption.isEmpty else {
                throw Invalid(description: "shot \"\(shot.id)\" needs a title and a caption")
            }
            guard !shot.title.contains("!"), !shot.caption.contains("!") else {
                throw Invalid(description: "shot \"\(shot.id)\": no exclamation marks (docs/design-system.md §5)")
            }
            if let size = shot.size, Shot.parseSize(size) == nil {
                throw Invalid(description: "shot \"\(shot.id)\": size \"\(size)\" should look like 1200x760")
            }
            if let zoom = shot.zoom, !(0.25...3).contains(zoom) {
                throw Invalid(description: "shot \"\(shot.id)\": zoom \(zoom) is outside 0.25–3")
            }
        }
    }

    /// The environment for one scene: `env` with `{data}` replaced.
    public func environment(data: String) -> [String: String] {
        env.mapValues { $0.replacingOccurrences(of: "{data}", with: data) }
    }
}

public struct Shot: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var caption: String
    /// The scene the app shows (`SLOP_SHOWCASE`); defaults to the id.
    public var scene: String?
    /// The main window's content size, "1200x760".
    public var size: String?
    /// Points of window per point of the 1440 × 900 canvas. Default: 1, smaller if it doesn't fit.
    public var zoom: Double?
    /// Draw a menu bar strip with the app's icon (default: the app is a menu bar app).
    public var menuBar: Bool?
    public var callout: Callout?

    public init(id: String, title: String, caption: String, scene: String? = nil, size: String? = nil,
                zoom: Double? = nil, menuBar: Bool? = nil, callout: Callout? = nil) {
        self.id = id
        self.title = title
        self.caption = caption
        self.scene = scene
        self.size = size
        self.zoom = zoom
        self.menuBar = menuBar
        self.callout = callout
    }

    public var sceneName: String { scene ?? id }

    public static func parseSize(_ text: String) -> CGSize? {
        let parts = text.split(whereSeparator: { "x×X,".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w >= 1, h >= 1 else { return nil }
        return CGSize(width: w, height: h)
    }
}

/// A magnified crop of the first window, to show a detail that's too small at gallery size.
public struct Callout: Codable, Equatable, Sendable {
    /// In the first window's points, origin top-left.
    public var x, y, width, height: Double
    /// Magnification relative to the window as placed. Default 2.
    public var zoom: Double?
    /// Which side of the window the callout sits on: left, right, top or bottom. Default: the
    /// side nearest the detail.
    public var side: Side?

    public enum Side: String, Codable, Sendable { case left, right, top, bottom }

    public init(x: Double, y: Double, width: Double, height: Double, zoom: Double? = nil, side: Side? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.zoom = zoom
        self.side = side
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// The ready file an app writes (SlopKit `ShowcaseReady`; kept in sync by hand, it's small).
public struct ReadyFile: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case window, panel, statusItem }
        public var id: UInt32
        public var kind: Kind
        public var title: String
        public var frame: Rect
        /// A PNG the app drew instead of a window to capture (the menu bar icon).
        public var image: String?

        public init(id: UInt32, kind: Kind, title: String = "", frame: Rect, image: String? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.frame = frame
            self.image = image
        }
    }

    public struct Rect: Codable, Equatable, Sendable {
        public var x, y, width, height: Double
        public init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
        public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    public var scene: String
    public var appearance: String
    public var scale: Double
    public var screen: Rect
    public var windows: [Window]
    public var error: String?

    public init(scene: String, appearance: String, scale: Double, screen: Rect, windows: [Window], error: String? = nil) {
        self.scene = scene
        self.appearance = appearance
        self.scale = scale
        self.screen = screen
        self.windows = windows
        self.error = error
    }

    public static func load(_ url: URL) throws -> ReadyFile {
        try JSONDecoder().decode(ReadyFile.self, from: Data(contentsOf: url))
    }
}

/// `web/public/shots/<slug>/manifest.json`: what was taken, when, from which version.
public struct ShotManifest: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        /// File names next to the manifest, by appearance: "light" → "hero-light.webp".
        public var light: String
        public var dark: String
        public var light1x: String
        public var dark1x: String
        public var width: Int
        public var height: Int

        public init(id: String, width: Int, height: Int) {
            self.id = id
            light = "\(id)-light.webp"
            dark = "\(id)-dark.webp"
            light1x = "\(id)-light@1x.webp"
            dark1x = "\(id)-dark@1x.webp"
            self.width = width
            self.height = height
        }
    }

    public var slug: String
    public var appVersion: String
    public var showcaseVersion: Int
    public var date: String
    public var shots: [Entry]

    public init(slug: String, appVersion: String, showcaseVersion: Int, date: String, shots: [Entry]) {
        self.slug = slug
        self.appVersion = appVersion
        self.showcaseVersion = showcaseVersion
        self.date = date
        self.shots = shots
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
