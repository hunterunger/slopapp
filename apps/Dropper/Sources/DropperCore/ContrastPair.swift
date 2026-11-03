import Foundation

/// The two colors in the Contrast Checker, kept across window closes and relaunches.
///
/// Decision (blind test round 1, F4): the checker never overwrites colors the person set.
/// The first time it opens it starts from the last two picks; after that it keeps its pair
/// and, when there are newer picks, *offers* them ("Use Last Picks") instead of replacing.
public struct ContrastPair: Equatable, Codable, Sendable {
    public var text: ColorValue
    public var background: ColorValue
    /// The history picks (newest first) the person has already been offered or used, so the
    /// same picks aren't offered twice.
    public var offeredPickIDs: [UUID]

    public static let blackOnWhite = ContrastPair(
        text: ColorValue(red: 0, green: 0, blue: 0), background: ColorValue(red: 1, green: 1, blue: 1), offeredPickIDs: [])

    public init(text: ColorValue, background: ColorValue, offeredPickIDs: [UUID]) {
        self.text = text
        self.background = background
        self.offeredPickIDs = offeredPickIDs
    }

    /// The pair for a first-ever open: the last two picks (older = text, newer = background),
    /// one pick as text on white, or black on white.
    public static func initial(from history: ColorHistory) -> ContrastPair {
        let items = Array(history.items.prefix(2))
        var pair = blackOnWhite
        switch items.count {
        case 2:
            pair.text = items[1].color
            pair.background = items[0].color
        case 1:
            pair.text = items[0].color
        default:
            break
        }
        pair.offeredPickIDs = items.map(\.id)
        return pair
    }

    /// Newer picks worth offering: the last two, if they haven't been offered yet and aren't
    /// already the pair shown.
    public func offer(from history: ColorHistory) -> (text: ColorValue, background: ColorValue)? {
        let items = Array(history.items.prefix(2))
        guard items.count == 2, items.map(\.id) != offeredPickIDs else { return nil }
        let candidate = (text: items[1].color, background: items[0].color)
        if candidate.text.identityKey == text.identityKey && candidate.background.identityKey == background.identityKey {
            return nil
        }
        return candidate
    }

    /// Marks the current last picks as seen (offer used, or picks made from the checker itself).
    public mutating func markOffered(_ history: ColorHistory) {
        offeredPickIDs = history.items.prefix(2).map(\.id)
    }

    public mutating func useOffer(from history: ColorHistory) {
        guard let offer = offer(from: history) else { return }
        text = offer.text
        background = offer.background
        markOffered(history)
    }
}
