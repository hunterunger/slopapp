import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

@Suite("Host patterns")
struct HostPatternTests {
    @Test("Plain domain matches itself and www, nothing else")
    func plainDomain() {
        let p = HostPattern("example.com")!
        #expect(p.matches(url("https://example.com/a")))
        #expect(p.matches(url("https://www.example.com")))
        #expect(p.matches(url("http://EXAMPLE.COM")))
        #expect(!p.matches(url("https://docs.example.com")))
        #expect(!p.matches(url("https://notexample.com")))
        #expect(!p.matches(url("https://example.com.evil.org")))
    }

    @Test("*. wildcard matches the bare domain and every subdomain")
    func subdomainWildcard() {
        let p = HostPattern("*.example.com")!
        #expect(p.matches(url("https://example.com")))
        #expect(p.matches(url("https://a.example.com")))
        #expect(p.matches(url("https://a.b.example.com/x")))
        #expect(!p.matches(url("https://badexample.com")))
        #expect(!p.matches(url("https://example.org")))
    }

    @Test("Wildcards in the middle and a lone star")
    func globs() {
        #expect(HostPattern("docs.*.com")!.matches(url("https://docs.google.com")))
        #expect(!HostPattern("docs.*.com")!.matches(url("https://mail.google.com")))
        #expect(HostPattern("*")!.matches(url("https://anything.at.all")))
        #expect(HostPattern("*zoom.us")!.matches(url("https://us02web.zoom.us/j/1")))
    }

    @Test("Ports must match when the pattern has one")
    func ports() {
        let p = HostPattern("localhost:3000")!
        #expect(p.matches(url("http://localhost:3000/")))
        #expect(!p.matches(url("http://localhost:8080/")))
        #expect(!p.matches(url("http://localhost/")))
        #expect(HostPattern("localhost")!.matches(url("http://localhost:8080/")))
    }

    @Test("Typing a full URL keeps just the host")
    func tolerantParsing() {
        #expect(HostPattern("https://Example.com/path?q=1")?.host == "example.com")
        #expect(HostPattern("  example.com  ")?.host == "example.com")
        #expect(HostPattern("user@example.com")?.host == "example.com")
        #expect(HostPattern("") == nil)
        #expect(HostPattern("   ") == nil)
        #expect(HostPattern("https://") == nil)
    }

    @Test("IPv6 and IPs")
    func ipAddresses() {
        #expect(HostPattern("::1")?.port == nil)
        #expect(HostPattern("::1")!.matches(url("http://[::1]:3000/")))
        #expect(HostPattern("[::1]:3000")!.matches(url("http://[::1]:3000/")))
        #expect(HostPattern("127.0.0.1")!.matches(url("http://127.0.0.1:5000/")))
    }

    @Test("Unicode patterns match punycode hosts (both directions)")
    func idn() {
        #expect(HostPattern("bücher.de")!.matches(url("https://xn--bcher-kva.de/")))
        #expect(HostPattern("bücher.de")!.matches(url("https://bücher.de/")))
        #expect(HostPattern("xn--bcher-kva.de")!.matches(url("https://bücher.de/")))
        #expect(HostPattern("*.bücher.de")!.matches(url("https://shop.bücher.de/")))
    }
}

@Suite("Path prefixes")
struct PathPrefixTests {
    @Test func prefixes() {
        let p = PathPrefix("/j/")!
        #expect(p.matches(url("https://zoom.us/j/123")))
        #expect(!p.matches(url("https://zoom.us/my/room")))
        #expect(PathPrefix("j")!.prefix == "/j")
        #expect(PathPrefix("/docs/*")!.prefix == "/docs/")
        #expect(PathPrefix("/") == nil)
        #expect(PathPrefix("") == nil)
        #expect(PathPrefix("/caf%C3%A9")!.matches(url("https://x.com/caf%C3%A9/menu")))
        #expect(PathPrefix("/café")!.matches(url("https://x.com/caf%C3%A9/menu")))
    }
}

