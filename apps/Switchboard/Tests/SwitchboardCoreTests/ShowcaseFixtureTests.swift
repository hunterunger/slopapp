import Foundation
import Testing
@testable import SwitchboardCore

@Suite struct ShowcaseFixtureTests {
    let config = ShowcaseFixtures.config()

    @Test func theHeroLinkShowsThePickerWithEveryBrowser() {
        let decision = Router.route(IncomingLink(url: ShowcaseFixtures.link), config: config)
        guard case .pick(let targets, _) = decision else {
            Issue.record("expected the picker, got \(decision)")
            return
        }
        #expect(targets.map(\.displayName) == ["Safari", "Google Chrome (Work)", "Google Chrome (Personal)", "Safari (Private)"])
    }

    @Test func theRulesDoWhatTheirScreenshotSays() {
        func destination(_ url: String, from source: String? = nil, holding: Modifiers = []) -> String? {
            let link = IncomingLink(url: URL(string: url)!, sourceBundleID: source, modifiers: holding)
            guard case .open(let target, _) = Router.route(link, config: config) else { return nil }
            return target.displayName
        }
        #expect(destination("https://github.com/acme/site/pull/1") == "Google Chrome (Work)")
        #expect(destination("https://acme.atlassian.net/browse/WEB-12") == "Google Chrome (Work)")
        #expect(destination("https://example.com", from: "com.tinyspeck.slackmacgap") == "Google Chrome (Work)")
        #expect(destination("https://www.figma.com/file/abc") == "Google Chrome (Work)")
        #expect(destination("https://www.youtube.com/watch?v=1") == "Safari")
        #expect(destination("https://example.com", holding: .shift) == "Safari (Private)")
    }

    @Test func everyRuleIsUsefulAndValid() {
        #expect(config.rules.allSatisfy { $0.hasConditions && $0.validationProblem == nil })
        #expect(RuleAnalysis.unused(in: config.rules, askModifiers: config.askModifiers).allSatisfy { $0 == nil })
    }

    @Test func itIsTheSameEveryTime() {
        #expect(ShowcaseFixtures.config() == ShowcaseFixtures.config())
    }
}
