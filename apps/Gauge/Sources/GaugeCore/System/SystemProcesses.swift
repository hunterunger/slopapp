import Darwin
import Foundation

/// Every process this user may inspect, via libproc. Root and other users' processes fail
/// `proc_pid_rusage` and are reported as unreadable, for `ps` to fill in.
public final class SystemProcesses: ProcessSource {
    private var pids = [Int32](repeating: 0, count: 4096)
    private var names: [ProcessKey: (name: String, path: String?)] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(1, info.denom)))
    }()

    public init() {}

    public func sweep() -> ProcessSweep {
        var count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        if count >= pids.count {
            pids = [Int32](repeating: 0, count: Int(count) * 2)
            count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride))
        }
        guard count > 0 else { return ProcessSweep(samples: []) }
        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(count))
        var unreadable = Set<Int32>()
        var live = Set<ProcessKey>()
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else {
                unreadable.insert(pid)
                continue
            }
            let key = ProcessKey(pid: pid, start: usage.ri_proc_start_abstime)
            live.insert(key)
            let identity = names[key] ?? {
                let identity = Self.identity(of: pid)
                names[key] = identity
                return identity
            }()
            // CPU times are in mach time units (not nanoseconds on Apple silicon).
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            let nanoseconds = ticks.multipliedFullWidth(by: timebase.numer)
            let cpu = timebase.numer == timebase.denom || nanoseconds.high >= timebase.denom
                ? ticks
                : timebase.denom.dividingFullWidth(nanoseconds).quotient
            samples.append(ProcessSample(key: key, name: identity.name, path: identity.path,
                                         cpuTime: cpu, memory: usage.ri_phys_footprint))
        }
        // Forget processes that are gone.
        if names.count > live.count * 2 { names = names.filter { live.contains($0.key) } }
        return ProcessSweep(samples: samples, unreadable: unreadable)
    }

    static func identity(of pid: Int32) -> (name: String, path: String?) {
        var pathBuffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? String(decoding: pathBuffer.prefix(Int(pathLength)), as: UTF8.self) : nil
        var nameBuffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        var name = nameLength > 0 ? String(decoding: nameBuffer.prefix(Int(nameLength)), as: UTF8.self) : ""
        // proc_name cuts at 32 bytes; the path has the whole name.
        if let path, let last = path.split(separator: "/").last, last.hasPrefix(name) || name.isEmpty {
            name = String(last)
        }
        return (name.isEmpty ? "PID \(pid)" : name, path)
    }
}

/// Runs `/bin/ps` (setuid, so it sees root processes) with a C locale, with a timeout.
public final class SystemPS: PSRunner {
    public init() {}

    public func run() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid,time,rss,comm"]
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchTime.now() + .seconds(3)
        let reader = DispatchQueue.global(qos: .utility)
        nonisolated(unsafe) var data = Data()
        let done = DispatchSemaphore(value: 0)
        reader.async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        // Lenient: ps can cut a name in the middle of a UTF-8 sequence.
        return String(decoding: data, as: UTF8.self)
    }
}
