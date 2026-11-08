import Foundation

/// The metrics Gauge keeps history for.
public enum Metric: String, Sendable, CaseIterable {
    case cpu, gpu, memory, networkDown, networkUp, diskRead, diskWrite
}

/// Everything measured on one tick.
public struct Snapshot: Sendable, Equatable {
    public var time: Double
    public var cpu: CPUUsage?
    public var gpu: Double?
    public var memory: MemoryStatus?
    public var paging: PagingRates?
    public var network: ByteRates?
    public var disk: ByteRates?
    public var load: SystemLoad?

    public init(time: Double, cpu: CPUUsage? = nil, gpu: Double? = nil, memory: MemoryStatus? = nil,
                paging: PagingRates? = nil, network: ByteRates? = nil, disk: ByteRates? = nil, load: SystemLoad? = nil) {
        self.time = time
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.paging = paging
        self.network = network
        self.disk = disk
        self.load = load
    }
}

/// Reads every cheap counter once per tick, turns them into rates and percentages, and keeps
/// the history. Not thread-safe: the app calls it from one serial queue only.
public final class GaugeEngine {
    public let sources: TickSources
    public let coreGroups: [CoreGroup]
    public private(set) var histories: [Metric: TimeSeries]
    public private(set) var latest: Snapshot?
    /// False once the GPU has failed to report utilisation a few times in a row: the GPU
    /// readout and section are hidden then.
    public private(set) var hasGPU = true

    private var previousTicks: [CPUTicks]?
    private var previousNetwork: (counters: [InterfaceCounters], time: Double)?
    private var previousDisk: (counters: DiskIOCounters, time: Double)?
    private var previousVM: (counters: VMCounters, time: Double)?
    private var gpuMisses = 0
    private var gpuEverRead = false

    public init(sources: TickSources) {
        self.sources = sources
        coreGroups = sources.cpu.coreGroups()
        histories = Dictionary(uniqueKeysWithValues: Metric.allCases.map { ($0, TimeSeries()) })
    }

    @discardableResult
    public func tick(at now: Double) -> Snapshot {
        var snapshot = Snapshot(time: now)

        if let ticks = sources.cpu.ticks() {
            if let previousTicks { snapshot.cpu = CPUMath.usage(from: previousTicks, to: ticks) }
            previousTicks = ticks
        }

        if let reading = sources.memory.read() {
            snapshot.memory = MemoryMath.status(reading)
            if let previousVM {
                snapshot.paging = MemoryMath.paging(from: previousVM.counters, to: reading.vm, seconds: now - previousVM.time)
            }
            previousVM = (reading.vm, now)
        }

        let network = sources.network.counters()
        if let previousNetwork {
            snapshot.network = NetworkMath.rates(from: previousNetwork.counters, to: network, seconds: now - previousNetwork.time)
        }
        previousNetwork = (network, now)

        if let disk = sources.diskIO.counters() {
            if let previousDisk {
                snapshot.disk = NetworkMath.rates(from: previousDisk.counters, to: disk, seconds: now - previousDisk.time)
            }
            previousDisk = (disk, now)
        }

        if hasGPU {
            if let gpu = sources.gpu.utilization() {
                snapshot.gpu = min(1, max(0, gpu))
                gpuMisses = 0
                gpuEverRead = true
            } else {
                gpuMisses += 1
                // Never read: give up after three tries. Read before: a longer grace, since
                // the driver can briefly drop the statistics while the GPU powers down.
                if gpuMisses >= (gpuEverRead ? 30 : 3) { hasGPU = false }
            }
        }

        snapshot.load = sources.load.load()

        record(snapshot)
        latest = snapshot
        return snapshot
    }

    private func record(_ snapshot: Snapshot) {
        let now = snapshot.time
        if let cpu = snapshot.cpu { histories[.cpu]?.append(cpu.total, at: now) }
        if let gpu = snapshot.gpu { histories[.gpu]?.append(gpu, at: now) }
        if let memory = snapshot.memory { histories[.memory]?.append(memory.pressureFraction, at: now) }
        if let network = snapshot.network {
            histories[.networkDown]?.append(network.down, at: now)
            histories[.networkUp]?.append(network.up, at: now)
        }
        if let disk = snapshot.disk {
            histories[.diskRead]?.append(disk.down, at: now)
            histories[.diskWrite]?.append(disk.up, at: now)
        }
    }

    /// Sampling stopped (sleep, display sleep): history gets a gap, and the counters are
    /// forgotten so the first reading after waking becomes the new baseline instead of a
    /// spike.
    public func pause(at now: Double) {
        for metric in Metric.allCases { histories[metric]?.appendGap(at: now) }
        previousTicks = nil
        previousNetwork = nil
        previousDisk = nil
        previousVM = nil
        latest = nil
    }

    /// Takes a baseline reading without recording anything (right after waking).
    public func prime(at now: Double) {
        previousTicks = sources.cpu.ticks()
        previousNetwork = (sources.network.counters(), now)
        previousDisk = sources.diskIO.counters().map { ($0, now) }
        previousVM = sources.memory.read().map { ($0.vm, now) }
    }

    /// The values the menu bar shows, from the latest tick.
    public func readoutValues(bootVolumeFree: UInt64?, battery: BatteryInfo?) -> ReadoutValues {
        ReadoutValues(cpu: latest?.cpu?.total, gpu: latest?.gpu, memoryPressure: latest?.memory?.pressureFraction,
                      network: latest?.network, bootVolumeFree: bootVolumeFree, battery: battery)
    }
}
