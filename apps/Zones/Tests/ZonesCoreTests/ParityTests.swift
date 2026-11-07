import Foundation
import Testing
@testable import ZonesCore

@Suite("Working hours")
struct WorkingHoursTests {
    @Test func standardHoursOnWorkdays() {
        let hours = WorkingHours.standard
        // Tuesday 2026-11-03 in London
        let london = T.zone("Europe/London")
        #expect(hours.contains(T.date("2026-11-03T09:00:00Z"), in: london))
        #expect(hours.contains(T.date("2026-11-03T16:59:00Z"), in: london))
        #expect(!hours.contains(T.date("2026-11-03T17:00:00Z"), in: london))
        #expect(!hours.contains(T.date("2026-11-03T08:59:00Z"), in: london))
        // Saturday
        #expect(!hours.contains(T.date("2026-11-07T12:00:00Z"), in: london))
    }

    @Test func overnightShiftBelongsToItsStartDay() {
        // 22:00–06:00, Monday to Friday nights
        let hours = WorkingHours(start: 22 * 60, end: 6 * 60, days: [2, 3, 4, 5, 6])
        #expect(hours.isOvernight)
        #expect(hours.contains(minute: 23 * 60, weekday: 6))   // Friday 23:00
        #expect(hours.contains(minute: 3 * 60, weekday: 7))    // Saturday 03:00 (Friday's shift)
        #expect(!hours.contains(minute: 23 * 60, weekday: 7))  // Saturday 23:00
        #expect(!hours.contains(minute: 3 * 60, weekday: 2))   // Monday 03:00 (Sunday night off)
        #expect(!hours.contains(minute: 12 * 60, weekday: 3))
    }

    @Test func activityBands() {
        let hours = WorkingHours.standard
        #expect(Activity.at(minute: 10 * 60, weekday: 3, hours: hours) == .working)
        #expect(Activity.at(minute: 18 * 60, weekday: 3, hours: hours) == .afterHours)
        #expect(Activity.at(minute: 7 * 60, weekday: 3, hours: hours) == .afterHours)
        #expect(Activity.at(minute: 6 * 60 + 59, weekday: 3, hours: hours) == .night)
        #expect(Activity.at(minute: 22 * 60, weekday: 3, hours: hours) == .night)
        #expect(Activity.at(minute: 12 * 60, weekday: 1, hours: hours) == .dayOff)
        // Working hours win over night for night workers.
        let nights = WorkingHours(start: 22 * 60, end: 6 * 60, days: [2, 3, 4, 5, 6])
        #expect(Activity.at(minute: 23 * 60, weekday: 3, hours: nights) == .working)
    }

    @Test func middleEastWorkweek() {
        // Sunday–Thursday
        let hours = WorkingHours(start: 9 * 60, end: 17 * 60, days: [1, 2, 3, 4, 5])
        let riyadhLikeZone = T.zone("Asia/Jerusalem")
        // Sunday 2026-11-08 10:00 local (UTC+2) is a workday; Friday isn't.
        #expect(Activity.at(T.date("2026-11-08T08:00:00Z"), in: riyadhLikeZone, hours: hours) == .working)
        #expect(Activity.at(T.date("2026-11-06T08:00:00Z"), in: riyadhLikeZone, hours: hours) == .dayOff)
        #expect(hours.daysText(locale: T.enUS) == "Sun–Thu")
    }

    @Test func textForSettings() {
        let formatter = T.formatter()
        #expect(WorkingHours.standard.summary(formatter: formatter) == "9:00 AM – 5:00 PM, Mon–Fri")
        #expect(WorkingHours(start: 0, end: 1440, days: Set(1...7)).daysText(locale: T.enUS) == "Every day")
        #expect(WorkingHours(start: 540, end: 1020, days: [7, 1]).daysText(locale: T.enUS) == "Sat, Sun")
        #expect(WorkingHours(start: 540, end: 1020, days: [6, 7, 1]).daysText(locale: T.enUS) == "Fri–Sun")
        #expect(WorkingHours(start: 540, end: 1020, days: [2, 4, 6]).daysText(locale: T.enUS) == "Mon, Wed, Fri")
        #expect(WorkingHours(start: 540, end: 1020, days: []).daysText(locale: T.enUS) == "No workdays")
        #expect(WorkingHours(start: 22 * 60, end: 6 * 60, days: [2]).spanText(formatter: T.formatter(.twentyFour)) == "22:00 – 06:00")
    }

