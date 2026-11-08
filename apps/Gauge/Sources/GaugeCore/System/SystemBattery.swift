import Foundation
import IOKit
import IOKit.ps

/// The internal battery from IOPowerSources, plus cycle count and health from the
/// `AppleSmartBattery` registry entry.
public final class SystemBattery: BatterySource {
    public init() {}

    public func read(details: Bool) -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool ?? true else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let toEmpty = description[kIOPSTimeToEmptyKey] as? Int
            let toFull = description[kIOPSTimeToFullChargeKey] as? Int
            var info = BatteryInfo(
                percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                source: onAC ? .powerAdapter : .battery,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
                // -1 while macOS is still estimating.
                minutesToEmpty: toEmpty.flatMap { $0 > 0 ? $0 : nil },
                minutesToFull: toFull.flatMap { $0 > 0 ? $0 : nil }
            )
            if onAC, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                info.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
            }
            if details { addDetails(to: &info) }
            return info
        }
        return nil
    }

    private func addDetails(to info: inout BatteryInfo) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        info.cycleCount = IOKitProperty.int(service, "CycleCount")
        // Maximum capacity as System Settings shows it: nominal charge capacity over design.
        let data = IOKitProperty.dictionary(service, "BatteryData")
        let design = (data?["DesignCapacity"] as? NSNumber)?.doubleValue ?? IOKitProperty.int(service, "DesignCapacity").map(Double.init)
        let nominal = (data?["NominalChargeCapacity"] as? NSNumber)?.doubleValue
            ?? IOKitProperty.int(service, "NominalChargeCapacity").map(Double.init)
            ?? IOKitProperty.int(service, "AppleRawMaxCapacity").map(Double.init)
        if let design, let nominal, design > 0 {
            info.healthPercent = Swift.min(100, Int((nominal / design * 100).rounded()))
        }
    }
}
