import Foundation

/// Facts from an app bundle's Info.plist.
public struct BundleInfo: Sendable, Equatable {
    public var bundleID: String
    public var version: String
    public var build: String

    public init(bundleID: String, version: String, build: String) {
        self.bundleID = bundleID
        self.version = version
        self.build = build
    }

    public var appVersion: AppVersion { AppVersion(version, build: build) }
}

/// Where a copy of an app lives, which decides what the launcher may do with it.
public enum CopyLocation: Sendable, Equatable {
    /// In the launcher's own folder (/Applications/Slopapp or ~/Applications/Slopapp).
    case managed
    /// Directly in /Applications or ~/Applications (e.g. downloaded from the website).
    /// Updated and removed in place, like a managed copy.
    case applications
    /// Anywhere else (a development build, Downloads...). Opened and shown, never changed.
    case elsewhere

    public var canModify: Bool { self != .elsewhere }
}

public struct InstalledCopy: Sendable, Equatable {
    public var url: URL
    public var info: BundleInfo
    public var location: CopyLocation
    public var signature: SignatureInfo?

    public init(url: URL, info: BundleInfo, location: CopyLocation, signature: SignatureInfo? = nil) {
        self.url = url
        self.info = info
        self.location = location
        self.signature = signature
    }
}

/// The folders the launcher installs into and recognises.
public struct InstallRoots: Sendable, Equatable {
    /// Where new installs go.
    public var installDirectory: URL
    /// Other folders whose copies count as managed (the other Slopapp folder).
    public var managedDirectories: [URL]
    /// Plain Applications folders: copies here are updated in place.
    public var applicationsDirectories: [URL]
    /// Look up other copies through LaunchServices (shown, never changed).
    public var searchesElsewhere: Bool

    public init(installDirectory: URL, managedDirectories: [URL], applicationsDirectories: [URL], searchesElsewhere: Bool = true) {
        self.installDirectory = installDirectory
        self.managedDirectories = managedDirectories
        self.applicationsDirectories = applicationsDirectories
        self.searchesElsewhere = searchesElsewhere
    }

    /// Picks the install folder: `override` (SLOPAPP_INSTALL_DIR) if given, else
    /// /Applications/Slopapp when /Applications is writable, else ~/Applications/Slopapp.
    /// With an override, nothing outside it is ever modified. With `searchesElsewhere` false
    /// (store screenshots), nothing outside it is even looked at.
    public static func resolve(override: URL?, home: URL, folderName: String = "Slopapp", searchesElsewhere: Bool = true,
                               isWritable: (URL) -> Bool) -> InstallRoots {
        if let override {
            return InstallRoots(installDirectory: override, managedDirectories: [], applicationsDirectories: [],
                                searchesElsewhere: searchesElsewhere)
        }
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let user = home.appendingPathComponent("Applications", isDirectory: true)
        let systemFolder = system.appendingPathComponent(folderName, isDirectory: true)
        let userFolder = user.appendingPathComponent(folderName, isDirectory: true)
        // An existing folder we can write to wins, so updates land where installs went.
        let install: URL
        if isWritable(systemFolder) || isWritable(system) {
            install = systemFolder
        } else {
            install = userFolder
        }
        let otherManaged = [systemFolder, userFolder].filter { $0 != install }
        return InstallRoots(installDirectory: install, managedDirectories: otherManaged, applicationsDirectories: [system, user],
                            searchesElsewhere: searchesElsewhere)
    }

    public func location(of url: URL) -> CopyLocation {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        if ([installDirectory] + managedDirectories).contains(where: { $0.standardizedFileURL.path == parent }) {
            return .managed
        }
        if applicationsDirectories.contains(where: { $0.standardizedFileURL.path == parent }) {
            return .applications
        }
        return .elsewhere
    }

    /// The paths a feed app would have in each known folder, in preference order.
    public func expectedPaths(appName: String) -> [URL] {
        ([installDirectory] + managedDirectories + applicationsDirectories)
            .map { $0.appendingPathComponent("\(appName).app", isDirectory: true) }
    }
}

/// Reads the file system and LaunchServices. Faked in tests.
public protocol AppLocating: Sendable {
    func bundleInfo(at url: URL) -> BundleInfo?
    /// Every copy LaunchServices knows for this bundle id (anywhere on disk).
    func registeredCopies(bundleID: String) -> [URL]
    func signature(at url: URL) -> SignatureInfo
}

public enum Inventory {
    /// Every copy of `bundleID` the launcher can see, best first: managed, then
    /// Applications, then elsewhere; higher versions first within each.
    public static func copies(of bundleID: String, appName: String, roots: InstallRoots, locator: any AppLocating, checkSignatures: Bool = true) -> [InstalledCopy] {
        var urls = roots.expectedPaths(appName: appName)
        if roots.searchesElsewhere {
            urls += locator.registeredCopies(bundleID: bundleID)
        }
        var seen = Set<String>()
        var copies: [InstalledCopy] = []
        for url in urls {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(key).inserted else { continue }
            // Skip copies in the Trash.
            if key.contains("/.Trash/") { continue }
            guard let info = locator.bundleInfo(at: url), info.bundleID == bundleID else { continue }
            let signature = checkSignatures ? locator.signature(at: url) : nil
            copies.append(InstalledCopy(url: url, info: info, location: roots.location(of: url), signature: signature))
        }
        let rank: (CopyLocation) -> Int = { [.managed: 0, .applications: 1, .elsewhere: 2][$0]! }
        return copies.sorted {
            rank($0.location) != rank($1.location) ? rank($0.location) < rank($1.location) : $0.info.appVersion > $1.info.appVersion
        }
    }
}
