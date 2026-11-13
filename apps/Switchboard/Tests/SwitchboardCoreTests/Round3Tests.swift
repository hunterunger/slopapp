import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

@Suite("Blind test round 3")
struct Round3Tests {
    let zoomRewrite = Rewrite(host: "*.zoom.us", find: "^https://[^/]+/j/(\\d+)\\?pwd=([^&]+).*$",
                              replacement: "zoommtg://zoom.us/join?confno=$1&pwd=$2", usesRegex: true)

    @Test("F1: a rewrite into an app link nothing opens is skipped, so the link reaches a browser")
    func unopenableAppLink() {
        let browsers = [Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari"),
                        Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome")]
        let config = Config(targets: browsers, didSeedTargets: true, rewrites: [zoomRewrite])
        let link = url("https://us02web.zoom.us/j/123?pwd=abc")
        let skipped = LinkPreparation.prepare(link, config: config, canOpen: { _ in false })
        #expect(skipped.url == link)
        #expect(skipped.steps == [.skippedAppLink(index: 0, scheme: "zoommtg")])
        #expect(Router.route(IncomingLink(url: skipped.url), config: config).reason == .fallback)
        // With the app installed, the rewrite applies.
        let applied = LinkPreparation.prepare(link, config: config, canOpen: { _ in true })
        #expect(applied.url == url("zoommtg://zoom.us/join?confno=123&pwd=abc"))
        // Later web rewrites still run after a skipped one.
        let both = Config(rewrites: [zoomRewrite, Rewrite(find: "us02web.", replacement: "")])
        #expect(LinkPreparation.prepare(link, config: both, canOpen: { _ in false }).url == url("https://zoom.us/j/123?pwd=abc"))
    }

    @Test("F1: the link keeps where it came from, for fallback and Reopen")
    func original() {
        let link = IncomingLink(url: url("zoommtg://x"), originalURL: url("https://zoom.us/j/1"))
        #expect(link.originalURL == url("https://zoom.us/j/1"))
        #expect(IncomingLink(url: url("https://a.com")).originalURL == nil)
    }

    @Test("F5: look-alike hosts stay in punycode; real ones show Unicode")
    func homographs() {
        #expect(Punycode.displayHost("xn--pple-43d.com") == "xn--pple-43d.com") // Cyrillic а + Latin
        #expect(Punycode.displayHost("xn--80ak6aa92e.com") == "xn--80ak6aa92e.com") // all-Cyrillic "аррӏе"
        #expect(Punycode.displayHost("xn--bcher-kva.de") == "bücher.de")
        #expect(Punycode.displayHost("xn--e1afmkfd.xn--p1ai") == "пример.рф") // Cyrillic under .рф
        #expect(Punycode.displayHost("xn--r8jz45g.jp") == "例え.jp")
        #expect(LinkText.host(of: url("https://xn--pple-43d.com/login")) == "xn--pple-43d.com")
    }

    @Test("F4: an empty email list is filled once with the mail apps here")
    func seedEmail() {
        let mail = InstalledApp(bundleID: "com.apple.mail", path: "/System/Applications/Mail.app", name: "Mail")
        var config = Config(didSeedTargets: true)
        let first = config.seedEmailTargets(from: [mail])
        #expect(first)
        #expect(config.emailTargets.map(\.bundleID) == ["com.apple.mail"])
        #expect(Router.route(IncomingLink(url: url("mailto:a@b.com")), config: config).reason == .onlyOneTarget)
        // Once only: removing Mail later doesn't bring it back.
        config.removeTarget(id: config.emailTargets[0].id)
        let again = config.seedEmailTargets(from: [mail])
        #expect(!again)
        #expect(config.emailTargets.isEmpty)
        // Settings from before this field: seeded on first use.
        let old = try? JSONDecoder().decode(Config.self, from: Data(#"{"targets":[],"rules":[]}"#.utf8))
        #expect(old?.didSeedEmailTargets == false)
    }

    @Test("F8: one kind of link, singular")
    func grammar() {
        #expect(LinkParser.intake(url("tel:+1555")) == .reject(reason: "Switchboard doesn't handle tel: links."))
    }

    @Test("Import of a broken file is refused, not half-read")
    func broken() {
        #expect(throws: SettingsTransfer.ReadError.notSettings) {
            try SettingsTransfer.read(Data(#"{ "version": 1, "rules": [ broken"#.utf8))
        }
    }
}
