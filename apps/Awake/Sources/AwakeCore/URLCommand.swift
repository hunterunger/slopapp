import Foundation

/// Commands from the URL scheme, for scripts, Shortcuts ("Open URL") and launchers:
///
///     slopawake://activate                    default duration
///     slopawake://activate?minutes=45         also hours=2, hours=1&minutes=30
///     slopawake://activate?until=17:30        24-hour clock, next occurrence
///     slopawake://activate?indefinitely
///     slopawake://deactivate
///     slopawake://toggle?hours=1
public enum URLCommand: Equatable, Sendable {
    public enum Start: Equatable, Sendable {
        case defaultDuration
        case duration(AwakeDuration)
        case until(hour: Int, minute: Int)
    }

    case activate(Start)
    case deactivate
    case toggle(Start)

    public static let scheme = "slopawake"

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme else { return nil }
        // Accept slopawake://activate and slopawake:activate.
        let verb = (components.host ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }.map { $0.value ?? "" }
        }
        let start: Start
        if let until = value("until") {
            let parts = until.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
            start = .until(hour: parts[0], minute: parts[1])
        } else if value("indefinitely") != nil {
            start = .duration(.indefinitely)
        } else if value("hours") != nil || value("minutes") != nil {
            guard let hours = Double(value("hours") ?? "0"), let minutes = Double(value("minutes") ?? "0"),
                  hours >= 0, minutes >= 0, hours.isFinite, minutes.isFinite else { return nil }
            let seconds = hours * 3600 + minutes * 60
            guard seconds > 0 else { return nil }
            start = .duration(AwakeDuration(seconds: seconds))
        } else {
            start = .defaultDuration
        }
        switch verb {
        case "activate", "on", "start": self = .activate(start)
        case "deactivate", "off", "stop": self = .deactivate
        case "toggle": self = .toggle(start)
        default: return nil
        }
    }
}

extension AwakeController {
    /// Runs a URL-scheme command.
    public func perform(_ command: URLCommand) {
        switch command {
        case .activate(let start): begin(start)
        case .deactivate: stop()
        case .toggle(let start): if isActive { stop() } else { begin(start) }
        }
    }

    private func begin(_ start: URLCommand.Start) {
        switch start {
        case .defaultDuration: startDefault()
        case .duration(let duration): self.start(duration)
        case .until(let hour, let minute):
            if let date = NextOccurrence.of(hour: hour, minute: minute, after: clock()) { self.start(.until(date)) }
        }
    }
}
