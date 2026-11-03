import Foundation

/// A browser profile, e.g. Chrome's "Work" profile in folder "Profile 1".
public struct BrowserProfile: Codable, Hashable, Sendable {
    /// The folder name the browser uses (`--profile-directory=<directory>`).
    public var directory: String
    /// The name people see ("Work").
    public var name: String

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

/// Something a link can open in: an app, optionally with a profile and options. The same app
/// can appear several times (different profiles, private, background).
public struct Target: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var bundleID: String
    /// Last known location of the app.
    public var appPath: String
    public var appName: String
    public var profile: BrowserProfile?
    public var privateWindow: Bool
    public var opensInBackground: Bool
    /// Hidden targets aren't offered in the picker, but rules can still use them.
    public var isHidden: Bool

    public init(
        id: UUID = UUID(),
        bundleID: String,
        appPath: String,
        appName: String,
        profile: BrowserProfile? = nil,
        privateWindow: Bool = false,
        opensInBackground: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appPath = appPath
        self.appName = appName
        self.profile = profile
        self.privateWindow = privateWindow
        self.opensInBackground = opensInBackground
        self.isHidden = isHidden
    }

    /// "Google Chrome", "Google Chrome (Work)", "Firefox (Private)".
    public var displayName: String {
        var extras: [String] = []
        if let profile { extras.append(profile.name) }
        if privateWindow { extras.append("Private") }
        return extras.isEmpty ? appName : "\(appName) (\(extras.joined(separator: ", ")))"
    }

    /// Short name for tight spaces (the picker): the profile name if any, else the app name.
    public var shortName: String {
        if let profile { return privateWindow ? "\(profile.name) (Private)" : profile.name }
        return privateWindow ? "Private" : appName
    }

    /// Which browser, profile and window kind this is, ignoring id and options. Used to bring
    /// back a removed target's identity when the same browser is added again.
    public var destinationKey: String {
        "\(bundleID.lowercased())|\(profile?.directory ?? "")|\(privateWindow)"
    }

    /// Same destination, ignoring id and visibility. Used to avoid duplicate entries.
    public func isSameDestination(as other: Target) -> Bool {
        bundleID == other.bundleID && profile?.directory == other.profile?.directory
            && privateWindow == other.privateWindow && opensInBackground == other.opensInBackground
    }
}
