import Foundation

/// Sessions and breaks as CSV, for spreadsheets and time logging. One row per record,
/// oldest first. Dates are ISO 8601 with the local offset so they sort and import cleanly.
public enum CSVExport {
    public static let header = [
        "Intention", "Category", "Type", "Start", "End", "Duration (minutes)", "Duration (seconds)",
        "Paused (seconds)", "Completed", "Counted", "Mood", "Notes",
    ]

    public static func make(_ records: [SessionRecord], categories: [Category], timeZone: TimeZone = .current) -> String {
        let dates = ISO8601DateFormatter()
        dates.timeZone = timeZone
        dates.formatOptions = [.withInternetDateTime]
        var lines = [header.map(escape).joined(separator: ",")]
        for record in records.filter({ !$0.deleted }).sorted(by: { $0.startedAt < $1.startedAt }) {
            let category = categories.first { $0.id == record.categoryID }?.name ?? record.categoryName ?? ""
            let fields = [
                record.label ?? "",
                record.isFocus ? category : "",
                record.kind.title,
                dates.string(from: record.startedAt),
                dates.string(from: record.endedAt),
                String(format: "%.1f", record.focused / 60),
                String(Int(record.focused.rounded())),
                String(Int(record.paused.rounded())),
                record.completed ? "yes" : "no",
                record.counted ? "yes" : "no",
                record.mood?.title ?? "",
                record.notes ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180: quote fields with commas, quotes or line breaks; double the quotes. A leading
    /// =, +, - or @ gets a quote mark first so spreadsheets don't run it as a formula.
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@".contains(first), Double(value) == nil { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "Focus Sessions 2026-11-03.csv"
    public static func fileName(now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "Focus Sessions %04d-%02d-%02d.csv", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
