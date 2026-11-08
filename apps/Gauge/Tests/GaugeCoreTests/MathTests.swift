import Foundation
import Testing
@testable import GaugeCore

@Suite struct CPUMathTests {
    @Test func usageFromTickDeltas() throws {
        let old = [CPUTicks(user: 100, system: 50, idle: 850), CPUTicks(user: 0, system: 0, idle: 1000)]
        let new = [CPUTicks(user: 150, system: 100, idle: 900), CPUTicks(user: 0, system: 0, idle: 1100)]
        let usage = try #require(CPUMath.usage(from: old, to: new))
        // Core 0: 50 user + 50 system of 150; core 1 idle. Whole chip: 100 of 250.
        #expect(abs(usage.total - 0.4) < 1e-9)
        #expect(abs(usage.user - 0.2) < 1e-9)
        #expect(abs(usage.system - 0.2) < 1e-9)
        #expect(abs(usage.perCore[0] - 100.0 / 150) < 1e-9)
        #expect(usage.perCore[1] == 0)
    }

    @Test func niceCountsAsUser() throws {
        let usage = try #require(CPUMath.usage(from: [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)],
                                               to: [CPUTicks(user: 10, system: 0, idle: 80, nice: 10)]))
        #expect(abs(usage.user - 0.2) < 1e-9)
    }

    @Test func wrappedCounterStillGivesTheRightDelta() throws {
        let old = [CPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 89)]
        let new = [CPUTicks(user: 10, system: 0, idle: 10)]
        let usage = try #require(CPUMath.usage(from: old, to: new))
        // 20 user ticks and 100 idle ticks across the wrap.
        #expect(abs(usage.total - 20.0 / 120) < 1e-9)
    }

    @Test func resetCountersAreDroppedNotReadAsASpike() {
        let old = [CPUTicks(user: 5_000_000, system: 1_000_000, idle: 90_000_000)]
        let new = [CPUTicks(user: 10, system: 5, idle: 100)]
        #expect(CPUMath.usage(from: old, to: new) == nil)
    }

    @Test func changedCoreCountOrNoTimeIsNil() {
        #expect(CPUMath.usage(from: ticks(1), to: [CPUTicks(user: 1, system: 1, idle: 1)]) == nil)
        #expect(CPUMath.usage(from: ticks(1), to: ticks(1)) == nil)
        #expect(CPUMath.usage(from: [], to: []) == nil)
    }

    @Test func groupsPerCoreValuesByKindInOrder() {
        let groups = [CoreGroup(name: "Performance", cpus: [2, 3]), CoreGroup(name: "Efficiency", cpus: [0, 1]),
                      CoreGroup(name: "Missing", cpus: [9])]
        let grouped = CPUMath.grouped([0.1, 0.2, 0.3, 0.4], by: groups)
        #expect(grouped.map(\.name) == ["Performance", "Efficiency"])
        #expect(grouped[0].values == [0.3, 0.4])
        #expect(grouped[1].values == [0.1, 0.2])
    }
}

@Suite struct MemoryMathTests {
    let reading = MemoryReading(
        vm: VMCounters(pageSize: 16384, free: 1000, wired: 2000, compressor: 500, purgeable: 100,
                       external: 3000, internal: 6100, pageins: 10, pageouts: 4, swapins: 2, swapouts: 1),
        totalBytes: 16384 * 20000, swapUsed: 1 << 30, swapTotal: 2 << 30, pressureLevel: 2, availablePercent: 62)

    @Test func breakdownMatchesActivityMonitor() {
        let status = MemoryMath.status(reading)
        #expect(status.app == 6000 * 16384)          // internal − purgeable
        #expect(status.wired == 2000 * 16384)
        #expect(status.compressed == 500 * 16384)
        #expect(status.cached == 3100 * 16384)       // external + purgeable
        #expect(status.used == 8500 * 16384)
        #expect(status.free == (20000 - 8500 - 3100) * 16384)
        #expect(status.swapUsed == 1 << 30)
        #expect(status.pressure == .warning)
        #expect(abs(status.pressureFraction - 0.38) < 1e-9)
    }

