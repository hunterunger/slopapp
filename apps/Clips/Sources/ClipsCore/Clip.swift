import Foundation

/// What a clip is, for icons, filters and how it pastes.
public enum ClipKind: Int, Sendable, CaseIterable, Codable {
    case text = 0
    case link = 1
    case image = 2
    case file = 3
    case color = 4
}

/// One pasteboard type and its bytes, e.g. ("public.utf8-plain-text", "hello").
public struct Representation: Sendable, Equatable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// Everything needed to put a clip back on the pasteboard: one entry per pasteboard item
/// (copying three files in Finder makes three items), each with its representations.
public struct ClipPayload: Sendable, Equatable {
    public var items: [[Representation]]

    public init(items: [[Representation]]) {
        self.items = items
    }

    public var byteCount: Int {
        items.reduce(0) { $0 + $1.reduce(0) { $0 + $1.data.count } }
    }

    /// The same clip as plain text only (for "Paste as Plain Text").
    public func plainText() -> ClipPayload? {
        for item in items {
            if let rep = item.first(where: { $0.type == PasteboardType.string }) {
                return ClipPayload(items: [[rep]])
            }
        }
        return nil
    }
}

/// One entry in the history: metadata plus a capped copy of its text for search and preview.
/// The full content (rich text, image bytes) lives in the database as a `ClipPayload`.
public struct Clip: Identifiable, Sendable, Equatable {
    /// Longest text shown in previews and rows. Longer text is still pasted in full.
    public static let textLimit = 10_000
    /// Longest text search looks through (1 million characters, about a 300-page book).
    public static let searchLimit = 1_000_000

    public var id: UUID
    public var kind: ClipKind
    /// Plain text (capped at `textLimit`). For files: one path per line. Empty for images.
    public var text: String
    /// Length of the full plain text, in characters.
    public var textLength: Int
    /// For text longer than `textLimit`: the first `searchLimit` characters, so search finds
    /// words far into long clips. Nil for short clips (then `text` is everything).
    public private(set) var longText: String?
    /// Pixel size of an image clip.
    public var imageWidth: Int
    public var imageHeight: Int
    /// Size of the stored payload.
    public var byteCount: Int
    public var hasRichText: Bool
    public var sourceBundleID: String?
    public var sourceName: String?
    public var created: Date
    public var lastUsed: Date
    public var useCount: Int
    public var isPinned: Bool
    /// Content fingerprint, so copying the same thing again moves it to the top instead of
    /// adding a duplicate.
    public var fingerprint: String

    /// Lowercased, accent-folded UTF-8 of text + source app, for fast substring search.
    public private(set) var searchKey: [UInt8]

    public init(
        id: UUID = UUID(), kind: ClipKind, text: String, textLength: Int? = nil, longText: String? = nil,
        imageWidth: Int = 0, imageHeight: Int = 0, byteCount: Int = 0, hasRichText: Bool = false,
        sourceBundleID: String? = nil, sourceName: String? = nil,
        created: Date, lastUsed: Date? = nil, useCount: Int = 1, isPinned: Bool = false,
        fingerprint: String
    ) {
        self.id = id
        self.kind = kind
        let count = text.count
        if count > Self.textLimit {
            self.text = String(text.prefix(Self.textLimit))
            self.longText = count > Self.searchLimit ? String(text.prefix(Self.searchLimit)) : text
        } else {
            self.text = text
            self.longText = longText
        }
        self.textLength = textLength ?? count
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteCount = byteCount
        self.hasRichText = hasRichText
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.created = created
        self.lastUsed = lastUsed ?? created
        self.useCount = useCount
        self.isPinned = isPinned
        self.fingerprint = fingerprint
        self.searchKey = []
        rebuildSearchKey()
    }

    public var isTruncated: Bool { textLength > text.count }

    /// True when search only covers the start of the text.
    public var isSearchTruncated: Bool { textLength > Self.searchLimit }

    /// The text search sees: up to `searchLimit` characters.
    public var searchableText: String { longText ?? text }

    /// File paths of a file clip.
    public var filePaths: [String] {
        kind == .file ? text.split(separator: "\n").map(String.init) : []
    }

    mutating func rebuildSearchKey() {
        var key = longText ?? text
        if kind == .image { key = "image" }
        if let sourceName { key += "\n" + sourceName }
        searchKey = Array(SearchText.fold(key).utf8)
    }

    public static func == (lhs: Clip, rhs: Clip) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.longText == rhs.longText
            && lhs.textLength == rhs.textLength && lhs.imageWidth == rhs.imageWidth
            && lhs.imageHeight == rhs.imageHeight && lhs.byteCount == rhs.byteCount
            && lhs.hasRichText == rhs.hasRichText && lhs.sourceBundleID == rhs.sourceBundleID
            && lhs.sourceName == rhs.sourceName && lhs.created == rhs.created
            && lhs.lastUsed == rhs.lastUsed && lhs.useCount == rhs.useCount
            && lhs.isPinned == rhs.isPinned && lhs.fingerprint == rhs.fingerprint
    }
}
