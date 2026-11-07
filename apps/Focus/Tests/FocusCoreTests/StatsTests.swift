import Foundation
import Testing
@testable import FocusCore

let enUS = Locale(identifier: "en_US")

/// ICU puts narrow and thin spaces in times and ranges.
func plain(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
}

/// A focus record ending `end` after t0's midnight, lasting `length` minutes.
func session(day: Int = 0, hour: Int, minute: Int = 0, length: Double = 25, category: String? = nil,
             mood: Mood? = nil, label: String? = nil, kind: Phase = .focus) -> SessionRecord {
    let midnight = utc.startOfDay(for: t0).addingTimeInterval(Double(day) * 86_400)
    let start = midnight.addingTimeInterval(Double(hour) * 3600 + Double(minute) * 60)
    return SessionRecord(startedAt: start, endedAt: start.addingTimeInterval(minutes(length)), planned: minutes(length),
                         focused: minutes(length), completed: true, label: label, kind: kind, categoryID: category, mood: mood)
}

@Suite("Stats")
struct StatsTests {
    let categories = Category.defaults

    @Test func rangesFollowTheCalendar() {
        var monday = utc
        monday.firstWeekday = 2
        let week = StatsRange.containing(t0, period: .week, calendar: monday) // t0 is Tuesday Nov 3
        #expect(week.start == utc.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        #expect(week.end == utc.date(from: DateComponents(year: 2026, month: 11, day: 9)))
        let month = StatsRange.containing(t0, period: .month, calendar: utc)
        #expect(month.shifted(by: -1, calendar: utc).start == utc.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let day = StatsRange.containing(t0, period: .day, calendar: utc)
        #expect(day.shifted(by: 1, calendar: utc).contains(t0.addingTimeInterval(86_400)))
    }

    @Test func titles() {
        let day = StatsRange.containing(t0, period: .day, calendar: utc)
        #expect(day.title(now: t0, calendar: utc, locale: enUS) == "Today")
        #expect(day.shifted(by: -1, calendar: utc).title(now: t0, calendar: utc, locale: enUS) == "Yesterday")
        #expect(day.shifted(by: -2, calendar: utc).title(now: t0, calendar: utc, locale: enUS) == "Sunday, Nov 1")
        var monday = utc
        monday.firstWeekday = 2
        let week = StatsRange.containing(t0, period: .week, calendar: monday)
        #expect(week.title(now: t0, calendar: monday, locale: enUS) == "This Week")
        #expect(plain(week.shifted(by: -2, calendar: monday).title(now: t0, calendar: monday, locale: enUS)) == "Oct 19 – 25")
        let month = StatsRange.containing(t0, period: .month, calendar: utc)
        #expect(month.shifted(by: -1, calendar: utc).title(now: t0, calendar: utc, locale: enUS) == "October 2026")
    }

    @Test func weekReportTotalsChartAndShares() {
        var monday = utc
        monday.firstWeekday = 2
        let records = [
            session(day: -1, hour: 9, category: "work", mood: .focused),
            session(day: -1, hour: 10, length: 50, category: "work", mood: .distracted),
            session(day: 0, hour: 9, category: "study", mood: .focused),
            session(day: 0, hour: 9, minute: 30, length: 5, kind: .shortBreak),
            session(day: 0, hour: 14, length: 10), // no category, unrated
            session(day: -10, hour: 9), // last month: outside the week
        ]
        let range = StatsRange.containing(t0, period: .week, calendar: monday)
        let report = StatsReport.make(range: range, records: records, categories: categories, now: t0, calendar: monday)
        #expect(report.totalFocus == minutes(110))
        #expect(report.totalBreak == minutes(5))
        #expect(report.sessions == 4)
        #expect(report.averagePerDay == minutes(55), "Mon and Tue have started")
        #expect(report.mostFocusedHour == 9, "a tie goes to the earlier hour")
        #expect(report.moods == [.focused: 2, .distracted: 1])
        #expect(report.unrated == 1)
        #expect(report.buckets.count == 7)
        #expect(report.buckets[0].seconds == ["work": minutes(75)])
        #expect(report.buckets[1].total == minutes(35))
        #expect(report.categories.map(\.name) == ["Work", "Study", "No Category"])
        #expect(abs(report.categories[0].share - 75.0 / 110.0) < 1e-9)
        #expect(report.records.count == 5)
        #expect(report.records.first?.kind == .focus, "newest first: the 14:00 session")
    }

