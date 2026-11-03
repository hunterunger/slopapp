import Foundation

/// The app a link must come from, by bundle ID (helpers are mapped to their main app).
public struct SourceAppMatch: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum RuleAction: Codable, Hashable, Sendable {
    /// Open in this target.
    case open(targetID: UUID)
    /// Show the picker.
    case ask
}

/// One routing rule. All conditions that are set must match; first matching rule wins.
public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    /// Host pattern; "" means any host. See `HostPattern`.
    public var host: String
    /// Path prefix; "" means any path. See `PathPrefix`.
    public var path: String
    public var sourceApp: SourceAppMatch?
    /// Keys that must be held; empty means "doesn't matter".
    public var modifiers: Modifiers
    public var action: RuleAction

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        host: String = "",
        path: String = "",
        sourceApp: SourceAppMatch? = nil,
        modifiers: Modifiers = [],
        action: RuleAction
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.host = host
        self.path = path
        self.sourceApp = sourceApp
        self.modifiers = modifiers
        self.action = action
    }

    /// A rule needs at least one condition, or it would swallow every link.
    public var hasConditions: Bool {
        HostPattern(host) != nil || PathPrefix(path) != nil || sourceApp != nil || !modifiers.isEmpty
    }

    public func matches(_ link: IncomingLink) -> Bool {
        guard isEnabled, hasConditions else { return false }
        if let pattern = HostPattern(host), !pattern.matches(link.url) { return false }
        if let prefix = PathPrefix(path), !prefix.matches(link.url) { return false }
        if let sourceApp {
            guard let source = link.sourceBundleID,
                  source.caseInsensitiveCompare(sourceApp.bundleID) == .orderedSame
            else { return false }
        }
        if !modifiers.isEmpty, !link.modifiers.isSuperset(of: modifiers) { return false }
        return true
    }

    /// Reads what someone typed or pasted into the Website field. Accepts a bare host
    /// ("example.com"), a wildcard ("*.example.com"), or a whole URL
    /// ("https://www.example.com/blog/post?x=1#top"), and returns the host pattern plus the
    /// path, if there was one. Scheme, user info, query and fragment are dropped, the host is
    /// lowercased, and a leading "www." is removed (a plain host already matches www).
    public static func parseWebsite(_ text: String) -> (host: String, path: String?) {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = rest.range(of: "://") { rest = String(rest[range.upperBound...]) }
        // Host ends at the first "/", "?" or "#".
        let hostEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        var host = String(rest[..<hostEnd])
        var path: String? = nil
        if hostEnd < rest.endIndex, rest[hostEnd] == "/" {
            var tail = String(rest[hostEnd...])
            if let cut = tail.firstIndex(where: { $0 == "?" || $0 == "#" }) { tail = String(tail[..<cut]) }
            if PathPrefix(tail) != nil { path = tail }
        }
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        host = host.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
        return (host, path)
    }

    /// The rule as it will be saved: Website parsed (a pasted URL becomes host + path, unless
    /// a path was entered separately), path cleaned, whitespace trimmed.
    public func normalized() -> Rule {
        var copy = self
        let parsed = Self.parseWebsite(host)
        copy.host = parsed.host
        let typedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if typedPath.isEmpty, let parsedPath = parsed.path {
            copy.path = parsedPath
        } else {
            copy.path = PathPrefix(typedPath)?.prefix ?? ""
        }
        return copy
    }

    /// Kept for callers that edit in place.
    public mutating func normalizeHostField() {
        self = normalized()
    }

    /// Why this rule can't be saved, in words for the editor, or nil if it's fine.
    /// Check the `normalized()` rule.
    public var validationProblem: String? {
        if !host.isEmpty, host.allSatisfy({ $0 == "*" || $0 == "." }) {
            return hasConditionsBesidesHost
                ? "“\(host)” matches every website. Leave Website empty instead."
                : "“\(host)” would catch every link. To choose where links no rule matches go, use “When no rule matches” under the rules."
        }
        if !host.isEmpty {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_*:[]"))
            if host.unicodeScalars.contains(where: { !allowed.contains($0) }) || host.hasPrefix(".") || host.contains("..") {
                return "“\(host)” isn't a website. Use a name like example.com or *.example.com."
            }
            if HostPattern(host) == nil {
                return "Enter a website, like example.com."
            }
        }
        if path.contains(where: \.isWhitespace) {
            return "Paths can't contain spaces."
        }
        if !hasConditions {
            return "Add a website, path, app or key to match."
        }
        return nil
    }

    private var hasConditionsBesidesHost: Bool {
        PathPrefix(path) != nil || sourceApp != nil || !modifiers.isEmpty
    }

    /// True if holding this rule's keys always shows the picker instead (the "always show the
    /// picker while holding" setting wins), so the rule can never run.
    public func isBlocked(byAskModifiers ask: Modifiers) -> Bool {
        !ask.isEmpty && !modifiers.isEmpty && modifiers.isSuperset(of: ask)
    }

    /// True if this rule matches every link `other` matches, so `other` placed below it
    /// could never be used. Conservative: says false when unsure.
    public func covers(_ other: Rule) -> Bool {
        guard hasConditions, other.hasConditions else { return false }
        if let mine = HostPattern(host) {
            guard let theirs = HostPattern(other.host), mine.covers(theirs) else { return false }
        }
        if let mine = PathPrefix(path) {
            guard let theirs = PathPrefix(other.path), theirs.prefix.hasPrefix(mine.prefix) else { return false }
        }
        if let sourceApp {
            guard let theirs = other.sourceApp,
                  theirs.bundleID.caseInsensitiveCompare(sourceApp.bundleID) == .orderedSame else { return false }
        }
        return other.modifiers.isSuperset(of: modifiers)
    }

    /// "*.example.com/docs from Slack with ⌥", or "Any link" (never for a valid rule).
    public var conditionSummary: String {
        var parts: [String] = []
        let hostText = host.trimmingCharacters(in: .whitespaces)
        let pathText = PathPrefix(path)?.prefix ?? ""
        if !hostText.isEmpty { parts.append(hostText + pathText) } else if !pathText.isEmpty { parts.append("Path \(pathText)") }
        if let sourceApp { parts.append(parts.isEmpty ? "Links from \(sourceApp.name)" : "from \(sourceApp.name)") }
        if !modifiers.isEmpty { parts.append(parts.isEmpty ? "Holding \(modifiers.symbol)" : "holding \(modifiers.symbol)") }
        return parts.isEmpty ? "Any link" : parts.joined(separator: " ")
    }
}