    @Test func wallClockWeekdays() {
        // 1970-01-01 was a Thursday; 2026-11-03 is a Tuesday.
        #expect(WallClock(Date(timeIntervalSince1970: 0), T.zone("UTC")).weekday == 5)
        #expect(WallClock(T.date("2026-11-03T12:00:00Z"), T.zone("UTC")).weekday == 3)
        // Before 1970 still works.
        #expect(WallClock(T.date("1969-12-31T12:00:00Z"), T.zone("UTC")).weekday == 4)
        // Kiritimati is already Wednesday.
        #expect(WallClock(T.date("2026-11-03T12:00:00Z"), T.zone("Pacific/Kiritimati")).weekday == 4)
    }
}

@Suite("Rows show activity")
@MainActor
struct ActivityRowTests {
    @Test func rowsUseEachPlacesHours() {
        var tokyo = T.city("Tokyo", "Asia/Tokyo")
        tokyo.workingHours = WorkingHours(start: 7 * 60, end: 15 * 60, days: [2, 3, 4, 5, 6])
        let london = T.city("London", "Europe/London")
        // Tue 08:00 Chicago = 14:00 London = 23:00 Tokyo
        let (model, storage, _) = T.model(now: "2026-11-03T14:00:00Z", local: "America/Chicago",
                                          places: [london, tokyo])
        #expect(model.rows.map(\.activity) == [.afterHours, .working, .night])
        // 06:30 Wednesday in Tokyo... move to Tokyo's 08:00: working by its own hours.
        model.setTime("8am", forRow: tokyo.id)
        #expect(model.rows[2].activity == .working)
        #expect(model.rows[1].activity == .night)
        // Same as default: stored as "no override".
        model.setWorkingHours(.standard, for: london.id)
        #expect(storage.places?[0].workingHours == nil)
        model.setWorkingHours(nil, for: tokyo.id)
        #expect(model.workingHours(for: tokyo.id) == .standard)
    }

    @Test func defaultHoursApplyToLocal() {
        var preferences = Preferences()
        preferences.defaultWorkingHours = WorkingHours(start: 6 * 60, end: 14 * 60, days: [2, 3, 4, 5, 6])
        let (model, _, _) = T.model(now: "2026-11-03T13:00:00Z", local: "America/Chicago", preferences: preferences)
        // 07:00 in Chicago
        #expect(model.localRow.activity == .working)
        #expect(model.rows[0].accessibilityLabel.contains("working hours"))
    }

    @Test func timeParts() {
        let formatter = T.formatter()
        let parts = formatter.timeParts(T.date("2026-11-03T17:20:00Z"), in: T.zone("UTC"))
        #expect(parts == TimeParts(main: "5:20", period: "PM", periodFirst: false))
        let twentyFour = T.formatter(.twentyFour).timeParts(T.date("2026-11-03T17:20:00Z"), in: T.zone("UTC"))
        #expect(twentyFour == TimeParts(main: "17:20", period: nil, periodFirst: false))
        let japanese = TimeFormatter(locale: Locale(identifier: "ja_JP"), hourCycle: .twelve)
            .timeParts(T.date("2026-11-03T17:20:00Z"), in: T.zone("UTC"))
        #expect(japanese.period != nil)
        #expect(japanese.periodFirst)
        #expect(japanese.main == "5:20")
    }
}

