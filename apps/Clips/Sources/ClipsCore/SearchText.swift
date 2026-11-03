import Foundation

/// Text folding and matching for search: case- and accent-insensitive, every word must match.
public enum SearchText {
    /// Lowercased with accents removed ("Café" → "cafe").
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The query split into folded words, each as UTF-8 bytes.
    public static func terms(_ query: String) -> [[UInt8]] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map { Array($0.utf8) }
    }

    /// True when every term occurs in `key`.
    public static func matches(_ key: [UInt8], terms: [[UInt8]]) -> Bool {
        for term in terms where !contains(key, term) { return false }
        return true
    }

    /// Where the query's words occur in `text` (case- and accent-insensitive), as NSRanges for
    /// bolding matches in a row title. Overlapping matches are merged.
    public static func highlights(in text: String, query: String) -> [NSRange] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty, !text.isEmpty else { return [] }
        let string = text as NSString
        var ranges: [NSRange] = []
        for word in words {
            var searchRange = NSRange(location: 0, length: string.length)
            while searchRange.length > 0 {
                let found = string.range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: searchRange)
                guard found.location != NSNotFound, found.length > 0 else { break }
                ranges.append(found)
                let next = found.location + found.length
                searchRange = NSRange(location: next, length: string.length - next)
            }
        }
        ranges.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, range.location <= last.location + last.length {
                merged[merged.count - 1].length = max(last.location + last.length, range.location + range.length) - last.location
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        if needle.isEmpty { return true }
        if needle.count > haystack.count { return false }
        return haystack.withUnsafeBufferPointer { h in
            needle.withUnsafeBufferPointer { n in
                memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil
            }
        }
    }
}

/// Which clips the panel shows.
public enum ClipFilter: String, Sendable, CaseIterable, Identifiable {
    case all, pinned, text, links, images, files

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .pinned: "Pinned"
        case .text: "Text"
        case .links: "Links"
        case .images: "Images"
        case .files: "Files"
        }
    }

    public func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: true
        case .pinned: clip.isPinned
        case .text: clip.kind == .text || clip.kind == .color
        case .links: clip.kind == .link
        case .images: clip.kind == .image
        case .files: clip.kind == .file
        }
    }
}

public enum ClipSearch {
    /// Clips matching `query` and `filter`, in history order (most recent first).
    public static func run(_ clips: [Clip], query: String, filter: ClipFilter = .all,
                           sourceBundleID: String? = nil) -> [Clip] {
        let terms = SearchText.terms(query)
        if terms.isEmpty, filter == .all, sourceBundleID == nil { return clips }
        return clips.filter { clip in
            filter.includes(clip)
                && (sourceBundleID == nil || clip.sourceBundleID == sourceBundleID)
                && (terms.isEmpty || SearchText.matches(clip.searchKey, terms: terms))
        }
    }
}
