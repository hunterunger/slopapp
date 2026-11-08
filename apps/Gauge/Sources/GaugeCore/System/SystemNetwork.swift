import Darwin
import Foundation
import SystemConfiguration

/// Interface byte counters from `sysctl(NET_RT_IFLIST2)` (64-bit, unlike `getifaddrs`' 32-bit
/// ones that wrap every 4 GB), and the primary connection from SystemConfiguration.
public final class SystemNetwork: NetworkSource {
    private var buffer: [UInt8] = []
    /// "Wi-Fi", "Ethernet"… by BSD name (listing every interface costs a few milliseconds).
    private var kinds: [String: String] = [:]
    private var store: SCDynamicStore?
    private var names: [UInt16: String] = [:]

    public init() {}

    /// Counted interfaces with a link, by index, found with a full listing every 10 s. Each
    /// tick then asks only for those: a full listing walks every tunnel, AirDrop and idle
    /// Thunderbolt interface too, and costs ten times as much.
    private var counted: [UInt16] = []
    private var listedAt: Double = -.infinity
    private let clock = SystemClock()

    public func counters() -> [InterfaceCounters] {
        let now = clock.now()
        if now - listedAt >= 10 {
            listedAt = now
            let all = read(index: 0)
            counted = all.filter(\.running).map(\.index)
            return all.map(\.counters)
        }
        var result: [InterfaceCounters] = []
        for index in counted {
            let found = read(index: index)
            if found.isEmpty { listedAt = -.infinity } // it went away: list again next tick
            result.append(contentsOf: found.map(\.counters))
        }
        return result
    }

    /// One interface's counters (or every counted interface's, for index 0).
    private func read(index: UInt16) -> [(index: UInt16, counters: InterfaceCounters, running: Bool)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var length = buffer.count
        // One call when the buffer is big enough (always, for a single interface); otherwise
        // ask for the size first.
        if buffer.isEmpty || sysctl(&mib, 6, &buffer, &length, nil, 0) != 0 {
            length = 0
            guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
            buffer = [UInt8](repeating: 0, count: length + 4096)
            guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [] }
        }

        var result: [(UInt16, InterfaceCounters, Bool)] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let name = self.name(for: message.ifm_index), NetworkMath.isCounted(name) {
                        let running = message.ifm_flags & Int32(IFF_RUNNING) != 0
                        result.append((message.ifm_index, InterfaceCounters(name: name, received: message.ifm_data.ifi_ibytes,
                                                                             sent: message.ifm_data.ifi_obytes), running))
                    }
                }
                offset += size
            }
        }
        return result
    }

    /// Interface names by index, cached (an index keeps its name until the interface goes).
    private func name(for index: UInt16) -> String? {
        if let name = names[index] { return name }
        var bytes = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(UInt32(index), &bytes) != nil else { return nil }
        let name = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        names[index] = name
        return name
    }

    public func primary() -> NetworkInfo? {
        if store == nil { store = SCDynamicStoreCreate(nil, "Gauge" as CFString, nil, nil) }
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let interface = global["PrimaryInterface"] as? String else { return nil }
        var kind = kinds[interface] ?? interface
        if kinds[interface] == nil, let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for candidate in all where SCNetworkInterfaceGetBSDName(candidate) as String? == interface {
                kind = SCNetworkInterfaceGetLocalizedDisplayName(candidate) as String? ?? interface
            }
            kinds[interface] = kind
        }
        if interface.hasPrefix("utun") || interface.hasPrefix("ipsec") { kind = "VPN" }
        let (ipv4, ipv6) = Self.addresses(of: interface)
        return NetworkInfo(interface: interface, kind: kind, ipv4: ipv4, ipv6: ipv6)
    }

    /// The interface's IPv4 address and first global IPv6 address.
    static func addresses(of interface: String) -> (String?, String?) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (nil, nil) }
        defer { freeifaddrs(list) }
        var ipv4: String?
        var ipv6: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, String(cString: entry.pointee.ifa_name) == interface else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if family == AF_INET, ipv4 == nil {
                ipv4 = text
            } else if family == AF_INET6, ipv6 == nil, !text.lowercased().hasPrefix("fe80") {
                ipv6 = text
            }
        }
        return (ipv4, ipv6)
    }
}

/// GPU utilisation from each accelerator's "PerformanceStatistics" (public IOKit,
/// undocumented key). The busiest GPU wins on Macs with two.
public final class SystemGPU: GPUSource {
    public init() {}

    public func utilization() -> Double? {
        var best: Double?
        IOKitProperty.forEachService("IOAccelerator") { entry in
            guard let stats = IOKitProperty.dictionary(entry, "PerformanceStatistics"),
                  let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { return }
            best = max(best ?? 0, value.doubleValue / 100)
        }
        return best
    }
}

/// Bytes read and written by physical disks. The drivers are found once a minute (disk
/// images are left out: their reads are counted again on the disk underneath), and each tick
/// only reads their statistics.
public final class SystemDiskIO: DiskIOSource {
    private var drivers: [io_registry_entry_t] = []
    private var foundAt: Double = -.infinity
    private let clock = SystemClock()

    public init() {}

    deinit { drivers.forEach { IOObjectRelease($0) } }

    public func counters() -> DiskIOCounters? {
        let now = clock.now()
        if now - foundAt >= 60 || drivers.isEmpty { findDrivers(now: now) }
        var read: UInt64 = 0
        var written: UInt64 = 0
        var found = false
        for entry in drivers {
            guard let stats = IOKitProperty.dictionary(entry, "Statistics") else {
                foundAt = -.infinity // a driver went away: look again next tick
                continue
            }
            found = true
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return found ? DiskIOCounters(read: read, written: written) : nil
    }

    private func findDrivers(now: Double) {
        drivers.forEach { IOObjectRelease($0) }
        drivers = []
        foundAt = now
        IOKitProperty.forEachService("IOBlockStorageDriver") { entry in
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(parent) }
            let protocolInfo = IOKitProperty.dictionary(parent, "Protocol Characteristics")
            if protocolInfo?["Physical Interconnect"] as? String == "Virtual Interface" { return }
            IOObjectRetain(entry)
            drivers.append(entry)
        }
    }
}
