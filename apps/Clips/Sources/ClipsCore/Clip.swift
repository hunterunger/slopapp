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
    /// A link's page title, when the copying app provided one (Safari's "Copy Link", a link
    /// copied from a web page). Never fetched from the network.
    public var title: String?
    /// A name the user gave the clip ("Home address"). Shown instead of the kind on its card,
    /// searched, and kept when the same content is copied again.
    public var label: String? {
        didSet { if label != oldValue { rebuildSearchKey() } }
    }
    /// The board the clip is pinned to, if any. Pinned clips are never removed automatically.
    public var boardID: UUID?
    /// Text found in an image clip (on-device, after capture). Nil until it has been looked
    /// for; empty when there was none.
    public var recognizedText: String? {
        didSet { if recognizedText != oldValue { rebuildSearchKey() } }
    }
    public var created: Date
    public var lastUsed: Date
    public var useCount: Int
    /// Content fingerprint, so copying the same thing again moves it to the top instead of
    /// adding a duplicate.
    public var fingerprint: String

    /// Lowercased, accent-folded UTF-8 of text + source app, for fast substring search.
    public private(set) var searchKey: [UInt8]

    public init(
        id: UUID = UUID(), kind: ClipKind, text: String, textLength: Int? = nil, longText: String? = nil,
        imageWidth: Int = 0, imageHeight: Int = 0, byteCount: Int = 0, hasRichText: Bool = false,
        sourceBundleID: String? = nil, sourceName: String? = nil, title: String? = nil,
        created: Date, lastUsed: Date? = nil, useCount: Int = 1, isPinned: Bool = false,
        boardID: UUID? = nil, label: String? = nil, recognizedText: String? = nil,
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
        self.title = title
        self.created = created
        self.lastUsed = lastUsed ?? created
        self.useCount = useCount
        self.boardID = boardID ?? (isPinned ? Board.pinnedID : nil)
        self.label = label
        self.recognizedText = recognizedText
        self.fingerprint = fingerprint
        self.searchKey = []
        rebuildSearchKey()
    }

    /// On a board. Setting it to true puts an unpinned clip on the default board (Pinned);
    /// setting it to false takes the clip off its board.
    public var isPinned: Bool {
        get { boardID != nil }
        set { boardID = newValue ? (boardID ?? Board.pinnedID) : nil }
    }

    /// Longest text kept from an image (a dense screenshot is a few thousand characters).
    public static let recognizedTextLimit = 5_000

    /// Text recognised in an image, if any was found.
    public var imageText: String? {
        guard kind == .image, let recognizedText, !recognizedText.isEmpty else { return nil }
        return recognizedText
    }

    public var isTruncated: Bool { textLength > text.count }

    /// True when search only covers the start of the text.
    public var isSearchTruncated: Bool { textLength > Self.searchLimit }

    /// The text search sees: up to `searchLimit` characters.
    public var searchableText: String { kind == .image ? (recognizedText ?? "") : (longText ?? text) }

    /// File paths of a file clip.
    public var filePaths: [String] {
        kind == .file ? text.split(separator: "\n").map(String.init) : []
    }

    mutating func rebuildSearchKey() {
        var key = longText ?? text
        if kind == .image { key = "image" + (recognizedText.map { "\n" + $0 } ?? "") }
        if let label { key += "\n" + label }
        if let title { key += "\n" + title }
        if let sourceName { key += "\n" + sourceName }
        searchKey = Array(SearchText.fold(key).utf8)
    }

    public static func == (lhs: Clip, rhs: Clip) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.longText == rhs.longText
            && lhs.textLength == rhs.textLength && lhs.imageWidth == rhs.imageWidth
            && lhs.imageHeight == rhs.imageHeight && lhs.byteCount == rhs.byteCount
            && lhs.hasRichText == rhs.hasRichText && lhs.sourceBundleID == rhs.sourceBundleID
            && lhs.sourceName == rhs.sourceName && lhs.title == rhs.title && lhs.created == rhs.created
            && lhs.lastUsed == rhs.lastUsed && lhs.useCount == rhs.useCount
            && lhs.boardID == rhs.boardID && lhs.label == rhs.label && lhs.recognizedText == rhs.recognizedText
            && lhs.fingerprint == rhs.fingerprint
    }
}
