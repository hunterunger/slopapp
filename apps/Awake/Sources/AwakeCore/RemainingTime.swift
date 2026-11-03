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
}