/// What happens when no rule matches.
public enum Fallback: Codable, Hashable, Sendable {
    case ask
    case open(targetID: UUID)
}

/// Everything the user configures. Saved as JSON.
public struct Config: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var targets: [Target]
    public var rules: [Rule]
    public var fallback: Fallback
    /// Holding these keys while clicking a link always shows the picker. Empty = off.
    public var askModifiers: Modifiers
    /// True once the browser list has been filled from what's installed.
    public var didSeedTargets: Bool
    /// Browsers the user removed. Rules keep pointing at them (and show the picker meanwhile),
    /// so adding the same browser back reconnects those rules.
    public var removedTargets: [Target]

    public init(
        targets: [Target] = [],
        rules: [Rule] = [],
        fallback: Fallback = .ask,
        askModifiers: Modifiers = .option,
        didSeedTargets: Bool = false,
        removedTargets: [Target] = []
    ) {
        self.version = Self.currentVersion
        self.targets = targets
        self.rules = rules
        self.fallback = fallback
        self.askModifiers = askModifiers
        self.didSeedTargets = didSeedTargets
        self.removedTargets = removedTargets
    }

    private enum CodingKeys: String, CodingKey {
        case version, targets, rules, fallback, askModifiers, didSeedTargets, removedTargets
    }

    /// Fields added after 0.1.0 are optional, so older settings files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        targets = try c.decode([Target].self, forKey: .targets)
        rules = try c.decode([Rule].self, forKey: .rules)
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .ask
        askModifiers = try c.decodeIfPresent(Modifiers.self, forKey: .askModifiers) ?? .option
        didSeedTargets = try c.decodeIfPresent(Bool.self, forKey: .didSeedTargets) ?? true
        removedTargets = try c.decodeIfPresent([Target].self, forKey: .removedTargets) ?? []
    }

    public func target(id: UUID) -> Target? {
        targets.first { $0.id == id }
    }

    /// A removed browser that rules still point at.
    public func removedTarget(id: UUID) -> Target? {
        removedTargets.first { $0.id == id }
    }

    /// Targets offered in the picker, in order. Order = number keys.
    public var pickerTargets: [Target] {
        targets.filter { !$0.isHidden }
    }

    /// Indexes of rules that open in this target.
    public func rulesUsing(_ targetID: UUID) -> [Int] {
        rules.indices.filter { rules[$0].action == .open(targetID: targetID) }
    }

    /// Removes a target from the list. Rules and the fallback keep pointing at it: until it's
    /// added back they show the picker instead (see `Router`).
    public mutating func removeTarget(id: UUID) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        let removed = targets.remove(at: index)
        let stillReferenced = !rulesUsing(id).isEmpty || fallback == .open(targetID: id)
        removedTargets.removeAll { $0.destinationKey == removed.destinationKey || $0.id == removed.id }
        if stillReferenced { removedTargets.append(removed) }
    }

    /// Adds a target, or shows it again if it's already listed. A previously removed target
    /// for the same browser/profile comes back with its old identity, so its rules reconnect.
    /// Returns the id of the target in the list.
    @discardableResult
    public mutating func addTarget(_ target: Target) -> UUID {
        if let existing = targets.firstIndex(where: { $0.isSameDestination(as: target) }) {
            targets[existing].isHidden = false
            return targets[existing].id
        }
        if let tombstone = removedTargets.firstIndex(where: { $0.destinationKey == target.destinationKey }),
           !targets.contains(where: { $0.id == removedTargets[tombstone].id }) {
            var restored = target
            restored.id = removedTargets[tombstone].id
            removedTargets.remove(at: tombstone)
            targets.append(restored)
            return restored.id
        }
        targets.append(target)
        return target.id
    }
}

/// Finds rules that can never be used because an earlier rule catches all their links.
public enum RuleAnalysis {
    /// Why a rule can never run, if it can't.
    public enum Unused: Equatable, Sendable {
        /// An earlier rule (index) catches all its links first.
        case shadowed(by: Int)
        /// Its keys are the "always show the picker" keys, which win.
        case askModifiers
    }

    public static func unused(in rules: [Rule], askModifiers: Modifiers) -> [Unused?] {
        let shadows = shadowing(in: rules)
        return rules.indices.map { i in
            guard rules[i].isEnabled else { return nil }
            if rules[i].isBlocked(byAskModifiers: askModifiers) { return .askModifiers }
            return shadows[i].map { .shadowed(by: $0) }
        }
    }

    /// For each rule, the index of an earlier enabled rule that covers it, if any.
    public static func shadowing(in rules: [Rule]) -> [Int?] {
        rules.indices.map { j in
            guard rules[j].isEnabled else { return nil }
            return rules.indices.prefix(j).first { i in rules[i].isEnabled && rules[i].covers(rules[j]) }
        }
    }
}