@Suite("Menu bar clocks")
@MainActor
struct MenuBarClocksTests {
    @Test func severalClocksInOrder() {
        let london = T.city("London", "Europe/London")
        let tokyo = T.city("Tokyo", "Asia/Tokyo")
        var preferences = Preferences()
        preferences.hourCycle = .twentyFour
        let (model, storage, _) = T.model(now: "2026-11-03T17:20:00Z", local: "America/Chicago",
                                          places: [london, tokyo], preferences: preferences)
        model.showInMenuBar(tokyo.id)
        model.showInMenuBar(london.id)
        #expect(model.menuBarTitle == "TOK 02:20   LON 17:20")
        #expect(storage.preferences?.menuBarPlaceIDs == [tokyo.id, london.id])
        #expect(model.isInMenuBar(london.id))
        #expect(!model.isInMenuBar(ClockRow.localID))
        // Adding twice doesn't duplicate.
        model.showInMenuBar(london.id)
        #expect(model.menuBarPlaces.count == 2)
        model.removeFromMenuBar(tokyo.id)
        #expect(model.menuBarTitle == "LON 17:20")
        model.removeFromMenuBar(london.id)
        #expect(model.preferences.menuBarDisplay == .iconOnly)
        #expect(model.menuBarTitle == nil)
    }

    @Test func implicitLocalClockStaysWhenAddingAnother() {
        let london = T.city("London", "Europe/London")
        var preferences = Preferences()
        preferences.hourCycle = .twentyFour
        preferences.menuBarDisplay = .iconAndTime
        let (model, _, _) = T.model(now: "2026-11-03T17:20:00Z", local: "America/Chicago",
                                    places: [london], preferences: preferences)
        #expect(model.menuBarTitle == "CHI 11:20")
        model.showInMenuBar(london.id)
        #expect(model.menuBarTitle == "CHI 11:20   LON 17:20")
        #expect(model.menuBarWidestTitles == ["CHI 10:00   LON 10:00", "CHI 22:00   LON 22:00"])
    }

    @Test func oldSingleClockSettingIsMigrated() throws {
        let id = UUID()
        let json = #"{"showLocalTime":true,"menuBarDisplay":"iconAndTime","menuBarPlaceID":"\#(id.uuidString)"}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.menuBarPlaceIDs == [id])
        #expect(preferences.defaultWorkingHours == .standard)
        #expect(preferences.rowStyle == .standard)
        // Round trip keeps everything.
        let again = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(again == preferences)
    }

    @Test func oldPlacesDecodeWithoutHours() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","kind":"city","name":"London","detail":"","timeZoneID":"Europe/London"}]"#
        let places = try JSONDecoder().decode([Place].self, from: Data(json.utf8))
        #expect(places[0].workingHours == nil)
    }
}

@Suite("Planner")
@MainActor
struct PlannerTests {
    @Test func hoursOfOrdinaryAndDaylightSavingDays() {
        let chicago = T.zone("America/Chicago")
        #expect(DayPlan.hours(ofDayContaining: T.date("2026-11-03T15:00:00Z"), in: chicago).count == 24)
        // 2026-11-01: clocks go back in the US: 25 hours.
        let fallBack = DayPlan.hours(ofDayContaining: T.date("2026-11-01T15:00:00Z"), in: chicago)
        #expect(fallBack.count == 25)
        #expect(fallBack.first == T.date("2026-11-01T05:00:00Z"))
        // 2026-03-08: forward: 23 hours.
        #expect(DayPlan.hours(ofDayContaining: T.date("2026-03-08T15:00:00Z"), in: chicago).count == 23)
    }

