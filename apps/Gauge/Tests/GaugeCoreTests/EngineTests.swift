import Foundation
import Testing
@testable import GaugeCore

@Suite struct EngineTests {
    @Test func firstTickIsABaselineThenRates() throws {
        let network = FakeNetwork([[InterfaceCounters(name: "en0", received: 0, sent: 0)],
                                   [InterfaceCounters(name: "en0", received: 4000, sent: 2000)]])
        let engine = GaugeEngine(sources: sources(cpu: FakeCPU([ticks(1), ticks(3)]), network: network,
                                                  gpu: FakeGPU([0.4, 0.5]),
                                                  disk: FakeDiskIO([DiskIOCounters(read: 0, written: 0), DiskIOCounters(read: 10, written: 20)])))
        let first = engine.tick(at: 0)
        #expect(first.cpu == nil)
        #expect(first.network == nil)
        #expect(first.gpu == 0.4)
        #expect(first.memory != nil)
        let second = engine.tick(at: 2)
        #expect(abs(try #require(second.cpu).total - 0.25) < 1e-9)
        #expect(second.network == ByteRates(down: 2000, up: 1000))
        #expect(second.disk == ByteRates(down: 5, up: 10))
        #expect(engine.histories[.cpu]?.latest == Double(Float(0.25)))
        #expect(engine.histories[.networkDown]?.latest == 2000)
        #expect(engine.readoutValues(bootVolumeFree: 5, battery: nil).cpu == second.cpu?.total)
    }

    @Test func pauseAddsAGapAndForgetsBaselines() {
        let engine = GaugeEngine(sources: sources(cpu: FakeCPU([ticks(1), ticks(2), ticks(100), ticks(101)])))
        engine.tick(at: 0)
        engine.tick(at: 1)
        engine.pause(at: 2)
        #expect(engine.latest == nil)
        // The first reading after waking is a baseline, not a spike over the sleep.
        #expect(engine.tick(at: 1000).cpu == nil)
        #expect(engine.tick(at: 1001).cpu != nil)
        let points = engine.histories[.cpu]!.points(span: .hour, now: 1001)
        #expect(points.contains { $0.isGap })
    }

    @Test func primeTakesABaseline() {
        let engine = GaugeEngine(sources: sources(cpu: FakeCPU([ticks(1), ticks(2)])))
        engine.prime(at: 0)
        #expect(engine.tick(at: 1).cpu != nil)
    }

    @Test func gpuHidesAfterRepeatedMisses() {
        let never = GaugeEngine(sources: sources(gpu: FakeGPU([nil, nil, nil, 0.5])))
        for second in 0..<3 { never.tick(at: Double(second)) }
        #expect(!never.hasGPU)
        #expect(never.tick(at: 4).gpu == nil) // no longer asked

        let flaky = GaugeEngine(sources: sources(gpu: FakeGPU([0.2, nil, nil, nil, nil, 0.3])))
        for second in 0..<6 { flaky.tick(at: Double(second)) }
        #expect(flaky.hasGPU)
    }

    @Test func gpuIsClamped() {
        let engine = GaugeEngine(sources: sources(gpu: FakeGPU([1.7])))
        #expect(engine.tick(at: 0).gpu == 1)
    }
}

@Suite struct SessionTests {
    func session(processes: FakeProcesses = FakeProcesses(), cpu: [[CPUTicks]?]? = nil) -> GaugeSession {
        let readings = cpu ?? (1...40).map { ticks($0) }
        return GaugeSession(sources: sources(cpu: FakeCPU(readings)), processes: processes, preferences: Preferences(),
                            hasBattery: true, locale: us)
    }

    @Test func closedPanelNeverSweepsProcesses() {
        let processes = FakeProcesses()
        let session = session(processes: processes)
        for second in 0..<5 {
            let output = session.tick(at: Double(second), interval: 2)
            #expect(output.panel == nil)
            #expect(!output.wantsPS)
        }
        #expect(processes.calls == 0)
    }

    @Test func menuBarDrawsFirstThenOnlyWhenItMatters() {
        let session = session()
        #expect(session.tick(at: 0, interval: 2).menuBar != nil) // dashes
        #expect(session.tick(at: 2, interval: 2).menuBar != nil) // first real value
        #expect(session.tick(at: 4, interval: 2).menuBar == nil) // same 25%
    }

    @Test func openPanelSweepsAndAsksForPSOnSchedule() {
        let sample = ProcessSample(key: ProcessKey(pid: 1, start: 1), name: "a", path: nil, cpuTime: 0, memory: 10)
        var later = sample
        later.cpuTime = 500_000_000
        let processes = FakeProcesses([ProcessSweep(samples: [sample]), ProcessSweep(samples: [later])])
        let session = session(processes: processes)
        session.setPanelOpen(true)
        let open = session.tick(at: 0, interval: 1)
        #expect(open.wantsPS)
        #expect(open.panel?.processesReady == false)
        #expect(open.panel?.topMemory.first?.name == "a")
        session.applyPS([], at: 0)
        let second = session.tick(at: 0.3, interval: 1)
        #expect(!second.wantsPS)
        #expect(second.panel?.processesReady == true)
        #expect(second.panel?.topCPU.first?.cpuPercent ?? 0 > 100)
        #expect(session.tick(at: 1.3, interval: 1).wantsPS)   // the second ps run, a second in
        #expect(processes.calls == 2)                         // no sweep: 1 s since the last
        session.applyPS([], at: 1.3)
        #expect(!session.tick(at: 2.3, interval: 1).wantsPS)
        #expect(processes.calls == 3)                         // every 2 s after the first two
        #expect(session.tick(at: 6.4, interval: 1).wantsPS)   // ps every 5 s
        session.setPanelOpen(false)
        #expect(session.tick(at: 7, interval: 2).panel == nil)
    }

    @Test func psResultsAfterCloseAreIgnored() {
        let session = session()
        session.applyPS([PSRow(pid: 1, cpuTime: 0, memory: 0, name: "x")], at: 0)
        session.setPanelOpen(true)
        let output = session.tick(at: 0, interval: 1)
        #expect(output.panel?.topCPU.isEmpty == true)
    }

    @Test func bootVolumeAndExternalChanges() {
        let session = session()
        session.preferences = Preferences(readouts: [.disk])
        session.volumes = [VolumeInfo(id: "/Volumes/X", name: "X", available: 1, total: 2),
                           VolumeInfo(id: "/", name: "Macintosh HD", available: 412_000_000_000, total: 1_000_000_000_000, isBoot: true)]
        #expect(session.bootVolumeFree == 412_000_000_000)
        _ = session.forceMenuBar(at: 0, interval: 2)
        #expect(session.externalChange(at: 1, interval: 2) == nil)
        session.volumes[1].available = 400_000_000_000
        #expect(session.externalChange(at: 2, interval: 2)?.segments.first?.fields.first?.text == "400 GB")
    }

    @Test func pauseRedrawsTheNextTick() {
        let session = session()
        _ = session.tick(at: 0, interval: 2)
        _ = session.tick(at: 2, interval: 2)
        session.pause(at: 3)
        #expect(session.tick(at: 100, interval: 2).menuBar != nil)
    }

    @Test func panelDataCarriesHistoryForTheSpan() {
        let session = session()
        session.setPanelOpen(true)
        for second in 0..<5 { _ = session.tick(at: Double(second), interval: 1) }
        let panel = session.tick(at: 5, interval: 1).panel
        #expect(panel?.history[.cpu]?.count == 5)
        #expect(panel?.peak(.cpu) == Double(Float(0.25)))
        #expect(panel?.span == .tenMinutes)
    }
}
