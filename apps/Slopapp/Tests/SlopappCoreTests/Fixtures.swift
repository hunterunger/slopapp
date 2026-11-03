import Foundation
@testable import SlopappCore

/// Real, tiny app bundles: Info.plist + a copy of /usr/bin/true, ad-hoc signed, zipped with ditto.
enum Fixture {
    static func tempDir(_ label: String = "t") -> URL {
        let dir = URL(fileURLWithPath: "/tmp/slopapp-test/unit", isDirectory: true)
            .appendingPathComponent("\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try! p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func makeApp(in dir: URL, name: String = "Tiny", bundleID: String = "app.slopapp.tiny",
                        version: String = "1.0.0", build: String = "1", sign: Bool = true) -> URL {
        let app = dir.appendingPathComponent("\(name).app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try! FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundleExecutable": name,
            "CFBundleShortVersionString": version, "CFBundleVersion": build, "CFBundlePackageType": "APPL",
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try! FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent(name))
        if sign {
            run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        } else {
            run("/usr/bin/codesign", ["--remove-signature", macOS.appendingPathComponent(name).path])
        }
        return app
    }

    static func zip(_ app: URL, to zip: URL) {
        run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    }

    /// A feed entry pointing at a zip on disk.
    static func feedApp(zip: URL, name: String = "Tiny", bundleID: String = "app.slopapp.tiny",
                        version: String = "1.0.0", sha: String? = nil) -> FeedApp {
        FeedApp(
            slug: name.lowercased(), name: name, tagline: "A tiny test app.", version: version, build: 1,
            minimumMacOS: "14.0", bundleId: bundleID, downloadUrl: zip,
            sha256: sha ?? (try! Checksum.sha256(zip)), size: 1
        )
    }
}
