import Foundation
import SlopappCore

/// Where the feed lives, where apps go, and the trust anchors. Production values come from
/// Info.plist (generated from app.json, which `scripts/feed.mjs` keeps in sync with
/// brand/brand.json). Environment overrides exist for testing only:
///
/// - `SLOPAPP_FEED_URL`: another feed (https, file:// or http://localhost). Also allows
///   file:// and loopback download URLs.
/// - `SLOPAPP_INSTALL_DIR`: install here; nothing outside it is ever changed.
/// - `SLOPAPP_TRASH_DIR`: "Move to Trash" moves here instead.
/// - `SLOPAPP_LIBRARY_DIR`: the Library folder "remove its settings" cleans.
/// - `SLOPAPP_STATE_DIR`: caches and the feed cache go here instead of ~/Library.
/// - `SLOPAPP_APPEARANCE=light|dark`: force an appearance for screenshots.
/// - `SLOPAPP_SMOKE_TEST=1` (set by scripts/smoke.sh): no network.
///
/// Store screenshots (`SLOP_SHOWCASE`, see Showcase.swift) put every one of these paths inside
/// the scene's data folder (`ShowcaseSandbox`) and look for apps nowhere else.
struct Config: Sendable {
    var feedURL: URL
    var isDeveloperFeed: Bool
    var requiredTeamID: String?
    var roots: InstallRoots
    var trashDirectory: URL?
    var library: URL
    var isTestingLibrary: Bool
    /// Replaces ~/Library/Caches/<id> and ~/Library/Application Support/<id> (testing only).
    var stateDirectory: URL?
    var forcedAppearance: String?
    var allowsNetwork: Bool

    static let defaultFeedURL = URL(string: "https://hunterunger.github.io/slopapp/feed.json")!

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment,
                     info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> Config {
        let isShowcase = ShowcaseSandbox.isActive(environment)
        let env = ShowcaseSandbox.environment(
            environment, data: ShowcaseSandbox.dataDirectory(environment, temporary: FileManager.default.temporaryDirectory))
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plistFeed = (info["SlopappFeedURL"] as? String).flatMap(URL.init(string:))
        let envFeed = env["SLOPAPP_FEED_URL"].flatMap { value -> URL? in
            value.hasPrefix("/") ? URL(fileURLWithPath: value) : URL(string: value)
        }
        let installOverride = env["SLOPAPP_INSTALL_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let roots = InstallRoots.resolve(override: installOverride, home: home, searchesElsewhere: !isShowcase) { url in
            FileManager.default.fileExists(atPath: url.path) && FileManager.default.isWritableFile(atPath: url.path)
        }
        let libraryOverride = env["SLOPAPP_LIBRARY_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return Config(
            feedURL: envFeed ?? plistFeed ?? defaultFeedURL,
            isDeveloperFeed: envFeed != nil,
            requiredTeamID: info["SlopappTeamID"] as? String,
            roots: roots,
            trashDirectory: env["SLOPAPP_TRASH_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            library: libraryOverride ?? home.appendingPathComponent("Library", isDirectory: true),
            isTestingLibrary: libraryOverride != nil,
            stateDirectory: env["SLOPAPP_STATE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            forcedAppearance: env["SLOPAPP_APPEARANCE"],
            allowsNetwork: env["SLOPAPP_SMOKE_TEST"] != "1"
        )
    }

    var urlPolicy: URLPolicy { URLPolicy(allowsLocal: isDeveloperFeed) }
    var signaturePolicy: SignaturePolicy { SignaturePolicy(requiredTeamID: requiredTeamID) }
}
