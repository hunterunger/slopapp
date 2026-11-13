import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

private let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")
private let chrome = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome")
private let preview = Target(bundleID: "com.apple.Preview", appPath: "/System/Applications/Preview.app", appName: "Preview")

@Suite("File types")
struct FileTypeTests {
    func config(rules: [Rule] = []) -> Config {
        var pdf = FileType.presets[0]
        pdf.app = preview
        pdf.fallback = .open(targetID: preview.id)
        return Config(targets: [safari, chrome], rules: rules, didSeedTargets: true, fileTypes: [pdf])
    }

    @Test("Kinds: web pages are web links, other files are files")
    func kinds() {
        #expect(LinkKind.of(url("file:///tmp/a.html")) == .web)
        #expect(LinkKind.of(url("file:///tmp/a.PDF")) == .file)
        #expect(LinkKind.of(url("mailto:a@b.c")) == .email)
        #expect(LinkKind.of(url("zoommtg://x")) == nil)
    }

    @Test("Intake: files are routed, web locations are read, folders refused")
    func intake() {
        #expect(LinkParser.intake(url("file:///tmp/a.pdf")) == .route(url("file:///tmp/a.pdf"), forcePicker: false))
        #expect(LinkParser.intake(url("file:///tmp/a.webloc")) == .readLinkFile(url("file:///tmp/a.webloc")))
        #expect(LinkParser.intake(url("file:///tmp/a.url")) == .readLinkFile(url("file:///tmp/a.url")))
        if case .reject = LinkParser.intake(url("file:///tmp/folder/")) {} else { Issue.record("folders should be refused") }
        #expect(LinkParser.intake(url("mailto:a@b.c")) == .route(url("mailto:a@b.c"), forcePicker: false))
        // Our own scheme only takes web and email links, never other files.
        if case .reject = LinkParser.intake(url("switchboard://open?url=file%3A%2F%2F%2Fetc%2Fpasswd")) {} else { Issue.record("file via switchboard: should be refused") }
        #expect(LinkParser.intake(url("switchboard://open?url=mailto%3Aa%40b.c&pick=1")) == .route(url("mailto:a@b.c"), forcePicker: true))
    }

