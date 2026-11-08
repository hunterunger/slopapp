import Foundation

/// Made-up but plausible readings for screenshots and reviews (`GAUGE_DEMO=1`), so they never
/// show the owner's real processes, volumes or network. Values drift smoothly over time, with
/// a burst of CPU every few minutes, so graphs look like a real afternoon.
public final class DemoWorld: @unchecked Sendable {
    private let clock: any MonotonicClock
    private let lock = NSLock()
    private var override: Double?

    public init(clock: any MonotonicClock) {
        self.clock = clock
    }

    /// Seconds, from the override while seeding history, else the clock.
    public var time: Double {
        lock.lock()
        defer { lock.unlock() }
        return override ?? clock.now()
    }

    public func setTime(_ time: Double?) {
        lock.lock()
        override = time
        lock.unlock()
    }

    /// 0...1 CPU load: a calm base, a slow swell, and a build every five minutes.
    public func cpuLoad(at t: Double) -> Double {
        let base = 0.11 + 0.05 * sin(t / 47) + 0.03 * sin(t / 7.3)
        let phase = t.truncatingRemainder(dividingBy: 300)
        let burst = phase < 40 ? 0.55 * sin(.pi * phase / 40) : 0
        return min(0.95, max(0.02, base + burst))
    }

    public func networkDown(at t: Double) -> Double {
        let phase = t.truncatingRemainder(dividingBy: 240)
        let download = phase > 150 && phase < 210 ? 2_400_000 + 600_000 * sin(t / 3) : 0
        return max(0, 18_000 + 12_000 * sin(t / 11) + download)
    }

    public func networkUp(at t: Double) -> Double { max(0, 9_000 + 6_000 * sin(t / 13 + 1)) }

    public func makeSources() -> (tick: TickSources, processes: any ProcessSource, volumes: any VolumeSource,
                                  battery: any BatterySource, network: any NetworkSource) {
        let network = DemoNetwork(world: self)
        return (TickSources(cpu: DemoCPU(world: self), memory: DemoMemory(world: self), network: network,
                            gpu: DemoGPU(world: self), diskIO: DemoDiskIO(world: self), load: DemoLoad(world: self)),
                DemoProcesses(world: self), DemoVolumes(), DemoBattery(), network)
    }
}

final class DemoCPU: CPUSource {
    let world: DemoWorld
    private var counters = [CPUTicks](repeating: CPUTicks(user: 0, system: 0, idle: 0), count: 14)
    private var last: Double?

    init(world: DemoWorld) { self.world = world }

    func ticks() -> [CPUTicks]? {
        let now = world.time
        defer { last = now }
        guard let last, now > last else { return counters }
        let total = (now - last) * 100
        let load = world.cpuLoad(at: now)
        for index in counters.indices {
            // Performance cores (4…13) carry most of a burst; efficiency cores stay busy.
            let share = index < 4 ? min(1, load * 0.6 + 0.2) : min(1, load * (0.8 + 0.05 * Double(index % 5)))
            let busy = UInt32(total * share)
            counters[index].user &+= busy * 2 / 3
            counters[index].system &+= busy - busy * 2 / 3
            counters[index].idle &+= UInt32(total) - min(UInt32(total), busy)
        }
        return counters
    }

    func coreGroups() -> [CoreGroup] {
        [CoreGroup(name: "Performance", cpus: Array(4..<14)), CoreGroup(name: "Efficiency", cpus: Array(0..<4))]
    }
}

final class DemoMemory: MemorySource {
    let world: DemoWorld
    init(world: DemoWorld) { self.world = world }

    func read() -> MemoryReading? {
        let t = world.time
        let page: UInt64 = 16384
        let total: UInt64 = 36 << 30
        let pages = total / page
        let app = UInt64(Double(pages) * (0.42 + 0.03 * sin(t / 90)))
        let available = Int(66 + 4 * sin(t / 90))
        return MemoryReading(
            vm: VMCounters(pageSize: page, free: pages / 20, wired: pages / 9, compressor: pages / 30, purgeable: pages / 100,
                           external: pages / 5, internal: app + pages / 100,
                           pageins: UInt64(t * 40), pageouts: UInt64(t * 0.5)),
            totalBytes: total, swapUsed: 512 << 20, swapTotal: 2 << 30, pressureLevel: 1, availablePercent: available)
    }
}

final class DemoNetwork: NetworkSource {
    let world: DemoWorld
    private var received: Double = 40_000_000_000
    private var sent: Double = 3_000_000_000
    private var last: Double?
    init(world: DemoWorld) { self.world = world }

    func counters() -> [InterfaceCounters] {
        let now = world.time
        if let last, now > last {
            received += world.networkDown(at: now) * (now - last)
            sent += world.networkUp(at: now) * (now - last)
        }
        last = now
        return [InterfaceCounters(name: "en0", received: UInt64(received), sent: UInt64(sent))]
    }

