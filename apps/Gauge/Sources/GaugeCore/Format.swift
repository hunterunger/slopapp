import Foundation

/// How network rates are shown.
public enum RateUnit: String, Sendable, Codable, CaseIterable {
    /// KB/s, MB/s (decimal, like Finder).
    case bytes
    /// Kbps, Mbps (what internet plans advertise).
    case bits

    public var title: String {
        switch self {
        case .bytes: "Bytes per second (MB/s)"
        case .bits: "Bits per second (Mbps)"
        }
    }
}

/// Every number Gauge shows goes through here, so the menu bar, the panel and VoiceOver
/// agree, and the fixed-width maths knows every shape a value can take.
public enum Format {
    // MARK: Percent

    /// "23%" for 0.23. Clamped to 0–100%, rounded to whole percent so an idle Mac produces
    /// the same string tick after tick (and the menu bar doesn't redraw).
    public static func percent(_ fraction: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let clamped = min(1, max(0, fraction.isFinite ? fraction : 0))
        return clamped.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Whole percent, 0...100, the value `percent` shows.
    public static func percentValue(_ fraction: Double) -> Int {
        Int((min(1, max(0, fraction.isFinite ? fraction : 0)) * 100).rounded())
    }

    /// A process's CPU in Activity Monitor's scale, where 100% is one core: "312%", "34%",
    /// "2.5%", "0%".
    public static func processPercent(_ percent: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let value = max(0, percent.isFinite ? percent : 0)
        if value < 0.05 { return (0.0).formatted(.percent.precision(.fractionLength(0)).locale(locale)) }
        let digits = value < 9.95 ? 1 : 0
        return (value / 100).formatted(.percent.precision(.fractionLength(digits)).locale(locale))
    }

    // MARK: Rates

    /// "0 KB/s", "8.4 KB/s", "40 KB/s", "120 KB/s", "1.2 MB/s": two significant figures, decimal
    /// units. Anything under 1 KB/s reads as 0, so background chatter doesn't flicker.
    public static func rate(_ bytesPerSecond: Double, unit: RateUnit = .bytes, locale: Locale = .autoupdatingCurrent) -> String {
        let (number, suffix) = rateParts(bytesPerSecond, unit: unit, locale: locale)
        return "\(number) \(suffix)"
    }

    /// The number and the unit separately, for laying them out in columns.
    public static func rateParts(_ bytesPerSecond: Double, unit: RateUnit = .bytes,
                                 locale: Locale = .autoupdatingCurrent) -> (number: String, unit: String) {
        let units = unit == .bytes ? ["KB/s", "MB/s", "GB/s", "TB/s"] : ["Kbps", "Mbps", "Gbps", "Tbps"]
        var value = max(0, bytesPerSecond.isFinite ? bytesPerSecond : 0) * (unit == .bits ? 8 : 1) / 1000
        if value < 1 { return (0.formatted(.number.locale(locale)), units[0]) }
        var index = 0
        var rounded = significant(value, figures: 2)
        while rounded >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
            rounded = significant(value, figures: 2)
        }
        return (number(rounded, locale: locale), units[index])
    }

    /// The widest strings `rate` can produce for `unit`, to size a fixed slot.
    public static func rateCandidates(unit: RateUnit, locale: Locale = .autoupdatingCurrent) -> [String] {
        // Digits are monospaced, so one value of each shape is enough: "8.8 X", "88 X", "880 X".
        let shapes: [Double] = [8.8, 88, 880]
        return [1e3, 1e6, 1e9].flatMap { scale in
            shapes.map { rate($0 * scale / (unit == .bits ? 8 : 1), unit: unit, locale: locale) }
        } + [rate(0, unit: unit, locale: locale)]
    }

    /// Rounds to `figures` significant figures.
    static func significant(_ value: Double, figures: Int) -> Double {
        guard value > 0 else { return 0 }
        let magnitude = (log10(value)).rounded(.down)
        let factor = pow(10, Double(figures - 1) - magnitude)
        return (value * factor).rounded() / factor
    }

    /// "1.2" below 10, "12" or "120" above.
    private static func number(_ value: Double, locale: Locale) -> String {
        value < 10
            ? value.formatted(.number.precision(.fractionLength(1)).locale(locale))
            : value.formatted(.number.precision(.fractionLength(0)).grouping(.never).locale(locale))
    }

    // MARK: Sizes

    /// Memory sizes, binary like Activity Monitor: "24.1 GB", "512 MB", "0 bytes".
    public static func memory(_ bytes: UInt64, locale: Locale = .autoupdatingCurrent) -> String {
        if bytes == 0 { return zero(locale: locale) }
        return Int64(clamping: bytes).formatted(.byteCount(style: .memory).locale(locale))
    }

    /// Disk sizes, decimal like Finder: "412.3 GB", "1.2 TB".
    public static func disk(_ bytes: UInt64, locale: Locale = .autoupdatingCurrent) -> String {
        if bytes == 0 { return zero(locale: locale) }
        return Int64(clamping: bytes).formatted(.byteCount(style: .file).locale(locale))
    }

    /// "0 MB" rather than the formatter's "Zero bytes", which reads oddly in a column of sizes.
    private static func zero(locale: Locale) -> String {
        "\(0.formatted(.number.locale(locale))) MB"
    }

    /// A compact disk size for the menu bar, three significant figures: "412 GB", "1.21 TB",
    /// "85.2 GB".
    public static func compactDisk(_ bytes: UInt64, locale: Locale = .autoupdatingCurrent) -> String {
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes) / 1000
        if value < 1 { return "0 KB" }
        var index = 0
        var rounded = significant(value, figures: 3)
        while rounded >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
            rounded = significant(value, figures: 3)
        }
        let digits = rounded < 10 ? 2 : rounded < 100 ? 1 : 0
        return "\(rounded.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))) \(units[index])"
    }

    public static func compactDiskCandidates(locale: Locale = .autoupdatingCurrent) -> [String] {
        [8.88, 88.8, 888].flatMap { shape in [1e9, 1e12].map { compactDisk(UInt64(shape * $0), locale: locale) } }
    }

    // MARK: Time

    /// "3d 4h", "5h 12m", "12m": the two largest units.
    public static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// "3:12" for 192 minutes.
    public static func hoursMinutes(_ minutes: Int) -> String {
        let value = max(0, minutes)
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    /// "2.14  1.98  1.80"
    public static func load(_ load: SystemLoad, locale: Locale = .autoupdatingCurrent) -> String {
        [load.oneMinute, load.fiveMinutes, load.fifteenMinutes]
            .map { $0.formatted(.number.precision(.fractionLength(2)).locale(locale)) }
            .joined(separator: "  ")
    }

    /// "12/s", "1,204/s"
    public static func perSecond(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        "\(Int(max(0, value).rounded()).formatted(.number.locale(locale)))/s"
    }

    // MARK: Spoken

    /// What VoiceOver reads for a rate: "1.2 megabytes per second".
    public static func spokenRate(_ bytesPerSecond: Double, unit: RateUnit = .bytes,
                                  locale: Locale = .autoupdatingCurrent) -> String {
        let (number, suffix) = rateParts(bytesPerSecond, unit: unit, locale: locale)
        let words: [String: String] = [
            "KB/s": "kilobytes per second", "MB/s": "megabytes per second", "GB/s": "gigabytes per second",
            "TB/s": "terabytes per second", "Kbps": "kilobits per second", "Mbps": "megabits per second",
            "Gbps": "gigabits per second", "Tbps": "terabits per second",
        ]
        return "\(number) \(words[suffix] ?? suffix)"
    }
}
