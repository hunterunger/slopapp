import Foundation

/// Where an app keeps its data: `~/Library/Application Support/<bundle id>`.
public enum AppPaths {
    /// The app's Application Support folder, created on first use.
    /// Falls back to the executable name when run outside a bundle (`swift run`).
    public static var applicationSupport: URL {
        get throws {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let dir = applicationSupport(in: base, bundleIdentifier: Bundle.main.bundleIdentifier,
                                         executableName: ProcessInfo.processInfo.processName)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    /// Pure path math, separated so it can be tested.
    public static func applicationSupport(in base: URL, bundleIdentifier: String?, executableName: String) -> URL {
        let folder = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? "app.slopapp.\(executableName.lowercased())"
        return base.appendingPathComponent(folder, isDirectory: true)
    }
}
