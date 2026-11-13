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
    /// Which links the rule is for. Web rules match websites and paths; email rules match
    /// the address (`host` holds `example.com` or `name@example.com`); file rules match
    /// `fileExtensions`. Rules from before email and files existed are web rules.
    public var kind: LinkKind
    /// File rules: extensions, lowercased, without dots ("pdf"). Empty = any file.
    public var fileExtensions: [String]

    public init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        kind: LinkKind = .web,
        host: String = "",
        path: String = "",
        fileExtensions: [String] = [],
        sourceApp: SourceAppMatch? = nil,
        modifiers: Modifiers = [],
        action: RuleAction
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.kind = kind
        self.host = host
        self.path = path
        self.fileExtensions = fileExtensions
        self.sourceApp = sourceApp
        self.modifiers = modifiers
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, host, path, sourceApp, modifiers, action, kind, fileExtensions
    }

    /// `kind` and `fileExtensions` are new: older settings files don't have them.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        sourceApp = try c.decodeIfPresent(SourceAppMatch.self, forKey: .sourceApp)
        modifiers = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []
        action = try c.decode(RuleAction.self, forKey: .action)
        // A kind from a newer version this one doesn't know: keep the rule, turned off, rather
        // than failing the whole file or letting it catch web links.
        if c.contains(.kind), (try? c.decode(LinkKind.self, forKey: .kind)) == nil {
            kind = .web
            isEnabled = false
        } else {
            kind = try c.decodeIfPresent(LinkKind.self, forKey: .kind) ?? .web
        }
        fileExtensions = try c.decodeIfPresent([String].self, forKey: .fileExtensions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(kind, forKey: .kind)
        try c.encode(host, forKey: .host)
        try c.encode(path, forKey: .path)
        if kind == .file || !fileExtensions.isEmpty { try c.encode(fileExtensions, forKey: .fileExtensions) }
        try c.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try c.encode(modifiers, forKey: .modifiers)
        try c.encode(action, forKey: .action)
    }

    /// The website pattern, for web rules.
    var hostPattern: HostPattern? { kind == .web ? HostPattern(host) : nil }
    /// The path prefix, for web rules.
    var pathPrefix: PathPrefix? { kind == .web ? PathPrefix(path) : nil }
    /// The address pattern, for email rules.
    var addressPattern: AddressPattern? { kind == .email ? AddressPattern(host) : nil }
    /// The extensions, for file rules.
    var extensionSet: Set<String> { kind == .file ? Set(fileExtensions.map { $0.lowercased() }) : [] }

    /// A rule needs at least one condition, or it would swallow every link.
    public var hasConditions: Bool {
        hostPattern != nil || pathPrefix != nil || addressPattern != nil || !extensionSet.isEmpty
            || sourceApp != nil || !modifiers.isEmpty
    }

    public func matches(_ link: IncomingLink) -> Bool {
        guard isEnabled, hasConditions, link.kind == kind else { return false }
        if let pattern = hostPattern, !pattern.matches(link.url) { return false }
        if let prefix = pathPrefix, !prefix.matches(link.url) { return false }
        if let pattern = addressPattern {
            guard let mail = MailtoLink(link.url), mail.recipients.contains(where: pattern.matches(address:)) else { return false }
        }
        let extensions = extensionSet
        if !extensions.isEmpty, !extensions.contains(link.url.pathExtension.lowercased()) { return false }
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
        switch kind {
        case .web: break
        case .email:
            var text = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if text.hasPrefix("mailto:") { text.removeFirst(7) }
            if text.hasPrefix("*@") || text.hasPrefix("@") { text.removeFirst(text.hasPrefix("*@") ? 2 : 1) }
            copy.host = text
            copy.path = ""
            copy.fileExtensions = []
            return copy
        case .file:
            copy.host = ""
            copy.path = ""
            copy.fileExtensions = FileType.parseExtensions(fileExtensions.joined(separator: " "))
            return copy
        }
        copy.fileExtensions = []
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
        switch kind {
        case .web: break
        case .email:
            if !host.isEmpty, host.allSatisfy({ $0 == "*" || $0 == "." || $0 == "@" }) {
                return "“\(host)” matches every address. Leave To empty instead."
            }
            if !host.isEmpty, AddressPattern(host) == nil || host.contains(where: \.isWhitespace) {
                return "“\(host)” isn't an email address or domain. Use name@example.com or example.com."
            }
            return hasConditions ? nil : "Add an address, app or key to match."
        case .file:
            if let bad = fileExtensions.first(where: { !FileType.isValidExtension($0) }) {
                return "“\(bad)” isn't a file extension. Use extensions like pdf or docx."
            }
            return hasConditions ? nil : "Add a file type, app or key to match."
        }
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
        pathPrefix != nil || sourceApp != nil || !modifiers.isEmpty
    }

    /// True if holding this rule's keys always shows the picker instead (the "always show the
    /// picker while holding" setting wins), so the rule can never run.
    public func isBlocked(byAskModifiers ask: Modifiers) -> Bool {
        !ask.isEmpty && !modifiers.isEmpty && modifiers.isSuperset(of: ask)
    }

    /// True if this rule matches every link `other` matches, so `other` placed below it
    /// could never be used. Conservative: says false when unsure.
    public func covers(_ other: Rule) -> Bool {
        guard kind == other.kind, hasConditions, other.hasConditions else { return false }
        if let mine = hostPattern {
            guard let theirs = other.hostPattern, mine.covers(theirs) else { return false }
        }
        if let mine = pathPrefix {
            guard let theirs = other.pathPrefix, theirs.prefix.hasPrefix(mine.prefix) else { return false }
        }
        if let mine = addressPattern {
            guard let theirs = other.addressPattern, mine.covers(theirs) else { return false }
        }
        let mine = extensionSet
        if !mine.isEmpty {
            let theirs = other.extensionSet
            guard !theirs.isEmpty, theirs.isSubset(of: mine) else { return false }
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
        switch kind {
        case .web:
            let hostText = host.trimmingCharacters(in: .whitespaces)
            let pathText = pathPrefix?.prefix ?? ""
            if !hostText.isEmpty { parts.append(hostText + pathText) } else if !pathText.isEmpty { parts.append("Path \(pathText)") }
        case .email:
            let to = host.trimmingCharacters(in: .whitespaces)
            parts.append(to.isEmpty ? "Email" : "Email to \(to)")
        case .file:
            let exts = fileExtensions.map { "." + $0 }
            parts.append(exts.isEmpty ? "Files" : "\(ListFormatter.localizedString(byJoining: exts)) files")
        }
        if let sourceApp {
            parts.append("\(parts.isEmpty ? "Links from" : "from") \(sourceApp.name)")
        }
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
    /// 2: email targets, file types, rewrites and app handoffs. Version 1 files load as they
    /// are (everything new starts empty or off).
    public static let currentVersion = 2

    public var version: Int
    /// Browsers (and other apps) for web links and web pages. Order = number keys.
    public var targets: [Target]
    /// All rules, of every kind, in order. A rule only ever matches links of its kind.
    public var rules: [Rule]
    /// Web links no rule matches.
    public var fallback: Fallback
    /// Holding these keys while clicking a link always shows the picker. Empty = off.
    public var askModifiers: Modifiers
    /// True once the browser list has been filled from what's installed.
    public var didSeedTargets: Bool
    /// Browsers the user removed. Rules keep pointing at them (and show the picker meanwhile),
    /// so adding the same browser back reconnects those rules.
    public var removedTargets: [Target]
    /// Row size in the picker.
    public var pickerSize: PickerSize
    /// Remove ad/campaign tracking parameters (utm_…, fbclid, …) before routing. Off by default.
    public var stripsTrackingParameters: Bool
    /// Mail apps and webmail, for email links. Order = number keys in their picker.
    public var emailTargets: [Target]
    /// Email links no rule matches.
    public var emailFallback: Fallback
    /// File types Switchboard was set up to open, with where each goes by default.
    public var fileTypes: [FileType]
    /// Applied to web links in order, before routing.
    public var rewrites: [Rewrite]
    /// Turned-on app handoffs (`Handoffs.all` ids), checked before rules.
    public var handoffs: [String]

    public init(
        targets: [Target] = [],
        rules: [Rule] = [],
        fallback: Fallback = .ask,
        askModifiers: Modifiers = .option,
        didSeedTargets: Bool = false,
        removedTargets: [Target] = [],
        pickerSize: PickerSize = .medium,
        stripsTrackingParameters: Bool = false,
        emailTargets: [Target] = [],
        emailFallback: Fallback = .ask,
        fileTypes: [FileType] = [],
        rewrites: [Rewrite] = [],
        handoffs: [String] = []
    ) {
        self.version = Self.currentVersion
        self.targets = targets
        self.rules = rules
        self.fallback = fallback
        self.askModifiers = askModifiers
        self.didSeedTargets = didSeedTargets
        self.removedTargets = removedTargets
        self.pickerSize = pickerSize
        self.stripsTrackingParameters = stripsTrackingParameters
        self.emailTargets = emailTargets
        self.emailFallback = emailFallback
        self.fileTypes = fileTypes
        self.rewrites = rewrites
        self.handoffs = handoffs
    }

    private enum CodingKeys: String, CodingKey {
        case version, targets, rules, fallback, askModifiers, didSeedTargets, removedTargets
        case pickerSize, stripsTrackingParameters
        case emailTargets, emailFallback, fileTypes, rewrites, handoffs
    }

    /// Fields added after 0.1.0 are optional, so older settings files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = Self.currentVersion
        targets = try c.decode([Target].self, forKey: .targets)
        rules = try c.decode([Rule].self, forKey: .rules)
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .ask
        askModifiers = try c.decodeIfPresent(Modifiers.self, forKey: .askModifiers) ?? .option
        didSeedTargets = try c.decodeIfPresent(Bool.self, forKey: .didSeedTargets) ?? true
        removedTargets = try c.decodeIfPresent([Target].self, forKey: .removedTargets) ?? []
        // An unknown size (from a newer version) falls back to the default instead of failing.
        pickerSize = (try? c.decodeIfPresent(PickerSize.self, forKey: .pickerSize)) ?? .medium
        stripsTrackingParameters = try c.decodeIfPresent(Bool.self, forKey: .stripsTrackingParameters) ?? false
        emailTargets = try c.decodeIfPresent([Target].self, forKey: .emailTargets) ?? []
        emailFallback = try c.decodeIfPresent(Fallback.self, forKey: .emailFallback) ?? .ask
        fileTypes = try c.decodeIfPresent([FileType].self, forKey: .fileTypes) ?? []
        rewrites = try c.decodeIfPresent([Rewrite].self, forKey: .rewrites) ?? []
        handoffs = try c.decodeIfPresent([String].self, forKey: .handoffs) ?? []
    }

    /// Any target: a browser, an email app or webmail, or a file type's app.
    public func target(id: UUID) -> Target? {
        targets.first { $0.id == id } ?? emailTargets.first { $0.id == id }
            ?? fileTypes.lazy.compactMap(\.app).first { $0.id == id }
    }

    /// A removed browser that rules still point at.
    public func removedTarget(id: UUID) -> Target? {
        removedTargets.first { $0.id == id }
    }

    /// Targets offered in the picker, in order. Order = number keys.
    public var pickerTargets: [Target] {
        targets.filter { !$0.isHidden }
    }

    /// What the picker offers for this link: browsers for web links; email apps for email;
    /// for a file, the app its type normally opens in, then the browsers.
    public func pickerTargets(for link: IncomingLink) -> [Target] {
        switch link.kind {
        case .email:
            return emailTargets.filter { !$0.isHidden }
        case .file:
            let usual = fileTypes.type(for: link.url)?.app.map { [$0] } ?? []
            return usual + pickerTargets.filter { browser in !usual.contains { $0.bundleID == browser.bundleID && browser.profile == nil } }
        case .web, nil:
            return pickerTargets
        }
    }

    /// Where links of this kind go when no rule matches.
    public func fallback(for link: IncomingLink) -> Fallback {
        switch link.kind {
        case .email: emailFallback
        case .file: fileTypes.type(for: link.url)?.fallback ?? .ask
        case .web, nil: fallback
        }
    }

    /// Indexes of rules that open in this target.
    public func rulesUsing(_ targetID: UUID) -> [Int] {
        rules.indices.filter { rules[$0].action == .open(targetID: targetID) }
    }

    /// True if a rule or a "when no rule matches" choice opens in this target.
    public func isReferenced(_ targetID: UUID) -> Bool {
        let open = Fallback.open(targetID: targetID)
        return !rulesUsing(targetID).isEmpty || fallback == open || emailFallback == open
            || fileTypes.contains { $0.fallback == open }
    }

    /// Removes a browser or email target from its list. Rules and fallbacks keep pointing at
    /// it: until it's added back they show the picker instead (see `Router`).
    public mutating func removeTarget(id: UUID) {
        let removed: Target
        if let index = targets.firstIndex(where: { $0.id == id }) {
            removed = targets.remove(at: index)
        } else if let index = emailTargets.firstIndex(where: { $0.id == id }) {
            removed = emailTargets.remove(at: index)
        } else {
            return
        }
        removedTargets.removeAll { $0.destinationKey == removed.destinationKey || $0.id == removed.id }
        if isReferenced(id) { removedTargets.append(removed) }
    }

    /// Adds a browser, or shows it again if it's already listed. A previously removed target
    /// for the same browser/profile comes back with its old identity, so its rules reconnect.
    /// Returns the id of the target in the list.
    @discardableResult
    public mutating func addTarget(_ target: Target) -> UUID {
        add(target, to: \.targets)
    }

    /// Adds a mail app or webmail to the email list (same rules as `addTarget`).
    @discardableResult
    public mutating func addEmailTarget(_ target: Target) -> UUID {
        add(target, to: \.emailTargets)
    }

    private mutating func add(_ target: Target, to list: WritableKeyPath<Config, [Target]>) -> UUID {
        if let existing = self[keyPath: list].firstIndex(where: { $0.isSameDestination(as: target) }) {
            self[keyPath: list][existing].isHidden = false
            return self[keyPath: list][existing].id
        }
        if let tombstone = removedTargets.firstIndex(where: { $0.destinationKey == target.destinationKey }),
           self.target(id: removedTargets[tombstone].id) == nil {
            var restored = target
            restored.id = removedTargets[tombstone].id
            removedTargets.remove(at: tombstone)
            self[keyPath: list].append(restored)
            return restored.id
        }
        self[keyPath: list].append(target)
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
