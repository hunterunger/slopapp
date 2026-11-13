import Foundation

/// Changes a web link before it's matched and opened: switch to a mirror, drop or replace part
/// of it, or turn it into an app's own link (`zoommtg:`), which then opens in that app.
public struct Rewrite: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    /// Only links to this website ("" = any). Same patterns as rules (`*.example.com`).
    public var host: String
    /// Text to find, or a regular expression when `usesRegex`.
    public var find: String
    /// What it becomes. With a regular expression, `$1`, `$2`… insert its groups.
    public var replacement: String
    public var usesRegex: Bool

    public init(id: UUID = UUID(), isEnabled: Bool = true, host: String = "", find: String = "",
                replacement: String = "", usesRegex: Bool = false) {
        self.id = id
        self.isEnabled = isEnabled
        self.host = host
        self.find = find
        self.replacement = replacement
        self.usesRegex = usesRegex
    }

    /// The rewritten link, or nil if this rewrite doesn't apply (off, other website, nothing
    /// found, or the result isn't a link Switchboard may open).
    public func apply(to url: URL) -> URL? {
        guard isEnabled, !find.isEmpty else { return nil }
        if let pattern = HostPattern(host), !pattern.matches(url) { return nil }
        let text = url.absoluteString
        let result: String
        if usesRegex {
            guard let regex = try? NSRegularExpression(pattern: find, options: [.caseInsensitive]) else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard regex.firstMatch(in: text, range: range) != nil else { return nil }
            result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
        } else {
            guard text.contains(find) else { return nil }
            result = text.replacingOccurrences(of: find, with: replacement)
        }
        guard result != text, let rewritten = URL(string: result), Self.isAllowedResult(rewritten) else { return nil }
        return rewritten
    }

    /// A rewrite may produce a web link or another app's link, never a file, a script, or our
    /// own scheme (which would loop).
    static func isAllowedResult(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        if ["file", "javascript", "data", LinkParser.ownScheme].contains(scheme) { return false }
        if scheme == "http" || scheme == "https" { return url.host?.isEmpty == false }
        return true
    }

    /// Why this rewrite can't be saved, or nil.
    public var validationProblem: String? {
        if find.isEmpty { return "Enter the part of the link to find." }
        if usesRegex {
            do {
                _ = try NSRegularExpression(pattern: find)
            } catch {
                return "That isn't a valid regular expression."
            }
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        if !trimmedHost.isEmpty, HostPattern(trimmedHost) == nil || trimmedHost.contains(" ") {
            return "“\(trimmedHost)” isn't a website. Use a name like example.com or *.example.com."
        }
        return nil
    }

    /// "twitter.com → nitter.net", or "/amp/ → (removed)".
    public var summary: String {
        let to = replacement.isEmpty ? "(removed)" : replacement
        let site = HostPattern(host) == nil ? "" : " on \(host.trimmingCharacters(in: .whitespaces))"
        return "\(find) → \(to)\(site)"
    }
}

/// What happened to a link before routing, in order. Shown in the tester and logs.
public enum LinkStep: Equatable, Sendable {
    case removedTracking
    /// Rewrite number `index` (0-based) changed the link.
    case rewritten(index: Int, to: URL)
    /// Rewrite number `index` would have made a `scheme:` link, but no app on this Mac opens
    /// those, so it was left out and the link went on as a web link.
    case skippedAppLink(index: Int, scheme: String)
}

/// A link after tracking removal and rewrites, ready to route.
public struct PreparedLink: Equatable, Sendable {
    public var url: URL
    public var steps: [LinkStep]
}

public enum LinkPreparation {
    /// Tracking removal (if on), then each rewrite in order, each on the result of the last.
    /// Stops once a rewrite turns the link into an app's link.
    ///
    /// - Parameters:
    ///   - allowAppLinks: false when the picker will show anyway (⌥ held, forced), so the
    ///     link stays a web link a browser can open.
    ///   - canOpen: whether some app (not Switchboard) opens this app link. A rewrite into a
    ///     link nothing opens is skipped instead of losing the link.
    public static func prepare(_ url: URL, config: Config, allowAppLinks: Bool = true,
                               canOpen: (URL) -> Bool = { _ in true }) -> PreparedLink {
        var current = url
        var steps: [LinkStep] = []
        guard LinkKind.of(url) == .web, !url.isFileURL else { return PreparedLink(url: url, steps: []) }
        if config.stripsTrackingParameters {
            let cleaned = TrackingParameters.strip(current)
            if cleaned != current { current = cleaned; steps.append(.removedTracking) }
        }
        for (index, rewrite) in config.rewrites.enumerated() {
            guard let next = rewrite.apply(to: current) else { continue }
            let isWeb = LinkKind.of(next) == .web
            if !isWeb && !allowAppLinks { continue }
            if LinkKind.of(next) == nil, !canOpen(next) {
                steps.append(.skippedAppLink(index: index, scheme: next.scheme ?? ""))
                continue
            }
            current = next
            steps.append(.rewritten(index: index, to: next))
            if !isWeb { break }
        }
        return PreparedLink(url: current, steps: steps)
    }
}
