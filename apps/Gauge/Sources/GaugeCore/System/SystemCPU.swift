import Darwin
import Foundation
import IOKit

/// `host_processor_info` ticks, and core kinds from sysctl and the device tree.
public final class SystemCPU: CPUSource {
    private let host = mach_host_self()

    public init() {}

    public func ticks() -> [CPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        var result: [CPUTicks] = []
        result.reserveCapacity(Int(count))
        for cpu in 0..<Int(count) {
            let base = cpu * states
            result.append(CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return result
    }

    public func coreGroups() -> [CoreGroup] {
        let logical = Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        let levels = Sysctl.int("hw.nperflevels") ?? 1
        guard levels > 1 else { return [CoreGroup(name: "Cores", cpus: Array(0..<logical))] }

        // Apple silicon: the device tree says which logical CPU is in which cluster.
        let clusters = Self.clusterTypes()
        let names = (0..<levels).map { Sysctl.string("hw.perflevel\($0).name") ?? "Level \($0)" }
        var groups: [CoreGroup] = []
        var assigned = Set<Int>()
        for name in names {
            // "Performance" ↔ "P", "Efficiency" ↔ "E"; any new kind matches on its initial.
            let letter = name.first.map { String($0).uppercased() } ?? "?"
            let cpus = clusters.filter { $0.value == letter }.map(\.key).sorted()
            guard !cpus.isEmpty else { continue }
            groups.append(CoreGroup(name: name, cpus: cpus))
            assigned.formUnion(cpus)
        }
        let rest = (0..<logical).filter { !assigned.contains($0) }
        if groups.isEmpty { return [CoreGroup(name: "Cores", cpus: Array(0..<logical))] }
        if !rest.isEmpty { groups.append(CoreGroup(name: "Other", cpus: rest)) }
        return groups
    }

    /// logical CPU id → cluster type letter ("E", "P"…), from `IODeviceTree:/cpus`.
    static func clusterTypes() -> [Int: String] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [Int: String] = [:]
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard let id = IOKitProperty.int(entry, "logical-cpu-id"),
                  let data = IOKitProperty.data(entry, "cluster-type"),
                  let letter = String(bytes: data.prefix { $0 != 0 }, encoding: .ascii), !letter.isEmpty else { continue }
            result[id] = letter
        }
        return result
    }
}

/// Small sysctl helpers.
enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4: return Int(Int32(truncatingIfNeeded: value))
        default: return Int(value)
        }
    }

    static func uint64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return size == 4 ? UInt64(UInt32(truncatingIfNeeded: value)) : value
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Registry property readers.
enum IOKitProperty {
    static func value(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func int(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        switch value(entry, key) {
        case let number as NSNumber: return number.intValue
        case let data as Data where data.count >= 4:
            return Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        default: return nil
        }
    }

    static func data(_ entry: io_registry_entry_t, _ key: String) -> Data? {
        value(entry, key) as? Data
    }

    static func dictionary(_ entry: io_registry_entry_t, _ key: String) -> [String: Any]? {
        value(entry, key) as? [String: Any]
    }

    /// Calls `body` for every service matching `className`, releasing each one.
    static func forEachService(_ className: String, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            body(entry)
            IOObjectRelease(entry)
        }
    }
}