    func primary() -> NetworkInfo? {
        NetworkInfo(interface: "en0", kind: "Wi-Fi", ipv4: "192.168.1.24", ipv6: nil)
    }
}

final class DemoGPU: GPUSource {
    let world: DemoWorld
    init(world: DemoWorld) { self.world = world }
    func utilization() -> Double? { min(1, max(0, 0.08 + 0.06 * sin(world.time / 17) + world.cpuLoad(at: world.time) * 0.2)) }
}

final class DemoDiskIO: DiskIOSource {
    let world: DemoWorld
    private var read: Double = 9e11
    private var written: Double = 6e11
    private var last: Double?
    init(world: DemoWorld) { self.world = world }

    func counters() -> DiskIOCounters? {
        let now = world.time
        if let last, now > last {
            let load = world.cpuLoad(at: now)
            read += (200_000 + 30_000_000 * max(0, load - 0.3)) * (now - last)
            written += (350_000 + 12_000_000 * max(0, load - 0.3)) * (now - last)
        }
        last = now
        return DiskIOCounters(read: UInt64(read), written: UInt64(written))
    }
}

final class DemoLoad: LoadSource {
    let world: DemoWorld
    init(world: DemoWorld) { self.world = world }
    func load() -> SystemLoad {
        let load = world.cpuLoad(at: world.time) * 14
        return SystemLoad(oneMinute: load, fiveMinutes: load * 0.8 + 0.6, fifteenMinutes: 2.1, uptime: 3 * 86_400 + 4 * 3600 + 12 * 60)
    }
}

final class DemoProcesses: ProcessSource {
    let world: DemoWorld
    private var cpu: [Int32: Double] = [:]
    private var last: Double?
    init(world: DemoWorld) { self.world = world }

    /// (pid, name, path, share of the CPU load in cores, memory)
    private static let table: [(Int32, String, String?, Double, UInt64)] = [
        (401, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", 0.9, 1_450 << 20),
        (402, "Safari Web Content", "/Applications/Safari.app/Contents/XPCServices/Web.xpc/Contents/MacOS/Web", 1.4, 2_100 << 20),
        (512, "Music", "/System/Applications/Music.app/Contents/MacOS/Music", 0.35, 610 << 20),
        (533, "Mail", "/System/Applications/Mail.app/Contents/MacOS/Mail", 0.2, 820 << 20),
        (540, "Photos", "/System/Applications/Photos.app/Contents/MacOS/Photos", 0.15, 960 << 20),
        (601, "Notes", "/System/Applications/Notes.app/Contents/MacOS/Notes", 0.05, 240 << 20),
        (622, "Preview", "/System/Applications/Preview.app/Contents/MacOS/Preview", 0.03, 180 << 20),
        (700, "swift-frontend", "/usr/bin/swift-frontend", 4.5, 1_300 << 20),
        (88, "Finder", "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", 0.08, 310 << 20),
    ]

    func sweep() -> ProcessSweep {
        let now = world.time
        let elapsed = last.map { max(0, now - $0) } ?? 0
        last = now
        let load = world.cpuLoad(at: now)
        var samples: [ProcessSample] = []
        for (pid, name, path, share, memory) in Self.table {
            // The compiler is the burst; everything else hums along.
            let cores = pid == 700 ? max(0, load - 0.2) * share : share * (0.6 + load)
            cpu[pid, default: 0] += cores * elapsed
            samples.append(ProcessSample(key: ProcessKey(pid: pid, start: 1), name: name, path: path,
                                         cpuTime: UInt64(cpu[pid]! * 1e9), memory: memory))
        }
        return ProcessSweep(samples: samples, unreadable: [])
    }
}

final class DemoVolumes: VolumeSource {
    func volumes() -> [VolumeInfo] {
        [VolumeInfo(id: "/", name: "Macintosh HD", available: 412_300_000_000, total: 994_660_000_000, isInternal: true, isBoot: true),
         VolumeInfo(id: "/Volumes/Archive", name: "Archive", available: 1_240_000_000_000, total: 2_000_000_000_000, isInternal: false)]
    }
}

final class DemoBattery: BatterySource {
    func read(details: Bool) -> BatteryInfo? {
        BatteryInfo(percent: 84, source: .battery, minutesToEmpty: 192, cycleCount: details ? 182 : nil, healthPercent: details ? 94 : nil)
    }
}

/// A clock you set by hand (tests and seeding).
public final class ManualClock: MonotonicClock, @unchecked Sendable {
    public var time: Double
    public init(_ time: Double = 0) { self.time = time }
    public func now() -> TimeInterval { time }
}
