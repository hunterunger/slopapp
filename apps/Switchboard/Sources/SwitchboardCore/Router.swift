import Foundation

/// Why a link went where it did. Shown in the rule tester and debug logs.
public enum RouteReason: Equatable, Sendable {
    case rule(index: Int)
    case fallback
    case askModifier
    case forced
    /// A rule matched but its target is gone (removed or uninstalled).
    case missingTarget(ruleIndex: Int)
    case onlyOneTarget
    /// A turned-on app handoff took the link (see `Handoffs`).
    case handoff(id: String)
    /// A rewrite turned the link into an app's own link.
    case rewrite
}

public enum RouteDecision: Equatable, Sendable {
    case open(Target, reason: RouteReason)
    case pick([Target], reason: RouteReason)
    /// Straight to an app, as the app's own link (a handoff, or a rewrite's result).
    case openInApp(AppLink, reason: RouteReason)
    /// Nothing to open it in: every target is hidden or missing.
    case noTargets

    public var reason: RouteReason? {
        switch self {
        case .open(_, let reason), .pick(_, let reason), .openInApp(_, let reason): reason
        case .noTargets: nil
        }
    }
}

/// Decides where a link goes. Pure and fast: no disk, no network, no allocation-heavy work.
public enum Router {
    /// - Parameters:
    ///   - isInstalled: whether a target's app still exists. Defaults to "yes".
    ///   - installedApp: which of a handoff's apps is installed (its bundle id), if any.
    public static func route(
        _ link: IncomingLink,
        config: Config,
        isInstalled: (Target) -> Bool = { _ in true },
        installedApp: (AppHandoff) -> String? = { _ in nil }
    ) -> RouteDecision {
        // An app's own link (a rewrite made it): straight to that app, no browser involved.
        guard let kind = link.kind else {
            return .openInApp(AppLink(url: link.url), reason: .rewrite)
        }
        let available = config.pickerTargets(for: link).filter(isInstalled)

        func pick(_ reason: RouteReason) -> RouteDecision {
            switch available.count {
            case 0: .noTargets
            case 1 where reason != .forced && reason != .askModifier: .open(available[0], reason: .onlyOneTarget)
            default: .pick(available, reason: reason)
            }
        }

        if link.forcePicker { return pick(.forced) }
        if !config.askModifiers.isEmpty, link.modifiers.isSuperset(of: config.askModifiers) {
            return pick(.askModifier)
        }

        // Apps that open their own links better, before any rule (they're specific: a
        // meeting link, an album). Holding the picker key is the way to a browser instead.
        if kind == .web, !link.url.isFileURL,
           let app = Handoffs.match(link.url, enabled: config.handoffs, source: link.sourceBundleID, installedApp: installedApp) {
            return .openInApp(app, reason: .handoff(id: app.handoffID ?? ""))
        }

        for (index, rule) in config.rules.enumerated() where rule.matches(link) {
            switch rule.action {
            case .ask:
                return pick(.rule(index: index))
            case .open(let id):
                if let target = config.target(id: id), isInstalled(target) {
                    return .open(target, reason: .rule(index: index))
                }
                return pick(.missingTarget(ruleIndex: index))
            }
        }

        switch config.fallback(for: link) {
        case .ask:
            return pick(.fallback)
        case .open(let id):
            if let target = config.target(id: id), isInstalled(target) {
                return .open(target, reason: .fallback)
            }
            return pick(.fallback)
        }
    }

    /// The browser the rules would choose, ignoring "show the picker" requests (forced picks,
    /// the ask keys). Used to preselect it when the picker shows anyway.
    public static func preferredTarget(
        for link: IncomingLink, config: Config, isInstalled: (Target) -> Bool = { _ in true }
    ) -> Target? {
        var plain = link
        plain.forcePicker = false
        var cfg = config
        cfg.askModifiers = []
        if case .open(let target, let reason) = route(plain, config: cfg, isInstalled: isInstalled), reason != .onlyOneTarget {
            return target
        }
        return nil
    }

