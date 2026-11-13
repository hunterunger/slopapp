import Foundation

/// Geometry of the panel's horizontal row of cards: where each card sits, which cards a
/// scroll position shows, and how far to scroll to bring one into view. Pure math, so the
/// view only lays out the dozen cards on screen however many clips there are.
public struct StripLayout: Equatable, Sendable {
    public var itemWidth: Double
    public var spacing: Double
    /// Space before the first card and after the last.
    public var inset: Double

    public init(itemWidth: Double, spacing: Double, inset: Double) {
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.inset = inset
    }

    var stride: Double { itemWidth + spacing }

    public func contentWidth(count: Int) -> Double {
        guard count > 0 else { return 0 }
        return inset * 2 + Double(count) * itemWidth + Double(count - 1) * spacing
    }

    /// Left edge of card `index`.
    public func x(of index: Int) -> Double {
        inset + Double(index) * stride
    }

    /// The cards at least partly visible with the strip scrolled to `offset`.
    public func visibleRange(offset: Double, viewportWidth: Double, count: Int) -> Range<Int> {
        guard count > 0, viewportWidth > 0 else { return 0..<0 }
        // First card whose right edge is past the left of the viewport, last card whose left
        // edge is before its right.
        let first = Int(((offset - inset - itemWidth) / stride).rounded(.down)) + 1
        let last = Int(((offset + viewportWidth - inset) / stride).rounded(.up)) - 1
        let lower = min(max(first, 0), count)
        let upper = min(max(last + 1, lower), count)
        return lower..<upper
    }

    /// The card at a point in content coordinates, if the point is on one (not in a gap).
    public func index(atX x: Double, count: Int) -> Int? {
        let position = x - inset
        guard position >= 0 else { return nil }
        let index = Int((position / stride).rounded(.down))
        guard index < count, position - Double(index) * stride <= itemWidth else { return nil }
        return index
    }

    /// The smallest scroll that shows all of card `index` (keeping the inset around it).
    /// Returns `offset` unchanged if it's already fully visible.
    public func offset(revealing index: Int, from offset: Double, viewportWidth: Double, count: Int) -> Double {
        guard count > 0, index >= 0, index < count else { return offset }
        let maxOffset = max(0, contentWidth(count: count) - viewportWidth)
        let left = x(of: index) - inset
        let right = x(of: index) + itemWidth + inset
        var result = offset
        if left < offset {
            result = left
        } else if right > offset + viewportWidth {
            result = right - viewportWidth
        }
        return min(max(result, 0), maxOffset)
    }

    /// How many whole cards fit in the viewport (at least 1), for Page Up / Page Down.
    public func pageSize(viewportWidth: Double) -> Int {
        max(1, Int(((viewportWidth - inset * 2 + spacing) / stride).rounded(.down)))
    }
}

/// What a key press in the panel does. The panel's search field has the caret, so
/// anything that returns nil here is left to it (typing searches).
public enum PanelCommand: Equatable, Sendable {
    /// Paste (or copy, per the setting) the selected clip.
    case choose(plain: Bool)
    /// ⌘1–⌘9: paste the nth clip in the strip.
    case quickPaste(index: Int, plain: Bool)
    case move(Int)
    /// ⇧-arrows: grow or shrink the selection.
    case extend(Int)
    /// ⇧Home / ⇧End, ⇧⌘↑ / ⇧⌘↓: extend the selection to the first or last card.
    case extendToFirst
    case extendToLast
    /// ⌘A: select every card in the strip.
    case selectAll
    case first
    case last
    case pageBack
    case pageForward
    case previousTab
    case nextTab
    /// Tab: move the keyboard between the search field and the cards.
    case toggleFocus
    case quickLook
    case copy
    case togglePin
    /// ⌘O: open a link or file.
    case open
    case delete
    case undo
    /// ⌘T: pause or resume recording.
    case togglePause
    /// ⌘F: put the keyboard back in the search field.
    case focusSearch
    case close
    case openHistory
    case openSettings
    /// ⌘E: edit the selected clip's text (and its title).
    case edit
    /// ⌘R: give the selected clip a title.
    case rename
    /// ⌥⌘1–⌥⌘9: pin the selection to board n (0-based).
    case pinToBoard(index: Int)
    /// ⇧⌘N: a new board (with the selection on it, if any).
    case newBoard
    /// ⇧⌘C: start a paste stack (with the selected cards, or empty to collect copies), or stop one.
    case pasteStack
}

/// The panel's keyboard model, kept apart from AppKit so it can be tested.
public enum PanelKeys {
    public struct Context: Equatable, Sendable {
        public var queryIsEmpty: Bool
        /// Tab moved the keyboard to the cards (typing a letter moves it back to search).
        public var cardsFocused: Bool
        public var quickLookOpen: Bool
        /// Part of the search text is selected (⌘C then copies that text, not the clip).
        public var searchHasSelection: Bool

