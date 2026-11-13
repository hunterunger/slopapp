import Foundation
import Testing
@testable import SwitchboardCore

private func url(_ s: String) -> URL { URL(string: s)! }

private let mail = Target(bundleID: "com.apple.mail", appPath: "/System/Applications/Mail.app", appName: "Mail")
private let chromeWork = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome",
                                profile: BrowserProfile(directory: "Profile 1", name: "Work"))
private let gmailWork = Target(bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app", appName: "Google Chrome",
                               profile: BrowserProfile(directory: "Profile 1", name: "Work"), webmail: Webmail(provider: .gmail))
private let safari = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari")

@Suite("Mailto links")
struct MailtoTests {
    @Test("Recipients, cc, bcc, subject and body, decoded")
    func parse() throws {
        let link = try #require(MailtoLink(url("mailto:a@x.com,b@y.com?CC=c@z.com&bcc=d@w.com&subject=Hi%20there%20%26%20more&body=Line%201%0D%0ALine+2")))
        #expect(link.to == ["a@x.com", "b@y.com"])
        #expect(link.cc == ["c@z.com"])
        #expect(link.bcc == ["d@w.com"])
        #expect(link.subject == "Hi there & more")
        // mailto isn't form encoding: + stays a plus.
        #expect(link.body == "Line 1\r\nLine+2")
        #expect(link.recipients.count == 4)
    }

    @Test("to= in the query adds recipients; empty mailto is a blank message")
    func toHeader() throws {
        #expect(MailtoLink(url("mailto:?to=a@x.com&to=b@y.com"))?.to == ["a@x.com", "b@y.com"])
        let blank = try #require(MailtoLink(url("mailto:")))
        #expect(blank.recipients.isEmpty)
        #expect(MailtoLink(url("https://example.com")) == nil)
    }

    @Test("Domains are lowercased")
    func domain() {
        #expect(MailtoLink.domain(of: "Ann@Example.COM") == "example.com")
        #expect(MailtoLink.domain(of: "nobody") == nil)
    }

    @Test("Rebuilt link encodes strictly")
    func rebuild() throws {
        let link = MailtoLink(to: ["a@x.com"], cc: ["c@z.com"], subject: "A&B=C", body: "x y")
        #expect(link.url.absoluteString == "mailto:a@x.com?cc=c@z.com&subject=A%26B%3DC&body=x%20y")
        #expect(MailtoLink(link.url) == link)
    }

    @Test("Address patterns: domain, subdomains, exact address")
    func addressPatterns() throws {
        let domain = try #require(AddressPattern("example.com"))
        #expect(domain.matches(address: "ann@example.com"))
        #expect(domain.matches(address: "Ann@EXAMPLE.com"))
        #expect(!domain.matches(address: "ann@mail.example.com"))
        let sub = try #require(AddressPattern("*.example.com"))
        #expect(sub.matches(address: "ann@mail.example.com"))
        #expect(sub.matches(address: "ann@example.com"))
        let exact = try #require(AddressPattern("Boss@Example.com"))
        #expect(exact.matches(address: "boss@example.com"))
        #expect(!exact.matches(address: "ann@example.com"))
        #expect(AddressPattern("*@example.com") == AddressPattern("example.com"))
        #expect(AddressPattern("mailto:boss@example.com") == AddressPattern("boss@example.com"))
        #expect(AddressPattern("") == nil)
        #expect(AddressPattern("@") == nil)
        #expect(sub.covers(domain))
        #expect(domain.covers(exact))
        #expect(!exact.covers(domain))
    }
}

@Suite("Webmail compose links")
struct WebmailTests {
    let message = MailtoLink(to: ["a@x.com", "b@y.com"], cc: ["c@z.com"], subject: "Hi & bye", body: "Line 1\nLine 2")

    @Test("Gmail, with and without an account")
    func gmail() throws {
        let plain = try #require(Webmail(provider: .gmail).composeURL(for: message))
        #expect(plain.absoluteString == "https://mail.google.com/mail/?view=cm&fs=1&to=a@x.com%2Cb@y.com&cc=c@z.com&su=Hi%20%26%20bye&body=Line%201%0ALine%202")
        let numbered = try #require(Webmail(provider: .gmail, account: "1").composeURL(for: message))
        #expect(numbered.absoluteString.hasPrefix("https://mail.google.com/mail/u/1/?view=cm"))
        let named = try #require(Webmail(provider: .gmail, account: "me@work.com").composeURL(for: message))
        #expect(named.absoluteString.hasPrefix("https://mail.google.com/mail/?authuser=me@work.com&view=cm"))
        // Fields that are empty are left out.
        let bare = try #require(Webmail(provider: .gmail).composeURL(for: MailtoLink(to: ["a@x.com"])))
        #expect(bare.absoluteString == "https://mail.google.com/mail/?view=cm&fs=1&to=a@x.com")
    }