    @Test func dayReportBucketsByHourAndFilters() {
        let records = [session(hour: 9, category: "work"), session(hour: 9, minute: 30, category: "study"), session(hour: 15)]
        let range = StatsRange.containing(t0, period: .day, calendar: utc)
        let report = StatsReport.make(range: range, records: records, categories: categories, now: t0, calendar: utc)
        #expect(report.buckets.count == 24)
        #expect(report.buckets[9].seconds == ["work": minutes(25), "study": minutes(25)])
        #expect(report.buckets[15].seconds == [StatsReport.noCategory: minutes(25)])
        let filtered = StatsReport.make(range: range, records: records, categories: categories, now: t0, calendar: utc, categoryFilter: "work")
        #expect(filtered.totalFocus == minutes(25))
        #expect(filtered.records.count == 1)
        let none = StatsReport.make(range: range, records: records, categories: categories, now: t0, calendar: utc, categoryFilter: StatsReport.noCategory)
        #expect(none.records.map(\.startedAt) == [records[2].startedAt])
    }

    @Test func emptyPeriod() {
        let range = StatsRange.containing(t0, period: .month, calendar: utc)
        let report = StatsReport.make(range: range, records: [], categories: categories, now: t0, calendar: utc)
        #expect(report.totalFocus == 0 && report.sessions == 0 && report.mostFocusedHour == nil)
        #expect(report.buckets.count == 30)
        #expect(report.categories.isEmpty)
    }

    @Test func compactDurations() {
        #expect(CompactDuration.text(0) == "0m")
        #expect(CompactDuration.text(minutes(59)) == "59m")
        #expect(CompactDuration.text(minutes(120)) == "2h")
        #expect(CompactDuration.text(minutes(125)) == "2h 5m")
        #expect(CompactDuration.hour(12, calendar: utc, locale: enUS) == "Noon")
        #expect(plain(CompactDuration.hour(15, calendar: utc, locale: enUS)) == "3 PM")
    }
}

@Suite("Intentions")
struct IntentionTests {
    let categories = Category.defaults + [Category(id: "deep", name: "Deep Work", color: .indigo)]

    @Test func parsesCategoryAndDuration() {
        #expect(IntentionParser.parse("Draft intro @work 45m", categories: categories)
            == ParsedIntention(text: "Draft intro", categoryID: "work", minutes: 45))
        #expect(IntentionParser.parse("@deepwork Refactor 1h30m", categories: categories)
            == ParsedIntention(text: "Refactor", categoryID: "deep", minutes: 90))
        #expect(IntentionParser.parse("Email @bob", categories: categories) == ParsedIntention(text: "Email @bob"))
        #expect(IntentionParser.parse("Read 30 pages", categories: categories) == ParsedIntention(text: "Read 30 pages"))
        #expect(IntentionParser.parse("Marathon 9h", categories: categories).minutes == 180, "clamped to the longest session")
        #expect(IntentionParser.parse("  ", categories: categories) == ParsedIntention(text: ""))
    }

    @Test func durations() {
        #expect(IntentionParser.duration("25m") == 25)
        #expect(IntentionParser.duration("25min") == 25)
        #expect(IntentionParser.duration("1h") == 60)
        #expect(IntentionParser.duration("2hr") == 120)
        #expect(IntentionParser.duration("1h30") == 90)
        #expect(IntentionParser.duration("30") == nil)
        #expect(IntentionParser.duration("0m") == nil)
        #expect(IntentionParser.duration("m") == nil)
        #expect(IntentionParser.duration("h1") == nil)
    }

    @Test func categoryMatchingIsForgiving() {
        #expect(IntentionParser.category(matching: "WORK", in: categories)?.id == "work")
        #expect(IntentionParser.category(matching: "st", in: categories)?.id == "study")
        #expect(IntentionParser.category(matching: "ｘ", in: categories) == nil)
        let accented = [Category(id: "e", name: "Études", color: .red)]
        #expect(IntentionParser.category(matching: "etu", in: accented)?.id == "e")
    }

    @Test func suggestionsRankWordStartsFirst() {
        let records = [
            session(hour: 8, label: "Rewrite docs"),
            session(hour: 9, label: "Write tests"),
            session(hour: 10, label: "write tests"),
            session(hour: 11, label: "Lunch"),
            session(hour: 12, label: "Code review writeup"),
            session(hour: 13, label: nil),
        ]
        let found = IntentionSuggestions.make(query: "wri", records: records)
        #expect(found.map(\.text) == ["Code review writeup", "write tests", "Rewrite docs"])
        #expect(IntentionSuggestions.make(query: "Lunch", records: records).isEmpty, "an exact match isn't suggested")
        #expect(IntentionSuggestions.make(query: "", records: records, limit: 2).map(\.text) == ["Code review writeup", "Lunch"])
    }
}

