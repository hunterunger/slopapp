import Foundation

// Every system read goes through one of these protocols, so tests pass fakes and the demo
// mode (screenshots) never shows the owner's real processes or numbers. The real
// implementations are in System/. They're called from the sampling queue, never the main
// actor, and must be cheap: see the costs in docs/research/gauge.md.

public protocol CPUSource: AnyObject {
    /// Cumulative ticks per logical CPU, or nil if the read failed.
    func ticks() -> [CPUTicks]?
    /// Core kinds (Performance, Efficiency…). Read once.
    func coreGroups() -> [CoreGroup]
}

public protocol MemorySource: AnyObject {
    func read() -> MemoryReading?
}

public protocol NetworkSource: AnyObject {
    /// Counters for every interface Gauge counts (see `NetworkMath.isCounted`).
    func counters() -> [InterfaceCounters]
    /// The primary connection right now. Called only while the panel is open.
    func primary() -> NetworkInfo?
}

public protocol GPUSource: AnyObject {
    /// 0...1, or nil when the GPU doesn't report utilisation.
    func utilization() -> Double?
}

public protocol DiskIOSource: AnyObject {
    func counters() -> DiskIOCounters?
}

public protocol VolumeSource: AnyObject {
    /// Volumes people care about, boot volume first. May block on a network volume, so it
    /// runs on its own queue.
    func volumes() -> [VolumeInfo]
}

public protocol BatterySource: AnyObject {
    /// nil on a Mac without a battery. `details` adds cycle count and health (a registry
    /// read), only wanted while the panel is open.
    func read(details: Bool) -> BatteryInfo?
}

public protocol LoadSource: AnyObject {
    func load() -> SystemLoad
}

/// One sweep over every process this user may inspect.
public protocol ProcessSource: AnyObject {
    func sweep() -> ProcessSweep
}

/// Runs `/bin/ps` for the processes `ProcessSource` can't read (root and other users').
public protocol PSRunner: AnyObject {
    func run() -> String?
}

/// Monotonic seconds (`CLOCK_UPTIME_RAW`): doesn't jump with the wall clock, and doesn't
/// advance during sleep.
public protocol MonotonicClock: AnyObject {
    func now() -> TimeInterval
}

/// The sources read on every tick, bundled.
public struct TickSources {
    public var cpu: any CPUSource
    public var memory: any MemorySource
    public var network: any NetworkSource
    public var gpu: any GPUSource
    public var diskIO: any DiskIOSource
    public var load: any LoadSource

    public init(cpu: any CPUSource, memory: any MemorySource, network: any NetworkSource,
                gpu: any GPUSource, diskIO: any DiskIOSource, load: any LoadSource) {
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.gpu = gpu
        self.diskIO = diskIO
        self.load = load
    }
}
