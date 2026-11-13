import Foundation

/// A link an app opens better than a browser: a Zoom meeting, an Apple Music album, a Figma
/// file. Turned on per app in Settings; when the app is installed, its links go straight to it
/// as the app's own link (`zoommtg://…`), before any rule.
public struct AppHandoff: Identifiable, Sendable {
    public let id: String
    /// "Zoom meetings", for the switch in Settings.
    public let title: String
    /// "Zoom": shown in logs, the tester and the toast.
    public let appName: String
    /// The app, newest bundle id first (an app that changed ids keeps working).
    public let bundleIDs: [String]
    /// "zoom.us/j/…", the links it takes.
    public let example: String
    let transform: @Sendable (URLComponents) -> URL?

    /// The app's own link for `url`, or nil if this app doesn't take it.
    public func appLink(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false else { return nil }
        var lowered = components
        lowered.host = components.host?.lowercased()
        return transform(lowered)
    }
}

/// Where a link went instead of a browser.
public struct AppLink: Equatable, Sendable {
    /// The app's own link (`zoommtg://…`).
    public var url: URL
    /// The app to open it in; nil = whichever app macOS uses for that kind of link.
    public var bundleID: String?
    /// "Zoom"; nil when a rewrite made the link and macOS picks the app.
    public var appName: String?
    /// The built-in handoff that made it, or nil for a rewrite.
    public var handoffID: String?

    public init(url: URL, bundleID: String? = nil, appName: String? = nil, handoffID: String? = nil) {
        self.url = url
        self.bundleID = bundleID
        self.appName = appName
        self.handoffID = handoffID
    }
}

public enum Handoffs {
    private static func host(_ c: URLComponents, is base: String) -> Bool {
        guard let host = c.host else { return false }
        return host == base || host == "www." + base
    }

    private static func host(_ c: URLComponents, under base: String) -> Bool {
        guard let host = c.host else { return false }
        return host == base || host.hasSuffix("." + base)
    }

    /// Path components without empty ones: "/j/123/" → ["j", "123"].
    private static func parts(_ c: URLComponents) -> [String] {
        c.path.split(separator: "/").map(String.init)
    }

    /// Same host and path under another scheme: https://music.apple.com/x → music://music.apple.com/x.
    private static func swapScheme(_ c: URLComponents, to scheme: String) -> URL? {
        var copy = c
        copy.scheme = scheme
        copy.port = nil
        return copy.url
    }