    @Test func pressureLevels() {
        #expect(MemoryPressure(level: 1) == .normal)
        #expect(MemoryPressure(level: 2) == .warning)
        #expect(MemoryPressure(level: 4) == .critical)
        #expect(MemoryPressure(level: 0) == .normal)
        #expect(MemoryPressure(level: 99) == .normal)
    }

    @Test func freeNeverUnderflows() {
        var odd = reading
        odd.totalBytes = 16384
        let status = MemoryMath.status(odd)
        #expect(status.free == 0)
        #expect(status.used == 16384)
    }

    @Test func availableOutOfRangeIsClamped() {
        var odd = reading
        odd.availablePercent = 130
        #expect(MemoryMath.status(odd).pressureFraction == 0)
        odd.availablePercent = -5
        #expect(MemoryMath.status(odd).pressureFraction == 1)
    }

    @Test func pagingRates() throws {
        let later = VMCounters(pageins: 30, pageouts: 4, swapins: 12, swapouts: 1)
        let rates = try #require(MemoryMath.paging(from: reading.vm, to: later, seconds: 2))
        #expect(rates.pageinsPerSecond == 10)
        #expect(rates.pageoutsPerSecond == 0)
        #expect(rates.swapinsPerSecond == 5)
        #expect(MemoryMath.paging(from: later, to: reading.vm, seconds: 2) == nil)
        #expect(MemoryMath.paging(from: reading.vm, to: later, seconds: 0) == nil)
    }
}

@Suite struct NetworkMathTests {
    @Test func countsOnlyPhysicalInterfaces() {
        #expect(NetworkMath.isCounted("en0"))
        #expect(NetworkMath.isCounted("en12"))
        for name in ["lo0", "utun3", "bridge0", "awdl0", "llw0", "anpi0", "en", "enx", "ap1", "gif0"] {
            #expect(!NetworkMath.isCounted(name), "\(name)")
        }
    }

    @Test func ratesSumInterfaces() throws {
        let old = [InterfaceCounters(name: "en0", received: 1000, sent: 500),
                   InterfaceCounters(name: "en1", received: 0, sent: 0)]
        let new = [InterfaceCounters(name: "en0", received: 5000, sent: 700),
                   InterfaceCounters(name: "en1", received: 2000, sent: 100)]
        let rates = try #require(NetworkMath.rates(from: old, to: new, seconds: 2))
        #expect(rates.down == 3000)
        #expect(rates.up == 150)
    }

    @Test func resetAndNewInterfacesAreSkipped() throws {
        let old = [InterfaceCounters(name: "en0", received: 10_000_000, sent: 10_000_000)]
        let new = [InterfaceCounters(name: "en0", received: 100, sent: 100),           // reset
                   InterfaceCounters(name: "en5", received: 9_000_000, sent: 9_000_000)] // new
        let rates = try #require(NetworkMath.rates(from: old, to: new, seconds: 1))
        #expect(rates == .zero)
    }

    @Test func noTimeIsNil() {
        #expect(NetworkMath.rates(from: [], to: [], seconds: 0) == nil)
        #expect(NetworkMath.rates(from: DiskIOCounters(read: 0, written: 0), to: DiskIOCounters(read: 1, written: 1), seconds: 0) == nil)
    }

    @Test func diskRates() throws {
        let rates = try #require(NetworkMath.rates(from: DiskIOCounters(read: 100, written: 0),
                                                   to: DiskIOCounters(read: 2100, written: 4000), seconds: 2))
        #expect(rates.down == 1000)
        #expect(rates.up == 2000)
        #expect(NetworkMath.rates(from: DiskIOCounters(read: 100, written: 0), to: DiskIOCounters(read: 0, written: 0),
                                  seconds: 1) == nil)
    }
}
