import Foundation
import Testing
@testable import GaugeCore

@Suite struct FormatTests {
    @Test func percentRoundsAndClamps() {
        #expect(Format.percent(0.234, locale: us) == "23%")
        #expect(Format.percent(0.235, locale: us) == "24%" || Format.percent(0.235, locale: us) == "23%")
        #expect(Format.percent(1.7, locale: us) == "100%")
        #expect(Format.percent(-1, locale: us) == "0%")
        #expect(Format.percent(.nan, locale: us) == "0%")
        #expect(Format.percentValue(0.996) == 100)
        #expect(Format.percentValue(.infinity) == 0)
    }

    @Test func percentFollowsTheLocale() {
        #expect(Format.percent(0.23, locale: Locale(identifier: "fr_FR")).contains("23"))
        #expect(Format.percent(0.23, locale: Locale(identifier: "fr_FR")) != "23%")
    }

    @Test(arguments: [
        (0.0, "0 KB/s"), (999.0, "0 KB/s"), (1000.0, "1.0 KB/s"), (8_440.0, "8.4 KB/s"), (9_960.0, "10 KB/s"),
        (40_200.0, "40 KB/s"), (123_000.0, "120 KB/s"), (999_400.0, "1.0 MB/s"), (1_234_567.0, "1.2 MB/s"),
        (98_000_000.0, "98 MB/s"), (1_250_000_000.0, "1.3 GB/s"), (5e15, "5000 TB/s"),
    ])
    func ratesHaveTwoSignificantFigures(bytes: Double, expected: String) {
        #expect(Format.rate(bytes, locale: us) == expected)
    }

    @Test func bitRates() {
        #expect(Format.rate(125_000, unit: .bits, locale: us) == "1.0 Mbps")
        #expect(Format.rate(100, unit: .bits, locale: us) == "0 Kbps")
        #expect(Format.rate(12_500_000, unit: .bits, locale: us) == "100 Mbps")
    }

    @Test func rateUsesTheLocalesDecimalSeparator() {
        #expect(Format.rate(1_234_567, locale: Locale(identifier: "de_DE")) == "1,2 MB/s")
    }

    @Test func rateCandidatesCoverEveryShape() {
        let candidates = Format.rateCandidates(unit: .bytes, locale: us)
        #expect(candidates.contains("880 KB/s"))
        #expect(candidates.contains("8.8 MB/s"))
        #expect(candidates.contains("0 KB/s"))
        // Every real value has the same shape (digits, separator, unit) as some candidate.
        func shape(_ text: String) -> String { String(text.map { $0.isNumber ? "8" : $0 }) }
        let shapes = Set(candidates.map(shape))
        for bytes in stride(from: 1000.0, to: 9e11, by: 7_777_777) {
            #expect(shapes.contains(shape(Format.rate(bytes, locale: us))), "\(Format.rate(bytes, locale: us))")
        }
    }

    @Test func significantFigures() {
        #expect(Format.significant(123.4, figures: 2) == 120)
        #expect(Format.significant(0.01234, figures: 2) == 0.012)
        #expect(Format.significant(0, figures: 2) == 0)
    }

    @Test func compactDisk() {
        #expect(Format.compactDisk(412_345_000_000, locale: us) == "412 GB")
        #expect(Format.compactDisk(85_240_000_000, locale: us) == "85.2 GB")
        #expect(Format.compactDisk(1_214_000_000_000, locale: us) == "1.21 TB")
        #expect(Format.compactDisk(999_900_000_000, locale: us) == "1.00 TB")
        #expect(Format.compactDisk(0, locale: us) == "0 KB")
    }

    @Test func processPercentUsesActivityMonitorScale() {
        #expect(Format.processPercent(312.4, locale: us) == "312%")
        #expect(Format.processPercent(34.4, locale: us) == "34%")
        #expect(Format.processPercent(2.54, locale: us) == "2.5%")
        #expect(Format.processPercent(0.01, locale: us) == "0%")
        #expect(Format.processPercent(-3, locale: us) == "0%")
    }

    @Test func uptime() {
        #expect(Format.uptime(59) == "0m")
        #expect(Format.uptime(12 * 60) == "12m")
        #expect(Format.uptime(5 * 3600 + 12 * 60) == "5h 12m")
        #expect(Format.uptime(5 * 3600) == "5h")
        #expect(Format.uptime(3 * 86_400 + 4 * 3600 + 59) == "3d 4h")
        #expect(Format.uptime(120 * 86_400) == "120d")
        #expect(Format.uptime(-5) == "0m")
    }

    @Test func hoursMinutesAndLoad() {
        #expect(Format.hoursMinutes(192) == "3:12")
        #expect(Format.hoursMinutes(5) == "0:05")
        #expect(Format.load(SystemLoad(oneMinute: 2.144, fiveMinutes: 1.98, fifteenMinutes: 1.8, uptime: 0), locale: us)
                == "2.14  1.98  1.80")
        #expect(Format.perSecond(1204.4, locale: us) == "1,204/s")
    }

    @Test func spokenRates() {
        #expect(Format.spokenRate(1_234_567, locale: us) == "1.2 megabytes per second")
        #expect(Format.spokenRate(0, unit: .bits, locale: us) == "0 kilobits per second")
    }

    @Test func memoryAndDiskSizes() {
        #expect(Format.memory(0, locale: us) == "0 MB")
        #expect(Format.disk(0, locale: us) == "0 MB")
        #expect(Format.disk(412_300_000_000, locale: us) == "412.3 GB")
    }
}
