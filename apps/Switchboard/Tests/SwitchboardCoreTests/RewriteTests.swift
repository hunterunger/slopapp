import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

private let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")
private let chrome = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome")

@Suite("Rewrites")
struct RewriteTests {
    @Test("Plain find and replace")
    func plain() {
        let mirror = Rewrite(find: "://twitter.com/", replacement: "://nitter.net/")
        #expect(mirror.apply(to: url("https://twitter.com/someone/status/1")) == url("https://nitter.net/someone/status/1"))
        #expect(mirror.apply(to: url("https://example.com")) == nil)
        let strip = Rewrite(find: "/amp/", replacement: "/")
        #expect(strip.apply(to: url("https://news.example/amp/story")) == url("https://news.example/story"))
    }

    @Test("Regular expressions with captures, ignoring case")
    func regex() {
        let rewrite = Rewrite(find: "^https://(www\\.)?reddit\\.com/(.*)$", replacement: "https://old.reddit.com/$2", usesRegex: true)
        #expect(rewrite.apply(to: url("https://www.reddit.com/r/mac/comments/1")) == url("https://old.reddit.com/r/mac/comments/1"))
        #expect(rewrite.apply(to: url("HTTPS://reddit.com/r/x")) != nil)
        #expect(rewrite.apply(to: url("https://example.com/")) == nil)
        let bad = Rewrite(find: "([", replacement: "", usesRegex: true)
        #expect(bad.validationProblem == "That isn't a valid regular expression.")
        #expect(bad.apply(to: url("https://example.com/([")) == nil)
    }

    @Test("A website condition limits where it applies")
    func scoped() {
        let rewrite = Rewrite(host: "*.example.com", find: "/old/", replacement: "/new/")
        #expect(rewrite.apply(to: url("https://docs.example.com/old/a")) == url("https://docs.example.com/new/a"))
        #expect(rewrite.apply(to: url("https://other.org/old/a")) == nil)
        #expect(Rewrite(host: "not a site", find: "x").validationProblem != nil)
    }

    @Test("Never into a file, script, data or our own link; off does nothing")
    func refused() {
        #expect(Rewrite(find: "https://example.com/", replacement: "file:///etc/").apply(to: url("https://example.com/passwd")) == nil)
        #expect(Rewrite(find: "https://example.com/", replacement: "javascript:").apply(to: url("https://example.com/x")) == nil)
        #expect(Rewrite(find: "https://example.com/", replacement: "switchboard://open?url=").apply(to: url("https://example.com/x")) == nil)
        #expect(Rewrite(isEnabled: false, find: "example", replacement: "x").apply(to: url("https://example.com")) == nil)
        #expect(Rewrite(find: "").validationProblem != nil)
        #expect(Rewrite(find: "example", replacement: "example").apply(to: url("https://example.com")) == nil)
    }

    @Test("Preparation: tracking first, then rewrites in order, each on the last result")
    func preparation() {
        var config = Config(stripsTrackingParameters: true)
        config.rewrites = [
            Rewrite(find: "a.example", replacement: "b.example"),
            Rewrite(find: "b.example", replacement: "c.example"),
            Rewrite(isEnabled: false, find: "c.example", replacement: "d.example"),
        ]
        let prepared = LinkPreparation.prepare(url("https://a.example/p?utm_source=x&id=1"), config: config)
        #expect(prepared.url == url("https://c.example/p?id=1"))
        #expect(prepared.steps == [.removedTracking, .rewritten(index: 0, to: url("https://b.example/p?id=1")),
                                   .rewritten(index: 1, to: url("https://c.example/p?id=1"))])
        // Email links and files are left alone.
        #expect(LinkPreparation.prepare(url("mailto:x@a.example"), config: config).steps.isEmpty)
        #expect(LinkPreparation.prepare(url("file:///tmp/a.example.html"), config: config).steps.isEmpty)
    }

    @Test("A rewrite into an app's link stops there and opens that app, unless the picker shows anyway")
    func appLink() {
        var config = Config(targets: [safari, chrome], didSeedTargets: true)
        config.rewrites = [
            Rewrite(find: "^https://vscode\\.dev/(.*)$", replacement: "vscode://$1", usesRegex: true),
            Rewrite(find: "vscode://", replacement: "never://"),
        ]
        let prepared = LinkPreparation.prepare(url("https://vscode.dev/file/a"), config: config)
        #expect(prepared.url == url("vscode://file/a"))
        #expect(prepared.steps.count == 1)
        #expect(Router.route(IncomingLink(url: prepared.url), config: config) == .openInApp(AppLink(url: url("vscode://file/a")), reason: .rewrite))
        // ⌥ held / forced: stays a web link so a browser can open it.
        let forPicker = LinkPreparation.prepare(url("https://vscode.dev/file/a"), config: config, allowAppLinks: false)
        #expect(forPicker.url == url("https://vscode.dev/file/a"))
    }
}

@Suite("App handoffs")
struct HandoffTests {
    func link(_ id: String, _ s: String) -> URL? { Handoffs.handoff(id: id)?.appLink(for: url(s)) }

