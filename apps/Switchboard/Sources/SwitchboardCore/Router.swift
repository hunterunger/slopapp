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
}

public enum RouteDecision: Equatable, Sendable {
    case open(Target, reason: RouteReason)
    case pick([Target], reason: RouteReason)
    /// Nothing to open it in: every target is hidden or missing.
    case noTargets

    public var reason: RouteReason? {
        switch self {
        case .open(_, let reason), .pick(_, let reason): reason
        case .noTargets: nil
        }
    }
}

/// Decides where a link goes. Pure and fast: no disk, no network, no allocation-heavy work.
public enum Router {
    /// - Parameter isInstalled: whether a target's app still exists. Defaults to "yes".
    public static func route(
        _ link: IncomingLink,
        config: Config,
        isInstalled: (Target) -> Bool = { _ in true }
    ) -> RouteDecision {
        let available = config.pickerTargets.filter(isInstalled)

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

        switch config.fallback {
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
    public static func describe(_ decision: RouteDecision) -> String {
        switch decision {
        case .noTargets:
            return "Nothing to open it in. Add a browser in the Browsers tab."
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
        case .onlyOneTarget: " (the only browser)"
        }
    }

    /// Builds the rule that "always open this host here" creates from the picker.
    public static func alwaysOpenRule(for url: URL, in target: Target) -> Rule? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        var base = host
        if base.hasPrefix("www.") { base.removeFirst(4) }
        var pattern = Punycode.displayHost(base)
        if let port = url.port { pattern += ":\(port)" }
        return Rule(host: pattern, action: .open(targetID: target.id))
    }

    /// Inserts a learned rule ("always open this host here"). An existing rule for exactly the
    /// same host with no other conditions is updated in place, so repeated picks don't pile up.
    /// Otherwise the rule goes above broader rules but below any more specific rule it would
    /// otherwise hide (e.g. example.org/docs stays above a learned example.org).
    /// Returns where the rule ended up.
    @discardableResult
    public static func insertLearnedRule(_ rule: Rule, into config: inout Config) -> Int {
        if let index = config.rules.firstIndex(where: {
            $0.host.caseInsensitiveCompare(rule.host) == .orderedSame
                && PathPrefix($0.path) == nil && $0.sourceApp == nil && $0.modifiers.isEmpty
        }) {
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
