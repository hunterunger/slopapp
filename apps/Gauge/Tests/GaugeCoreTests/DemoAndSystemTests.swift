import Foundation
import Testing
@testable import GaugeCore

@Suite struct DemoTests {
    @Test func demoSessionProducesEverySection() throws {
        let clock = ManualClock(1000)
        let world = DemoWorld(clock: clock)
        let sources = world.makeSources()
        let session = GaugeSession(sources: sources.tick, processes: sources.processes, preferences: Preferences(),
                                   hasBattery: true, locale: us)
        session.setPanelOpen(true)
        _ = session.tick(at: 1000, interval: 1)
        clock.time = 1001
        let panel = try #require(session.tick(at: 1001, interval: 1).panel)
        let cpu = try #require(panel.snapshot.cpu)
        #expect(cpu.total > 0 && cpu.total < 1)
        #expect(panel.snapshot.gpu != nil)
        #expect(panel.snapshot.memory?.pressure == .normal)
        #expect(panel.snapshot.network != nil)
        #expect(panel.snapshot.disk != nil)
        #expect(panel.topCPU.count == 5)
        #expect(panel.topMemory.first?.name == "Safari")
        #expect(panel.coreGroups.map(\.name) == ["Performance", "Efficiency"])
        #expect(sources.battery.read(details: true)?.cycleCount == 182)
        #expect(sources.volumes.volumes().first?.isBoot == true)
        #expect(sources.network.primary()?.kind == "Wi-Fi")
    }

    @Test func demoLoadStaysInRange() {
        let world = DemoWorld(clock: ManualClock())
        for t in stride(from: 0.0, to: 3600, by: 7) {
            #expect((0...1).contains(world.cpuLoad(at: t)))
            #expect(world.networkDown(at: t) >= 0)
        }
    }

    @Test func seedingWithAnOverriddenTimeFillsTheHour() {
        let clock = ManualClock(5000)
        let world = DemoWorld(clock: clock)
        let sources = world.makeSources()
        let session = GaugeSession(sources: sources.tick, processes: sources.processes, preferences: Preferences(),
                                   hasBattery: true, locale: us)
        for step in stride(from: 1400.0, to: 5000, by: 2) {
            world.setTime(step)
            _ = session.tick(at: step, interval: 2)
        }
        world.setTime(nil)
        #expect(world.time == 5000)
        #expect(session.engine.histories[.cpu]!.points(span: .hour, now: 5000).count > 100)
    }
}

/// The real sources, read once: they must not crash and must return sane shapes. Values
/// aren't checked (they're this Mac's), and processes and volumes aren't read at all.
@Suite struct SystemSourceTests {
    @Test func cpuTicksAndGroups() throws {
        let cpu = SystemCPU()
        let first = try #require(cpu.ticks())
        #expect(first.count == ProcessInfo.processInfo.activeProcessorCount || first.count > 0)
        let groups = cpu.coreGroups()
        #expect(!groups.isEmpty)
        #expect(Set(groups.flatMap(\.cpus)).count == groups.flatMap(\.cpus).count) // no CPU twice
    }

    @Test func memoryLoadAndClock() throws {
        let memory = try #require(SystemMemory().read())
        #expect(memory.totalBytes > 0)
        #expect([1, 2, 4].contains(memory.pressureLevel))
        let status = MemoryMath.status(memory)
        #expect(status.used <= status.total)
        let load = SystemLoadSource().load()
        #expect(load.uptime > 0)
        let clock = SystemClock()
        let a = clock.now()
        #expect(clock.now() >= a)
    }

    @Test func networkGPUAndDiskCountersDontCrash() {
        let network = SystemNetwork()
        #expect(network.counters().allSatisfy { NetworkMath.isCounted($0.name) })
        _ = network.counters() // the per-interface path
        if let gpu = SystemGPU().utilization() { #expect((0...1).contains(gpu)) }
        _ = SystemDiskIO().counters()
    }
}
