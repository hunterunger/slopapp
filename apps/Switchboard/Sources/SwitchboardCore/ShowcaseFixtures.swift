import Foundation

/// Synthetic settings for the store screenshots (`SLOP_SHOWCASE`, docs/screenshots.md): two
/// browsers everyone has a reason to keep apart, made-up profile names, and a handful of
/// rules people actually write. Nothing here comes from the Mac it runs on except the two
/// apps' locations (for their icons).
public enum ShowcaseFixtures {
    public static let safariID = "com.apple.Safari"
    public static let chromeID = "com.google.Chrome"

    /// The link the hero picker is choosing a browser for. No rule matches it.
    public static let link = URL(string: "https://en.wikipedia.org/wiki/Telephone_switchboard")!

    /// The browser selected in the Browsers scene, so its options show.
    public static var selectedTarget: UUID { chromeWork }

    // Fixed ids, so every run of a scene is the same.
    static let safari = UUID(uuidString: "5A1F0000-0000-4000-8000-000000000001")!
    static let chromeWork = UUID(uuidString: "5A1F0000-0000-4000-8000-000000000002")!
    static let chromePersonal = UUID(uuidString: "5A1F0000-0000-4000-8000-000000000003")!
    static let safariPrivate = UUID(uuidString: "5A1F0000-0000-4000-8000-000000000004")!

    private static func rule(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "5A1F0000-0000-4000-8000-0000000001%02d", n))!
    }

    /// - Parameters: where the two apps are on this Mac (for their icons).
    public static func config(safariPath: String = "/Applications/Safari.app",
                              chromePath: String = "/Applications/Google Chrome.app") -> Config {
        let targets = [
            Target(id: safari, bundleID: safariID, appPath: safariPath, appName: "Safari"),
            Target(id: chromeWork, bundleID: chromeID, appPath: chromePath, appName: "Google Chrome",
                   profile: BrowserProfile(directory: "Profile 1", name: "Work")),
            Target(id: chromePersonal, bundleID: chromeID, appPath: chromePath, appName: "Google Chrome",
                   profile: BrowserProfile(directory: "Default", name: "Personal")),
            Target(id: safariPrivate, bundleID: safariID, appPath: safariPath, appName: "Safari", privateWindow: true),
        ]
        let rules = [
            Rule(id: rule(1), host: "github.com", action: .open(targetID: chromeWork)),
            Rule(id: rule(2), host: "*.atlassian.net", action: .open(targetID: chromeWork)),
            Rule(id: rule(3), sourceApp: SourceAppMatch(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
                 action: .open(targetID: chromeWork)),
            Rule(id: rule(4), host: "figma.com", action: .open(targetID: chromeWork)),
            Rule(id: rule(5), host: "youtube.com", action: .open(targetID: safari)),
            Rule(id: rule(6), modifiers: .shift, action: .open(targetID: safariPrivate)),
        ]
        return Config(targets: targets, rules: rules, fallback: .ask, askModifiers: .option, didSeedTargets: true,
                      pickerSize: .medium)
    }
}
