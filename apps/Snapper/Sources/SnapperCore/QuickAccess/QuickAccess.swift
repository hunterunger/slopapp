import Foundation

/// Which bottom corner the capture cards sit in.
public enum CardCorner: String, Sendable, CaseIterable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var title: String { self == .left ? "Bottom Left" : "Bottom Right" }
}

/// When cards close by themselves.
public enum AutoClose: Int, Sendable, CaseIterable, Identifiable {
    case never = 0
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300

    public var id: Int { rawValue }
    public var interval: TimeInterval? { self == .never ? nil : TimeInterval(rawValue) }

    public var title: String {
        switch self {
        case .never: "Never"
        case .tenSeconds: "After 10 Seconds"
        case .thirtySeconds: "After 30 Seconds"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        }
    }
}

/// What happens to a card when it closes by itself.
public enum AutoCloseAction: String, Sendable, CaseIterable, Identifiable {
    case close
    case saveAndClose
    public var id: String { rawValue }
    public var title: String { self == .close ? "Close" : "Save and Close" }
}

/// What happens right after a capture.
public struct AfterCapture: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let showCard = AfterCapture(rawValue: 1 << 0)
    public static let copy = AfterCapture(rawValue: 1 << 1)
    public static let save = AfterCapture(rawValue: 1 << 2)

    public static let `default`: AfterCapture = [.showCard]
}

/// The stack of capture cards and their auto-close timers. Pure state: the app asks it which
/// cards are due (`due(at:)`) from a single timer, so tests drive time directly.
public struct CardQueue<ID: Hashable & Sendable>: Sendable {
    public struct Entry: Sendable, Equatable {
        public var id: ID
        /// When the card closes by itself; nil = never (or paused while hovered).
        public var deadline: Date?
    }

    /// At most this many cards show; adding another closes the oldest.
    public let limit: Int
    public private(set) var entries: [Entry] = []

    public init(limit: Int = 5) {
        self.limit = max(1, limit)
    }

    public var ids: [ID] { entries.map(\.id) }

    /// Adds a card (newest last). Returns the ids pushed out by the limit, oldest first.
    @discardableResult
    public mutating func add(_ id: ID, now: Date, autoClose: AutoClose) -> [ID] {
        entries.append(Entry(id: id, deadline: autoClose.interval.map { now.addingTimeInterval($0) }))
        var evicted: [ID] = []
        while entries.count > limit {
            evicted.append(entries.removeFirst().id)
        }
        return evicted
    }

    public mutating func remove(_ id: ID) {
        entries.removeAll { $0.id == id }
    }

    /// Hovering a card stops its timer; leaving restarts the full interval.
    public mutating func setHovering(_ id: ID, _ hovering: Bool, now: Date, autoClose: AutoClose) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].deadline = hovering ? nil : autoClose.interval.map { now.addingTimeInterval($0) }
    }

    /// Restarts every timer after the setting changes.
    public mutating func reschedule(now: Date, autoClose: AutoClose) {
        for index in entries.indices {
            entries[index].deadline = autoClose.interval.map { now.addingTimeInterval($0) }
        }
    }

    /// Cards whose time is up.
    public func due(at now: Date) -> [ID] {
        entries.filter { $0.deadline.map { $0 <= now } ?? false }.map(\.id)
    }

    /// The next time a card is due, for scheduling one timer.
    public var nextDeadline: Date? {
        entries.compactMap(\.deadline).min()
    }
}

/// The size of a capture card: the card's width, and the capture's aspect ratio within
/// limits. Wide captures are cropped (aspect fill) rather than making the card so short that
/// its buttons collide; tall ones stop at 1.1 × the width.
public enum CardLayout {
    public static func thumbnailSize(for size: CGSize, width: CGFloat, minHeight: CGFloat) -> CGSize {
        let floor = max(minHeight, width * 0.42)
        guard size.width > 0, size.height > 0 else { return CGSize(width: width, height: max(floor, width * 0.62).rounded()) }
        let height = min(max(width * size.height / size.width, floor), max(width * 1.1, floor))
        return CGSize(width: width, height: height.rounded())
    }
}
