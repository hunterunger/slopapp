import Foundation

/// A kind of junk: things apps and developer tools recreate when they need them.
public enum JunkCategory: String, CaseIterable, Sendable, Identifiable {
    case userCaches, logs, crashReports, derivedData, xcodeCaches, deviceSupport, simulatorCaches, archives, packageCaches

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .userCaches: "App Caches"
        case .logs: "Logs"
        case .crashReports: "Crash Reports"
        case .derivedData: "Xcode Derived Data"
        case .xcodeCaches: "Xcode Caches and Previews"
        case .deviceSupport: "Device Support Files"
        case .simulatorCaches: "Simulator Caches"
        case .archives: "Xcode Archives"
        case .packageCaches: "Package Manager Caches"
        }
    }

    /// One plain sentence: what it is and what happens after it's gone.
    public var detail: String {
        switch self {
        case .userCaches: "Files apps keep to load faster. They rebuild them as needed."
        case .logs: "Activity logs written by apps. Safe to remove."
        case .crashReports: "Reports saved when apps crashed. Only useful for sending to developers."
        case .derivedData: "Build products and indexes. Xcode rebuilds them on the next build."
        case .xcodeCaches: "Xcode's download and preview caches. Recreated on demand."
        case .deviceSupport: "Debug symbols for devices you've connected. Downloaded again when you connect that device."
        case .simulatorCaches: "Caches shared by Simulator devices. Recreated on demand."
        case .archives: "Builds you archived. Keep the ones you may need to read crash logs from shipped versions."
        case .packageCaches: "Downloads kept by Homebrew, npm, CocoaPods and others. Downloaded again when needed."
        }
    }

    public var systemImage: String {
        switch self {
        case .userCaches: "internaldrive"
        case .logs: "doc.text"
        case .crashReports: "exclamationmark.triangle"
        case .derivedData: "hammer"
        case .xcodeCaches: "hammer.circle"
        case .deviceSupport: "iphone"
        case .simulatorCaches: "ipad.and.iphone"
        case .archives: "archivebox"
        case .packageCaches: "shippingbox"
        }
    }

    public var isDeveloper: Bool {
        switch self {
        case .userCaches, .logs, .crashReports: false
        default: true
        }
    }
}

public struct JunkItem: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    public var name: String
    public var category: JunkCategory
    /// Checked when the scan finishes. Archives, the newest device support per platform and
    /// running apps' caches start unchecked.
    public var isRecommended: Bool
    /// Why it starts unchecked, if it does ("App is running").
    public var note: String?

    public init(url: URL, name: String, category: JunkCategory, isRecommended: Bool = true, note: String? = nil) {
        self.url = url
        self.name = name
        self.category = category
        self.isRecommended = isRecommended
        self.note = note
    }
}

/// Lists junk items (sizes are measured separately so the list shows up at once).
public struct JunkScanner: Sendable {
    public var environment: TidyEnvironment
    public var runningBundleIDs: Set<String>
    /// Display names for bundle-id-named caches (`com.acme.Widget` → `Widget`).
    public var appNames: [String: String]

