import Foundation
import Testing
@testable import ZonesCore

@MainActor
@Suite struct ModelTests {
    @Test func firstRunIsLocalPlusUTC() {
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago")
        #expect(model.rows.map(\.label) == ["Chicago", "UTC"])
        #expect(model.rows[0].isLocal)
        #expect(model.showsAddHint)
        #expect(model.preferences.menuBarDisplay == .iconOnly)
        #expect(model.menuBarTitle == nil)
    }

    @Test func placesPersist() {
        let (model, storage, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago")
        model.add(T.city("London", "Europe/London"))
        #expect(storage.places?.map(\.name) == ["UTC", "London"])
        #expect(!model.showsAddHint)
        let reloaded = ZonesModel(storage: storage, clock: FixedClock(now: .now, timeZone: T.zone("UTC")), locale: T.enUS)
        #expect(reloaded.places.map(\.name) == ["UTC", "London"])
    }

    @Test func removeAndUndo() {
        let places = [T.city("London", "Europe/London"), T.city("Tokyo", "Asia/Tokyo"), Place.utc()]
        let (model, storage, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: places)
        let tokyo = places[1].id
        model.selection = tokyo
        model.remove(tokyo)
        #expect(model.places.map(\.name) == ["London", "UTC"])
        #expect(model.selection == places[2].id)  // selection moves to the next row
        #expect(model.canUndo)
        model.undo()
        #expect(model.places.map(\.name) == ["London", "Tokyo", "UTC"])
        #expect(storage.places?.count == 3)
        #expect(!model.canUndo)
    }

    @Test func moveAndSort() {
        let places = [T.city("Tokyo", "Asia/Tokyo"), T.city("London", "Europe/London"), T.city("LA", "America/Los_Angeles")]
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: places)
        model.move(places[0].id, by: 1)
        #expect(model.places.map(\.name) == ["London", "Tokyo", "LA"])
        #expect(!model.canMove(places[2].id, by: 1))
        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(model.places.map(\.name) == ["LA", "London", "Tokyo"])
        model.sortByTimeDifference()
        #expect(model.places.map(\.name) == ["LA", "London", "Tokyo"])
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(model.places.map(\.name) == ["London", "Tokyo", "LA"])
        model.sortByTimeDifference()
        #expect(model.places.map(\.name) == ["LA", "London", "Tokyo"])
    }

    @Test func sortCanBeUndone() {
        let places = [T.city("Tokyo", "Asia/Tokyo"), T.city("London", "Europe/London"), T.city("LA", "America/Los_Angeles")]
        let (model, storage, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: places)
        model.sortByTimeDifference()
        #expect(model.places.map(\.name) == ["LA", "London", "Tokyo"])
        #expect(model.pendingUndo?.menuTitle == "Undo Sort")
        model.undo()
        #expect(model.places.map(\.name) == ["Tokyo", "London", "LA"])
        #expect(storage.places?.map(\.name) == ["Tokyo", "London", "LA"])
        // Sorting an already sorted list offers nothing to undo.
        model.sortByTimeDifference()
        model.undo()
        #expect(model.places.map(\.name) == ["Tokyo", "London", "LA"])
        model.sortByTimeDifference()
        model.panelDidClose()
        model.sortByTimeDifference()
        #expect(!model.canUndo)
    }

