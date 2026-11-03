import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

private let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")
private let chrome = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome")
private let chromeWork = Target(
    bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome",
    profile: BrowserProfile(directory: "Profile 1", name: "Work")
)

@Suite("Router")
struct RouterTests {
    func config(rules: [Rule] = [], fallback: Fallback = .ask, ask: Modifiers = .option, targets: [Target] = [safari, chrome, chromeWork]) -> Config {
        Config(targets: targets, rules: rules, fallback: fallback, askModifiers: ask, didSeedTargets: true)
    }

    @Test("No rules: the picker, with visible targets in order")
    func fallbackAsk() {
        let decision = Router.route(IncomingLink(url: url("https://example.com")), config: config())
        #expect(decision == .pick([safari, chrome, chromeWork], reason: .fallback))
    }

    @Test("Fallback can open a chosen target")
    func fallbackOpen() {
        let decision = Router.route(IncomingLink(url: url("https://example.com")), config: config(fallback: .open(targetID: chrome.id)))
        #expect(decision == .open(chrome, reason: .fallback))
    }

    @Test("First matching rule wins")
    func ordering() {
        let rules = [
            Rule(host: "docs.example.com", action: .open(targetID: chromeWork.id)),
            Rule(host: "*.example.com", action: .open(targetID: safari.id)),
        ]
        #expect(Router.route(IncomingLink(url: url("https://docs.example.com/a")), config: config(rules: rules))
            == .open(chromeWork, reason: .rule(index: 0)))
        #expect(Router.route(IncomingLink(url: url("https://www.example.com")), config: config(rules: rules))
            == .open(safari, reason: .rule(index: 1)))
        #expect(Router.route(IncomingLink(url: url("https://other.org")), config: config(rules: rules))
            == .pick([safari, chrome, chromeWork], reason: .fallback))
    }

    @Test("Holding the ask key beats rules")
    func askModifier() {
        let rules = [Rule(host: "example.com", action: .open(targetID: safari.id))]
        let link = IncomingLink(url: url("https://example.com"), modifiers: [.option, .shift])
        #expect(Router.route(link, config: config(rules: rules)) == .pick([safari, chrome, chromeWork], reason: .askModifier))
        // Turned off: rules apply.
        #expect(Router.route(link, config: config(rules: rules, ask: [])) == .open(safari, reason: .rule(index: 0)))
    }

    @Test("A rule can require modifiers")
    func ruleModifiers() {
        let rules = [Rule(modifiers: [.command], action: .open(targetID: chrome.id))]
        #expect(Router.route(IncomingLink(url: url("https://x.com"), modifiers: [.command]), config: config(rules: rules))
            == .open(chrome, reason: .rule(index: 0)))
        #expect(Router.route(IncomingLink(url: url("https://x.com")), config: config(rules: rules)).reason == .fallback)
    }

    @Test("Source-app rules")
    func sourceApp() {
        let rules = [Rule(sourceApp: SourceAppMatch(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"), action: .open(targetID: chromeWork.id))]
        #expect(Router.route(IncomingLink(url: url("https://x.com"), sourceBundleID: "com.tinyspeck.slackmacgap"), config: config(rules: rules))
            == .open(chromeWork, reason: .rule(index: 0)))
        #expect(Router.route(IncomingLink(url: url("https://x.com"), sourceBundleID: nil), config: config(rules: rules)).reason == .fallback)
    }

    @Test("A rule whose target is gone falls back to the picker")
    func missingTarget() {
        let gone = UUID()
        let rules = [Rule(host: "example.com", action: .open(targetID: gone))]
        #expect(Router.route(IncomingLink(url: url("https://example.com")), config: config(rules: rules))
            == .pick([safari, chrome, chromeWork], reason: .missingTarget(ruleIndex: 0)))
        // Uninstalled app.
        let rules2 = [Rule(host: "example.com", action: .open(targetID: chrome.id))]
        let decision = Router.route(IncomingLink(url: url("https://example.com")), config: config(rules: rules2)) { $0.bundleID != "com.google.Chrome" }
        #expect(decision == .open(safari, reason: .onlyOneTarget))
    }

    @Test("Hidden targets aren't offered, but rules can still use them")
    func hidden() {
        var hiddenChrome = chrome; hiddenChrome.isHidden = true
        let cfg = config(rules: [Rule(host: "example.com", action: .open(targetID: chrome.id))], targets: [safari, hiddenChrome, chromeWork])
        #expect(Router.route(IncomingLink(url: url("https://example.com")), config: cfg) == .open(hiddenChrome, reason: .rule(index: 0)))
        #expect(Router.route(IncomingLink(url: url("https://other.com")), config: cfg) == .pick([safari, chromeWork], reason: .fallback))
    }

    @Test("One visible target opens directly, unless the picker was asked for")
    func singleTarget() {
        let cfg = config(targets: [safari])
        #expect(Router.route(IncomingLink(url: url("https://x.com")), config: cfg) == .open(safari, reason: .onlyOneTarget))
        #expect(Router.route(IncomingLink(url: url("https://x.com"), modifiers: .option), config: cfg) == .pick([safari], reason: .askModifier))
        #expect(Router.route(IncomingLink(url: url("https://x.com"), forcePicker: true), config: cfg) == .pick([safari], reason: .forced))
    }

    @Test("No visible targets")
    func noTargets() {
        var s = safari; s.isHidden = true
        #expect(Router.route(IncomingLink(url: url("https://x.com")), config: config(targets: [s])) == .noTargets)
        #expect(Router.route(IncomingLink(url: url("https://x.com")), config: config(targets: [])) == .noTargets)
    }

    @Test("Descriptions for the rule tester")
    func describe() {
        #expect(Router.describe(.open(chromeWork, reason: .rule(index: 1))) == "Opens in Google Chrome (Work) (rule 2)")
        #expect(Router.describe(.pick([], reason: .fallback)) == "Shows the picker (no rule matches)")
    }

    @Test("Always open here builds a host rule and replaces an older one")
    func learnedRule() {
        var cfg = config()
        let rule = Router.alwaysOpenRule(for: url("https://www.Example.com/a?b"), in: chrome)!
        #expect(rule.host == "example.com")
        Router.insertLearnedRule(rule, into: &cfg)
        #expect(cfg.rules.count == 1)
        let again = Router.alwaysOpenRule(for: url("https://example.com/other"), in: safari)!
        Router.insertLearnedRule(again, into: &cfg)
        #expect(cfg.rules.count == 1)
        #expect(cfg.rules[0].action == .open(targetID: safari.id))
        #expect(Router.alwaysOpenRule(for: url("https://xn--bcher-kva.de:8443/"), in: chrome)?.host == "bücher.de:8443")
        #expect(Router.alwaysOpenRule(for: url("file:///tmp/a.html"), in: chrome) == nil)
    }

    @Test("Removing a target keeps rules pointing at it; they show the picker until it's back")
    func removeTarget() {
        var cfg = config(rules: [Rule(host: "a.com", action: .open(targetID: chrome.id))], fallback: .open(targetID: chrome.id))
        cfg.removeTarget(id: chrome.id)
        #expect(cfg.targets == [safari, chromeWork])
        #expect(cfg.rules[0].action == .open(targetID: chrome.id))
        #expect(cfg.fallback == .open(targetID: chrome.id))
        #expect(cfg.removedTarget(id: chrome.id)?.appName == "Google Chrome")
        #expect(Router.route(IncomingLink(url: url("https://a.com")), config: cfg) == .pick([safari, chromeWork], reason: .missingTarget(ruleIndex: 0)))
        #expect(Router.route(IncomingLink(url: url("https://b.com")), config: cfg) == .pick([safari, chromeWork], reason: .fallback))

        // Adding the same browser back (a new Target value) reconnects the rule.
        let readded = cfg.addTarget(Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome"))
        #expect(readded == chrome.id)
        #expect(cfg.removedTargets.isEmpty)
        #expect(Router.route(IncomingLink(url: url("https://a.com")), config: cfg).reason == .rule(index: 0))
    }

    @Test("Removing a target nothing uses leaves no trace")
    func removeUnused() {
        var cfg = config()
        cfg.removeTarget(id: chrome.id)
        #expect(cfg.removedTargets.isEmpty)
        // A different profile of the same app doesn't take over a removed target's identity.
        var cfg2 = config(rules: [Rule(host: "a.com", action: .open(targetID: chromeWork.id))])
        cfg2.removeTarget(id: chromeWork.id)
        let other = cfg2.addTarget(Target(bundleID: "com.google.Chrome", appPath: "/A.app", appName: "Google Chrome", profile: BrowserProfile(directory: "Profile 2", name: "Home")))
        #expect(other != chromeWork.id)
        #expect(cfg2.removedTargets.count == 1)
    }

    @Test("Adding a listed destination shows it instead of duplicating")
    func addDuplicate() {
        var hidden = chrome; hidden.isHidden = true
        var cfg = config(targets: [safari, hidden])
        let id = cfg.addTarget(Target(bundleID: "com.google.Chrome", appPath: "/x", appName: "Google Chrome"))
        #expect(id == chrome.id)
        #expect(cfg.targets.count == 2)
        #expect(cfg.targets[1].isHidden == false)
    }

    @Test("Learned rules go below more specific rules, above broader ones")
    func learnedPlacement() {
        let docs = Rule(host: "example.org", path: "/docs", action: .open(targetID: chromeWork.id))
        let broad = Rule(host: "*.org", action: .open(targetID: safari.id))
        var cfg = config(rules: [docs, broad])
        let learned = Router.alwaysOpenRule(for: url("https://example.org/home"), in: chrome)!
        let index = Router.insertLearnedRule(learned, into: &cfg)
        #expect(index == 1)
        #expect(cfg.rules.map(\.host) == ["example.org", "example.org", "*.org"])
        #expect(Router.route(IncomingLink(url: url("https://example.org/docs/a")), config: cfg).reason == .rule(index: 0))
        #expect(Router.route(IncomingLink(url: url("https://example.org/home")), config: cfg) == .open(chrome, reason: .rule(index: 1)))
        #expect(RuleAnalysis.shadowing(in: cfg.rules) == [nil, nil, nil])
    }

    @Test("Old settings files without newer fields still load")
    func decodeOld() throws {
        let json = #"{"version":1,"targets":[],"rules":[],"fallback":{"ask":{}},"askModifiers":2,"didSeedTargets":true}"#
        let cfg = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(cfg.removedTargets.isEmpty)
        #expect(cfg.askModifiers == .option)
    }
}

@Suite("Rule editing")
struct RuleEditingTests {
    let t = UUID()

    @Test("A pasted URL becomes host + path, without scheme, www, query or fragment")
    func pastedURL() {
        let rule = Rule(host: "https://www.Example.com/blog/post?x=1#top", action: .ask).normalized()
        #expect(rule.host == "example.com")
        #expect(rule.path == "/blog/post")
        #expect(rule.validationProblem == nil)
        #expect(rule.matches(IncomingLink(url: url("https://www.example.com/blog/post?x=2"))))
        #expect(rule.matches(IncomingLink(url: url("https://example.com/blog/post/comments"))))
        #expect(!rule.matches(IncomingLink(url: url("https://example.com/about"))))
    }

    @Test("Bare host and wildcard pass through")
    func plain() {
        #expect(Rule(host: " Example.com ", action: .ask).normalized().host == "example.com")
        #expect(Rule(host: "*.Example.com", action: .ask).normalized().host == "*.example.com")
        #expect(Rule(host: "example.com/", action: .ask).normalized().path == "")
        #expect(Rule(host: "localhost:3000/app?debug", action: .ask).normalized().host == "localhost:3000")
        #expect(Rule(host: "www.", action: .ask).normalized().host == "www")
    }

    @Test("A separately typed path wins over the pasted one")
    func separatePath() {
        let rule = Rule(host: "https://zoom.us/j/123", path: "/my", action: .ask).normalized()
        #expect(rule.host == "zoom.us")
        #expect(rule.path == "/my")
        #expect(Rule(host: "x.com", path: "/a/b?q=1", action: .ask).normalized().path == "/a/b")
    }

    @Test("Rules that can't match are refused with a reason")
    func validation() {
        #expect(Rule(host: "my site", action: .ask).normalized().validationProblem != nil)
        #expect(Rule(host: "exa$mple.com", action: .ask).normalized().validationProblem != nil)
        #expect(Rule(host: ".example.com", action: .ask).normalized().validationProblem != nil)
        #expect(Rule(host: "", action: .ask).normalized().validationProblem == "Add a website, path, app or key to match.")
        #expect(Rule(host: "x.com", path: "/a b", action: .ask).validationProblem == "Paths can't contain spaces.")
        #expect(Rule(host: "bücher.de", action: .ask).normalized().validationProblem == nil)
        #expect(Rule(host: "[::1]:3000", action: .ask).normalized().validationProblem == nil)
        #expect(Rule(modifiers: .command, action: .ask).validationProblem == nil)
    }
}

@Suite("Shadowed rules")
struct ShadowTests {
    let a = UUID()

    @Test("Host coverage")
    func hostCoverage() {
        #expect(HostPattern("*.example.com")!.covers(HostPattern("docs.example.com")!))
        #expect(HostPattern("*.example.com")!.covers(HostPattern("example.com")!))
        #expect(HostPattern("*.example.com")!.covers(HostPattern("*.a.example.com")!))
        #expect(!HostPattern("example.com")!.covers(HostPattern("*.example.com")!))
        #expect(HostPattern("example.com")!.covers(HostPattern("www.example.com")!))
        #expect(!HostPattern("example.com")!.covers(HostPattern("docs.example.com")!))
        #expect(HostPattern("*")!.covers(HostPattern("anything.org")!))
        #expect(!HostPattern("localhost:3000")!.covers(HostPattern("localhost")!))
        #expect(HostPattern("localhost")!.covers(HostPattern("localhost:3000")!))
        #expect(HostPattern("docs.*.com")!.covers(HostPattern("docs.google.com")!) == false) // www.docs.google.com isn't docs.*.com... is: conservative either way
    }

    @Test("A broad rule above a narrow one hides it")
    func shadowing() {
        let rules = [
            Rule(host: "*.example.com", action: .ask),
            Rule(host: "docs.example.com", path: "/a", action: .ask),     // hidden by 0
            Rule(host: "other.com", action: .ask),
            Rule(isEnabled: false, host: "*", action: .ask),                 // disabled: hides nothing
            Rule(host: "other.com", modifiers: .command, action: .ask),     // hidden by 2
            Rule(sourceApp: SourceAppMatch(bundleID: "s", name: "S"), action: .ask),
            Rule(host: "z.com", sourceApp: SourceAppMatch(bundleID: "S", name: "S"), action: .ask), // hidden by 5
        ]
        #expect(RuleAnalysis.shadowing(in: rules) == [nil, 0, nil, nil, 2, nil, 5])
    }

    @Test("Narrow above broad is fine")
    func noShadow() {
        let rules = [Rule(host: "docs.example.com", action: .ask), Rule(host: "*.example.com", action: .ask)]
        #expect(RuleAnalysis.shadowing(in: rules) == [nil, nil])
    }
}

@Suite("Incoming links")
struct LinkParserTests {
    @Test("Web links and HTML files are routed; other schemes aren't")
    func intake() {
        #expect(LinkParser.intake(url("https://example.com")) == .route(url("https://example.com"), forcePicker: false))
        #expect(LinkParser.intake(url("HTTP://Example.com/")) == .route(url("HTTP://Example.com/"), forcePicker: false))
        #expect(LinkParser.intake(url("file:///tmp/page.html")) == .route(url("file:///tmp/page.html"), forcePicker: false))
        if case .reject = LinkParser.intake(url("file:///tmp/a.pdf")) {} else { Issue.record("pdf accepted") }
        if case .reject = LinkParser.intake(url("mailto:a@example.com")) {} else { Issue.record("mailto accepted") }
        if case .reject = LinkParser.intake(url("https:///nohost")) {} else { Issue.record("hostless accepted") }
        if case .reject = LinkParser.intake(url("javascript:alert(1)")) {} else { Issue.record("javascript accepted") }
    }

    @Test("Our own scheme wraps a link and can force the picker")
    func ownScheme() {
        let inner = "https://example.com/a?b=1&c=2"
        let encoded = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(LinkParser.intake(url("switchboard://open?url=\(encoded)")) == .route(url(inner), forcePicker: false))
        #expect(LinkParser.intake(url("switchboard://open?url=\(encoded)&pick=1")) == .route(url(inner), forcePicker: true))
        if case .reject = LinkParser.intake(url("switchboard://open")) {} else { Issue.record("empty accepted") }
        let nested = "switchboard://open?url=" + "switchboard://open?url=https%3A%2F%2Fx.com".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        if case .reject = LinkParser.intake(url(nested)) {} else { Issue.record("nested own scheme accepted") }
    }

    @Test("Very long URLs are accepted and displayed truncated")
    func longURL() {
        let long = "https://example.com/" + String(repeating: "a", count: 10_000) + "?q=" + String(repeating: "b", count: 5_000)
        let u = url(long)
        #expect(LinkParser.intake(u) == .route(u, forcePicker: false))
        let detail = LinkText.detail(of: u, maxLength: 48)
        #expect(detail.count == 48)
        #expect(detail.contains("…"))
    }

    @Test("Display text: Unicode hosts, no www, ports kept, files by name")
    func display() {
        #expect(LinkText.host(of: url("https://www.Example.com/a")) == "example.com")
        #expect(LinkText.host(of: url("https://xn--bcher-kva.de/")) == "bücher.de")
        #expect(LinkText.host(of: url("http://localhost:3000/")) == "localhost:3000")
        #expect(LinkText.host(of: url("file:///Users/me/Downloads/report.html")) == "report.html")
        #expect(LinkText.detail(of: url("https://example.com/")) == "")
        #expect(LinkText.detail(of: url("https://example.com/caf%C3%A9?x=1")) == "/café?x=1")
    }

    @Test func truncateMiddle() {
        #expect(LinkText.truncateMiddle("abcdefghij", maxLength: 5) == "ab…ij")
        #expect(LinkText.truncateMiddle("abc", maxLength: 5) == "abc")
        #expect(LinkText.truncateMiddle("abcdef", maxLength: 6) == "abcdef")
    }

    @Test("Finds a link in clipboard text")
    func clipboard() {
        #expect(LinkParser.webLink(in: "  https://example.com/a \n") == url("https://example.com/a"))
        #expect(LinkParser.webLink(in: "example.com/path") == url("https://example.com/path"))
        #expect(LinkParser.webLink(in: "hello world") == nil)
        #expect(LinkParser.webLink(in: "localhost") == nil)
        #expect(LinkParser.webLink(in: "ftp://example.com") == nil)
        #expect(LinkParser.webLink(in: "") == nil)
    }
}

@Suite("Round 2")
struct RoundTwoTests {
    let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")
    let chrome = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome")
    func u(_ s: String) -> URL { URL(string: s)! }

    @Test("A forced picker still knows which browser the rules would pick")
    func preferred() {
        let cfg = Config(targets: [safari, chrome], rules: [Rule(host: "example.com", action: .open(targetID: chrome.id))], didSeedTargets: true)
        #expect(Router.preferredTarget(for: IncomingLink(url: u("https://example.com"), forcePicker: true), config: cfg) == chrome)
        #expect(Router.preferredTarget(for: IncomingLink(url: u("https://example.com"), modifiers: .option), config: cfg) == chrome)
        #expect(Router.preferredTarget(for: IncomingLink(url: u("https://other.com"), forcePicker: true), config: cfg) == nil)
        var withFallback = cfg; withFallback.fallback = .open(targetID: safari.id)
        #expect(Router.preferredTarget(for: IncomingLink(url: u("https://other.com"), forcePicker: true), config: withFallback) == safari)
    }

    @Test("Website made only of wildcards is refused")
    func wildcards() {
        for host in ["*", "*.", "**", "*.*"] {
            let problem = Rule(host: host, action: .ask).normalized().validationProblem
            #expect(problem?.contains("When no rule matches") == true, "\(host)")
        }
        #expect(Rule(host: "*", sourceApp: SourceAppMatch(bundleID: "a", name: "A"), action: .ask).normalized().validationProblem?.contains("Leave Website empty") == true)
        #expect(Rule(host: "*.example.com", action: .ask).normalized().validationProblem == nil)
    }

    @Test("Rules needing the ask keys never run")
    func askConflict() {
        let optionRule = Rule(host: "a.com", modifiers: [.option], action: .ask)
        #expect(optionRule.isBlocked(byAskModifiers: .option))
        #expect(Rule(host: "a.com", modifiers: [.option, .command], action: .ask).isBlocked(byAskModifiers: .option))
        #expect(!Rule(host: "a.com", modifiers: [.command], action: .ask).isBlocked(byAskModifiers: .option))
        #expect(!optionRule.isBlocked(byAskModifiers: []))
        #expect(!Rule(host: "a.com", action: .ask).isBlocked(byAskModifiers: .option))
        let rules = [Rule(host: "*.a.com", action: .ask), Rule(host: "b.a.com", action: .ask), optionRule]
        #expect(RuleAnalysis.unused(in: rules, askModifiers: .option) == [nil, .shadowed(by: 0), .askModifiers])
    }

    @Test("Links inside surrounding text")
    func linksInText() {
        #expect(LinkParser.webLink(in: "see https://example.com/a?b=1, thanks") == u("https://example.com/a?b=1"))
        #expect(LinkParser.webLink(in: "Meeting: www.example.org/room 3pm")?.host == "www.example.org")
        #expect(LinkParser.webLink(in: "open file.txt e.g. now") == nil)
        #expect(LinkParser.webLink(in: "mailto:me@example.com and ftp://x.org") == nil)
        #expect(LinkParser.webLink(in: "first http://a.com then https://b.com") == u("http://a.com"))
        #expect(LinkParser.webLink(in: "example.com/path") == u("https://example.com/path"))
    }

    @Test("Smart punctuation is undone")
    func plain() {
        #expect(LinkParser.plainText("\u{201C}example.com\u{201D}") == "\"example.com\"")
        #expect(LinkParser.plainText("a\u{2014}b") == "a--b")
    }

    @Test("Profile folder check")
    func folderCheck() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "sbtest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appending(path: "Library/Application Support/Google/Chrome")
        try FileManager.default.createDirectory(at: dir.appending(path: "Profile 1"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appending(path: "Local State"))
        #expect(ChromiumProfiles.checkFolder("Profile 1", dataDirectory: "Google/Chrome", home: home) == .exists)
        #expect(ChromiumProfiles.checkFolder("Profile 9", dataDirectory: "Google/Chrome", home: home) == .missing)
        #expect(ChromiumProfiles.checkFolder("Profile 1", dataDirectory: "Nope", home: home) == .unknown)
        #expect(ChromiumProfiles.checkFolder("../x", dataDirectory: "Google/Chrome", home: home) == .unknown)
    }
}
