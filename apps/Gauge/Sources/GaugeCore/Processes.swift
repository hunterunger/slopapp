import Foundation

/// A process, told apart from a later one that reuses its PID by its start time.
public struct ProcessKey: Hashable, Sendable {
    public var pid: Int32
    /// Opaque start stamp (mach time); 0 when unknown (rows from `ps`).
    public var start: UInt64

    public init(pid: Int32, start: UInt64) {
        self.pid = pid
        self.start = start
    }
}

/// One process as read by `proc_pid_rusage`.
public struct ProcessSample: Sendable, Equatable {
    public var key: ProcessKey
    public var name: String
    /// Executable path, when readable.
    public var path: String?
    /// User + system CPU time, nanoseconds.
    public var cpuTime: UInt64
    /// Physical footprint (Activity Monitor's "Memory"), bytes.
    public var memory: UInt64

    public init(key: ProcessKey, name: String, path: String?, cpuTime: UInt64, memory: UInt64) {
        self.key = key
        self.name = name
        self.path = path
        self.cpuTime = cpuTime
        self.memory = memory
    }
}

public struct ProcessSweep: Sendable, Equatable {
    public var samples: [ProcessSample]
    /// PIDs that exist but can't be read as this user (root, other users).
    public var unreadable: Set<Int32>

    public init(samples: [ProcessSample], unreadable: Set<Int32> = []) {
        self.samples = samples
        self.unreadable = unreadable
    }
}

/// One row of `ps -Aceo pid,time,rss,comm`.
public struct PSRow: Sendable, Equatable {
    public var pid: Int32
    /// Cumulative CPU time, nanoseconds.
    public var cpuTime: UInt64
    /// Resident memory, bytes (ps can't see footprint).
    public var memory: UInt64
    public var name: String

    public init(pid: Int32, cpuTime: UInt64, memory: UInt64, name: String) {
        self.pid = pid
        self.cpuTime = cpuTime
        self.memory = memory
        self.name = name
    }
}

public enum PSParser {
    /// Parses `ps -Aceo pid,time,rss,comm` (run with `LC_ALL=C`). Skips the header and any line
    /// it can't read rather than failing the lot. Names keep their spaces and are decoded
    /// leniently by the caller, since `ps` can cut a name in the middle of a UTF-8 character.
    public static func parse(_ output: String) -> [PSRow] {
        var rows: [PSRow] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let time = cpuTime(fields[1]),
                  let rss = UInt64(fields[2]) else { continue }
            let name = fields[3].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            rows.append(PSRow(pid: pid, cpuTime: time, memory: rss * 1024, name: name))
        }
        return rows
    }

    /// "114:08.71", "1:02:03.45", "2-03:04:05.00" (days-hours:minutes:seconds) in nanoseconds.
    public static func cpuTime<S: StringProtocol>(_ text: S) -> UInt64? {
        var days = 0.0
        var rest = Substring(text)
        if let dash = rest.firstIndex(of: "-") {
            guard let value = Double(rest[..<dash]) else { return nil }
            days = value
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), let seconds = Double(parts.last!.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        var total = seconds
        var multiplier = 60.0
        for part in parts.dropLast().reversed() {
            guard let value = Double(part) else { return nil }
            total += value * multiplier
            multiplier *= 60
        }
        total += days * 86_400
        guard total >= 0, total.isFinite else { return nil }
        return UInt64(total * 1e9)
    }
}

/// A process's usage between two sweeps.
public struct ProcessUsage: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    public var path: String?
    /// The outermost `.app` the executable is in (`AppGrouping.appPath(for:)`), resolved once
    /// per process by the tracker.
    public var appPath: String?
    /// Activity Monitor's scale: 100 = one core fully busy. Nil on the first sighting.
    public var cpuPercent: Double?
    public var memory: UInt64
    /// Read through `ps` (root or another user's), so memory is resident size.
    public var isRestricted: Bool

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, path: String?, appPath: String? = nil, cpuPercent: Double?, memory: UInt64,
                isRestricted: Bool = false) {
        self.pid = pid
        self.name = name
        self.path = path
        self.appPath = appPath
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.isRestricted = isRestricted
    }
}

