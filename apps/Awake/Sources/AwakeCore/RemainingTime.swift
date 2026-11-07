import Foundation

/// Short, menu-friendly remaining-time text. Deterministic (no locale) so it's easy to test.
public enum RemainingTime {
    public static func string(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "Less than a minute left" }
        // Round up so "14 min 10 s" reads as "15 min left", matching the chosen preset.
        let totalMinutes = Int((seconds / 60).rounded(.up))
        if totalMinutes < 60 { return "\(totalMinutes) min left" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr left" : "\(hours) hr \(minutes) min left"
    }

    /// For the menu bar, next to the icon: "1h 05m", "45m", "<1m".
    public static func compact(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let minutes = totalMinutes % 60
        return "\(totalMinutes / 60)h " + (minutes < 10 ? "0\(minutes)m" : "\(minutes)m")
    }
}
