import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

private let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")
private let chromeWork = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome",
                                profile: BrowserProfile(directory: "Profile 1", name: "Work"))
private let mail = Target(bundleID: "com.apple.mail", appPath: "/System/Applications/Mail.app", appName: "Mail")

private func everything() -> Config { fixture }

private let fixture: Config = {
    let gmail = Target(bundleID: chromeWork.bundleID, appPath: chromeWork.appPath, appName: chromeWork.appName,
                       profile: chromeWork.profile, webmail: Webmail(provider: .gmail, account: "me@work.com"))
    var pdf = FileType.presets[0]
    pdf.app = Target(bundleID: "com.apple.Preview", appPath: "/System/Applications/Preview.app", appName: "Preview")
    pdf.fallback = .open(targetID: pdf.app!.id)
    return Config(
        targets: [safari, chromeWork],
        rules: [
            Rule(host: "github.com", action: .open(targetID: chromeWork.id)),
            Rule(kind: .email, host: "work.com", action: .open(targetID: gmail.id)),
            Rule(kind: .file, fileExtensions: ["pdf"], modifiers: .shift, action: .open(targetID: safari.id)),
        ],
        fallback: .open(targetID: safari.id), askModifiers: .control, didSeedTargets: true,
        pickerSize: .large, stripsTrackingParameters: true,
        emailTargets: [mail, gmail], emailFallback: .open(targetID: mail.id), fileTypes: [pdf],
        rewrites: [Rewrite(host: "reddit.com", find: "www.reddit", replacement: "old.reddit")],
        handoffs: ["zoom", "music"]
    )
}()

