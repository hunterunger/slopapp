import Foundation

/// How hard macOS is working to find memory. The headline of the memory section: used
/// memory is always high on macOS (it caches files in free memory), pressure is what matters.
public enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical

    /// From `kern.memorystatus_vm_pressure_level` (1, 2, 4). Unknown values read as normal.
    public init(level: Int) {
        switch level {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

/// Memory the way Activity Monitor breaks it down, in bytes.
public struct MemoryStatus: Sendable, Equatable {
    public var total: UInt64
    /// Anonymous memory apps use, minus what they've marked purgeable.
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    /// File-backed and purgeable memory macOS can drop at once.
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure
    /// 0...1: how much of memory macOS considers spoken for (100 − available %).
    public var pressureFraction: Double

    public init(total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
                swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure, pressureFraction: Double) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.pressure = pressure
        self.pressureFraction = pressureFraction
    }

    /// App + wired + compressed, Activity Monitor's "Memory Used".
    public var used: UInt64 { min(total, app + wired + compressed) }
    /// What's left after used and cached.
    public var free: UInt64 {
        let taken = used + cached
        return total > taken ? total - taken : 0
    }
}

/// Pager activity per second, from two readings.
public struct PagingRates: Sendable, Equatable {
    public var pageinsPerSecond: Double
    public var pageoutsPerSecond: Double
    public var swapinsPerSecond: Double
    public var swapoutsPerSecond: Double
}

public enum MemoryMath {
    public static func status(_ reading: MemoryReading) -> MemoryStatus {
        let vm = reading.vm
        let page = vm.pageSize
        let anonymous = vm.internal > vm.purgeable ? vm.internal - vm.purgeable : 0
        let available = Double(min(100, max(0, reading.availablePercent)))
        return MemoryStatus(
            total: reading.totalBytes,
            app: anonymous * page,
            wired: vm.wired * page,
            compressed: vm.compressor * page,
            cached: (vm.external + vm.purgeable) * page,
            swapUsed: reading.swapUsed,
            swapTotal: reading.swapTotal,
            pressure: MemoryPressure(level: reading.pressureLevel),
            pressureFraction: (100 - available) / 100
        )
    }

    /// Nil when no time passed or a counter went backwards (a reset).
    public static func paging(from old: VMCounters, to new: VMCounters, seconds: TimeInterval) -> PagingRates? {
        guard seconds > 0, new.pageins >= old.pageins, new.pageouts >= old.pageouts,
              new.swapins >= old.swapins, new.swapouts >= old.swapouts else { return nil }
        return PagingRates(
            pageinsPerSecond: Double(new.pageins - old.pageins) / seconds,
            pageoutsPerSecond: Double(new.pageouts - old.pageouts) / seconds,
            swapinsPerSecond: Double(new.swapins - old.swapins) / seconds,
            swapoutsPerSecond: Double(new.swapouts - old.swapouts) / seconds
        )
    }
}
