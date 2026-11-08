import Foundation

/// Bytes per second in each direction.
public struct ByteRates: Sendable, Equatable {
    public var down: Double
    public var up: Double

    public init(down: Double, up: Double) {
        self.down = down
        self.up = up
    }

    public static let zero = ByteRates(down: 0, up: 0)
}

public enum NetworkMath {
    /// Which interfaces count toward the totals: the physical ones (Wi-Fi, Ethernet, USB and
    /// Thunderbolt adapters are all `en*`). VPN tunnels (`utun*`) and bridges carry traffic
    /// that's already counted on the physical interface underneath, loopback never leaves
    /// the Mac, and AirDrop's `awdl`/`llw` are left out with them.
    public static func isCounted(_ name: String) -> Bool {
        guard name.hasPrefix("en"), name.count > 2 else { return false }
        return name.dropFirst(2).allSatisfy(\.isNumber)
    }

    /// Rates between two readings `seconds` apart. Interfaces that appeared, vanished or whose
    /// counters went backwards (reset by a driver reload or sleep) are skipped rather than
    /// read as a spike. Nil when no time passed.
    public static func rates(from previous: [InterfaceCounters], to current: [InterfaceCounters],
                             seconds: TimeInterval) -> ByteRates? {
        guard seconds > 0 else { return nil }
        var old: [String: InterfaceCounters] = [:]
        for counters in previous { old[counters.name] = counters }
        var down: UInt64 = 0
        var up: UInt64 = 0
        for counters in current {
            guard let before = old[counters.name],
                  counters.received >= before.received, counters.sent >= before.sent else { continue }
            down += counters.received - before.received
            up += counters.sent - before.sent
        }
        return ByteRates(down: Double(down) / seconds, up: Double(up) / seconds)
    }

    /// Disk read/write rates; same rules (nil on a reset or no time).
    public static func rates(from previous: DiskIOCounters, to current: DiskIOCounters, seconds: TimeInterval) -> ByteRates? {
        guard seconds > 0, current.read >= previous.read, current.written >= previous.written else { return nil }
        return ByteRates(down: Double(current.read - previous.read) / seconds,
                         up: Double(current.written - previous.written) / seconds)
    }
}
