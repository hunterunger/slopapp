import Foundation
import Testing
@testable import GaugeCore

@Suite struct PSParserTests {
    @Test func parsesRowsAndSkipsJunk() {
        let output = """
          PID      TIME    RSS COMM
            1 114:08.71  24928 launchd
          541   0:01.50   1024 WindowServer
          812 1:02:03.45   2048 Google Chrome Helper (Renderer)
          900 2-03:04:05.00 10 backupd
          bad line here
          901 notatime 10 x
          902 0:00.00 7
        """
        let rows = PSParser.parse(output)
        #expect(rows.map(\.pid) == [1, 541, 812, 900])
        #expect(rows[0].cpuTime == UInt64((114 * 60 + 8.71) * 1e9))
        #expect(rows[0].memory == 24928 * 1024)
        #expect(rows[2].name == "Google Chrome Helper (Renderer)")
        #expect(rows[2].cpuTime == UInt64((3600 + 2 * 60 + 3.45) * 1e9))
        #expect(rows[3].cpuTime == UInt64((2 * 86_400 + 3 * 3600 + 4 * 60 + 5.0) * 1e9))
    }

    @Test func truncatedUTF8NamesDecodeLeniently() {
        // "Café" cut in the middle of "é" (0xC3 0xA9) by ps.
        var bytes = Array("  10 0:01.00 100 Caf".utf8)
        bytes.append(0xC3)
        let rows = PSParser.parse(String(decoding: bytes, as: UTF8.self))
        #expect(rows.count == 1)
        #expect(rows[0].name.hasPrefix("Caf"))
    }

    @Test func cpuTimeFormats() {
        #expect(PSParser.cpuTime("0:00.00") == 0)
        #expect(PSParser.cpuTime("1:00.50") == 60_500_000_000)
        #expect(PSParser.cpuTime("1,5") == 1_500_000_000) // a comma locale slipping through
        #expect(PSParser.cpuTime("") == nil)
        #expect(PSParser.cpuTime("a:b") == nil)
        #expect(PSParser.cpuTime("1:2:3:4") == nil)
        #expect(PSParser.cpuTime("x-1:00.00") == nil)
    }
}

@Suite struct ProcessTrackerTests {
    func sample(_ pid: Int32, start: UInt64 = 1, cpu: UInt64, memory: UInt64 = 100, path: String? = nil) -> ProcessSample {
        ProcessSample(key: ProcessKey(pid: pid, start: start), name: "p\(pid)", path: path, cpuTime: cpu, memory: memory)
    }

    @Test func cpuPercentIsDeltaOverWallTime() {
        let tracker = ProcessTracker()
        let first = tracker.update(sweep: ProcessSweep(samples: [sample(10, cpu: 0)]), at: 0)
        #expect(first[0].cpuPercent == nil)
        // 1.5 s of CPU over 0.5 s of wall time: three cores' worth.
        let second = tracker.update(sweep: ProcessSweep(samples: [sample(10, cpu: 1_500_000_000)]), at: 0.5)
        #expect(second[0].cpuPercent == 300)
    }

    @Test func reusedPIDIsANewProcess() {
        let tracker = ProcessTracker()
        _ = tracker.update(sweep: ProcessSweep(samples: [sample(10, start: 1, cpu: 9_000_000_000)]), at: 0)
        let reused = tracker.update(sweep: ProcessSweep(samples: [sample(10, start: 2, cpu: 100)]), at: 1)
        #expect(reused[0].cpuPercent == nil)
    }

    @Test func psFillsInUnreadableProcesses() {
        let tracker = ProcessTracker()
        tracker.update(ps: [PSRow(pid: 99, cpuTime: 0, memory: 1 << 20, name: "WindowServer"),
                            PSRow(pid: 10, cpuTime: 0, memory: 1, name: "p10")], at: 0)
        tracker.update(ps: [PSRow(pid: 99, cpuTime: 500_000_000, memory: 1 << 20, name: "WindowServer"),
                            PSRow(pid: 10, cpuTime: 0, memory: 1, name: "p10")], at: 5)
        let usage = tracker.update(sweep: ProcessSweep(samples: [sample(10, cpu: 0)], unreadable: [99, 10, 123]), at: 5)
        #expect(usage.count == 2) // 10 from the sweep (not doubled), 99 from ps, 123 unknown
        let server = usage.first { $0.pid == 99 }
        #expect(server?.isRestricted == true)
        #expect(server?.cpuPercent == 10)
        #expect(server?.memory == 1 << 20)
    }

