import Foundation
import Testing
@testable import TallyCore

final class MemoryRatesStorage: RatesStorage {
    var stored: StoredRates = .none
    var saves = 0
    func load() -> StoredRates { stored }
    func save(_ table: RateTable) throws {
        saves += 1
        stored = .table(table)
    }
    func delete() throws { stored = .none }
}

struct FakeFetcher: RatesFetching {
    var result: Result<Data, URLError>
    func fetch() async throws -> Data { try result.get() }
}

let ecbXML = Data("""
<gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
<Cube><Cube time='2026-11-03'><Cube currency='USD' rate='1.0850'/><Cube currency='GBP' rate='0.8430'/></Cube></Cube>
</gesmes:Envelope>
""".utf8)

@MainActor @Suite struct RatesUpdating {
    let published = RateTable(date: "2026-11-03", rates: [:]).publishedDate!

    @Test func doesNothingWhileDownloadingIsOff() async {
        let storage = MemoryRatesStorage()
        let updater = RatesUpdater(storage: storage, fetcher: FakeFetcher(result: .success(ecbXML)), now: { published })
        #expect(await updater.updateIfDue(enabled: false) == false)
        #expect(storage.saves == 0)
        #expect(updater.state == .off)
    }

    @Test func fetchesOnceThenWaits() async {
        let storage = MemoryRatesStorage()
        var clock = published.addingTimeInterval(17 * 3600)
        let updater = RatesUpdater(storage: storage, fetcher: FakeFetcher(result: .success(ecbXML)), now: { clock })
        #expect(await updater.updateIfDue(enabled: true))
        #expect(storage.saves == 1)
        #expect(updater.state == .loaded(fixtureRates, stale: false))
        clock = clock.addingTimeInterval(3600)
        #expect(await updater.updateIfDue(enabled: true) == false)
        #expect(storage.saves == 1)
    }

    @Test func oldRatesAreDueAndMarkedStale() async {
        let storage = MemoryRatesStorage()
        storage.stored = .table(fixtureRates)
        let later = published.addingTimeInterval(9 * 86_400)
        let updater = RatesUpdater(storage: storage, fetcher: FakeFetcher(result: .failure(URLError(.notConnectedToInternet))), now: { later })
        #expect(updater.state == .loaded(fixtureRates, stale: true))
        #expect(updater.isDue(enabled: true))
        await updater.update()
        // A failed download keeps the old rates and says what to do.
        #expect(updater.table == fixtureRates)
        if case .failed(let message) = updater.status {
            #expect(message.contains("Update Now"))
        } else {
            Issue.record("expected a failure status")
        }
        // ...and doesn't retry until the interval passes.
        #expect(!updater.isDue(enabled: true))
    }

    @Test func badPayloadIsReportedAndNothingIsSaved() async {
        let storage = MemoryRatesStorage()
        let updater = RatesUpdater(storage: storage, fetcher: FakeFetcher(result: .success(Data("<html/>".utf8))), now: { published })
        await updater.update()
        #expect(storage.saves == 0)
        #expect(updater.status != .idle)
    }

    @Test func deleteGoesBackToOff() async {
        let storage = MemoryRatesStorage()
        let updater = RatesUpdater(storage: storage, fetcher: FakeFetcher(result: .success(ecbXML)), now: { published })
        await updater.update()
        updater.delete()
        #expect(updater.state == .off)
    }
}

@Suite struct Files {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tally-tests-\(UUID().uuidString)")

    @Test func sheetRoundTrips() throws {
        let storage = FileSheetStorage(directory: dir)
        #expect(storage.load() == nil)
        try storage.save("a = 1\n€5 “quoted”\n")
        #expect(storage.load() == "a = 1\n€5 “quoted”\n")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func ratesRoundTripAndCorruptFilesAreReported() throws {
        let storage = FileRatesStorage(directory: dir)
        #expect(storage.load() == .none)
        try storage.save(fixtureRates)
        #expect(storage.load() == .table(fixtureRates))
        try Data("{ nope".utf8).write(to: storage.url)
        #expect(storage.load() == .unreadable)
        try storage.delete()
        #expect(storage.load() == .none)
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite struct Copying {
    let f = ResultFormatter(locale: usLocale)

    @Test func copyTextWithAndWithoutUnit() {
        let out = SheetEngine().evaluate("1 m + 20 cm\n$1,234.5\nhello")
        #expect(SheetText.copyText(out[0], formatter: f, includeUnit: true) == "1.2 m")
        #expect(SheetText.copyText(out[0], formatter: f, includeUnit: false) == "1.2")
        #expect(SheetText.copyText(out[1], formatter: f, includeUnit: false) == "1234.50")
        #expect(SheetText.copyText(out[2], formatter: f, includeUnit: true) == nil)
    }

    @Test func copyAllAppendsAnswers() {
        let lines = ["# Trip", "rent = 1450", "rent / 3", "12 * 4 =", "note", "1"]
        let out = SheetEngine().evaluate(lines: lines)
        #expect(SheetText.copyAll(lines: lines, outputs: out, formatter: f) ==
            "# Trip\nrent = 1450\nrent / 3 = 483.3333333\n12 * 4 = 48\nnote\n1")
    }

    @Test func lineLookup() {
        let starts = SheetText.lineStarts(of: "ab\n\ncd\n" as NSString)
        #expect(starts == [0, 3, 4, 7])
        #expect(SheetText.lineIndex(containing: 0, lineStarts: starts) == 0)
        #expect(SheetText.lineIndex(containing: 2, lineStarts: starts) == 0)
        #expect(SheetText.lineIndex(containing: 3, lineStarts: starts) == 1)
        #expect(SheetText.lineIndex(containing: 5, lineStarts: starts) == 2)
        #expect(SheetText.lineIndex(containing: 7, lineStarts: starts) == 3)
        #expect(SheetText.lineStarts(of: "" as NSString) == [0])
    }
}

@Suite struct Content {
    @Test func welcomeSheetShowsAnswers() {
        let r = sheet(SheetText.welcome)
        #expect(r == ["—", "—", "$186.40", "18%", "$219.95", "$54.99", "3.106855961 mi", "—", "—"])
    }

    @Test func everySyntaxGuideExampleWorks() {
        for section in SyntaxGuide.sections {
            let results = SheetEngine().evaluate(lines: section.examples)
            for (example, out) in zip(section.examples, results) {
                let isNote = example.hasPrefix("#") || example.hasPrefix("//")
                if isNote {
                    #expect(out.result == .none, "\(example)")
                } else if example.contains(" in CAD") {
                    #expect(out.result.quantity != nil, "\(example)")
                } else {
                    #expect(out.result.quantity != nil, "\(section.title): \(example) → \(out.result)")
                }
            }
        }
    }
}
