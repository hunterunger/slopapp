import Foundation

/// CPU usage between two tick readings. Fractions are 0...1 of the whole chip (all cores).
public struct CPUUsage: Sendable, Equatable {
    public var user: Double
    public var system: Double
    /// Per logical CPU, 0...1.
    public var perCore: [Double]

    public init(user: Double, system: Double, perCore: [Double]) {
        self.user = user
        self.system = system
        self.perCore = perCore
    }

    public var total: Double { min(1, user + system) }
}

public enum CPUMath {
    /// Usage from `previous` to `current`. Nil when the readings can't be compared: a
    /// different number of CPUs (a CPU went offline), no time passed, or a counter that
    /// went backwards by more than a wrap explains (a reset), which would read as a spike.
    public static func usage(from previous: [CPUTicks], to current: [CPUTicks]) -> CPUUsage? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var all: UInt64 = 0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        for (old, new) in zip(previous, current) {
            // Wrapping subtraction handles a 32-bit counter that rolled over.
            let dUser = UInt64(new.user &- old.user) + UInt64(new.nice &- old.nice)
            let dSystem = UInt64(new.system &- old.system)
            let dIdle = UInt64(new.idle &- old.idle)
            let total = dUser + dSystem + dIdle
            // A reset shows up as an enormous wrapped delta. Ticks run at 100 Hz, so more
            // than a day's worth between two samples can't be real.
            if total > Self.implausibleTicks { return nil }
            user += dUser
            system += dSystem
            all += total
            perCore.append(total == 0 ? 0 : Double(dUser + dSystem) / Double(total))
        }
        guard all > 0 else { return nil }
        return CPUUsage(user: Double(user) / Double(all), system: Double(system) / Double(all), perCore: perCore)
    }

    /// A day of ticks at 100 Hz.
    static let implausibleTicks: UInt64 = 100 * 86_400

    /// The per-core values grouped by core kind, in the groups' order. CPUs missing from
    /// every group are left out; groups with no readable CPUs are dropped.
    public static func grouped(_ perCore: [Double], by groups: [CoreGroup]) -> [(name: String, values: [Double])] {
        groups.compactMap { group in
            let values = group.cpus.compactMap { perCore.indices.contains($0) ? perCore[$0] : nil }
            return values.isEmpty ? nil : (group.name, values)
        }
    }
}
