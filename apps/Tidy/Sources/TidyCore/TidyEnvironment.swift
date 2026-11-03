import Foundation

/// Where Tidy looks and where "Move to Trash" puts things.
///
/// Normally that's the real home folder, `/Applications`, `~/Applications`, `/Library` and the
/// user's Trash. Setting any `TIDY_*` variable switches to **test mode**: every scan and every
/// move happens inside the given fixture folders, and nothing outside them is ever touched.
///
///     TIDY_HOME=/tmp/tidy-test/home                 the home folder to scan (required in test mode)
///     TIDY_APPS_DIRS=/tmp/tidy-test/Applications    colon-separated app folders (default: $TIDY_HOME/Applications)
///     TIDY_TRASH_DIR=/tmp/tidy-test/Trash           where "Move to Trash" moves things (default: $TIDY_HOME/.Trash)
///     TIDY_SYSTEM_LIBRARY=/tmp/tidy-test/Library    stands in for /Library (default in test mode: none)
///     TIDY_RUNNING_IDS=com.example.App,...          bundle ids to treat as running (test mode only)
public struct TidyEnvironment: Sendable, Equatable {
    public var home: URL
    public var applicationDirectories: [URL]
    /// `/Library` (or its stand-in). Items there usually need an administrator to remove.
    public var systemLibrary: URL?
    /// `nil` means the user's real Trash.
    public var trashDirectory: URL?
    public var isTestMode: Bool
    /// Bundle ids test mode pretends are running, so the "quit it first" path can be tried.
    public var simulatedRunningBundleIDs: Set<String>
    /// Ask LaunchServices whether an app is installed somewhere else (off in test mode, so
    /// fixtures behave the same on every Mac).
    public var usesLaunchServices: Bool
    /// Problems with the test-mode setup, shown in the window so they're never silent.
    public var warnings: [String]

    public init(home: URL, applicationDirectories: [URL], systemLibrary: URL?, trashDirectory: URL?,
                isTestMode: Bool, simulatedRunningBundleIDs: Set<String> = [], usesLaunchServices: Bool,
                warnings: [String] = []) {
        self.home = home.standardizedFileURL
        self.applicationDirectories = applicationDirectories.map(\.standardizedFileURL)
        self.systemLibrary = systemLibrary?.standardizedFileURL
        self.trashDirectory = trashDirectory?.standardizedFileURL
        self.isTestMode = isTestMode
        self.simulatedRunningBundleIDs = simulatedRunningBundleIDs
        self.usesLaunchServices = usesLaunchServices
        self.warnings = warnings
    }

    public static let variableNames = ["TIDY_HOME", "TIDY_APPS_DIRS", "TIDY_TRASH_DIR", "TIDY_SYSTEM_LIBRARY"]

    public static var current: TidyEnvironment {
        from(environment: ProcessInfo.processInfo.environment,
             realHome: FileManager.default.homeDirectoryForCurrentUser)
    }

    public static func from(environment env: [String: String], realHome: URL) -> TidyEnvironment {
        func value(_ key: String) -> String? {
            guard let raw = env[key]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            return raw
        }
        func directory(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }

        let isTestMode = variableNames.contains { value($0) != nil }
        guard isTestMode else {
            return TidyEnvironment(
                home: realHome,
                applicationDirectories: [URL(fileURLWithPath: "/Applications", isDirectory: true),
                                         realHome.appendingPathComponent("Applications", isDirectory: true)],
                systemLibrary: URL(fileURLWithPath: "/Library", isDirectory: true),
                trashDirectory: nil,
                isTestMode: false,
                usesLaunchServices: true
            )
        }

        var warnings: [String] = []
        let home: URL
        if let path = value("TIDY_HOME") {
            home = directory(path)
        } else {
            // Never fall back to the real home in test mode: scan an empty place instead.
            home = URL(fileURLWithPath: "/var/empty", isDirectory: true)
            warnings.append("TIDY_HOME isn't set, so there's nothing to scan.")
        }
        let apps = value("TIDY_APPS_DIRS").map { $0.split(separator: ":").map { directory(String($0)) } }
            ?? [home.appendingPathComponent("Applications", isDirectory: true)]
        let trash = value("TIDY_TRASH_DIR").map(directory) ?? home.appendingPathComponent(".Trash", isDirectory: true)
        let running = Set((value("TIDY_RUNNING_IDS") ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return TidyEnvironment(
            home: home,
            applicationDirectories: apps,
            systemLibrary: value("TIDY_SYSTEM_LIBRARY").map(directory),
            trashDirectory: trash,
            isTestMode: true,
            simulatedRunningBundleIDs: running,
            usesLaunchServices: false,
            warnings: warnings
        )
    }

    /// `home/Library`.
    public var library: URL { home.appendingPathComponent("Library", isDirectory: true) }

    /// Short description for the window subtitle in test mode.
    public var testModeSummary: String? {
        guard isTestMode else { return nil }
        return "Test mode: \(home.path)"
    }
}