    @Test func overlapOfWorkingHours() {
        let chicago = T.zone("America/Chicago")
        let hours = DayPlan.hours(ofDayContaining: T.date("2026-11-03T15:00:00Z"), in: chicago)
        let places: [(zone: TimeZone, hours: WorkingHours)] = [
            (chicago, .standard), (T.zone("Europe/London"), .standard),
        ]
        let flags = DayPlan.overlap(hours: hours, places: places)
        // London is +6 h: 9–11 Chicago is 15–17 London.
        #expect(DayPlan.runs(flags) == [9..<11])
        #expect(DayPlan.overlapText(hours: hours, flags: flags, local: chicago, formatter: T.formatter())
                == "9:00 AM – 11:00 AM")
        // Add India (+11:30): 9:00 Chicago is 20:30 there. No overlap.
        let withIndia = places + [(T.zone("Asia/Kolkata"), .standard)]
        #expect(DayPlan.runs(DayPlan.overlap(hours: hours, places: withIndia)).isEmpty)
        #expect(DayPlan.overlapText(hours: hours, flags: DayPlan.overlap(hours: hours, places: withIndia),
                                    local: chicago, formatter: T.formatter()) == nil)
    }

    @Test func halfHourZonesOnlyCountFullHours() {
        // Local Kolkata, place London (−5:30 in winter): Kolkata 14:30–22:30 = London 9–17.
        let kolkata = T.zone("Asia/Kolkata")
        let hours = DayPlan.hours(ofDayContaining: T.date("2026-11-03T08:00:00Z"), in: kolkata)
        let flags = DayPlan.overlap(hours: hours, places: [(kolkata, .standard), (T.zone("Europe/London"), .standard)])
        // Kolkata works 9–17; London from 14:30: only 15:00–17:00 Kolkata is fully shared.
        #expect(DayPlan.runs(flags) == [15..<17])
    }

    @Test func runsAndIndex() {
        #expect(DayPlan.runs([false, true, true, false, true]) == [1..<3, 4..<5])
        #expect(DayPlan.runs([]) == [])
        let hours = DayPlan.hours(ofDayContaining: T.date("2026-11-03T15:00:00Z"), in: T.zone("UTC"))
        #expect(DayPlan.index(of: T.date("2026-11-03T15:30:00Z"), in: hours) == 15)
        #expect(DayPlan.index(of: T.date("2026-11-04T00:00:00Z"), in: hours) == nil)
    }

    @Test func dayStripBands() {
        // London, Tue 2026-11-03 00:00 to 24:00 UTC.
        let strip = DayStrip.make(zone: T.zone("Europe/London"), hours: .standard,
                                  from: T.date("2026-11-03T00:00:00Z"), to: T.date("2026-11-04T00:00:00Z"))
        #expect(strip.segments.map(\.activity) == [.night, .afterHours, .working, .afterHours, .night])
        #expect(abs(strip.segments[2].start - 9.0 / 24) < 0.0001)
        #expect(abs(strip.segments[2].end - 17.0 / 24) < 0.0001)
        #expect(strip.segments.last?.end == 1)
        #expect(strip.midnights.isEmpty)
        // Centred on noon UTC: Tokyo passes midnight at 15:00 UTC.
        let tokyo = DayStrip.make(zone: T.zone("Asia/Tokyo"), hours: .standard,
                                  from: T.date("2026-11-03T00:00:00Z"), to: T.date("2026-11-04T00:00:00Z"))
        #expect(tokyo.midnights.count == 1)
        #expect(abs(tokyo.midnights[0] - 15.0 / 24) < 0.0001)
    }

    @Test func goToDayKeepsWallTime() {
        let (model, _, _) = T.model(now: "2026-10-28T14:00:00Z", local: "Europe/Berlin")  // 15:00 CET... CEST until 25 Oct
        let wall = T.wall(model.instant, "Europe/Berlin")
        // Jump past the Berlin and US changes.
        model.goToDay(T.date("2026-11-10T12:00:00Z"))
        #expect(T.wall(model.instant, "Europe/Berlin") == wall)
        #expect(model.dateText == "Tue, Nov 10")
        model.goToDay(T.date("2026-10-20T12:00:00Z"))
        #expect(T.wall(model.instant, "Europe/Berlin") == wall)
        #expect(model.dateText == "Tue, Oct 20")
    }

    @Test func sortByName() {
        let places = [T.city("Tokyo", "Asia/Tokyo"), T.city("london", "Europe/London"), T.city("Berlin", "Europe/Berlin")]
        let (model, _, _) = T.model(now: "2026-11-03T15:00:00Z", local: "America/Chicago", places: places)
        model.sortByName()
        #expect(model.places.map(\.label) == ["Berlin", "london", "Tokyo"])
        #expect(model.pendingUndo?.menuTitle == "Undo Sort")
        model.undo()
        #expect(model.places.map(\.label) == ["Tokyo", "london", "Berlin"])
    }
}