    @Test("Outlook (work and personal), Yahoo, Fastmail, Proton")
    func others() throws {
        let work = try #require(Webmail(provider: .outlookWork).composeURL(for: message))
        #expect(work.absoluteString.hasPrefix("https://outlook.office.com/mail/deeplink/compose?to=a@x.com%2Cb@y.com&cc=c@z.com&subject=Hi%20%26%20bye"))
        let personal = try #require(Webmail(provider: .outlookPersonal).composeURL(for: message))
        #expect(personal.host == "outlook.live.com")
        let yahoo = try #require(Webmail(provider: .yahoo).composeURL(for: message))
        #expect(yahoo.absoluteString.hasPrefix("https://compose.mail.yahoo.com/?to="))
        let fastmail = try #require(Webmail(provider: .fastmail).composeURL(for: message))
        #expect(fastmail.absoluteString.hasPrefix("https://app.fastmail.com/action/compose/?mailto=mailto%3Aa@x.com%2Cb@y.com%3Fcc%3D"))
        let proton = try #require(Webmail(provider: .proton).composeURL(for: message))
        #expect(proton.absoluteString.hasPrefix("https://mail.proton.me/inbox/#mailto=mailto%3A"))
    }

    @Test("Custom templates fill placeholders, encoded, and must be web addresses")
    func custom() throws {
        let webmail = Webmail(provider: .custom, template: "https://mail.example.org/new?to={to}&s={subject}")
        #expect(webmail.templateProblem == nil)
        #expect(webmail.composeURL(for: message)?.absoluteString == "https://mail.example.org/new?to=a@x.com%2Cb@y.com&s=Hi%20%26%20bye")
        #expect(Webmail(provider: .custom, template: "").templateProblem != nil)
        #expect(Webmail(provider: .custom, template: "https://mail.example.org/new").templateProblem != nil)
        let notWeb = Webmail(provider: .custom, template: "javascript:alert({to})")
        #expect(notWeb.templateProblem != nil)
        #expect(notWeb.composeURL(for: message) == nil)
    }

    @Test("A webmail target opens the compose page in its browser and profile")
    func launchPlan() throws {
        let plan = try #require(LaunchPlan.make(for: gmailWork, url: url("mailto:a@x.com?subject=Hi")))
        #expect(plan.method == .launchWithArguments(["--profile-directory=Profile 1", "https://mail.google.com/mail/?view=cm&fs=1&to=a@x.com&su=Hi"]))
        // Never hands a browser a mailto link (it would come straight back to us).
        #expect(LaunchPlan.make(for: gmailWork, url: url("https://example.com")) == nil)
        let broken = Target(bundleID: "com.apple.Safari", appPath: "/Applications/Safari.app", appName: "Safari",
                            webmail: Webmail(provider: .custom, template: "nonsense"))
        #expect(LaunchPlan.make(for: broken, url: url("mailto:a@x.com")) == nil)
        // A mail app just gets the mailto link.
        #expect(LaunchPlan.make(for: mail, url: url("mailto:a@x.com"))?.method == .openURL(url("mailto:a@x.com")))
    }

    @Test("Names: webmail targets read as the service in the browser")
    func names() {
        #expect(gmailWork.displayName == "Gmail in Google Chrome (Work)")
        #expect(gmailWork.pickerTitle == "Gmail")
        #expect(gmailWork.pickerSubtitle == "Google Chrome · Work")
        var account = gmailWork
        account.webmail?.account = "me@work.com"
        #expect(account.pickerTitle == "Gmail (me@work.com)")
        #expect(!account.isSameDestination(as: gmailWork))
        #expect(account.destinationKey != gmailWork.destinationKey)
    }
}

@Suite("Email routing")
struct EmailRoutingTests {
    func config(rules: [Rule] = [], emailFallback: Fallback = .ask) -> Config {
        Config(targets: [safari, chromeWork], rules: rules, didSeedTargets: true,
               emailTargets: [mail, gmailWork], emailFallback: emailFallback)
    }

    @Test("Email links get the email picker, never the browsers")
    func picker() {
        let decision = Router.route(IncomingLink(url: url("mailto:a@x.com")), config: config())
        #expect(decision == .pick([mail, gmailWork], reason: .fallback))
        #expect(Router.route(IncomingLink(url: url("https://example.com")), config: config()) == .pick([safari, chromeWork], reason: .fallback))
    }