/// Turns sweeps into per-process CPU percentages, Activity Monitor style: the change in CPU
/// time over the change in wall time. Processes read through `ps` get theirs from the change
/// in `ps`'s cumulative time column between its runs.
public final class ProcessTracker {
    private var previous: [ProcessKey: UInt64] = [:]
    private var previousTime: Double?
    private var psPrevious: [Int32: (name: String, cpuTime: UInt64)] = [:]
    private var psPreviousTime: Double?
    /// Latest `ps` usage for the PIDs a sweep can't read.
    private var psUsage: [Int32: ProcessUsage] = [:]
    /// Each process's app bundle, worked out once (string searching every path every second
    /// adds up over a thousand processes).
    private var apps: [ProcessKey: String?] = [:]

    public init() {}

    /// Forget everything (the panel closed, or the Mac slept).
    public func reset() {
        apps = [:]
        previous = [:]
        previousTime = nil
        psPrevious = [:]
        psPreviousTime = nil
        psUsage = [:]
    }

    public func update(ps rows: [PSRow], at time: Double) {
        let elapsed = psPreviousTime.map { time - $0 } ?? 0
        var next: [Int32: (String, UInt64)] = [:]
        var usage: [Int32: ProcessUsage] = [:]
        for row in rows {
            next[row.pid] = (row.name, row.cpuTime)
            var percent: Double?
            // Same PID and name, and the time didn't go backwards: the same process.
            if elapsed > 0, let old = psPrevious[row.pid], old.name == row.name, row.cpuTime >= old.cpuTime {
                percent = Double(row.cpuTime - old.cpuTime) / (elapsed * 1e9) * 100
            }
            usage[row.pid] = ProcessUsage(pid: row.pid, name: row.name, path: nil, cpuPercent: percent,
                                          memory: row.memory, isRestricted: true)
        }
        psPrevious = next
        psPreviousTime = time
        psUsage = usage
    }

    /// Usage for every process in `sweep`, plus `ps`'s rows for the ones it couldn't read.
    public func update(sweep: ProcessSweep, at time: Double) -> [ProcessUsage] {
        let elapsed = previousTime.map { time - $0 } ?? 0
        var next: [ProcessKey: UInt64] = [:]
        next.reserveCapacity(sweep.samples.count)
        var result: [ProcessUsage] = []
        result.reserveCapacity(sweep.samples.count + sweep.unreadable.count)
        var seen = Set<Int32>()
        for sample in sweep.samples {
            next[sample.key] = sample.cpuTime
            seen.insert(sample.key.pid)
            var percent: Double?
            if elapsed > 0, let old = previous[sample.key], sample.cpuTime >= old {
                percent = Double(sample.cpuTime - old) / (elapsed * 1e9) * 100
            }
            let app: String?
            if let known = apps[sample.key] {
                app = known
            } else {
                app = AppGrouping.appPath(for: sample.path)
                apps[sample.key] = .some(app)
            }
            result.append(ProcessUsage(pid: sample.key.pid, name: sample.name, path: sample.path, appPath: app,
                                       cpuPercent: percent, memory: sample.memory))
        }
        if apps.count > next.count * 2 { apps = apps.filter { next[$0.key] != nil } }
        for pid in sweep.unreadable where !seen.contains(pid) {
            if let usage = psUsage[pid] { result.append(usage) }
        }
        previous = next
        previousTime = time
        return result
    }
}

/// Processes rolled up into the app they belong to (a browser and all its helpers), or kept
/// alone when they don't belong to an app.
public struct ProcessGroup: Sendable, Equatable, Identifiable {
    /// The app bundle's path, or "name:<name>" for processes outside an app.
    public var id: String
    public var name: String
    /// The outermost `.app` bundle, if any (for its icon).
    public var appPath: String?
    public var cpuPercent: Double
    public var memory: UInt64
    public var pids: [Int32]
    /// Any member was read through `ps`.
    public var isRestricted: Bool

    public init(id: String, name: String, appPath: String?, cpuPercent: Double, memory: UInt64, pids: [Int32], isRestricted: Bool) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.cpuPercent = cpuPercent
        self.memory = memory
        self.pids = pids
        self.isRestricted = isRestricted
    }

    public var count: Int { pids.count }
}