@Suite("Calendar file")
struct CalendarFileTests {
    @Test func eventFile() {
        let text = CalendarFile.ics(start: T.date("2026-11-03T17:00:00Z"), duration: 3600, title: "Meeting",
                                    notes: "London: Tue, Nov 3, 5:00 PM GMT\nTokyo: Wed, Nov 4, 2:00 AM JST",
                                    uid: "abc", stamp: T.date("2026-11-01T00:00:00Z"))
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(text.contains("DTSTART:20261103T170000Z\r\n"))
        #expect(text.contains("DTEND:20261103T180000Z\r\n"))
        #expect(text.contains("DTSTAMP:20261101T000000Z\r\n"))
        #expect(text.contains("UID:abc@zones.slopapp.app"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        // Commas and newlines escaped, long lines folded.
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
        #expect(unfolded.contains(#"DESCRIPTION:London: Tue\, Nov 3\, 5:00 PM GMT\nTokyo: Wed\, Nov 4\, 2:00 AM JST"#))
        for line in text.components(separatedBy: "\r\n") {
            #expect(line.utf8.count <= 75)
        }
    }

    @Test func foldingKeepsCharactersWhole() {
        let line = "SUMMARY:" + String(repeating: "é", count: 60)
        let folded = CalendarFile.fold(line)
        #expect(folded.replacingOccurrences(of: "\r\n ", with: "") == line)
        for part in folded.components(separatedBy: "\r\n") { #expect(part.utf8.count <= 75) }
    }
}

@Suite("Planner labels")
struct PlannerLabelTests {
    @Test func hourLabels() {
        let twelve = T.formatter(.twelve)
        let utc = T.zone("UTC")
        #expect(twelve.hourLabel(T.date("2026-11-03T09:00:00Z"), in: utc) == TimeParts(main: "9", period: "AM", periodFirst: false))
        #expect(twelve.hourLabel(T.date("2026-11-03T12:00:00Z"), in: utc) == TimeParts(main: "12", period: "PM", periodFirst: false))
        #expect(twelve.hourLabel(T.date("2026-11-03T00:00:00Z"), in: utc).main == "Tue")
        #expect(twelve.hourLabel(T.date("2026-11-03T09:00:00Z"), in: T.zone("Asia/Kolkata")) == TimeParts(main: "2:30", period: "PM", periodFirst: false))
        let day = T.formatter(.twentyFour)
        #expect(day.hourLabel(T.date("2026-11-03T09:00:00Z"), in: utc) == TimeParts(main: "09", period: nil, periodFirst: false))
        #expect(day.hourLabel(T.date("2026-11-03T19:00:00Z"), in: T.zone("Asia/Kolkata")) == TimeParts(main: "00:30", period: "Wed", periodFirst: false))
        #expect(twelve.hourLabel(T.date("2026-11-03T19:00:00Z"), in: T.zone("Asia/Kolkata")) == TimeParts(main: "12:30", period: "Wed", periodFirst: false))
        #expect(T.formatter(.twelve).usesDayPeriod)
        #expect(!T.formatter(.twentyFour).usesDayPeriod)
        #expect(TimeFormatter(locale: Locale(identifier: "en_US"), hourCycle: .system).usesDayPeriod)
        #expect(!TimeFormatter(locale: Locale(identifier: "de_DE"), hourCycle: .system).usesDayPeriod)
    }
}