    @Test func addingAnExistingPlaceFindsIt() {
        let london = T.city("London", "Europe/London")
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: [london])
        var again = T.city("London", "Europe/London")
        again.id = UUID()
        #expect(model.existingID(for: again) == london.id)
        model.highlight(london.id)
        #expect(model.selection == london.id)
        #expect(model.recentlyAdded == london.id)
        #expect(model.existingID(for: T.city("Paris", "Europe/Paris")) == nil)
    }

    @Test func renameAndRevert() {
        let place = T.city("Melbourne", "Australia/Melbourne")
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: [place])
        model.rename(place.id, to: "  Mum ")
        #expect(model.rows[1].label == "Mum")
        model.rename(place.id, to: "")
        #expect(model.rows[1].label == "Melbourne")
    }

    @Test func arrowStepsAndEscape() {
        let (model, _, _) = T.model(now: "2026-11-03T15:07:00Z", local: "America/New_York")
        #expect(model.deltaText == "Now")
        model.step(.quarterHour, by: 1)
        #expect(model.isScrubbed)
        #expect(model.rows[0].time == "10:15 AM")
        #expect(model.deltaText == "+8 min")
        model.step(.hour, by: 2)
        #expect(model.rows[0].time == "12:00 PM")
        model.step(.day, by: 1)
        #expect(model.dateText == "Wed, Nov 4")
        // First Esc returns to now and keeps the panel open; the second closes.
        #expect(model.escape())
        #expect(!model.isScrubbed)
        #expect(!model.escape())
    }

    @Test func steppingBackToNowClearsTheScrub() {
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/New_York")
        model.step(.quarterHour, by: 1)
        model.step(.quarterHour, by: -1)
        #expect(!model.isScrubbed)
    }

    @Test func dragUpdatesEveryRow() {
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/New_York",
                                    places: [T.city("London", "Europe/London")])
        model.drag(from: model.now, points: 40)  // +2 h
        #expect(model.rows.map(\.time) == ["12:00 PM", "5:00 PM"])
        #expect(model.deltaText == "+2 h")
    }

    @Test func closingThePanelResetsToNow() {
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/New_York")
        model.step(.hour, by: 3)
        model.selection = ClockRow.localID
        model.panelDidClose()
        #expect(!model.isScrubbed)
        #expect(model.selection == nil)
    }

    @Test func typedTimeOnARowMovesEveryone() {
        let london = T.city("London", "Europe/London")
        let tokyo = T.city("Tokyo", "Asia/Tokyo")
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: [london, tokyo])
        #expect(model.setTime("3pm", forRow: london.id) == .applied)
        #expect(model.rows.map(\.time) == ["9:00 AM", "3:00 PM", "12:00 AM"])
        #expect(model.rows[2].subtitle == "Tomorrow · +15 h")
        #expect(model.setTime("soon", forRow: london.id) == .invalid)
        #expect(model.rows[1].time == "3:00 PM")  // unchanged
    }

    @Test func typedTimeInAGapExplainsItself() {
        let (model, _, _) = T.model(now: "2026-03-08T15:00:00Z", local: "America/New_York")
        model.setTime("2:30am", forRow: ClockRow.localID)
        #expect(model.rows[0].time == "3:00 AM")
        #expect(model.notice?.contains("doesn't exist") == true)
        let (fall, _, _) = T.model(now: "2026-11-01T15:00:00Z", local: "America/New_York")
        fall.setTime("1:30am", forRow: ClockRow.localID)
        #expect(fall.notice?.contains("happens twice") == true)
    }

    @Test func copyTimesUsesTheShownInstant() {
        let (model, _, _) = T.model(now: "2026-11-03T17:00:00Z", local: "America/Chicago",
                                    places: [T.city("Tokyo", "Asia/Tokyo")])
        #expect(model.timesText == "Chicago: Tue, Nov 3, 11:00 AM CST\nTokyo: Wed, Nov 4, 2:00 AM JST")
        model.step(.hour, by: 1)
        #expect(model.timesText.contains("12:00 PM"))
        model.preferences.copyFormat = .singleLine
        #expect(model.timesText == "12:00 PM Chicago · 3:00 AM Tokyo (Wed)")
    }

    @Test func menuBarClock() {
        let london = T.city("London", "Europe/London")
        let (model, storage, _) = T.model(now: "2026-11-03T17:20:00Z", local: "America/Chicago", places: [london],
                                          preferences: { var p = Preferences(); p.hourCycle = .twentyFour; return p }())
        #expect(model.menuBarTitle == nil)
        model.showInMenuBar(london.id)
        #expect(model.preferences.menuBarDisplay == .iconAndTime)
        #expect(model.menuBarTitle == "LON 17:20")
        #expect(storage.preferences?.menuBarPlaceID == london.id)
        // Scrubbing doesn't change the menu bar: it always shows now.
        model.step(.hour, by: 3)
        #expect(model.menuBarTitle == "LON 17:20")
        // Removing the place falls back to local time.
        model.remove(london.id)
        #expect(model.menuBarTitle == "CHI 11:20")
    }

    @Test func timeZoneChangeFollowsTheMac() {
        let (model, _, clock) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago")
        #expect(model.rows[0].label == "Chicago")
        clock.timeZone = T.zone("Asia/Tokyo")
        clock.now = T.date("2026-11-03T15:01:00Z")
        model.refresh()
        #expect(model.rows[0].label == "Tokyo")
        #expect(model.rows[0].time == "12:01 AM")
    }

    @Test func hiddenLocalTime() {
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago")
        model.preferences.showLocalTime = false
        #expect(model.rows.map(\.label) == ["UTC"])
        model.remove(model.places[0].id)
        #expect(model.isEmpty)
    }

    @Test func selectionWithArrows() {
        let places = [T.city("London", "Europe/London")]
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: places)
        model.moveSelection(by: 1)
        #expect(model.selection == ClockRow.localID)
        model.moveSelection(by: 1)
        #expect(model.selection == places[0].id)
        model.moveSelection(by: 1)
        #expect(model.selection == places[0].id)
        model.moveSelection(by: -1)
        #expect(model.selection == ClockRow.localID)
    }

    @Test func addingTheSameClockIsDetected() {
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago")
        #expect(model.contains(.utc()))
        #expect(!model.contains(T.city("London", "Europe/London")))
    }
}