public enum ProcessSort: Sendable {
    case cpu, memory
}

public enum AppGrouping {
    /// The outermost `.app` in an executable path: Chrome's renderer helpers belong to
    /// "/Applications/Google Chrome.app".
    public static func appPath(for executable: String?) -> String? {
        guard let executable, executable.hasPrefix("/") else { return nil }
        guard let range = executable.range(of: ".app/") else {
            return executable.hasSuffix(".app") ? executable : nil
        }
        return String(executable[..<range.lowerBound]) + ".app"
    }

    /// "Google Chrome" for "/Applications/Google Chrome.app".
    public static func appName(for appPath: String) -> String {
        let last = (appPath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    /// Groups by app when `byApp`, otherwise one group per process. Processes outside an app
    /// are grouped by name when `byApp` (four `node` processes read as one row of four).
    public static func group(_ processes: [ProcessUsage], byApp: Bool) -> [ProcessGroup] {
        guard byApp else {
            return processes.map { process in
                ProcessGroup(id: "pid:\(process.pid)", name: process.name, appPath: process.appPath,
                             cpuPercent: process.cpuPercent ?? 0, memory: process.memory, pids: [process.pid],
                             isRestricted: process.isRestricted)
            }
        }
        struct Key: Hashable {
            let app: String?
            let name: String
        }
        var groups: [Key: ProcessGroup] = [:]
        groups.reserveCapacity(processes.count)
        var order: [Key] = []
        for process in processes {
            let key = process.appPath.map { Key(app: $0, name: "") } ?? Key(app: nil, name: process.name)
            if groups[key] == nil {
                groups[key] = ProcessGroup(id: process.appPath ?? "name:" + process.name,
                                           name: process.appPath.map(appName(for:)) ?? process.name, appPath: process.appPath,
                                           cpuPercent: 0, memory: 0, pids: [], isRestricted: false)
                order.append(key)
            }
            groups[key]!.cpuPercent += process.cpuPercent ?? 0
            groups[key]!.memory += process.memory
            groups[key]!.pids.append(process.pid)
            if process.isRestricted { groups[key]!.isRestricted = true }
        }
        return order.compactMap { groups[$0] }
    }

    /// The top `count` by CPU or memory. Ties keep a stable order by name, so rows don't swap
    /// places every second. Idle processes never make the CPU list.
    public static func top(_ groups: [ProcessGroup], by sort: ProcessSort, count: Int = 5) -> [ProcessGroup] {
        func before(_ a: ProcessGroup, _ b: ProcessGroup) -> Bool {
            switch sort {
            case .cpu:
                if a.cpuPercent != b.cpuPercent { return a.cpuPercent > b.cpuPercent }
            case .memory:
                if a.memory != b.memory { return a.memory > b.memory }
            }
            return a.name != b.name ? a.name < b.name : a.id < b.id
        }
        // One pass keeping the best `count` (a thousand processes, five rows: no full sort).
        var best: [Int] = []
        best.reserveCapacity(count + 1)
        for index in groups.indices {
            if sort == .cpu, groups[index].cpuPercent <= 0 { continue }
            if best.count == count, let last = best.last, !before(groups[index], groups[last]) { continue }
            let position = best.firstIndex { before(groups[index], groups[$0]) } ?? best.count
            best.insert(index, at: position)
            if best.count > count { best.removeLast() }
        }
        return best.map { groups[$0] }
    }

    /// "Safari, 34% CPU, 1.2 GB memory, PID 812" for ⌘C.
    public static func copyText(_ group: ProcessGroup, sort: ProcessSort, locale: Locale = .autoupdatingCurrent) -> String {
        var parts = [group.name]
        parts.append("\(Format.processPercent(group.cpuPercent, locale: locale)) CPU")
        parts.append("\(Format.memory(group.memory, locale: locale)) memory")
        if group.pids.count == 1 {
            parts.append("PID \(group.pids[0])")
        } else {
            parts.append("\(group.pids.count) processes")
        }
        return parts.joined(separator: ", ")
    }
}