@Suite("Export")
struct ExportTests {
    @Test func csvRowsAndEscaping() {
        var tricky = session(hour: 9, category: "work", mood: .neutral, label: "Plan, \"Q4\"")
        tricky.notes = "line one\nline two"
        tricky.paused = 90
        let formula = session(hour: 10, label: "=SUM(A1)")
        var gone = session(hour: 11, label: "gone")
        gone.deleted = true
        let rest = session(hour: 9, minute: 25, length: 5, category: "work", kind: .shortBreak)
        let csv = CSVExport.make([formula, rest, tricky, gone], categories: Category.defaults, timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "Intention,Category,Type,Start,End,Duration (minutes),Duration (seconds),Paused (seconds),Completed,Counted,Mood,Notes")
        #expect(lines[1] == "\"Plan, \"\"Q4\"\"\",Work,Focus,2026-11-03T09:00:00Z,2026-11-03T09:25:00Z,25.0,1500,90,yes,yes,Neutral,\"line one\nline two\"")
        #expect(lines[2] == ",,Short break,2026-11-03T09:25:00Z,2026-11-03T09:30:00Z,5.0,300,0,yes,no,,")
        #expect(lines[3].hasPrefix("'=SUM(A1),"))
        #expect(!csv.contains("gone"))
        #expect(CSVExport.fileName(now: t0, calendar: utc) == "Focus Sessions 2026-11-03.csv")
    }
}

@Suite("History log")
struct HistoryLogTests {
    @Test func laterLinesReplaceEarlierOnesAndDeletesStick() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStorage(directory: dir)
        var a = session(hour: 9, label: "a")
        let b = session(hour: 10, label: "b")
        try store.append(a)
        try store.append(b)
        a.mood = .focused
        try store.append(a)
        var gone = b
        gone.deleted = true
        try store.append(gone)
        #expect(store.allRecords().map(\.label) == ["a"])
        #expect(store.allRecords().first?.mood == .focused)
        #expect(store.records(since: utc.startOfDay(for: t0)).map(\.mood) == [.focused])
    }
}

@Suite("Chart axis")
struct ChartAxisTests {
    @Test func roundStepsCoverTheTallestBar() {
        // 3h 55m tallest day: hour steps, axis to 4h.
        #expect(ChartAxis.scale(maxMinutes: 235).step == 60)
        #expect(ChartAxis.scale(maxMinutes: 235).top == 240)
        // A light week: 50 minutes → 15 min steps to 1h.
        #expect(ChartAxis.scale(maxMinutes: 50).step == 15)
        #expect(ChartAxis.scale(maxMinutes: 50).top == 60)
        // Exactly on a step: no extra empty step.
        #expect(ChartAxis.scale(maxMinutes: 120).step == 30)
        #expect(ChartAxis.scale(maxMinutes: 120).top == 120)
    }

    @Test func emptyAndOddInputGetAnHourAxis() {
        #expect(ChartAxis.scale(maxMinutes: 0).step == 15)
        #expect(ChartAxis.scale(maxMinutes: 0).top == 60)
        #expect(ChartAxis.scale(maxMinutes: .nan).step == 15)
        #expect(ChartAxis.scale(maxMinutes: .nan).top == 60)
    }

    @Test func menuBarWidthTemplateKeepsTheItemFromNarrowing() {
        #expect(TimeText.widthTemplate(for: "9m") == "00m")
        #expect(TimeText.widthTemplate(for: "25m") == "00m")
        #expect(TimeText.widthTemplate(for: "9:59") == "00:00")
        #expect(TimeText.widthTemplate(for: "1:05:00") == "0:00:00")
        #expect(TimeText.widthTemplate(for: "120m") == "000m")
    }

    @Test func hugeDaysStillGetFewTicks() {
        let (step, top) = ChartAxis.scale(maxMinutes: 20 * 60)
        #expect(step == 360)
        #expect(top == 1440)
    }
}
