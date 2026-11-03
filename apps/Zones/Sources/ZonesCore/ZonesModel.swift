import Foundation
import Observation

/// Everything the panel and menu bar show, and every action on it. The views are thin.
@MainActor
@Observable
public final class ZonesModel {
    // MARK: State

    public private(set) var places: [Place]
    public var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            if preferences.hourCycle != oldValue.hourCycle { rebuildFormatter() }
            storage.savePreferences(preferences)
        }
    }
    /// The real current time, refreshed on minute boundaries and system clock changes.
    public private(set) var now: Date
    public private(set) var localTimeZone: TimeZone
    /// The time being looked at when it isn't now (scrubbed, typed or stepped).
    public private(set) var scrubbed: Date?
    /// The highlighted row (keyboard ↑↓, click).
    public var selection: UUID?
    /// One line shown under the list: a daylight saving note for a typed time, etc.
    public private(set) var notice: String?
    /// What ⌘Z undoes (a remove or a sort), offered until the panel closes.
    public private(set) var pendingUndo: UndoAction?

    public enum UndoAction: Equatable {
        case remove(Place, index: Int)
        case sort(previous: [Place])

        /// "Undo Remove London", "Undo Sort"
        public var menuTitle: String {
            switch self {
            case .remove(let place, _): "Undo Remove \(place.label)"
            case .sort: "Undo Sort"
            }
        }

        /// "Removed London", "Sorted by time difference"
        public var message: String {
            switch self {
            case .remove(let place, _): "Removed \(place.label)"
            case .sort: "Sorted by time difference"
            }
        }
    }

    /// The last removed place, if the pending undo is a remove.
    public var lastRemoved: (place: Place, index: Int)? {
        if case .remove(let place, let index) = pendingUndo { return (place, index) }
        return nil
    }
    /// A place just added, highlighted briefly.
    public private(set) var recentlyAdded: UUID?
    public private(set) var formatter: TimeFormatter

    private let storage: ZonesStorage
    private let clock: SystemClock
    private let locale: Locale

    public init(storage: ZonesStorage, clock: SystemClock, locale: Locale = .autoupdatingCurrent) {
        self.storage = storage
        self.clock = clock
        self.locale = locale
        let preferences = storage.loadPreferences() ?? Preferences()
        self.preferences = preferences
        // First run: local time (shown by default) plus UTC.
        self.places = storage.loadPlaces() ?? [.utc()]
        self.now = clock.now
        self.localTimeZone = clock.timeZone
        self.formatter = TimeFormatter(locale: locale, hourCycle: preferences.hourCycle)
    }

    // MARK: Derived

    /// The instant every row shows.
    public var instant: Date { scrubbed ?? now }
    public var isScrubbed: Bool { scrubbed != nil }

    public var rows: [ClockRow] {
        ClockRows.make(places: places, local: localTimeZone, showLocal: preferences.showLocalTime,
                       at: instant, formatter: formatter)
    }

    /// "Now" or "+3 h 15 min".
    public var deltaText: String {
        guard let scrubbed else { return "Now" }
        return Scrubbing.deltaText(from: now, to: scrubbed)
    }

    /// "Tue, Nov 3" in local time for the shown instant.
    public var dateText: String { formatter.shortDate(instant, in: localTimeZone) }

    /// "Now, Tuesday, November 3" / "3 hours 15 minutes later, Wednesday, November 4".
    public var timeAccessibilityValue: String {
        let date = formatter.longDate(instant, in: localTimeZone) + ", " + formatter.time(instant, in: localTimeZone)
        guard let scrubbed else { return "Now, " + date }
        let seconds = Int((scrubbed.timeIntervalSince(now) / 60).rounded()) * 60
        if seconds == 0 { return "Now, " + date }
        return Scrubbing.spokenDelta(seconds) + ", " + date
    }

    /// Show the "add the places you work with" hint while the list is still the first-run seed.
    public var showsAddHint: Bool {
        places.count <= 1 && places.allSatisfy { $0.kind == .utc }
    }

    /// Nothing at all to show (local time hidden and no places).
    public var isEmpty: Bool { rows.isEmpty }

    /// The place the menu bar shows, when it shows a time.
    public var menuBarPlace: Place? {
        guard preferences.menuBarDisplay.showsTime else { return nil }
        if let id = preferences.menuBarPlaceID, let place = places.first(where: { $0.id == id }) {
            return place
        }
        // Local time when chosen, or when the chosen place was removed.
        return localPlace
    }

    /// Local time as a place (for the menu bar and copying).
    public var localPlace: Place {
        Place(id: ClockRow.localID, kind: .zone, name: ClockRows.localName(for: localTimeZone),
              detail: "Local time", timeZoneID: localTimeZone.identifier)
    }

    /// Menu bar text ("LON 5:20 PM"), always for the real current time.
    public var menuBarTitle: String? {
        menuBarPlace.map { MenuBarClock.title(for: $0, at: now, formatter: formatter) }
    }

    /// Text for Copy Times: every row at the shown instant.
    public var timesText: String {
        TimesText.make(copyEntries, at: instant, format: preferences.copyFormat, formatter: formatter)
    }

    public func timeText(forRow id: UUID) -> String? {
        guard let entry = entry(forRow: id) else { return nil }
        return TimesText.make([entry], at: instant, format: preferences.copyFormat == .iso8601 ? .iso8601 : .list,
                              formatter: formatter)
    }

    private var copyEntries: [TimesText.Entry] {
        rows.map { TimesText.Entry(label: $0.label, zone: $0.timeZone) }
    }

    private func entry(forRow id: UUID) -> TimesText.Entry? {
        rows.first { $0.id == id }.map { TimesText.Entry(label: $0.label, zone: $0.timeZone) }
    }

    // MARK: Clock

    /// Re-reads the clock and time zone (minute tick, wake, time zone or clock change).
    public func refresh() {
        now = clock.now
        let zone = clock.timeZone
        if zone != localTimeZone { localTimeZone = zone }
    }

    /// Re-creates formatters after a locale change.
    public func localeChanged() {
        rebuildFormatter()
    }

    private func rebuildFormatter() {
        formatter = TimeFormatter(locale: locale, hourCycle: preferences.hourCycle)
    }

    // MARK: Scrubbing

    public enum Step: Sendable {
        case quarterHour, hour, day
    }

    public func step(_ step: Step, by count: Int) {
        notice = nil
        let base = instant
        let target: Date
        switch step {
        case .quarterHour: target = Scrubbing.step(from: base, marks: count, of: Scrubbing.quarterHour, local: localTimeZone)
        case .hour: target = Scrubbing.step(from: base, marks: count, of: Scrubbing.hour, local: localTimeZone)
        case .day: target = Scrubbing.step(from: base, days: count, local: localTimeZone)
        }
        setInstant(target)
    }

    /// Sets the shown time. Within a minute of now counts as now.
    public func setInstant(_ date: Date) {
        if abs(date.timeIntervalSince(now)) < 60 {
            scrubbed = nil
        } else {
            scrubbed = date
        }
    }

    /// Live drag: `points` of horizontal travel since the drag began at `start`.
    public func drag(from start: Date, points: Double) {
        notice = nil
        setInstant(Scrubbing.drag(from: start, points: points, local: localTimeZone))
    }

    public func resetToNow() {
        scrubbed = nil
        notice = nil
    }

    /// Esc: first leaves a scrubbed time, then asks to close. Returns true if handled
    /// (the panel should stay open).
    public func escape() -> Bool {
        if notice != nil, scrubbed == nil { notice = nil; return true }
        if scrubbed != nil { resetToNow(); return true }
        return false
    }

    /// The panel closed: next time it opens at "now" with nothing pending.
    public func panelDidClose() {
        scrubbed = nil
        notice = nil
        selection = nil
        pendingUndo = nil
        recentlyAdded = nil
    }

    // MARK: Typed times

    public enum TypedTimeOutcome: Equatable {
        case applied
        case invalid
    }

    /// "3pm" typed on a row: show the moment it's 3 pm there, on the day that row shows.
    @discardableResult
    public func setTime(_ text: String, forRow id: UUID) -> TypedTimeOutcome {
        guard let typed = TypedTime(parsing: text), let row = rows.first(where: { $0.id == id }) else {
            return .invalid
        }
        let resolution = typed.resolve(in: row.timeZone, onDayOf: instant)
        setInstant(resolution.instant)
        if resolution.skippedGap {
            let asked = formatter.time(TypedTime.referenceDate(typed), in: TimeZone(secondsFromGMT: 0)!)
            notice = "\(asked) doesn't exist in \(row.label) that day (clocks go forward). Showing \(formatter.time(resolution.instant, in: row.timeZone))."
        } else if resolution.wasAmbiguous {
            notice = "\(formatter.time(resolution.instant, in: row.timeZone)) happens twice in \(row.label) that day. Showing the first."
        } else {
            notice = nil
        }
        return .applied
    }

    // MARK: Editing the list

    public func add(_ place: Place) {
        var place = place
        place.id = UUID()
        places.append(place)
        recentlyAdded = place.id
        selection = place.id
        save()
    }

    public func clearRecentlyAdded() { recentlyAdded = nil }

    /// Removes a place; `undo()` puts it back. The local row can't be removed (hide
    /// it with `preferences.showLocalTime`).
    public func remove(_ id: UUID) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        let removed = places.remove(at: index)
        pendingUndo = .remove(removed, index: index)
        if selection == id {
            let ids = rows.map(\.id)
            selection = ids.isEmpty ? nil : ids[min(index + (preferences.showLocalTime ? 1 : 0), ids.count - 1)]
        }
        if preferences.menuBarPlaceID == id { preferences.menuBarPlaceID = nil }
        save()
    }

    public var canUndo: Bool { pendingUndo != nil }

    public func undo() {
        switch pendingUndo {
        case .remove(let place, let index):
            places.insert(place, at: min(index, places.count))
            selection = place.id
        case .sort(let previous):
            places = previous
        case nil:
            return
        }
        pendingUndo = nil
        save()
    }

    /// Moves a place up (−1) or down (+1).
    public func move(_ id: UUID, by delta: Int) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard places.indices.contains(target) else { return }
        places.swapAt(index, target)
        save()
    }

    public func canMove(_ id: UUID, by delta: Int) -> Bool {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return false }
        return places.indices.contains(index + delta)
    }

    /// For List.onMove in Settings.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { places[$0] }
        var remaining = places.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        places = remaining
        save()
    }

    /// Renames a place. An empty name goes back to the original.
    public func rename(_ id: UUID, to name: String) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        places[index].customName = trimmed.isEmpty || trimmed == places[index].name ? nil : trimmed
        save()
    }

    /// Sorts places by their current offset from UTC (west to east).
    public func sortByTimeDifference() {
        let at = instant
        let previous = places
        places.sort { $0.timeZone.secondsFromGMT(for: at) < $1.timeZone.secondsFromGMT(for: at) }
        if places != previous { pendingUndo = .sort(previous: previous) }
        save()
    }

    public func showInMenuBar(_ id: UUID) {
        preferences.menuBarPlaceID = id
        if !preferences.menuBarDisplay.showsTime { preferences.menuBarDisplay = .iconAndTime }
    }

    public func isInMenuBar(_ id: UUID) -> Bool {
        guard preferences.menuBarDisplay.showsTime else { return false }
        return menuBarPlace?.id == id
    }

    /// The listed place that is the same clock, if any.
    public func existingID(for place: Place) -> UUID? {
        places.first { $0.isSameClock(as: place) }?.id
    }

    /// Selects and briefly highlights a listed place (adding one that's already there).
    public func highlight(_ id: UUID) {
        selection = id
        recentlyAdded = id
    }

    /// Is this place (or the same clock) already listed?
    public func contains(_ place: Place) -> Bool {
        places.contains { $0.isSameClock(as: place) }
    }

    // MARK: Selection

    public func moveSelection(by delta: Int) {
        let ids = rows.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = delta >= 0 ? ids.first : ids.last
            return
        }
        selection = ids[max(0, min(ids.count - 1, index + delta))]
    }

    private func save() {
        storage.savePlaces(places)
    }
}

extension TypedTime {
    /// A date whose UTC wall time is this time of day, for formatting it in the user's style.
    static func referenceDate(_ typed: TypedTime) -> Date {
        Date(timeIntervalSince1970: TimeInterval(typed.hour * 3600 + typed.minute * 60))
    }
}