    public static let all: [AppHandoff] = [
        AppHandoff(id: "zoom", title: "Zoom meetings", appName: "Zoom", bundleIDs: ["us.zoom.xos"],
                   example: "zoom.us/j/…") { c in
            let p = parts(c)
            guard host(c, under: "zoom.us"), p.count >= 2, ["j", "s", "w"].contains(p[0]),
                  !p[1].isEmpty, p[1].allSatisfy(\.isNumber) else { return nil }
            var out = URLComponents()
            out.scheme = "zoommtg"
            out.host = c.host
            out.path = "/join"
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: p[1])]
            if let pwd = c.queryItems?.first(where: { $0.name == "pwd" })?.value, !pwd.isEmpty {
                items.append(URLQueryItem(name: "pwd", value: pwd))
            }
            out.queryItems = items
            return out.url
        },
        AppHandoff(id: "teams", title: "Microsoft Teams meetings and chats", appName: "Microsoft Teams",
                   bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"], example: "teams.microsoft.com/l/…") { c in
            guard host(c, is: "teams.microsoft.com") || host(c, is: "teams.live.com"), c.path.hasPrefix("/l/") else { return nil }
            var text = "msteams:" + c.percentEncodedPath
            if let query = c.percentEncodedQuery, !query.isEmpty { text += "?" + query }
            return URL(string: text)
        },
        AppHandoff(id: "music", title: "Apple Music", appName: "Music", bundleIDs: ["com.apple.Music"],
                   example: "music.apple.com/…") { c in
            guard host(c, is: "music.apple.com"), c.path.count > 1 else { return nil }
            return swapScheme(c, to: "music")
        },
        AppHandoff(id: "podcasts", title: "Apple Podcasts", appName: "Podcasts", bundleIDs: ["com.apple.podcasts"],
                   example: "podcasts.apple.com/…") { c in
            guard host(c, is: "podcasts.apple.com"), c.path.count > 1 else { return nil }
            return swapScheme(c, to: "podcasts")
        },
        AppHandoff(id: "appstore", title: "App Store pages", appName: "App Store", bundleIDs: ["com.apple.AppStore"],
                   example: "apps.apple.com/…/app/…") { c in
            guard host(c, is: "apps.apple.com"), parts(c).contains("app") else { return nil }
            return swapScheme(c, to: "macappstore")
        },
        AppHandoff(id: "spotify", title: "Spotify", appName: "Spotify", bundleIDs: ["com.spotify.client"],
                   example: "open.spotify.com/…") { c in
            guard host(c, is: "open.spotify.com") else { return nil }
            var p = parts(c)
            if let first = p.first, first.hasPrefix("intl-") { p.removeFirst() }
            let kinds = ["track", "album", "playlist", "artist", "episode", "show"]
            guard p.count >= 2, kinds.contains(p[0]), !p[1].isEmpty,
                  p[1].allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return URL(string: "spotify:\(p[0]):\(p[1])")
        },
        AppHandoff(id: "figma", title: "Figma files", appName: "Figma", bundleIDs: ["com.figma.Desktop"],
                   example: "figma.com/design/…") { c in
            let p = parts(c)
            guard host(c, is: "figma.com"), p.count >= 2,
                  ["file", "design", "proto", "board", "slides", "deck", "make"].contains(p[0]) else { return nil }
            var text = "figma://" + c.percentEncodedPath.dropFirst()
            if let query = c.percentEncodedQuery, !query.isEmpty { text += "?" + query }
            return URL(string: text)
        },
        AppHandoff(id: "slack", title: "Slack channels", appName: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"],
                   example: "app.slack.com/client/…") { c in
            let p = parts(c)
            guard host(c, is: "app.slack.com"), p.count >= 3, p[0] == "client",
                  p[1].hasPrefix("T") || p[1].hasPrefix("E") else { return nil }
            var out = URLComponents()
            out.scheme = "slack"
            out.host = "channel"
            out.queryItems = [URLQueryItem(name: "team", value: p[1]), URLQueryItem(name: "id", value: p[2])]
            return out.url
        },
        AppHandoff(id: "notion", title: "Notion pages", appName: "Notion", bundleIDs: ["notion.id"],
                   example: "notion.so/…") { c in
            guard host(c, is: "notion.so"), c.path.count > 1 else { return nil }
            var copy = c
            copy.scheme = "notion"
            copy.host = "www.notion.so"
            return copy.url
        },
        AppHandoff(id: "linear", title: "Linear issues and projects", appName: "Linear", bundleIDs: ["com.linear"],
                   example: "linear.app/…/issue/…") { c in
            let p = parts(c)
            guard host(c, is: "linear.app"), p.count >= 3,
                  ["issue", "project", "view", "team", "cycle", "initiative"].contains(p[1]) else { return nil }
            var text = "linear://" + c.percentEncodedPath.dropFirst()
            if let query = c.percentEncodedQuery, !query.isEmpty { text += "?" + query }
            return URL(string: text)
        },
        AppHandoff(id: "discord", title: "Discord channels and invites", appName: "Discord", bundleIDs: ["com.hnc.Discord"],
                   example: "discord.com/channels/…") { c in
            let p = parts(c)
            if host(c, is: "discord.gg"), p.count == 1 {
                return URL(string: "discord://discord.com/invite/\(p[0])")
            }
            guard host(c, is: "discord.com") || host(c, is: "discordapp.com"), p.count >= 2,
                  p[0] == "channels" || p[0] == "invite" else { return nil }
            return URL(string: "discord://discord.com" + c.percentEncodedPath)
        },
    ]

    public static func handoff(id: String) -> AppHandoff? {
        all.first { $0.id == id }
    }

    /// The first turned-on handoff whose app is installed and takes this link.
    ///
    /// - Parameters:
    ///   - source: the app the link came from. A link an app sent out on purpose ("Open in
    ///     Browser") never goes back to that app, or it would bounce forever.
    ///   - installedApp: the bundle id from `bundleIDs` that's installed, if any.
    public static func match(
        _ url: URL, enabled: [String], source: String?, installedApp: (AppHandoff) -> String?
    ) -> AppLink? {
        for id in enabled {
            guard let handoff = handoff(id: id), let appURL = handoff.appLink(for: url) else { continue }
            if let source, handoff.bundleIDs.contains(where: { $0.caseInsensitiveCompare(source) == .orderedSame }) { continue }
            guard let bundleID = installedApp(handoff) else { continue }
            return AppLink(url: appURL, bundleID: bundleID, appName: handoff.appName, handoffID: handoff.id)
        }
        return nil
    }
}
