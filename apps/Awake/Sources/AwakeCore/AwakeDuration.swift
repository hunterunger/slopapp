import Foundation

/// How long to keep the Mac awake. `nil` seconds means until turned off.
public struct AwakeDuration: Hashable, Sendable, Identifiable {
    public let seconds: TimeInterval?

    public init(seconds: TimeInterval?) {
        self.seconds = seconds
    }

    public static func minutes(_ m: Double) -> AwakeDuration { AwakeDuration(seconds: m * 60) }
    public static func hours(_ h: Double) -> AwakeDuration { AwakeDuration(seconds: h * 3600) }
    public static let indefinitely = AwakeDuration(seconds: nil)

    /// The choices shown in the menu.
    public static let presets: [AwakeDuration] = [.minutes(15), .hours(1), .hours(2), .hours(4), .indefinitely]

    public var id: Double { seconds ?? -1 }

    public var title: String {
        guard let seconds else { return "Until Turned Off" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "1 Minute" : "\(minutes) Minutes" }
        let hours = minutes / 60
        if minutes % 60 == 0 { return hours == 1 ? "1 Hour" : "\(hours) Hours" }
        return "\(hours) hr \(minutes % 60) min"
    }

    /// Parses "90s", "15m", "2h", a bare number of minutes ("30"), or "forever"/"on".
    /// Used by the `AWAKE_ACTIVATE` launch variable.
    public init?(parsing text: String) {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if ["forever", "on", "indefinitely", "always"].contains(value) {
            self = .indefinitely
            return
        }
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600]
        var multiplier = 60.0
        var digits = Substring(value)
        if let last = value.last, let unit = units[last] {
            multiplier = unit
            digits = digits.dropLast()
        }
        guard let number = Double(digits), number > 0, number.isFinite else { return nil }
        self.init(seconds: number * multiplier)
    }
}
