import Darwin
import Foundation

/// `host_statistics64`, swap and memory-pressure sysctls.
public final class SystemMemory: MemorySource {
    private let host = mach_host_self()
    private let total = Sysctl.uint64("hw.memsize") ?? 0
    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    public init() {}

    public func read() -> MemoryReading? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let vm = VMCounters(
            pageSize: pageSize, free: UInt64(stats.free_count), active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count), speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count), external: UInt64(stats.external_page_count),
            internal: UInt64(stats.internal_page_count), pageins: stats.pageins, pageouts: stats.pageouts,
            swapins: stats.swapins, swapouts: stats.swapouts
        )
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        return MemoryReading(
            vm: vm, totalBytes: total,
            swapUsed: hasSwap ? swap.xsu_used : 0, swapTotal: hasSwap ? swap.xsu_total : 0,
            pressureLevel: Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1,
            availablePercent: Sysctl.int("kern.memorystatus_level") ?? 100
        )
    }
}

/// Load averages and uptime.
public final class SystemLoadSource: LoadSource {
    private let bootTime: Date? = {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1e6)
    }()

    public init() {}

    public func load() -> SystemLoad {
        var averages = [Double](repeating: 0, count: 3)
        _ = getloadavg(&averages, 3)
        let uptime = bootTime.map { Date().timeIntervalSince($0) } ?? ProcessInfo.processInfo.systemUptime
        return SystemLoad(oneMinute: averages[0], fiveMinutes: averages[1], fifteenMinutes: averages[2], uptime: uptime)
    }
}

/// `CLOCK_UPTIME_RAW`: monotonic, stops during sleep.
public final class SystemClock: MonotonicClock {
    public init() {}

    public func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9
    }
}
