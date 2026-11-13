import Foundation

/// How long unpinned clips are kept.
public enum HistoryRetention: String, Sendable, CaseIterable, Identifiable {
    case day, week, month, threeMonths, year, forever

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        case .threeMonths: "3 Months"
        case .year: "1 Year"
        case .forever: "Forever"
        }
    }

    public var maxAge: TimeInterval? {
        let day: TimeInterval = 86_400
        switch self {
        case .day: return day
        case .week: return 7 * day
        case .month: return 31 * day
        case .threeMonths: return 92 * day
        case .year: return 366 * day
        case .forever: return nil
        }
    }

    public static let `default` = HistoryRetention.month
}

/// The in-memory history, most recently used first. Pure: persistence is the caller's job,
/// driven by what each method returns.
public struct History: Sendable {
    /// Upper bound on unpinned clips regardless of age, to keep memory and search bounded.
    public static let defaultItemLimit = 10_000

    public private(set) var clips: [Clip]
    public var itemLimit: Int

    public init(clips: [Clip] = [], itemLimit: Int = History.defaultItemLimit) {
        self.clips = clips.sorted { $0.lastUsed > $1.lastUsed }
        self.itemLimit = itemLimit
    }

    public enum RecordResult: Equatable, Sendable {
        /// A new clip at the top.
        case inserted(Clip)
        /// The same content was already in the history: it moved to the top. Store the new
        /// payload too (the formatting may differ).
        case bumped(Clip)
    }

    public func clip(id: UUID) -> Clip? { clips.first { $0.id == id } }

    /// Adds a captured clip, or moves an existing one with the same content to the top.
    @discardableResult
    public mutating func record(_ clip: Clip) -> RecordResult {
        if let index = clips.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
            var existing = clips.remove(at: index)
            existing.lastUsed = clip.created
            existing.useCount += 1
            existing.sourceBundleID = clip.sourceBundleID ?? existing.sourceBundleID
            existing.sourceName = clip.sourceName ?? existing.sourceName
            existing.title = clip.title ?? existing.title
            existing.hasRichText = clip.hasRichText
            existing.byteCount = clip.byteCount
            existing.rebuildSearchKey()
            clips.insert(existing, at: 0)
            return .bumped(existing)
        }
        clips.insert(clip, at: 0)
        return .inserted(clip)
    }

    /// Marks a clip as just used (pasted or copied from Clips) and moves it to the top.
    @discardableResult
    public mutating func touch(id: UUID, now: Date) -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        var clip = clips.remove(at: index)
        clip.lastUsed = now
        clip.useCount += 1
        clips.insert(clip, at: 0)
        return clip
    }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool, id: UUID) -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        clips[index].isPinned = pinned
        return clips[index]
    }

    /// Puts clips on a board (or takes them off with nil). Returns the clips that changed.
    @discardableResult
    public mutating func setBoard(_ boardID: UUID?, ids: Set<UUID>) -> [Clip] {
        var changed: [Clip] = []
        for index in clips.indices where ids.contains(clips[index].id) && clips[index].boardID != boardID {
            clips[index].boardID = boardID
            changed.append(clips[index])
        }
        return changed
    }

    /// Takes every clip off a board that's being deleted. They stay in the history, unpinned.
    @discardableResult
    public mutating func releaseBoard(_ boardID: UUID) -> [Clip] {
        setBoard(nil, ids: Set(clips.filter { $0.boardID == boardID }.map(\.id)))
    }

    /// How many clips are on a board.
    public func count(onBoard boardID: UUID) -> Int {
        clips.reduce(0) { $0 + ($1.boardID == boardID ? 1 : 0) }
    }

    /// Replaces a clip with an edited version of itself (same id), where it is.
    @discardableResult
    public mutating func replace(_ clip: Clip) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return false }
        clips[index] = clip
        return true
    }

    /// Gives a clip a label (nil removes it). Returns the clip if it changed.
    @discardableResult
    public mutating func setLabel(_ label: String?, id: UUID) -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == id }), clips[index].label != label else { return nil }
        clips[index].label = label
        return clips[index]
    }

    /// Stores the text found in an image clip. Returns the clip, or nil if it's gone.
    @discardableResult
    public mutating func setRecognizedText(_ text: String, id: UUID) -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        clips[index].recognizedText = text
        return clips[index]
    }

    /// Image clips whose text hasn't been looked for yet, newest first.
    public var imagesAwaitingText: [UUID] {
        clips.filter { $0.kind == .image && $0.recognizedText == nil }.map(\.id)
    }

    /// Removes clips and returns them (with their positions) so the removal can be undone.
    @discardableResult
    public mutating func remove(ids: Set<UUID>) -> [Clip] {
        let removed = clips.filter { ids.contains($0.id) }
        clips.removeAll { ids.contains($0.id) }
        return removed
    }

    /// Puts removed clips back where their dates say they belong.
    public mutating func restore(_ restored: [Clip]) {
        let existing = Set(clips.map(\.id))
        clips.append(contentsOf: restored.filter { !existing.contains($0.id) })
        clips.sort { $0.lastUsed > $1.lastUsed }
    }

    /// Removes every unpinned clip (or every clip). Returns what was removed.
    @discardableResult
    public mutating func clear(keepPinned: Bool = true) -> [Clip] {
        let removed = clips.filter { !keepPinned || !$0.isPinned }
        clips.removeAll { !keepPinned || !$0.isPinned }
        return removed
    }

    /// Drops unpinned clips older than the retention period or beyond the item limit.
    /// Returns the ids removed.
    @discardableResult
    public mutating func prune(retention: HistoryRetention, now: Date) -> [UUID] {
        var removed: [UUID] = []
        var unpinnedKept = 0
        let cutoff = retention.maxAge.map { now.addingTimeInterval(-$0) }
        clips.removeAll { clip in
            guard !clip.isPinned else { return false }
            if let cutoff, clip.lastUsed < cutoff {
                removed.append(clip.id)
                return true
            }
            unpinnedKept += 1
            if unpinnedKept > itemLimit {
                removed.append(clip.id)
                return true
            }
            return false
        }
        return removed
    }
}