        public init(queryIsEmpty: Bool = true, cardsFocused: Bool = false, quickLookOpen: Bool = false,
                    searchHasSelection: Bool = false) {
            self.queryIsEmpty = queryIsEmpty
            self.cardsFocused = cardsFocused
            self.quickLookOpen = quickLookOpen
            self.searchHasSelection = searchHasSelection
        }
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    /// Key codes for 1–9 on the number row and the keypad.
    static let digitKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    /// `characters` is the key's character ignoring modifiers (layout-aware letters).
    public static func command(keyCode: UInt16, characters: String?, modifiers: Modifiers,
                               context: Context) -> PanelCommand? {
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        if command, let number = digitKeys[keyCode] {
            return option ? .pinToBoard(index: number - 1) : .quickPaste(index: number - 1, plain: shift)
        }
        switch keyCode {
        case 36, 76: return .choose(plain: shift) // Return, Enter
        case 123: return command ? .previousTab : (shift ? .extend(-1) : .move(-1)) // ←
        case 124: return command ? .nextTab : (shift ? .extend(1) : .move(1)) // →
        case 125: return command ? (shift ? .extendToLast : .last) : (shift ? .extend(1) : .move(1)) // ↓
        case 126: return command ? (shift ? .extendToFirst : .first) : (shift ? .extend(-1) : .move(-1)) // ↑
        case 115: return shift ? .extendToFirst : .first // Home
        case 119: return shift ? .extendToLast : .last // End
        case 116: return .pageBack // Page Up
        case 121: return .pageForward // Page Down
        case 48: return .toggleFocus // Tab, ⇧Tab
        case 49 where !command && !modifiers.contains(.control): // Space
            if context.quickLookOpen || context.cardsFocused || context.queryIsEmpty { return .quickLook }
            return nil
        default: break
        }
        guard command else { return nil }
        if keyCode == 51 || keyCode == 117 { return .delete } // ⌘⌫, ⌘⌦
        switch characters?.lowercased() {
        case "c" where shift: return .pasteStack
        case "c": return context.searchHasSelection ? nil : .copy
        case "a" where !shift: return .selectAll
        case "e" where !shift: return .edit
        case "r" where !shift: return .rename
        case "n" where shift: return .newBoard
        case "p": return .togglePin
        case "o": return .open
        case "t": return .togglePause
        case "f": return .focusSearch
        case "z" where !shift: return .undo
        case "w": return .close
        case "y": return .openHistory
        case ",": return .openSettings
        default: return nil
        }
    }
}

/// The strip panel's vertical stack and its corners, from a few inputs. One `inset` runs from
/// the panel's edges to the top bar and to the cards, and every rounded shape inside is
/// concentric with the panel's corner: a shape `p` in from a corner of radius `R` has radius
/// `R − p`.
public struct StripGeometry: Equatable, Sendable {
    public var panelRadius: Double
    public var inset: Double
    public var controlHeight: Double
    public var cardHeight: Double
    /// How far the selection ring reaches outside a card.
    public var ringOutset: Double
    /// Room the card strip keeps above and below the cards (ring and shadow), at least
    /// `ringOutset` and at most `inset`.
    public var overflow: Double
    /// Smallest radius a nested shape gets (when the inset swallows the corner).
    public var minimumRadius: Double = 2

    public init(panelRadius: Double, inset: Double, controlHeight: Double, cardHeight: Double, ringOutset: Double,
                overflow: Double? = nil) {
        self.panelRadius = panelRadius
        self.inset = inset
        self.controlHeight = controlHeight
        self.cardHeight = cardHeight
        self.ringOutset = ringOutset
        self.overflow = min(max(overflow ?? ringOutset, ringOutset), inset)
    }

    /// The card strip's own height: the cards plus room above and below.
    public var stripHeight: Double { cardHeight + overflow * 2 }
    /// Between the top bar and the strip view (the overflow makes up the rest of `inset`).
    public var barToStrip: Double { inset - overflow }
    public var bottomPadding: Double { inset - overflow }
    public var panelHeight: Double { inset + controlHeight + barToStrip + stripHeight + bottomPadding }

    /// Distance from the panel's top edge to a card's top edge, and from a card's bottom edge
    /// to the panel's bottom edge.
    public var cardTop: Double { inset + controlHeight + barToStrip + overflow }
    public var cardBottomGap: Double { panelHeight - cardTop - cardHeight }

    public var cardRadius: Double { nested(padding: inset) }
    public var ringRadius: Double { nested(padding: inset - ringOutset) }

    private func nested(padding: Double) -> Double { max(panelRadius - padding, minimumRadius) }
}