@Suite("Punycode")
struct PunycodeTests {
    @Test func decodesKnownLabels() {
        #expect(Punycode.decode("bcher-kva") == "bücher")
        #expect(Punycode.decode("r8jz45g") == "例え")
        #expect(Punycode.displayHost("xn--bcher-kva.de") == "bücher.de")
        #expect(Punycode.displayHost("www.example.com") == "www.example.com")
    }

    @Test func rejectsGarbage() {
        #expect(Punycode.decode("!!!") == nil)
        #expect(Punycode.displayHost("xn--!!!.com") == "xn--!!!.com")
        #expect(Punycode.decode("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz") == nil)
    }
}

@Suite("Rules")
struct RuleTests {
    let target = UUID()

    @Test("A rule with no conditions never matches")
    func emptyRuleNeverMatches() {
        let rule = Rule(action: .open(targetID: target))
        #expect(!rule.hasConditions)
        #expect(!rule.matches(IncomingLink(url: url("https://example.com"))))
    }

    @Test("All set conditions must match")
    func allConditions() {
        let rule = Rule(
            host: "*.example.com", path: "/docs",
            sourceApp: SourceAppMatch(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            modifiers: [.command], action: .open(targetID: target)
        )
        let good = IncomingLink(url: url("https://a.example.com/docs/x"), sourceBundleID: "com.tinyspeck.slackmacgap", modifiers: [.command, .shift])
        #expect(rule.matches(good))
        var wrongSource = good; wrongSource.sourceBundleID = "com.apple.mail"
        #expect(!rule.matches(wrongSource))
        var unknownSource = good; unknownSource.sourceBundleID = nil
        #expect(!rule.matches(unknownSource))
        var noKey = good; noKey.modifiers = []
        #expect(!rule.matches(noKey))
        var wrongPath = good; wrongPath.url = url("https://a.example.com/blog")
        #expect(!rule.matches(wrongPath))
    }

    @Test("Source app match ignores case")
    func sourceCase() {
        let rule = Rule(sourceApp: SourceAppMatch(bundleID: "com.apple.Mail", name: "Mail"), action: .ask)
        #expect(rule.matches(IncomingLink(url: url("https://x.com"), sourceBundleID: "com.apple.mail")))
    }

    @Test("Disabled rules don't match")
    func disabled() {
        let rule = Rule(isEnabled: false, host: "example.com", action: .ask)
        #expect(!rule.matches(IncomingLink(url: url("https://example.com"))))
    }

    @Test("A URL typed into the host field is split into host and path")
    func normalizeHostField() {
        var rule = Rule(host: "https://zoom.us/j/", action: .ask)
        rule.normalizeHostField()
        #expect(rule.host == "zoom.us")
        #expect(rule.path == "/j/")
        var keepsPath = Rule(host: "zoom.us/j/", path: "/other", action: .ask)
        keepsPath.normalizeHostField()
        #expect(keepsPath.host == "zoom.us")
        #expect(keepsPath.path == "/other")
    }

    @Test func summaries() {
        #expect(Rule(host: "*.example.com", path: "/docs", action: .ask).conditionSummary == "*.example.com/docs")
        #expect(Rule(sourceApp: SourceAppMatch(bundleID: "a", name: "Slack"), action: .ask).conditionSummary == "Links from Slack")
        #expect(Rule(host: "x.com", sourceApp: SourceAppMatch(bundleID: "a", name: "Mail"), modifiers: [.option, .command], action: .ask).conditionSummary == "x.com from Mail holding ⌥⌘")
    }
}

@Suite("Modifiers")
struct ModifierTests {
    @Test func symbolsAndNames() {
        let all: Modifiers = [.command, .shift, .option, .control]
        #expect(all.symbol == "⌃⌥⇧⌘")
        #expect(Modifiers.option.name == "Option")
        #expect(Modifiers([.control, .option]).name == "Control-Option")
        #expect(Modifiers().symbol == "")
    }
}
