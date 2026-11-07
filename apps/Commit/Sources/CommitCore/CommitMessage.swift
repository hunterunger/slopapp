import Foundation

/// The composer's rules: subject guide at 50, warning past 72, body guide at 72.
public struct CommitMessage: Sendable, Equatable, Codable {
    public var subject: String
    public var body: String

    public static let subjectGuide = 50
    public static let subjectLimit = 72
    public static let bodyGuide = 72

    public init(subject: String = "", body: String = "") {
        self.subject = subject
        self.body = body
    }

    /// Splits a full message (first line → subject, the rest after a blank line → body).
    public init(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        subject = parts.first.map(String.init) ?? ""
        body = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    public var isEmpty: Bool { subject.trimmingCharacters(in: .whitespaces).isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What goes to `git commit -F -`.
    public var text: String {
        let s = subject.trimmingCharacters(in: .whitespaces)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? s + "\n" : s + "\n\n" + b + "\n"
    }

    public enum SubjectLength: Sendable, Equatable { case fine, long, tooLong }

    public var subjectLength: SubjectLength {
        let n = subject.count
        if n > Self.subjectLimit { return .tooLong }
        if n > Self.subjectGuide { return .long }
        return .fine
    }

    /// "42/50"; past 50 it counts against 72.
    public var counterText: String {
        let n = subject.count
        return n > Self.subjectGuide ? "\(n)/\(Self.subjectLimit)" : "\(n)/\(Self.subjectGuide)"
    }

    /// A short reason shown when the subject is long, nil when it's fine.
    public var subjectHint: String? {
        switch subjectLength {
        case .fine: nil
        case .long: "Short subjects read best in logs."
        case .tooLong: "Subjects over 72 characters get cut off in many tools."
        }
    }

    /// Body lines longer than the guide (1-based line numbers).
    public var longBodyLines: [Int] {
        let lines: [Substring] = body.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [Int] = []
        for (offset, line) in lines.enumerated() where line.count > Self.bodyGuide { result.append(offset + 1) }
        return result
    }
}

/// The commit button's title: says what it does.
public enum CommitButtonTitle {
    public static func title(stagedFiles: Int, amend: Bool) -> String {
        if amend { return stagedFiles == 0 ? "Amend Message" : "Amend Last Commit" }
        switch stagedFiles {
        case 0: return "Commit"
        case 1: return "Commit 1 File"
        default: return "Commit \(stagedFiles) Files"
        }
    }
}

/// Per-repository commit message drafts, saved as you type and restored after quit or crash.
public final class DraftStore: @unchecked Sendable {
    private let file: URL
    private var drafts: [String: CommitMessage]
    private let lock = NSLock()

    public init(directory: URL) {
        file = directory.appendingPathComponent("drafts.json")
        drafts = (try? JSONDecoder().decode([String: CommitMessage].self, from: Data(contentsOf: file))) ?? [:]
    }

    public func draft(for repository: String) -> CommitMessage? {
        lock.withLock { drafts[repository] }
    }

    public func save(_ message: CommitMessage, for repository: String) {
        let snapshot: [String: CommitMessage] = lock.withLock {
            if message.isEmpty { drafts.removeValue(forKey: repository) } else { drafts[repository] = message }
            return drafts
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// Recently opened repositories, newest first (File › Open Recent and the welcome window).
public struct RecentRepositories: Sendable, Equatable {
    public private(set) var paths: [String]
    public static let limit = 12

    public init(paths: [String] = []) {
        self.paths = Array(paths.prefix(Self.limit))
    }

    public mutating func add(_ path: String) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit { paths.removeLast(paths.count - Self.limit) }
    }

    public mutating func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    public mutating func clear() { paths = [] }
}

/// Relative dates for history rows ("5 min ago", "Yesterday", "12 Mar 2024").
public enum RelativeDate {
    public static func string(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 && calendar.isDate(date, inSameDayAs: now) {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hr ago" : "\(hours) hr ago"
        }
        if calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) { return "Yesterday" }
        if seconds < 7 * 86_400 {
            let f = DateFormatter(); f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate("EEEE")
            return f.string(from: date)
        }
        let f = DateFormatter(); f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy")
        return f.string(from: date)
    }
}

/// Byte counts for binary files ("4.2 MB").
public enum ByteSize {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
