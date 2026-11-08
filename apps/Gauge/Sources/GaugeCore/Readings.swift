import Foundation

// Raw readings, exactly as the system reports them. Everything Gauge shows is computed
// from these by the pure functions in CPUMath, MemoryMath, NetworkMath and friends, so the
// maths is tested against fakes and never needs the real system.

/// Cumulative scheduler ticks for one logical CPU (`host_processor_info`). 32-bit counters
/// that wrap, so deltas use wrapping subtraction.
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// One kind of core (Performance, Efficiency, or whatever a future chip adds) and which
/// logical CPUs belong to it.
public struct CoreGroup: Sendable, Equatable {
    public var name: String
    public var cpus: [Int]

    public init(name: String, cpus: [Int]) {
        self.name = name
        self.cpus = cpus
    }
}

/// `host_statistics64(HOST_VM_INFO64)` page counts plus the pager counters.
public struct VMCounters: Sendable, Equatable {
    public var pageSize: UInt64
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var speculative: UInt64
    public var wired: UInt64
    /// Pages the compressor occupies (`compressor_page_count`).
    public var compressor: UInt64
    public var purgeable: UInt64
    /// File-backed pages (`external_page_count`).
    public var external: UInt64
    /// Anonymous pages (`internal_page_count`).
    public var `internal`: UInt64
    public var pageins: UInt64
    public var pageouts: UInt64
    public var swapins: UInt64
    public var swapouts: UInt64

    public init(pageSize: UInt64 = 16384, free: UInt64 = 0, active: UInt64 = 0, inactive: UInt64 = 0,
                speculative: UInt64 = 0, wired: UInt64 = 0, compressor: UInt64 = 0, purgeable: UInt64 = 0,
                external: UInt64 = 0, internal: UInt64 = 0, pageins: UInt64 = 0, pageouts: UInt64 = 0,
                swapins: UInt64 = 0, swapouts: UInt64 = 0) {
        self.pageSize = pageSize
        self.free = free
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressor = compressor
        self.purgeable = purgeable
        self.external = external
        self.internal = `internal`
        self.pageins = pageins
        self.pageouts = pageouts
        self.swapins = swapins
        self.swapouts = swapouts
    }
}

/// Everything about memory in one read.
public struct MemoryReading: Sendable, Equatable {
    public var vm: VMCounters
    public var totalBytes: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public var pressureLevel: Int
    /// `kern.memorystatus_level`: percent of memory the system considers available.
    public var availablePercent: Int

    public init(vm: VMCounters, totalBytes: UInt64, swapUsed: UInt64 = 0, swapTotal: UInt64 = 0,
                pressureLevel: Int = 1, availablePercent: Int = 100) {
        self.vm = vm
        self.totalBytes = totalBytes
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressureLevel = pressureLevel
        self.availablePercent = availablePercent
    }
}

/// 64-bit byte counters for one network interface (`NET_RT_IFLIST2` / `if_data64`).
public struct InterfaceCounters: Sendable, Equatable {
    public var name: String
    public var received: UInt64
    public var sent: UInt64

    public init(name: String, received: UInt64, sent: UInt64) {
        self.name = name
        self.received = received
        self.sent = sent
    }
}

/// Bytes read and written by every block storage driver, summed.
public struct DiskIOCounters: Sendable, Equatable {
    public var read: UInt64
    public var written: UInt64

    public init(read: UInt64, written: UInt64) {
        self.read = read
        self.written = written
    }
}

/// A mounted volume someone would recognise (no hidden system volumes).
public struct VolumeInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Free space as Finder counts it (includes purgeable space).
    public var available: UInt64
    public var total: UInt64
    public var isInternal: Bool
    public var isBoot: Bool

    public init(id: String, name: String, available: UInt64, total: UInt64, isInternal: Bool = true, isBoot: Bool = false) {
        self.id = id
        self.name = name
        self.available = available
        self.total = total
        self.isInternal = isInternal
        self.isBoot = isBoot
    }

    public var used: UInt64 { total > available ? total - available : 0 }
    /// 0...1
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

/// The internal battery, if there is one.
public struct BatteryInfo: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case battery
        case powerAdapter
    }

    public var percent: Int
    public var source: Source
    public var isCharging: Bool
    public var isCharged: Bool
    /// nil while macOS is still estimating.
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var adapterWatts: Int?
    public var cycleCount: Int?
    /// Maximum capacity as a percent of design capacity (System Settings › Battery's number).
    public var healthPercent: Int?

    public init(percent: Int, source: Source, isCharging: Bool = false, isCharged: Bool = false,
                minutesToEmpty: Int? = nil, minutesToFull: Int? = nil, adapterWatts: Int? = nil,
                cycleCount: Int? = nil, healthPercent: Int? = nil) {
        self.percent = percent
        self.source = source
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
        self.adapterWatts = adapterWatts
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }
}

/// `ProcessInfo.thermalState`, in our words.
public enum ThermalLevel: Int, Sendable, Equatable, CaseIterable {
    case nominal, fair, serious, critical

    public var title: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    public var explanation: String {
        switch self {
        case .nominal: "Your Mac isn't limiting performance to stay cool."
        case .fair: "Your Mac is warm. Fans may run faster."
        case .serious: "Your Mac is hot and is slowing down to cool off."
        case .critical: "Your Mac is very hot and is slowing down a lot to cool off."
        }
    }
}

/// The primary network connection, read when the panel opens.
public struct NetworkInfo: Sendable, Equatable {
    /// BSD name, e.g. "en0".
    public var interface: String
    /// "Wi-Fi", "Ethernet", "Thunderbolt Bridge"…
    public var kind: String
    public var ipv4: String?
    public var ipv6: String?

    public init(interface: String, kind: String, ipv4: String? = nil, ipv6: String? = nil) {
        self.interface = interface
        self.kind = kind
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }
}

/// Load averages and uptime.
public struct SystemLoad: Sendable, Equatable {
    public var oneMinute: Double
    public var fiveMinutes: Double
    public var fifteenMinutes: Double
    public var uptime: TimeInterval

    public init(oneMinute: Double, fiveMinutes: Double, fifteenMinutes: Double, uptime: TimeInterval) {
        self.oneMinute = oneMinute
        self.fiveMinutes = fiveMinutes
        self.fifteenMinutes = fifteenMinutes
        self.uptime = uptime
    }
}