    public init(environment: TidyEnvironment, runningBundleIDs: Set<String> = [], appNames: [String: String] = [:]) {
        self.environment = environment
        self.runningBundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
        self.appNames = Dictionary(appNames.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    /// Caches under `~/Library/Caches` that belong to package managers, not apps.
    static let packageCacheNames: Set<String> = [
        "homebrew", "cocoapods", "org.swift.swiftpm", "yarn", "pip", "pnpm", "go-build", "carthage", "org.carthage.carthagekit",
        "node-gyp", "deno", "bun", "pip-tools", "pypoetry", "ms-playwright",
    ]
    /// Package caches outside `Library` (relative to home).
    static let dotPackageCaches = [".npm/_cacache", ".gradle/caches", ".cache/pip", ".cache/yarn", ".pub-cache/hosted"]

    public func scan() -> [JunkItem] {
        let home = environment.home
        let library = environment.library
        var items: [JunkItem] = []

        // App caches and package caches.
        for url in children(library.appendingPathComponent("Caches")) {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            if lower.hasPrefix("com.apple.dt.") {
                let names = ["com.apple.dt.xcode": "Xcode Cache", "com.apple.dt.xcodebuild": "xcodebuild Cache"]
                items.append(JunkItem(url: url, name: names[lower] ?? name, category: .xcodeCaches))
                continue
            }
            if BundleID.isApple(lower) || lower.hasPrefix("group.com.apple.") || lower == "cloudkit" || lower == "familycircle" { continue }
            if Self.packageCacheNames.contains(lower) {
                items.append(JunkItem(url: url, name: name, category: .packageCaches))
                continue
            }
            let running = runningBundleIDs.contains { BundleID.matches(lower, $0) }
            items.append(JunkItem(url: url, name: displayName(for: name), category: .userCaches,
                                  isRecommended: !running, note: running ? "App is running" : nil))
        }
        for relative in Self.dotPackageCaches {
            let url = home.appendingPathComponent(relative)
            guard exists(url) else { continue }
            // Gradle's cache holds every dependency of every project; re-downloading is slow.
            let isGradle = relative.hasPrefix(".gradle")
            items.append(JunkItem(url: url, name: "~/" + relative, category: .packageCaches, isRecommended: !isGradle,
                                  note: isGradle ? "Slow to download again" : nil))
        }

        // Logs and crash reports.
        for url in children(library.appendingPathComponent("Logs")) {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            if lower == "diagnosticreports" || lower == "coresimulator" || BundleID.isApple(lower) { continue }
            items.append(JunkItem(url: url, name: displayName(for: name), category: .logs))
        }
        for url in children(library.appendingPathComponent("Logs/DiagnosticReports")) where !isDirectory(url) {
            items.append(JunkItem(url: url, name: url.lastPathComponent, category: .crashReports))
        }

        // Xcode.
        let xcode = library.appendingPathComponent("Developer/Xcode")
        for url in children(xcode.appendingPathComponent("DerivedData")) {
            if url.lastPathComponent == "ModuleCache.noindex" {
                items.append(JunkItem(url: url, name: "Module Cache", category: .derivedData, isRecommended: false,
                                      note: "Slow to rebuild"))
                continue
            }
            let workspace = Self.derivedDataWorkspace(url)
            let missing = workspace.map { !FileManager.default.fileExists(atPath: $0) } ?? false
            let name = workspace.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                ?? Self.derivedDataName(url.lastPathComponent)
            items.append(JunkItem(url: url, name: name, category: .derivedData, note: missing ? "Project not found" : nil))
        }
        for name in ["DocumentationCache", "iOS Device Logs"] {
            let url = xcode.appendingPathComponent(name)
            if exists(url) {
                items.append(JunkItem(url: url, name: name == "DocumentationCache" ? "Documentation Cache" : name,
                                      category: name == "iOS Device Logs" ? .logs : .xcodeCaches))
            }
        }
        let previews = xcode.appendingPathComponent("UserData/Previews")
        if exists(previews) { items.append(JunkItem(url: previews, name: "SwiftUI Previews", category: .xcodeCaches)) }
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            let versions = children(xcode.appendingPathComponent("\(platform) DeviceSupport")).filter(isDirectory)
            let newest = versions.max { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for url in versions {
                let isNewest = url == newest
                items.append(JunkItem(url: url, name: "\(platform) \(url.lastPathComponent)", category: .deviceSupport,
                                      isRecommended: !isNewest, note: isNewest ? "Newest \(platform) version" : nil))
            }
        }
        for dateFolder in children(xcode.appendingPathComponent("Archives")) where isDirectory(dateFolder) {
            for archive in children(dateFolder) where archive.pathExtension == "xcarchive" {
                items.append(JunkItem(url: archive, name: archive.deletingPathExtension().lastPathComponent, category: .archives,
                                      isRecommended: false, note: "Kept unless you check it"))
            }
        }
        for url in children(library.appendingPathComponent("Developer/CoreSimulator/Caches")) {
            items.append(JunkItem(url: url, name: url.lastPathComponent, category: .simulatorCaches))
        }
        for url in children(library.appendingPathComponent("Logs/CoreSimulator")) {
            items.append(JunkItem(url: url, name: "Simulator log: \(url.lastPathComponent)", category: .logs))
        }
        return items
    }

    func displayName(for name: String) -> String {
        if let appName = appNames[name.lowercased()] { return appName }
        return name
    }

    /// The project a DerivedData folder was built from (`info.plist` → `WorkspacePath`).
    static func derivedDataWorkspace(_ folder: URL) -> String? {
        AppCatalog.infoPlist(folder.appendingPathComponent("info.plist"))?["WorkspacePath"] as? String
    }

    /// `MyApp-bxkfjqwmzrdhgnaefyeqtgsaulwo` → `MyApp`.
    static func derivedDataName(_ folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        let suffix = folder[folder.index(after: dash)...]
        guard suffix.count == 28, suffix.allSatisfy({ $0.isLowercase && $0.isASCII }) else { return folder }
        return String(folder[..<dash])
    }

    private func children(_ url: URL) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") }.sorted().map { url.appendingPathComponent($0) }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