    @Test("Zoom meeting links become zoommtg join links, password kept")
    func zoom() {
        #expect(link("zoom", "https://us02web.zoom.us/j/123456789?pwd=abcDEF.1") == url("zoommtg://us02web.zoom.us/join?action=join&confno=123456789&pwd=abcDEF.1"))
        #expect(link("zoom", "https://zoom.us/j/987") == url("zoommtg://zoom.us/join?action=join&confno=987"))
        #expect(link("zoom", "https://zoom.us/pricing") == nil)
        #expect(link("zoom", "https://notzoom.us/j/1") == nil)
        #expect(link("zoom", "https://zoom.us/j/abc") == nil)
    }

    @Test("Music, Podcasts and App Store swap the scheme")
    func apple() {
        #expect(link("music", "https://music.apple.com/us/album/x/123?i=4") == url("music://music.apple.com/us/album/x/123?i=4"))
        #expect(link("music", "https://music.apple.com/") == nil)
        #expect(link("podcasts", "https://podcasts.apple.com/us/podcast/x/id1") == url("podcasts://podcasts.apple.com/us/podcast/x/id1"))
        #expect(link("appstore", "https://apps.apple.com/us/app/x/id123") == url("macappstore://apps.apple.com/us/app/x/id123"))
        #expect(link("appstore", "https://apps.apple.com/us/story/id1") == nil)
    }

    @Test("Spotify, Figma, Slack, Notion, Teams, Linear, Discord")
    func thirdParty() {
        #expect(link("spotify", "https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC?si=x") == url("spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        #expect(link("spotify", "https://open.spotify.com/") == nil)
        #expect(link("figma", "https://www.figma.com/design/KEY123/My-File?node-id=1-2") == url("figma://design/KEY123/My-File?node-id=1-2"))
        #expect(link("figma", "https://www.figma.com/pricing") == nil)
        #expect(link("slack", "https://app.slack.com/client/T0123/C0456/thread/x") == url("slack://channel?team=T0123&id=C0456"))
        #expect(link("slack", "https://slack.com/intl/en-gb/") == nil)
        #expect(link("notion", "https://www.notion.so/team/Page-abc123") == url("notion://www.notion.so/team/Page-abc123"))
        #expect(link("teams", "https://teams.microsoft.com/l/meetup-join/19%3ameeting/0?context=x") == url("msteams:/l/meetup-join/19%3ameeting/0?context=x"))
        #expect(link("linear", "https://linear.app/acme/issue/ENG-1/title") == url("linear://acme/issue/ENG-1/title"))
        #expect(link("linear", "https://linear.app/pricing") == nil)
        #expect(link("discord", "https://discord.gg/abc") == url("discord://discord.com/invite/abc"))
        #expect(link("discord", "https://discord.com/channels/1/2") == url("discord://discord.com/channels/1/2"))
    }

    @Test("Matching: on, installed, and never back to the app the link came from")
    func matching() {
        let zoomURL = url("https://zoom.us/j/1")
        let installed: (AppHandoff) -> String? = { $0.bundleIDs.first }
        #expect(Handoffs.match(zoomURL, enabled: [], source: nil, installedApp: installed) == nil)
        #expect(Handoffs.match(zoomURL, enabled: ["zoom"], source: nil, installedApp: { _ in nil }) == nil)
        let match = Handoffs.match(zoomURL, enabled: ["music", "zoom"], source: nil, installedApp: installed)
        #expect(match == AppLink(url: url("zoommtg://zoom.us/join?action=join&confno=1"), bundleID: "us.zoom.xos", appName: "Zoom", handoffID: "zoom"))
        #expect(Handoffs.match(zoomURL, enabled: ["zoom"], source: "us.zoom.xos", installedApp: installed) == nil)
        // The newer Teams wins when both are listed; the older one works if that's what's installed.
        let teams = url("https://teams.microsoft.com/l/chat/0/0")
        #expect(Handoffs.match(teams, enabled: ["teams"], source: nil, installedApp: { $0.bundleIDs.last })?.bundleID == "com.microsoft.teams")
    }

    @Test("Router: handoffs before rules, but the picker key and forced picks win")
    func routing() {
        var config = Config(targets: [safari, chrome], rules: [Rule(host: "zoom.us", action: .open(targetID: chrome.id))],
                            didSeedTargets: true, handoffs: ["zoom"])
        let installed: (AppHandoff) -> String? = { $0.bundleIDs.first }
        let zoom = IncomingLink(url: url("https://zoom.us/j/42"))
        #expect(Router.route(zoom, config: config, installedApp: installed).reason == .handoff(id: "zoom"))
        // Not installed: the rule applies.
        #expect(Router.route(zoom, config: config).reason == .rule(index: 0))
        // ⌥ held or forced: the browsers.
        var held = zoom; held.modifiers = .option
        #expect(Router.route(held, config: config, installedApp: installed).reason == .askModifier)
        var forced = zoom; forced.forcePicker = true
        #expect(Router.route(forced, config: config, installedApp: installed).reason == .forced)
        // Off: the rule.
        config.handoffs = []
        #expect(Router.route(zoom, config: config, installedApp: installed).reason == .rule(index: 0))
        // The preselected row ignores handoffs (the browser the rules would pick).
        config.handoffs = ["zoom"]
        #expect(Router.preferredTarget(for: forced, config: config) == chrome)
        #expect(Router.describe(.openInApp(AppLink(url: url("zoommtg://x"), appName: "Zoom"), reason: .handoff(id: "zoom"))) == "Opens in Zoom (Open in apps)")
    }
}