    @Test("Web location files: plist .webloc and INI .url")
    func internetLocations() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["URL": "https://example.com/a"], format: .xml, options: 0)
        #expect(InternetLocation.url(from: plist) == url("https://example.com/a"))
        let binary = try PropertyListSerialization.data(fromPropertyList: ["URL": "mailto:a@b.c"], format: .binary, options: 0)
        #expect(InternetLocation.url(from: binary) == url("mailto:a@b.c"))
        let ini = Data("[InternetShortcut]\r\nURL=https://example.org/x\r\nIconIndex=0\r\n".utf8)
        #expect(InternetLocation.url(from: ini) == url("https://example.org/x"))
        // A location pointing at a file or an app link isn't followed.
        let file = try PropertyListSerialization.data(fromPropertyList: ["URL": "file:///etc/passwd"], format: .xml, options: 0)
        #expect(InternetLocation.url(from: file) == nil)
        #expect(InternetLocation.url(from: Data("junk".utf8)) == nil)
    }

    @Test("A file goes where its type normally opens; its picker lists that app first")
    func routing() {
        let pdf = IncomingLink(url: url("file:///tmp/report.pdf"))
        #expect(Router.route(pdf, config: config()) == .open(preview, reason: .fallback))
        var held = pdf; held.modifiers = .option
        #expect(Router.route(held, config: config()) == .pick([preview, safari, chrome], reason: .askModifier))
        // A type nobody listed: the browsers, with the picker.
        #expect(Router.route(IncomingLink(url: url("file:///tmp/a.xyz")), config: config()) == .pick([safari, chrome], reason: .fallback))
        // Web pages keep following web rules and the web fallback, as before.
        var web = config(); web.fallback = .open(targetID: chrome.id)
        #expect(Router.route(IncomingLink(url: url("file:///tmp/a.html")), config: web) == .open(chrome, reason: .fallback))
    }

    @Test("File rules match extensions (and apps, keys); web rules don't match files")
    func rules() {
        let rules = [
            Rule(sourceApp: SourceAppMatch(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"), action: .open(targetID: safari.id)),
            Rule(kind: .file, fileExtensions: ["pdf"], sourceApp: SourceAppMatch(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
                 action: .open(targetID: chrome.id)),
        ]
        let fromSlack = IncomingLink(url: url("file:///tmp/a.pdf"), sourceBundleID: "com.tinyspeck.slackmacgap")
        #expect(Router.route(fromSlack, config: config(rules: rules)) == .open(chrome, reason: .rule(index: 1)))
        #expect(Router.route(IncomingLink(url: url("file:///tmp/a.pdf")), config: config(rules: rules)) == .open(preview, reason: .fallback))
        // The web rule for Slack still covers web pages from Slack, as before.
        let page = IncomingLink(url: url("file:///tmp/a.html"), sourceBundleID: "com.tinyspeck.slackmacgap")
        #expect(Router.route(page, config: config(rules: rules)) == .open(safari, reason: .rule(index: 0)))
    }

    @Test("Extensions typed for a rule are cleaned up and checked")
    func extensions() {
        #expect(FileType.parseExtensions("PDF, .docx *.txt pdf") == ["pdf", "docx", "txt"])
        let rule = Rule(kind: .file, fileExtensions: [".PDF", "docx"], action: .ask).normalized()
        #expect(rule.fileExtensions == ["pdf", "docx"])
        #expect(rule.validationProblem == nil)
        #expect(rule.conditionSummary == ".pdf and .docx files")
        #expect(Rule(kind: .file, fileExtensions: ["a/b"], action: .ask).validationProblem != nil)
        #expect(Rule(kind: .file, action: .ask).validationProblem == "Add a file type, app or key to match.")
        let broad = Rule(kind: .file, fileExtensions: ["pdf", "docx"], action: .ask)
        #expect(broad.covers(Rule(kind: .file, fileExtensions: ["pdf"], action: .ask)))
        #expect(!Rule(kind: .file, fileExtensions: ["pdf"], action: .ask).covers(broad))
    }

    @Test("Always use from the picker: a rule for the extension; web pages get none")
    func learned() {
        let rule = Router.alwaysOpenRule(for: url("file:///tmp/a.PDF"), in: chrome)
        #expect(rule?.kind == .file)
        #expect(rule?.fileExtensions == ["pdf"])
        #expect(Router.alwaysOpenLabel(for: url("file:///tmp/a.pdf")) == ".pdf Files")
        #expect(Router.alwaysOpenLabel(for: url("file:///tmp/a.html")) == nil)
    }

    @Test("Removing a browser a file type falls back to keeps it as removed")
    func references() {
        var cfg = config()
        cfg.fileTypes[0].fallback = .open(targetID: chrome.id)
        cfg.removeTarget(id: chrome.id)
        #expect(cfg.removedTargets.map(\.id) == [chrome.id])
        #expect(cfg.target(id: preview.id) == preview)
    }
}

@Suite("Safari menus")
struct SafariMenuTests {
    // File menus as Accessibility reports them. ⇧ is modifier mask 1.
    let english: [MenuItemSnapshot] = [
        MenuItemSnapshot("New Window", children: [
            MenuItemSnapshot("New Personal Window", key: "N"),
            MenuItemSnapshot("New Work Window"),
            MenuItemSnapshot("New School Stuff Window"),
        ]),
        MenuItemSnapshot("New Private Window", key: "N", modifiers: 1),
        MenuItemSnapshot("New Tab", key: "T"),
        MenuItemSnapshot(""),
        MenuItemSnapshot("Open File…", key: "O"),
    ]
    // German titles: the shortcut, not the title, finds the private window.
    let german: [MenuItemSnapshot] = [
        MenuItemSnapshot("Neues Fenster", children: [
            MenuItemSnapshot("Neues Fenster „Privat“", key: "N"),
            MenuItemSnapshot("Neues Fenster „Arbeit“"),
        ]),
        MenuItemSnapshot("Neues privates Fenster", key: "n", modifiers: 1),
    ]

    @Test("Private window by its ⇧⌘N shortcut, in any language")
    func privateWindow() {
        #expect(SafariMenu.path(for: .privateWindow, inFileMenu: english) == [1])
        #expect(SafariMenu.path(for: .privateWindow, inFileMenu: german) == [1])
        #expect(SafariMenu.path(for: .privateWindow, inFileMenu: [MenuItemSnapshot("New Window", key: "N")]) == nil)
        let disabled = [MenuItemSnapshot("New Private Window", key: "N", modifiers: 1, isEnabled: false)]
        #expect(SafariMenu.path(for: .privateWindow, inFileMenu: disabled) == nil)
    }

    @Test("Profiles by name in File ▸ New Window")
    func profiles() {
        #expect(SafariMenu.path(for: .profile("Work"), inFileMenu: english) == [0, 1])
        #expect(SafariMenu.path(for: .profile("work"), inFileMenu: english) == [0, 1])
        #expect(SafariMenu.path(for: .profile("School Stuff"), inFileMenu: english) == [0, 2])
        #expect(SafariMenu.path(for: .profile("Arbeit"), inFileMenu: german) == [0, 1])
        #expect(SafariMenu.path(for: .profile("Gaming"), inFileMenu: english) == nil)
        #expect(SafariMenu.path(for: .profile(" "), inFileMenu: english) == nil)
        // No profiles: New Window is a plain item.
        #expect(SafariMenu.path(for: .profile("Work"), inFileMenu: [MenuItemSnapshot("New Window", key: "N")]) == nil)
    }

    @Test("Profile names for Find Profiles")
    func names() {
        #expect(SafariMenu.profileNames(inFileMenu: english) == ["Personal", "Work", "School Stuff"])
        #expect(SafariMenu.profileNames(inFileMenu: german) == ["Privat", "Arbeit"])
        #expect(SafariMenu.profileNames(inFileMenu: [MenuItemSnapshot("New Window", key: "N")]).isEmpty)
    }

    @Test("Safari targets: private beats profile; profiles use the name")
    func plans() {
        let link = url("https://example.com")
        let work = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari",
                          profile: BrowserProfile(directory: "Work", name: "Work"))
        #expect(LaunchPlan.make(for: work, url: link)?.method == .safariWindow(.profile("Work"), link))
        var both = work; both.privateWindow = true
        #expect(LaunchPlan.make(for: both, url: link)?.method == .safariWindow(.privateWindow, link))
        #expect(LaunchPlan.make(for: safari, url: link)?.needsAccessibility == false)
        #expect(LaunchPlan.make(for: work, url: link)?.url == link)
    }
}

@Suite("Default app roles")
@MainActor
struct HandlerRoleTests {
    let own = AppRef(path: "/Applications/Switchboard.app", bundleID: "app.slopapp.switchboard")
    let safariRef = AppRef(path: "/Applications/Safari.app", bundleID: "com.apple.Safari")
    let mailRef = AppRef(path: "/System/Applications/Mail.app", bundleID: "com.apple.mail")
    let previewRef = AppRef(path: "/System/Applications/Preview.app", bundleID: "com.apple.Preview")

    func registry() -> MemoryAppRegistry {
        MemoryAppRegistry(schemes: ["http": safariRef, "https": safariRef, "mailto": mailRef],
                          types: ["public.html": safariRef, "com.adobe.pdf": previewRef,
                                  "com.apple.web-internet-location": safariRef, "com.microsoft.internet-shortcut": safariRef])
    }

    @Test("Browser: http, https and web pages; nothing else")
    func browser() async throws {
        let fake = registry()
        let roles = HandlerRoles(registry: fake, own: own)
        #expect(!roles.holds(.browser))
        let previous = try await roles.become(.browser)
        #expect(previous == safariRef)
        #expect(roles.holds(.browser))
        #expect(fake.changes == ["http → /Applications/Switchboard.app", "https → /Applications/Switchboard.app",
                                 "public.html → /Applications/Switchboard.app"])
        #expect(fake.schemes["mailto"] == mailRef)
        try await roles.handBack(.browser, to: safariRef)
        #expect(!roles.holds(.browser))
    }

    @Test("Email: only mailto, and hands back to the mail app")
    func email() async throws {
        let fake = registry()
        let roles = HandlerRoles(registry: fake, own: own)
        let previous = try await roles.become(.email)
        #expect(previous == mailRef)
        #expect(fake.changes == ["mailto → /Applications/Switchboard.app"])
        #expect(roles.holds(.email))
        #expect(fake.schemes["http"] == safariRef)
        try await roles.handBack(.email, to: mailRef)
        #expect(fake.schemes["mailto"] == mailRef)
        // Handing back to ourselves does nothing.
        try await roles.handBack(.email, to: own)
        #expect(fake.changes.count == 2)
    }

    @Test("File types: every type identifier, previous app remembered")
    func files() async throws {
        let fake = registry()
        let roles = HandlerRoles(registry: fake, own: own)
        let pdf = FileType.presets[0]
        let web = FileType.presets[1]
        #expect(try await roles.become(.fileType(pdf)) == previewRef)
        #expect(try await roles.become(.fileType(pdf)) == nil)
        #expect(try await roles.become(.fileType(web)) == safariRef)
        #expect(fake.types["com.apple.web-internet-location"] == own)
        #expect(fake.types["com.microsoft.internet-shortcut"] == own)
        #expect(roles.holds(.fileType(web)))
        // Same bundle id elsewhere counts as us (a test copy at another path).
        let elsewhere = HandlerRoles(registry: fake, own: AppRef(path: "/tmp/Switchboard.app", bundleID: "app.slopapp.switchboard"))
        #expect(elsewhere.holds(.fileType(pdf)))
    }
}