    @Test("Email rules match any recipient's domain; web rules never match email")
    func rules() {
        let rules = [
            Rule(host: "work.com", action: .open(targetID: chromeWork.id)),
            Rule(kind: .email, host: "work.com", action: .open(targetID: gmailWork.id)),
        ]
        #expect(Router.route(IncomingLink(url: url("mailto:ann@work.com")), config: config(rules: rules)) == .open(gmailWork, reason: .rule(index: 1)))
        #expect(Router.route(IncomingLink(url: url("mailto:me@home.org?cc=ann@work.com")), config: config(rules: rules)) == .open(gmailWork, reason: .rule(index: 1)))
        #expect(Router.route(IncomingLink(url: url("https://work.com")), config: config(rules: rules)) == .open(chromeWork, reason: .rule(index: 0)))
        #expect(Router.route(IncomingLink(url: url("mailto:me@home.org")), config: config(rules: rules)).reason == .fallback)
    }

    @Test("Source app and keys work for email rules too; email fallback")
    func sourceAndFallback() {
        let rules = [Rule(kind: .email, sourceApp: SourceAppMatch(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"), action: .open(targetID: gmailWork.id))]
        let fromSlack = IncomingLink(url: url("mailto:x@y.com"), sourceBundleID: "com.tinyspeck.slackmacgap")
        #expect(Router.route(fromSlack, config: config(rules: rules)) == .open(gmailWork, reason: .rule(index: 0)))
        let other = IncomingLink(url: url("mailto:x@y.com"))
        #expect(Router.route(other, config: config(rules: rules, emailFallback: .open(targetID: mail.id))) == .open(mail, reason: .fallback))
        // The ask key still forces the picker.
        let held = IncomingLink(url: url("mailto:x@y.com"), sourceBundleID: "com.tinyspeck.slackmacgap", modifiers: .option)
        #expect(Router.route(held, config: config(rules: rules)) == .pick([mail, gmailWork], reason: .askModifier))
    }

    @Test("No email targets: nothing to open, said for email")
    func none() {
        let cfg = Config(targets: [safari], didSeedTargets: true)
        let decision = Router.route(IncomingLink(url: url("mailto:x@y.com")), config: cfg)
        #expect(decision == .noTargets)
        #expect(Router.describe(decision, kind: .email).contains("Email tab"))
    }

    @Test("Always use from the picker makes an email rule for the recipient's domain")
    func learned() throws {
        let rule = try #require(Router.alwaysOpenRule(for: url("mailto:Ann@Work.com?subject=x"), in: gmailWork))
        #expect(rule.kind == .email)
        #expect(rule.host == "work.com")
        #expect(Router.alwaysOpenLabel(for: url("mailto:ann@work.com")) == "Email to work.com")
        #expect(Router.alwaysOpenRule(for: url("mailto:"), in: gmailWork) == nil)
        var cfg = config()
        Router.insertLearnedRule(rule, into: &cfg)
        Router.insertLearnedRule(Rule(kind: .email, host: "work.com", action: .open(targetID: mail.id)), into: &cfg)
        #expect(cfg.rules.count == 1)
        #expect(cfg.rules[0].action == .open(targetID: mail.id))
        // A web rule for the same host is a different rule.
        Router.insertLearnedRule(Rule(host: "work.com", action: .open(targetID: safari.id)), into: &cfg)
        #expect(cfg.rules.count == 2)
    }

    @Test("Email rule editing: validation, normalizing, summaries, shadowing")
    func ruleEditing() {
        #expect(Rule(kind: .email, host: "mailto:*@Work.com", action: .ask).normalized().host == "work.com")
        #expect(Rule(kind: .email, host: "not an address", action: .ask).normalized().validationProblem != nil)
        #expect(Rule(kind: .email, host: "*", action: .ask).normalized().validationProblem != nil)
        #expect(Rule(kind: .email, action: .ask).validationProblem == "Add an address, app or key to match.")
        #expect(Rule(kind: .email, host: "work.com", action: .ask).conditionSummary == "Email to work.com")
        let broad = Rule(kind: .email, host: "*.work.com", action: .ask)
        let narrow = Rule(kind: .email, host: "boss@work.com", action: .ask)
        #expect(broad.covers(narrow))
        #expect(!Rule(host: "*.work.com", action: .ask).covers(narrow))
        #expect(RuleAnalysis.shadowing(in: [broad, narrow]) == [nil, 0])
    }
}
