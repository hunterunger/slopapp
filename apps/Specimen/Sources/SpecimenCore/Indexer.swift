import Foundation

/// The disposable on-disk cache of slow per-face facts, keyed by face id + file date.
public struct IndexCache: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var modified: Date?
        public var details: FaceDetails
    }

    public static let currentVersion = 3
    public var version = IndexCache.currentVersion
    public var entries: [String: Entry] = [:]
    /// The last full index, shown at launch while the fresh one builds.
    public var faces: [FontFace] = []

    public init(entries: [String: Entry] = [:], faces: [FontFace] = []) {
        self.entries = entries
        self.faces = faces
    }

    /// Reads the cache; a missing, damaged or old cache is just empty.
    public static func load(from url: URL) -> IndexCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? PropertyListDecoder().decode(IndexCache.self, from: data),
              cache.version == currentVersion else { return IndexCache() }
        return cache
    }

    /// Writes atomically, so a quit mid-write never leaves a half cache.
    public func save(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Builds the face index: lists every face (fast), then fills in slow facts from the cache
/// or the font, and classifies. Pure apart from the `FontSystem` it's given.
public struct FontIndexer: Sendable {
    public let system: any FontSystem

    public init(system: any FontSystem) {
        self.system = system
    }

    public struct Result: Sendable {
        public var faces: [FontFace]
        public var cache: IndexCache
        /// Faces whose details were read from the font (not the cache).
        public var freshlyRead: Int
    }

    /// `progress` is called with (done, total) every so often while reading fonts.
    public func build(cache: IndexCache, progress: (@Sendable (Int, Int) -> Void)? = nil) -> Result {
        let listed = system.listFaces()
        var newCache = IndexCache()
        var faces: [FontFace] = []
        faces.reserveCapacity(listed.count)
        var fresh = 0
        for (index, face) in listed.enumerated() {
            if Task.isCancelled { break }
            let modified = face.path.flatMap(system.modificationDate(path:))
            let details: FaceDetails
            if let entry = cache.entries[face.id], entry.modified == modified {
                details = entry.details
            } else {
                // Each font read loads its tables; let them go before the next one.
                details = autoreleasepool { system.details(for: face) }
                fresh += 1
            }
            newCache.entries[face.id] = IndexCache.Entry(modified: modified, details: details)
            faces.append(Self.makeFace(face, details: details, modified: modified))
            if index % 50 == 49 { progress?(index + 1, listed.count) }
        }
        newCache.faces = faces
        return Result(faces: faces, cache: newCache, freshlyRead: fresh)
    }

    public static func makeFace(_ face: SystemFace, details: FaceDetails, modified: Date?) -> FontFace {
        let facts = FontFacts(
            familyName: face.familyName, styleName: face.styleName, isMonospaceTrait: face.isMonospaceTrait,
            stylisticClass: face.stylisticClass, panose: details.panose, equalAdvances: details.equalAdvances,
            coversBasicLatin: details.coversBasicLatin, hasColorGlyphs: details.hasColorGlyphs
        )
        return FontFace(
            postScriptName: face.postScriptName, familyName: face.familyName, displayFamilyName: face.displayFamilyName,
            styleName: face.styleName, fullName: face.fullName, path: face.path, isEnabled: face.isEnabled,
            weight: face.weight, width: face.width, slant: face.slant, isItalic: face.isItalic,
            isVariable: !details.axes.isEmpty, axes: details.axes, format: face.format,
            category: Classifier.classify(facts), coversBasicLatin: details.coversBasicLatin,
            hasColorGlyphs: details.hasColorGlyphs, fileModified: modified
        )
    }

    /// Only the enabled state changed (e.g. after turning fonts on or off): re-list, reuse details.
    public static func applyStates(_ listed: [SystemFace], to faces: [FontFace]) -> [FontFace]? {
        let states = Dictionary(listed.map { ($0.id, $0.isEnabled) }, uniquingKeysWith: { a, _ in a })
        guard states.count == faces.count, faces.allSatisfy({ states[$0.id] != nil }) else { return nil }
        return faces.map { face in
            var face = face
            face.isEnabled = states[face.id] ?? face.isEnabled
            return face
        }
    }

    /// A bigger library for performance testing: every face repeated `copies` times under
    /// numbered family names. Display only: previews still use the real fonts.
    public static func stressCopies(_ faces: [FontFace], copies: Int) -> [FontFace] {
        guard copies > 1 else { return faces }
        var result = faces
        for copy in 2...copies {
            for face in faces {
                var clone = face
                clone.familyName = "\(face.familyName) \(copy)"
                clone.displayFamilyName = "\(face.displayFamilyName) \(copy)"
                clone.id = "\(face.id)#\(copy)"
                result.append(clone)
            }
        }
        return result
    }
}
