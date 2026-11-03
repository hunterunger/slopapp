import Foundation

/// Short display strings for clips.
public enum ClipText {
    /// One line for a list row: the first non-blank line, whitespace collapsed, capped.
    public static func title(of clip: Clip, limit: Int = 200) -> String {
        switch clip.kind {
        case .image:
            return clip.imageWidth > 0 ? "Image, \(clip.imageWidth) × \(clip.imageHeight)" : "Image"
        case .file:
            let names = clip.filePaths.map { ($0 as NSString).lastPathComponent }
            if names.count <= 1 { return names.first ?? "File" }
            return "\(names[0]) and \(names.count - 1) more"
        case .text, .link, .color:
            return oneLine(clip.text, limit: limit)
        }
    }

    /// When the query's first match isn't near the start of the text (so a row title can't
    /// show it), a one-line excerpt around it: "…words before match words after…".
    /// Nil when there's no query, no match, or the match is already in the first
    /// `visibleLength` characters.
    public static func snippet(in text: String, query: String, visibleLength: Int = 40,
                               before: Int = 24, length: Int = 120) -> String? {
        let words = query.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty, !text.isEmpty else { return nil }
        let string = text as NSString
        var first = NSNotFound
        for word in words {
            let found = string.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
            if found.location != NSNotFound { first = min(first, found.location) }
        }
        guard first != NSNotFound else { return nil }
        // Already visible in the title?
        // The "x" stands for the match itself. +2: a trailing space at the cut gets trimmed,
        // and collapsed text never has two spaces in a row.
        let lead = oneLine(string.substring(to: first) + "x", limit: visibleLength + 2)
        if lead.count <= visibleLength { return nil }
        var start = max(0, first - before)
        // Start on a word boundary when one is close.
        if start > 0 {
            let window = NSRange(location: start, length: first - start)
            let space = string.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: window)
            if space.location != NSNotFound { start = space.location + 1 }
            start = string.rangeOfComposedCharacterSequence(at: start).location
        }
        let end = min(string.length, start + length)
        let body = oneLine(string.substring(with: string.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))), limit: length)
        return (start > 0 ? "…" : "") + body + (end < string.length ? "…" : "")
    }

    public static func oneLine(_ text: String, limit: Int = 200) -> String {
        var result = ""
        var lastWasSpace = true
        for character in text.prefix(limit * 4) {
            if character.isWhitespace || character.isNewline {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
            if result.count >= limit { break }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// "now", "5 min", "3 hr", "Yesterday", "Mon", "12 Oct", "12 Oct 2024".
    public static func age(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3_600)) hr" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let template: String
        if seconds < 6 * 86_400 {
            template = "EEE"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            template = "d MMM"
        } else {
            template = "d MMM yyyy"
        }
        let formatter = FormatterCache.formatter(template: template, calendar: calendar)
        return formatter.string(from: date)
    }

    /// "Just now", "5 min ago", "3 hr ago", "Yesterday", "Mon", "12 Oct".
    public static func ageSentence(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let short = age(of: date, now: now, calendar: calendar)
        if short == "now" { return "Just now" }
        if short.hasSuffix(" min") || short.hasSuffix(" hr") { return short + " ago" }
        return short
    }

    /// "1 line · 42 characters", "1,204 × 800 · 2.1 MB", "3 files".
    public static func details(of clip: Clip) -> String {
        switch clip.kind {
        case .image:
            let size = ByteCountFormatter.string(fromByteCount: Int64(clip.byteCount), countStyle: .file)
            return "\(clip.imageWidth) × \(clip.imageHeight) · \(size)"
        case .file:
            let count = clip.filePaths.count
            return count == 1 ? "1 file" : "\(count.formatted()) files"
        case .text, .link, .color:
            let lines = clip.text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let lineText = lines == 1 ? "1 line" : "\(lines.formatted()) lines"
            let chars = clip.textLength == 1 ? "1 character" : "\(clip.textLength.formatted()) characters"
            return clip.isTruncated ? chars : "\(lineText) · \(chars)"
        }
    }
}

/// Date formatters are expensive to make (they load ICU data), and rows ask for one per
/// render, so keep one per template and calendar.
enum FormatterCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    static func formatter(template: String, calendar: Calendar) -> DateFormatter {
        let key = "\(template)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(calendar.locale?.identifier ?? "")"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }
}