    @Test func psRowWithANewNameOrLessTimeIsNew() {
        let tracker = ProcessTracker()
        tracker.update(ps: [PSRow(pid: 5, cpuTime: 1_000, memory: 0, name: "a"), PSRow(pid: 6, cpuTime: 9_000, memory: 0, name: "b")], at: 0)
        tracker.update(ps: [PSRow(pid: 5, cpuTime: 2_000, memory: 0, name: "z"), PSRow(pid: 6, cpuTime: 1_000, memory: 0, name: "b")], at: 1)
        let usage = tracker.update(sweep: ProcessSweep(samples: [], unreadable: [5, 6]), at: 1)
        #expect(usage.allSatisfy { $0.cpuPercent == nil })
    }

    @Test func trackerResolvesTheAppOnce() {
        let tracker = ProcessTracker()
        let path = "/Applications/Safari.app/Contents/MacOS/Safari"
        let usage = tracker.update(sweep: ProcessSweep(samples: [sample(1, cpu: 0, path: path), sample(2, cpu: 0, path: "/usr/bin/x")]), at: 0)
        #expect(usage[0].appPath == "/Applications/Safari.app")
        #expect(usage[1].appPath == nil)
    }

    @Test func resetForgets() {
        let tracker = ProcessTracker()
        _ = tracker.update(sweep: ProcessSweep(samples: [sample(1, cpu: 0)]), at: 0)
        tracker.reset()
        #expect(tracker.update(sweep: ProcessSweep(samples: [sample(1, cpu: 10)]), at: 1)[0].cpuPercent == nil)
    }
}

@Suite struct AppGroupingTests {
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/A/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

    @Test func outermostAppWins() {
        #expect(AppGrouping.appPath(for: helper) == "/Applications/Google Chrome.app")
        #expect(AppGrouping.appPath(for: chrome) == "/Applications/Google Chrome.app")
        #expect(AppGrouping.appPath(for: "/usr/libexec/trustd") == nil)
        #expect(AppGrouping.appPath(for: "relative/X.app/y") == nil)
        #expect(AppGrouping.appPath(for: nil) == nil)
        #expect(AppGrouping.appName(for: "/Applications/Google Chrome.app") == "Google Chrome")
    }

    @Test func helpersRollUpIntoTheirApp() {
        let app = "/Applications/Google Chrome.app"
        let processes = [
            ProcessUsage(pid: 1, name: "Google Chrome", path: chrome, appPath: app, cpuPercent: 10, memory: 100),
            ProcessUsage(pid: 2, name: "Google Chrome Helper (Renderer)", path: helper, appPath: app, cpuPercent: 30, memory: 300),
            ProcessUsage(pid: 3, name: "node", path: "/opt/node/bin/node", cpuPercent: 50, memory: 10),
            ProcessUsage(pid: 4, name: "node", path: "/opt/node/bin/node", cpuPercent: nil, memory: 10),
            ProcessUsage(pid: 5, name: "WindowServer", path: nil, cpuPercent: 20, memory: 5, isRestricted: true),
        ]
        let groups = AppGrouping.group(processes, byApp: true)
        #expect(groups.count == 3)
        let browser = groups.first { $0.name == "Google Chrome" }
        #expect(browser?.cpuPercent == 40)
        #expect(browser?.memory == 400)
        #expect(browser?.count == 2)
        #expect(browser?.appPath == "/Applications/Google Chrome.app")
        #expect(groups.first { $0.name == "node" }?.count == 2)
        #expect(groups.first { $0.name == "WindowServer" }?.isRestricted == true)

        let flat = AppGrouping.group(processes, byApp: false)
        #expect(flat.count == 5)
        #expect(flat[1].appPath == "/Applications/Google Chrome.app")
    }

    @Test func topIsStableOnTiesAndSkipsIdle() {
        var groups = ["b", "a", "c"].map { ProcessGroup(id: $0, name: $0, appPath: nil, cpuPercent: 5, memory: 1, pids: [1], isRestricted: false) }
        #expect(AppGrouping.top(groups, by: .cpu, count: 2).map(\.name) == ["a", "b"])
        groups[1].cpuPercent = 0
        #expect(AppGrouping.top(groups, by: .cpu).map(\.name) == ["b", "c"])
        var busy = groups
        busy[2].memory = 9
        #expect(AppGrouping.top(busy, by: .memory).first?.name == "c")
    }

    @Test func copyText() {
        let one = ProcessGroup(id: "x", name: "Safari", appPath: nil, cpuPercent: 34, memory: 1_288_490_189, pids: [812], isRestricted: false)
        #expect(AppGrouping.copyText(one, sort: .cpu, locale: us) == "Safari, 34% CPU, 1.2 GB memory, PID 812")
        var many = one
        many.pids = [1, 2, 3]
        #expect(AppGrouping.copyText(many, sort: .cpu, locale: us).hasSuffix("3 processes"))
    }
}
