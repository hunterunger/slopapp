import Foundation

/// A named group of colors. No duplicates (the same 8-bit color, including how far out of
/// sRGB it is); a locked palette refuses every change except unlocking.
public struct Palette: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var note: String
    public var colors: [PickedColor]
    public var isLocked: Bool
    /// Shown in the Color Dock at the screen edge.
    public var inDock: Bool
    public var created: Date
    public var modified: Date

    public init(id: UUID = UUID(), name: String, note: String = "", colors: [PickedColor] = [], isLocked: Bool = false,
                created: Date, modified: Date? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.colors = []
        self.isLocked = false
        self.inDock = false
        self.created = created
        self.modified = modified ?? created
        for color in colors { add(color, at: created) }
        self.isLocked = isLocked
        self.modified = modified ?? created
    }

    enum CodingKeys: String, CodingKey {
        case id, name, note, colors, isLocked, inDock, created, modified
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        colors = try c.decodeIfPresent([PickedColor].self, forKey: .colors) ?? []
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        inDock = try c.decodeIfPresent(Bool.self, forKey: .inDock) ?? false
        created = try c.decode(Date.self, forKey: .created)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
    }

    public func contains(_ color: ColorValue) -> Bool {
        colors.contains { $0.color.identityKey == color.identityKey }
    }

    /// Adds at the end. Returns false (and changes nothing) if locked or already there.
    @discardableResult
    public mutating func add(_ item: PickedColor, at date: Date) -> Bool {
        guard !isLocked, !contains(item.color) else { return false }
        colors.append(item)
        modified = date
        return true
    }

    @discardableResult
    public mutating func add(_ color: ColorValue, at date: Date) -> Bool {
        add(PickedColor(color: color, date: date), at: date)
    }

    @discardableResult
    public mutating func remove(_ ids: Set<PickedColor.ID>, at date: Date) -> Bool {
        guard !isLocked else { return false }
        let before = colors.count
        colors.removeAll { ids.contains($0.id) }
        if colors.count != before { modified = date }
        return colors.count != before
    }

    /// Replaces an entry (edited name, note or color). Refused when locked, or when the new
    /// color is already another entry of this palette.
    @discardableResult
    public mutating func update(_ item: PickedColor, at date: Date) -> Bool {
        guard !isLocked, let index = colors.firstIndex(where: { $0.id == item.id }) else { return false }
        if colors.contains(where: { $0.id != item.id && $0.color.identityKey == item.color.identityKey }) { return false }
        var item = item
        item.modified = date
        colors[index] = item
        modified = date
        return true
    }

    /// Moves the entries at `offsets` to `destination` (an index in the list before the move,
    /// as SwiftUI's `onMove` reports it).
    @discardableResult
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int, at date: Date) -> Bool {
        guard !isLocked, !offsets.isEmpty else { return false }
        let moving = offsets.compactMap { colors.indices.contains($0) ? colors[$0] : nil }
        let insertAt = destination - offsets.filter { $0 < destination }.count
        colors.removeAll { item in moving.contains { $0.id == item.id } }
        colors.insert(contentsOf: moving, at: min(max(insertAt, 0), colors.count))
        modified = date
        return true
    }

    public enum SortOrder: String, CaseIterable, Sendable, Identifiable {
        case hue, lightness, name, dateAdded
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .hue: "Hue"
            case .lightness: "Lightness"
            case .name: "Name"
            case .dateAdded: "Date Added"
            }
        }
    }

    /// Sorts once; dragging afterwards still works.
    @discardableResult
    public mutating func sort(by order: SortOrder, at date: Date) -> Bool {
        guard !isLocked else { return false }
        switch order {
        case .hue:
            // Grays last, by lightness; colors by OKLCH hue.
            colors.sort { a, b in
                let la = ColorMath.oklch(fromSRGB: a.color.sRGB.clamped), lb = ColorMath.oklch(fromSRGB: b.color.sRGB.clamped)
                let grayA = la.c < 0.025, grayB = lb.c < 0.025
                if grayA != grayB { return !grayA }
                if grayA { return la.l > lb.l }
                return la.h == lb.h ? la.l > lb.l : la.h < lb.h
            }
        case .lightness:
            colors.sort { ColorMath.oklab(fromSRGB: $0.color.sRGB).l > ColorMath.oklab(fromSRGB: $1.color.sRGB).l }
        case .name:
            colors.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .dateAdded:
            colors.sort { $0.date < $1.date }
        }
        modified = date
        return true
    }

    /// The copy made by Duplicate: new ids, unlocked, "Name copy".
    public func duplicate(at date: Date) -> Palette {
        Palette(name: name + " copy", note: note,
                colors: colors.map { PickedColor(color: $0.color, date: $0.date, name: $0.name, note: $0.note) },
                created: date)
    }

    /// Appends another palette's colors that aren't here yet. Returns how many were added.
    @discardableResult
    public mutating func merge(_ other: Palette, at date: Date) -> Int {
        var added = 0
        for item in other.colors where add(PickedColor(color: item.color, date: item.date, name: item.name, note: item.note), at: date) {
            added += 1
        }
        return added
    }
}
