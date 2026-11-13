import Foundation

/// Exactly how to hand a link to a target. Built in the core so it's testable; executed by
/// the app with NSWorkspace.
public struct LaunchPlan: Equatable, Sendable {
    public enum Method: Equatable, Sendable {
        /// `NSWorkspace.open([url], withApplicationAt:)`: the normal path, fastest.
        case openURL(URL)
        /// Launch (a new instance of) the app with arguments. Needed for profiles and private
        /// windows: the browser's running instance picks the arguments up and opens the URL.
        case launchWithArguments([String])
        /// Safari: open this kind of window from its File menu (needs Accessibility), then
        /// hand it the link, which opens in that new front window.
        case safariWindow(SafariWindowRequest, URL)
    }

    public var appPath: String
    public var method: Method
    public var activates: Bool

    public init(appPath: String, method: Method, activates: Bool) {
        self.appPath = appPath
        self.method = method
        self.activates = activates
    }

    /// The link the target actually gets: webmail turns a mailto link into its compose page.
    public var url: URL? {
        switch method {
        case .openURL(let url), .safariWindow(_, let url): url
        case .launchWithArguments(let arguments): arguments.last.flatMap(URL.init(string:))
        }
    }

    /// Whether this plan needs Accessibility (Safari windows).
    public var needsAccessibility: Bool {
        if case .safariWindow = method { return true }
        return false
    }

    /// - Parameter background: open without bringing the browser forward (target option, or ⇧ in the picker).
    /// - Returns: nil when the link can't go to this target: a webmail target given something
    ///   that isn't a mailto link, or a custom compose address that doesn't work. Never falls
    ///   back to giving a browser the mailto link (it would hand it straight back to us).
    public static func make(for target: Target, url: URL, background: Bool = false) -> LaunchPlan? {
        let activates = !(background || target.opensInBackground)
        var url = url
        if let webmail = target.webmail {
            guard let mail = MailtoLink(url), let compose = webmail.composeURL(for: mail) else { return nil }
            url = compose
        }
        let family = BrowserCatalog.family(for: target.bundleID)
        var arguments: [String] = []

        switch family {
        case .chromium:
            if let profile = target.profile {
                arguments.append("--profile-directory=\(profile.directory)")
            }
            if target.privateWindow {
                arguments.append("--incognito")
            }
        case .firefox:
            if target.privateWindow {
                arguments.append("-private-window")
            }
        case .safari:
            // Private beats profile: Safari's private windows aren't tied to a profile.
            if target.privateWindow {
                return LaunchPlan(appPath: target.appPath, method: .safariWindow(.privateWindow, url), activates: true)
            }
            if let profile = target.profile {
                return LaunchPlan(appPath: target.appPath, method: .safariWindow(.profile(profile.directory), url), activates: true)
            }
        case .other:
            break
        }

        guard !arguments.isEmpty else {
            return LaunchPlan(appPath: target.appPath, method: .openURL(url), activates: activates)
        }
        arguments.append(url.absoluteString)
        return LaunchPlan(appPath: target.appPath, method: .launchWithArguments(arguments), activates: activates)
    }
}

/// Drops a second delivery of the same link within a short window. macOS (and some apps)
/// can deliver one click twice; opening two tabs is a known failure of link routers.
public struct Deduplicator: Sendable {
    public var window: TimeInterval
    private var last: (url: String, time: TimeInterval)?

    public init(window: TimeInterval = 0.4) {
        self.window = window
    }

    /// Returns true if this link should be handled, false if it's a duplicate.
    public mutating func accept(_ url: URL, at time: TimeInterval) -> Bool {
        let key = url.absoluteString
        if let last, last.url == key, time - last.time >= 0, time - last.time < window {
            return false
        }
        last = (key, time)
        return true
    }
}

/// Maps a process's bundle path to the app a person would recognise: helper apps inside
/// another app's bundle ("Slack.app/Contents/Frameworks/Slack Helper.app") count as the
/// outer app.
public enum SourceApp {
    public static func outermostAppPath(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
        return components[...index].joined(separator: "/")
    }
}