    /// One line for the rule tester: "Opens in Google Chrome (Work), rule 2".
    public static func describe(_ decision: RouteDecision, kind: LinkKind? = .web) -> String {
        switch decision {
        case .noTargets:
            return kind == .email
                ? "Nothing to write it in. Add a mail app or webmail in the Email tab."
                : "Nothing to open it in. Add a browser in the Browsers tab."
        case .openInApp(let app, let reason):
            if let name = app.appName { return "Opens in \(name)" + suffix(reason) }
            return "Opens in the app for \(app.url.scheme ?? "these") links" + suffix(reason)
        case .open(let target, let reason):
            return "Opens in \(target.displayName)" + suffix(reason)
        case .pick(_, let reason):
            return "Shows the picker" + suffix(reason)
        }
    }

    private static func suffix(_ reason: RouteReason) -> String {
        switch reason {
        case .rule(let index): " (rule \(index + 1))"
        case .fallback: " (no rule matches)"
        case .askModifier: " (key held)"
        case .forced: ""
        case .missingTarget(let index): " (rule \(index + 1)'s browser is missing)"
        case .onlyOneTarget: " (the only choice)"
        case .handoff: " (Open in apps)"
        case .rewrite: " (a rewrite)"
        }
    }

    /// Builds the rule that "always open this here" creates from the picker: the link's host
    /// for a web link, the recipient's domain for an email, the extension for a file.
    public static func alwaysOpenRule(for url: URL, in target: Target) -> Rule? {
        switch LinkKind.of(url) {
        case .email:
            guard let address = MailtoLink(url)?.to.first, let domain = MailtoLink.domain(of: address) else { return nil }
            return Rule(kind: .email, host: Punycode.displayHost(domain), action: .open(targetID: target.id))
        case .file:
            let ext = url.pathExtension.lowercased()
            guard FileType.isValidExtension(ext) else { return nil }
            return Rule(kind: .file, fileExtensions: [ext], action: .open(targetID: target.id))
        case .web, nil:
            guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
            var base = host
            if base.hasPrefix("www.") { base.removeFirst(4) }
            var pattern = Punycode.displayHost(base)
            if let port = url.port { pattern += ":\(port)" }
            return Rule(host: pattern, action: .open(targetID: target.id))
        }
    }

    /// What "Always Open … Here" says for this link: "example.com", "email to example.com",
    /// ".pdf files"; nil when there's no rule to make (a local web page).
    public static func alwaysOpenLabel(for url: URL) -> String? {
        guard let rule = alwaysOpenRule(for: url, in: Target(bundleID: "", appPath: "", appName: "")) else { return nil }
        switch rule.kind {
        case .web: return rule.host
        case .email: return "Email to \(rule.host)"
        case .file: return ".\(rule.fileExtensions.first ?? "") Files"
        }
    }

    /// The existing rule a learned rule replaces: same kind and condition, nothing else.
    public static func learnedRuleTwin(of rule: Rule, in rules: [Rule]) -> Int? {
        rules.firstIndex {
            $0.kind == rule.kind && $0.host.caseInsensitiveCompare(rule.host) == .orderedSame
                && Set($0.fileExtensions) == Set(rule.fileExtensions)
                && PathPrefix($0.path) == nil && $0.sourceApp == nil && $0.modifiers.isEmpty
        }
    }

    /// Inserts a learned rule ("always open this host here"). An existing rule for exactly the
    /// same host with no other conditions is updated in place, so repeated picks don't pile up.
    /// Otherwise the rule goes above broader rules but below any more specific rule it would
    /// otherwise hide (e.g. example.org/docs stays above a learned example.org).
    /// Returns where the rule ended up.
    @discardableResult
    public static func insertLearnedRule(_ rule: Rule, into config: inout Config) -> Int {
        if let index = learnedRuleTwin(of: rule, in: config.rules) {
            config.rules[index].action = rule.action
            config.rules[index].isEnabled = true
            return index
        }
        let index = learnedRuleIndex(for: rule, in: config.rules)
        config.rules.insert(rule, at: index)
        return index
    }

    /// Just below the last existing rule that the new rule would hide; the top if none.
    public static func learnedRuleIndex(for rule: Rule, in rules: [Rule]) -> Int {
        guard let last = rules.lastIndex(where: { rule.covers($0) }) else { return 0 }
        return last + 1
    }
}
