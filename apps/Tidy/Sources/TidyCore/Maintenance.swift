import Foundation

/// Housekeeping macOS can do on request. Only tasks with a real, explainable effect: no
/// "free up RAM", "speed up" or "repair permissions" (see the research doc for why).
public enum MaintenanceTask: String, CaseIterable, Sendable, Identifiable, Codable {
    case flushDNS, reindexSpotlight, resetQuickLook, clearFontCaches

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flushDNS: "Flush DNS Cache"
        case .reindexSpotlight: "Rebuild Spotlight Index"
        case .resetQuickLook: "Reset Quick Look"
        case .clearFontCaches: "Clear Font Caches"
        }
    }

    /// One plain sentence: when it helps and what happens.
    public var detail: String {
        switch self {
        case .flushDNS:
            "Helps when a website moved or won't load but works elsewhere. macOS looks up addresses again."
        case .reindexSpotlight:
            "Helps when Spotlight misses files or finds ones that are gone. Rebuilding takes a while and uses the processor until it's done."
        case .resetQuickLook:
            "Helps when previews or thumbnails are wrong or blank. macOS makes them again as you browse."
        case .clearFontCaches:
            "Helps when text shows in the wrong font or garbled. Takes effect after you log out and back in."
        }
    }

    public var systemImage: String {
        switch self {
        case .flushDNS: "network"
        case .reindexSpotlight: "magnifyingglass"
        case .resetQuickLook: "eye"
        case .clearFontCaches: "textformat"
        }
    }

    /// macOS asks for an administrator's password before running it.
    public var needsAdmin: Bool {
        switch self {
        case .flushDNS, .reindexSpotlight: true
        case .resetQuickLook, .clearFontCaches: false
        }
    }

    /// Fixed commands, never built from user input. Run as the user unless `needsAdmin`.
    public var commands: [[String]] {
        switch self {
        case .flushDNS: [["/usr/bin/dscacheutil", "-flushcache"], ["/usr/bin/killall", "-HUP", "mDNSResponder"]]
        case .reindexSpotlight: [["/usr/bin/mdutil", "-E", "/"]]
        case .resetQuickLook: [["/usr/bin/qlmanage", "-r", "cache"], ["/usr/bin/qlmanage", "-r"]]
        case .clearFontCaches: [["/usr/bin/atsutil", "databases", "-removeUser"]]
        }
    }

    /// The commands as one shell line, for the administrator prompt.
    public var shellLine: String {
        commands.map { $0.joined(separator: " ") }.joined(separator: "; ")
    }
}

public enum TaskError: Error, Equatable, Sendable, CustomStringConvertible {
    case cancelled
    case failed(String)

    public var description: String {
        switch self {
        case .cancelled: "You cancelled the password prompt."
        case .failed(let message): message
        }
    }
}

/// Runs maintenance tasks. The real one runs commands; test mode records them instead.
public protocol TaskRunner: Sendable {
    func run(_ task: MaintenanceTask) throws
}

/// The real runner. Admin tasks go through macOS's own administrator prompt.
public struct SystemTaskRunner: TaskRunner {
    public init() {}

    public func run(_ task: MaintenanceTask) throws {
        if task.needsAdmin {
            // The script is a fixed string from `MaintenanceTask`; nothing user-supplied.
            let script = "do shell script \"\(task.shellLine)\" with administrator privileges"
            let (status, error) = Self.execute(["/usr/bin/osascript", "-e", script])
            if status != 0 {
                if error.contains("-128") || error.lowercased().contains("cancel") { throw TaskError.cancelled }
                throw TaskError.failed(error.isEmpty ? "It stopped with an error." : error)
            }
            return
        }
        for command in task.commands {
            let (status, error) = Self.execute(command)
            if status != 0 { throw TaskError.failed(error.isEmpty ? "It stopped with an error." : error) }
        }
    }

    static func execute(_ command: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmed)
    }
}

/// Test mode: appends "task-id" lines to a log file and changes nothing on the Mac.
/// `TIDY_TASK_FAIL=flushDNS,...` makes those tasks fail, and `cancel` in it simulates
/// cancelling the password prompt, so error paths can be walked.
public struct RecordingTaskRunner: TaskRunner {
    public let log: URL
    public let failing: Set<String>

    public init(log: URL, failing: Set<String> = []) {
        self.log = log
        self.failing = failing
    }

    public func run(_ task: MaintenanceTask) throws {
        if task.needsAdmin && failing.contains("cancel") { throw TaskError.cancelled }
        if failing.contains(task.rawValue) { throw TaskError.failed("Simulated failure (test mode).") }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(task.rawValue)\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }
}