@Suite("Settings import and export")
struct TransferTests {
    @Test("Export → import gives back the same settings, as readable JSON")
    func roundTrip() throws {
        let config = everything()
        let data = try SettingsTransfer.export(config, at: Date(timeIntervalSince1970: 0))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"format\" : \"Switchboard settings\""))
        #expect(text.contains("\"exportedAt\" : \"1970-01-01T00:00:00Z\""))
        #expect(text.contains("\"provider\" : \"gmail\""))
        #expect(text.contains("\n  ")) // pretty-printed
        #expect(try SettingsTransfer.read(data) == config)
    }

    @Test("A plain config.json imports too; other JSON and newer formats are refused")
    func reading() throws {
        let raw = try JSONEncoder().encode(everything())
        #expect(try SettingsTransfer.read(raw) == everything())
        #expect(throws: SettingsTransfer.ReadError.notSettings) { try SettingsTransfer.read(Data("{\"hello\": 1}".utf8)) }
        #expect(throws: SettingsTransfer.ReadError.notSettings) { try SettingsTransfer.read(Data("not json".utf8)) }
        let newer = Data(#"{"format": "Switchboard settings", "formatVersion": 9, "settings": {}}"#.utf8)
        #expect(throws: SettingsTransfer.ReadError.newerFormat(9)) { try SettingsTransfer.read(newer) }
    }

    @Test("Replace: the file's settings, all of them")
    func replace() {
        let current = Config(targets: [safari], rules: [Rule(host: "a.com", action: .ask)], didSeedTargets: true)
        let plan = SettingsTransfer.plan(importing: everything(), into: current, mode: .replace)
        #expect(plan.result == everything())
        #expect(plan.summary.browsers == 2)
        #expect(plan.summary.rules == 3)
        #expect(plan.summary.appHandoffs == 2)
        for part in ["2 browsers", "2 email apps", "3 rules", "1 rewrite", "2 apps to open links in", "1 file type"] {
            #expect(plan.summary.itemsText.contains(part))
        }
    }

    @Test("Merge into empty settings adds everything")
    func mergeIntoEmpty() {
        let plan = SettingsTransfer.plan(importing: everything(), into: Config(didSeedTargets: true), mode: .merge)
        #expect(plan.result.targets == everything().targets)
        #expect(plan.result.rules == everything().rules)
        #expect(plan.result.emailTargets == everything().emailTargets)
        #expect(plan.result.fileTypes == everything().fileTypes)
        #expect(plan.result.handoffs == ["zoom", "music"])
        // Scalar settings stay as they were.
        #expect(plan.result.pickerSize == .medium)
        #expect(plan.result.askModifiers == .option)
    }

    @Test("Merge keeps what's here, skips duplicates, and reconnects rules to browsers already here")
    func merge() {
        // Here: the same Chrome Work profile under another id, one rule, Zoom on.
        let myChrome = Target(bundleID: chromeWork.bundleID, appPath: chromeWork.appPath, appName: chromeWork.appName, profile: chromeWork.profile)
        let current = Config(targets: [myChrome], rules: [Rule(host: "github.com", action: .open(targetID: myChrome.id))],
                             didSeedTargets: true, handoffs: ["zoom"])
        let plan = SettingsTransfer.plan(importing: everything(), into: current, mode: .merge)
        // Safari added; Chrome Work matched to mine.
        #expect(plan.result.targets.map(\.displayName) == ["Google Chrome (Work)", "Safari"])
        #expect(plan.result.targets[0].id == myChrome.id)
        #expect(plan.summary.browsers == 1)
        // The github rule already exists once its target is reconnected; the other two are added after mine.
        #expect(plan.summary.duplicateRules == 1)
        #expect(plan.summary.rules == 2)
        #expect(plan.result.rules.count == 3)
        #expect(plan.result.rules[0] == current.rules[0])
        #expect(plan.result.handoffs == ["zoom", "music"])
        #expect(plan.summary.appHandoffs == 1)
        // Every rule points at something that exists.
        for rule in plan.result.rules {
            if case .open(let id) = rule.action { #expect(plan.result.target(id: id) != nil) }
        }
        // Merging the same file again adds nothing.
        let again = SettingsTransfer.plan(importing: everything(), into: plan.result, mode: .merge)
        #expect(again.summary.isEmpty)
        #expect(again.result == plan.result)
    }

    @Test("Ids that clash with different things here get new ids")
    func clashingIDs() {
        // A different browser here with the same id as the file's Safari.
        let impostor = Target(id: safari.id, bundleID: "org.mozilla.firefox", appPath: "/Applications/Firefox.app", appName: "Firefox")
        let current = Config(targets: [impostor], didSeedTargets: true)
        let incoming = Config(targets: [safari], rules: [Rule(host: "a.com", action: .open(targetID: safari.id))], didSeedTargets: true)
        let plan = SettingsTransfer.plan(importing: incoming, into: current, mode: .merge)
        #expect(plan.result.targets.count == 2)
        let importedSafari = plan.result.targets[1]
        #expect(importedSafari.id != safari.id)
        #expect(plan.result.rules[0].action == .open(targetID: importedSafari.id))
    }
}

@Suite("Settings from earlier versions")
struct MigrationTests {
    /// A settings file as Switchboard 0.2.0 wrote it.
    let v020 = """
    {
      "askModifiers" : 2,
      "didSeedTargets" : true,
      "fallback" : { "ask" : {} },
      "pickerSize" : "medium",
      "removedTargets" : [],
      "rules" : [
        { "action" : { "open" : { "targetID" : "5A1F0000-0000-4000-8000-000000000002" } },
          "host" : "github.com", "id" : "5A1F0000-0000-4000-8000-000000000101", "isEnabled" : true,
          "modifiers" : 0, "path" : "" },
        { "action" : { "ask" : {} }, "host" : "", "id" : "5A1F0000-0000-4000-8000-000000000102", "isEnabled" : true,
          "modifiers" : 0, "path" : "", "sourceApp" : { "bundleID" : "com.tinyspeck.slackmacgap", "name" : "Slack" } }
      ],
      "stripsTrackingParameters" : true,
      "targets" : [
        { "appName" : "Safari", "appPath" : "/Applications/Safari.app", "bundleID" : "com.apple.Safari",
          "id" : "5A1F0000-0000-4000-8000-000000000001", "isHidden" : false, "opensInBackground" : false, "privateWindow" : false },
        { "appName" : "Google Chrome", "appPath" : "/Applications/Google Chrome.app", "bundleID" : "com.google.Chrome",
          "id" : "5A1F0000-0000-4000-8000-000000000002", "isHidden" : false, "opensInBackground" : false, "privateWindow" : false,
          "profile" : { "directory" : "Profile 1", "name" : "Work" } }
      ],
      "version" : 1
    }
    """

    @Test("A 0.2.0 file loads with every setting kept and everything new empty or off")
    func loads() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(v020.utf8))
        #expect(config.targets.count == 2)
        #expect(config.targets[1].profile?.name == "Work")
        #expect(config.targets.allSatisfy { $0.webmail == nil })
        #expect(config.rules.count == 2)
        #expect(config.rules.allSatisfy { $0.kind == .web && $0.fileExtensions.isEmpty })
        #expect(config.stripsTrackingParameters)
        #expect(config.askModifiers == .option)
        #expect(config.emailTargets.isEmpty)
        #expect(config.emailFallback == .ask)
        #expect(config.fileTypes.isEmpty)
        #expect(config.rewrites.isEmpty)
        #expect(config.handoffs.isEmpty)
        #expect(config.version == Config.currentVersion)
    }

    @Test("Old rules route exactly as before")
    func routesTheSame() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(v020.utf8))
        let chrome = config.targets[1]
        #expect(Router.route(IncomingLink(url: url("https://github.com/a")), config: config) == .open(chrome, reason: .rule(index: 0)))
        let slack = IncomingLink(url: url("https://x.org"), sourceBundleID: "com.tinyspeck.slackmacgap")
        #expect(Router.route(slack, config: config).reason == .rule(index: 1))
        // A web page from Slack still follows the Slack rule.
        let page = IncomingLink(url: url("file:///tmp/a.html"), sourceBundleID: "com.tinyspeck.slackmacgap")
        #expect(Router.route(page, config: config).reason == .rule(index: 1))
        // Email links don't match old web rules.
        let mailFromSlack = IncomingLink(url: url("mailto:a@github.com"), sourceBundleID: "com.tinyspeck.slackmacgap")
        #expect(Router.route(mailFromSlack, config: config) == .noTargets)
    }

    @Test("Saved again, the file has the new keys and still loads")
    func resave() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(v020.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(config), as: UTF8.self)
        #expect(text.contains("\"kind\":\"web\""))
        #expect(text.contains("\"emailTargets\":[]"))
        #expect(!text.contains("fileExtensions")) // web rules don't write the files-only key
        #expect(try JSONDecoder().decode(Config.self, from: Data(text.utf8)) == config)
    }

    @Test("A rule kind from a newer version doesn't break the file")
    func unknownKind() throws {
        let json = #"{"id":"5A1F0000-0000-4000-8000-000000000101","action":{"ask":{}},"kind":"telephone","host":"x"}"#
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        #expect(rule.kind == .web)
        #expect(!rule.isEnabled)
        #expect(!rule.matches(IncomingLink(url: URL(string: "https://x")!)))
    }
}
