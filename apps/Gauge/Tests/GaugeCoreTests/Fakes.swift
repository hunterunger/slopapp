import Foundation
@testable import GaugeCore

final class FakeCPU: CPUSource {
    var readings: [[CPUTicks]?]
    var groups: [CoreGroup]
    init(_ readings: [[CPUTicks]?], groups: [CoreGroup] = [CoreGroup(name: "Cores", cpus: [0, 1])]) {
        self.readings = readings
        self.groups = groups
    }
    func ticks() -> [CPUTicks]? { readings.isEmpty ? nil : readings.removeFirst() }
    func coreGroups() -> [CoreGroup] { groups }
}

final class FakeMemory: MemorySource {
    var reading: MemoryReading?
    init(_ reading: MemoryReading? = MemoryReading(vm: VMCounters(), totalBytes: 16 << 30, availablePercent: 70)) {
        self.reading = reading
    }
    func read() -> MemoryReading? { reading }
}

final class FakeNetwork: NetworkSource {
    var readings: [[InterfaceCounters]]
    var info: NetworkInfo?
    init(_ readings: [[InterfaceCounters]] = []) { self.readings = readings }
    func counters() -> [InterfaceCounters] { readings.isEmpty ? [] : readings.removeFirst() }
    func primary() -> NetworkInfo? { info }
}

final class FakeGPU: GPUSource {
    var values: [Double?]
    init(_ values: [Double?] = []) { self.values = values }
    func utilization() -> Double? { values.isEmpty ? nil : values.removeFirst() }
}

final class FakeDiskIO: DiskIOSource {
    var readings: [DiskIOCounters?]
    init(_ readings: [DiskIOCounters?] = []) { self.readings = readings }
    func counters() -> DiskIOCounters? { readings.isEmpty ? nil : readings.removeFirst() }
}

final class FakeLoad: LoadSource {
    func load() -> SystemLoad { SystemLoad(oneMinute: 1.5, fiveMinutes: 1.25, fifteenMinutes: 1, uptime: 3600) }
}

final class FakeProcesses: ProcessSource {
    var sweeps: [ProcessSweep]
    var calls = 0
    init(_ sweeps: [ProcessSweep] = []) { self.sweeps = sweeps }
    func sweep() -> ProcessSweep {
        calls += 1
        return sweeps.isEmpty ? ProcessSweep(samples: []) : sweeps.removeFirst()
    }
}

final class MemoryStorage: PreferenceStorage {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
}

/// Two cores; `busy` of every 100 ticks per core are user time.
func ticks(_ step: Int, busy: UInt32 = 25) -> [CPUTicks] {
    let n = UInt32(step) * 100
    return [CPUTicks(user: n * busy / 100, system: 0, idle: n - n * busy / 100),
            CPUTicks(user: n * busy / 100, system: 0, idle: n - n * busy / 100)]
}

func sources(cpu: FakeCPU = FakeCPU([]), memory: FakeMemory = FakeMemory(), network: FakeNetwork = FakeNetwork(),
             gpu: FakeGPU = FakeGPU(), disk: FakeDiskIO = FakeDiskIO()) -> TickSources {
    TickSources(cpu: cpu, memory: memory, network: network, gpu: gpu, diskIO: disk, load: FakeLoad())
}

let us = Locale(identifier: "en_US")
