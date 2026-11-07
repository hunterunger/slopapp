import Foundation
import TidyCore

/// A realistic fake Mac for testing Tidy: apps with bundle ids, their leftovers in every
/// Library folder, decoys that must never match, leftovers of deleted apps, caches, logs,
/// Xcode junk, and large and old files. Used by the unit tests and by
/// `apps/Tidy/Scripts/make-fixtures.sh` for walkthroughs and blind tests.
///
/// Everything lives under `root`, which must be inside `/tmp/tidy-test` (or the system temp
/// folder for unit tests), so creating or removing a fixture can never touch real data.
public struct Fixture: Sendable {
    public let root: URL
    public var home: URL { root.appendingPathComponent("home") }
    public var applications: URL { root.appendingPathComponent("Applications") }
    public var trash: URL { root.appendingPathComponent("Trash") }
    public var systemLibrary: URL { root.appendingPathComponent("Library") }
    public var library: URL { home.appendingPathComponent("Library") }

    /// Bundle ids test mode treats as running.
    public static let runningIDs: Set<String> = ["com.fixture.Busybee"]

    public var environment: TidyEnvironment {
        TidyEnvironment.from(environment: [
            "TIDY_HOME": home.path,
            "TIDY_APPS_DIRS": applications.path,
            "TIDY_TRASH_DIR": trash.path,
            "TIDY_SYSTEM_LIBRARY": systemLibrary.path,
            "TIDY_RUNNING_IDS": Self.runningIDs.sorted().joined(separator: ","),
        ], realHome: URL(fileURLWithPath: "/var/empty"))
    }

    public enum FixtureError: Error, CustomStringConvertible {
        case unsafeRoot(String)
        public var description: String {
            switch self {
            case .unsafeRoot(let path): "Refusing to use \(path): fixtures must live in /tmp/tidy-test or the temp folder."
            }
        }
    }

    static func isSafeRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        return ["/private/tmp/tidy-test", "/tmp/tidy-test"].contains { path == $0 || path.hasPrefix($0 + "/") }
            || (path.hasPrefix(temp + "/") && path.contains("tidy-test"))
    }

    /// Removes a fixture (making read-only folders writable first).
    public static func remove(_ root: URL) throws {
        guard isSafeRoot(root) else { throw FixtureError.unsafeRoot(root.path) }
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        if let walker = fm.enumerator(atPath: root.path) {
            for case let relative as String in walker {
                let path = root.appendingPathComponent(relative).path
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                }
            }
        }
        try fm.removeItem(at: root)
    }

    /// Builds a fresh fixture at `root` (replacing any old one). `unit` scales large files:
    /// 1 MB for walkthroughs, smaller for unit tests. Large files are sparse, so they report
    /// their full size without using the disk space.
    @discardableResult
    public static func create(at root: URL, unit: Int64 = 1_000_000, now: Date = Date()) throws -> Fixture {
        try remove(root)
        let fixture = Fixture(root: root.standardizedFileURL)
        try fixture.build(unit: unit, now: now)
        return fixture
    }

    // MARK: Building

    private func build(unit: Int64, now: Date) throws {
        let fm = FileManager.default
        for dir in [home, applications, trash, systemLibrary] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for folder in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"] {
            try dir(home.appendingPathComponent(folder))
        }
        try buildApps()
        try buildLeftovers()
        try buildOrphans()
        try buildJunk()
        try buildLargeFiles(unit: unit, now: now)
        try buildSystemLibrary()
        try buildTrash(now: now)
        try buildMailDownloads(now: now)
    }

    /// Things already in the Trash (for Trash Bins): files and a folder, no apps (apps in the
    /// Trash change what Leftovers finds).
    private func buildTrash(now: Date) throws {
        try data(trash, "Old invoice.pdf", 300_000)
        try data(trash, "project-backup.zip", 1_500_000)
        try data(trash, "Screenshots/Screen 1.png", 400_000)
        try data(trash, "Screenshots/Screen 2.png", 350_000)
        // Like Finder: a folder someone made read-only still empties.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: trash.appendingPathComponent("Screenshots").path)
        // A Mac has a .DS_Store here; it's never listed.
        try data(trash, ".DS_Store", 6_000)
    }

    /// Copies of opened Mail attachments: one untouched, one edited after it was saved.
    private func buildMailDownloads(now: Date) throws {
        let folder = library.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads")
        let day: TimeInterval = 86_400
        try data(folder, "6A1B2C3D-0000-4000-8000-000000000001/Invoice 2026-09.pdf", 220_000)
        try data(folder, "6A1B2C3D-0000-4000-8000-000000000002/Contract draft.docx", 90_000)
        let fm = FileManager.default
        let untouched = folder.appendingPathComponent("6A1B2C3D-0000-4000-8000-000000000001/Invoice 2026-09.pdf").path
        try fm.setAttributes([.creationDate: now.addingTimeInterval(-20 * day), .modificationDate: now.addingTimeInterval(-20 * day)],
                             ofItemAtPath: untouched)
        let edited = folder.appendingPathComponent("6A1B2C3D-0000-4000-8000-000000000002/Contract draft.docx").path
        try fm.setAttributes([.creationDate: now.addingTimeInterval(-10 * day), .modificationDate: now.addingTimeInterval(-2 * day)],
                             ofItemAtPath: edited)
    }

    private func buildApps() throws {
        try app("Notely", id: "com.fixture.Notely", version: "2.3.1", payload: 3_400_000,
                embedded: [("Contents/Library/LoginItems/Notely Launcher.app", "com.fixture.NotelyLauncher"),
                           ("Contents/PlugIns/Share.appex", "com.fixture.Notely.ShareExtension")])
        try app("Notely Mini", id: "com.fixture.Notely.Mini", version: "1.0", payload: 800_000)
        try app("NotelyPro", id: "com.fixture.NotelyPro", version: "5.1", payload: 1_200_000)
        try app("Code", id: "com.fixture.code-editor", version: "1.95", payload: 2_000_000)
        try app("Photo Sorter", id: "com.fixture.PhotoSorter", version: "3.0", payload: 1_500_000)
        try app("Ox", id: "com.fixture.ox", version: "0.9", payload: 300_000)
        try app("Busybee", id: "com.fixture.Busybee", version: "4.2", payload: 900_000)
        try app("Syncer", id: "com.fixture.Syncer", version: "7.0", payload: 1_100_000)
        try app("Chatter", id: "com.fixture.Chatter", version: "12.4", payload: 4_000_000, executable: "Electron")
        try app("Tasker", id: "com.fixture.Tasker", version: "2.0", payload: 600_000)
        try app("Tasker", id: "com.otherdev.Tasker", version: "1.1", payload: 500_000, folder: "Setapp")
        try app("Grapher", id: "com.fixture.Grapher", version: "1.4", payload: 700_000, folder: "Utilities")
        try app("Safari", id: "com.apple.Safari", version: "26.0", payload: 500_000)
    }

    private func buildLeftovers() throws {
        let L = library
        // Notely: every kind of per-app location.
        try data(L, "Application Support/Notely/notes.db", 1_800_000)
        try data(L, "Application Support/com.fixture.Notely/state.json", 40_000)
        try data(L, "Caches/com.fixture.Notely/Cache.db", 2_200_000)
        try data(L, "Caches/com.fixture.Notely.ShipIt/update.zip", 900_000)
        try plist(L, "Preferences/com.fixture.Notely.plist")
        try plist(L, "Preferences/com.fixture.NotelyLauncher.plist")
        try plist(L, "Preferences/ByHost/com.fixture.Notely.6F1E2A3B-1111-2222-3333-444455556666.plist")
        try data(L, "Containers/com.fixture.Notely/Data/Library/notes.sqlite", 1_200_000)
        try data(L, "Containers/com.fixture.Notely.ShareExtension/Data/tmp.bin", 30_000)
        try data(L, "Group Containers/ABCDE12345.com.fixture.Notely/shared.db", 500_000)
        try data(L, "Group Containers/group.com.fixture.Notely/widgets.json", 20_000)
        try data(L, "Application Scripts/com.fixture.Notely/run.scpt", 2_000)
        try launchAgent(L, "LaunchAgents/com.fixture.Notely.helper.plist", label: "com.fixture.Notely.helper",
                        program: applications.appendingPathComponent("Notely.app/Contents/MacOS/Notely").path)
        try data(L, "Saved Application State/com.fixture.Notely.savedState/windows.plist", 12_000)
        try data(L, "HTTPStorages/com.fixture.Notely/httpstorages.sqlite", 60_000)
        try data(L, "HTTPStorages/com.fixture.Notely.binarycookies", 4_000)
        try data(L, "WebKit/com.fixture.Notely/WebsiteData/LocalStorage.db", 80_000)
        try data(L, "Cookies/com.fixture.Notely.binarycookies", 4_000)
        try data(L, "Logs/Notely/notely.log", 150_000)
        try data(L, "Logs/DiagnosticReports/Notely-2026-10-01-101010.ips", 30_000)

        // Notely Mini (bundle id is under Notely's) and NotelyPro (shares a prefix, not an id).
        try data(L, "Application Support/Notely Mini/mini.db", 200_000)
        try plist(L, "Preferences/com.fixture.Notely.Mini.plist")
        try data(L, "Caches/com.fixture.Notely.Mini/c.db", 100_000)
        try data(L, "Caches/com.fixture.NotelyPro/c.db", 100_000)
        try data(L, "Application Support/NotelyPro/pro.db", 100_000)

        // Code: a common word, so only its bundle id counts. "Code" belongs to someone else.
        try data(L, "Application Support/Code/User/settings.json", 50_000)
        try data(L, "Application Support/com.fixture.code-editor/state.db", 70_000)
        try plist(L, "Preferences/com.fixture.code-editor.plist")

        // Photo Sorter, with look-alikes that must not match.
        try data(L, "Application Support/Photo Sorter/library.db", 300_000)
        try data(L, "Application Support/Photos/other.db", 10_000)
        try data(L, "Application Support/Photo Sorter Backup/backup.db", 10_000)
        try data(L, "Caches/Sorter/c.db", 10_000)
        try plist(L, "Preferences/com.fixture.PhotoSorter.plist")

        // Ox: too short to match by name.
        try data(L, "Application Support/Ox/ox.db", 10_000)
        try plist(L, "Preferences/com.fixture.ox.plist")

        // Busybee (treated as running in test mode).
        try data(L, "Caches/com.fixture.Busybee/c.db", 400_000)
        try plist(L, "Preferences/com.fixture.Busybee.plist")

        // Syncer: a launch agent named after another vendor that runs a program in the app.
        try launchAgent(L, "LaunchAgents/com.othervendor.syncd.plist", label: "com.othervendor.syncd",
                        program: applications.appendingPathComponent("Syncer.app/Contents/MacOS/Syncer").path)
        try data(L, "Application Support/Syncer/sync.db", 250_000)
        try data(L, "Logs/Syncer.log", 20_000)

        // Chatter: an Electron app. "Electron" folders belong to no one in particular.
        try data(L, "Application Support/Chatter/IndexedDB/db.bin", 900_000)
        try data(L, "Application Support/Electron/shared.bin", 10_000)
        try data(L, "Caches/com.fixture.Chatter/c.db", 300_000)
        try data(L, "Caches/com.fixture.Chatter.ShipIt/u.zip", 500_000)
        try data(L, "Logs/DiagnosticReports/Electron-2026-09-12-080000.ips", 20_000)

        // Two apps named Tasker: the name is ambiguous, ids are not.
        try data(L, "Application Support/Tasker/tasks.db", 40_000)
        try plist(L, "Preferences/com.fixture.Tasker.plist")
        try plist(L, "Preferences/com.otherdev.Tasker.plist")

        try plist(L, "Preferences/com.fixture.Grapher.plist")

        // macOS's own items: never offered.
        try plist(L, "Preferences/com.apple.Safari.plist")
        try plist(L, "Preferences/com.apple.dock.plist")
        try plist(L, "Preferences/.GlobalPreferences.plist")
        try plist(L, "Preferences/loginwindow.plist")
        try plist(L, "Preferences/pbs.plist")
        try data(L, "Containers/com.apple.Safari/Data/x.bin", 10_000)
        try data(L, "Group Containers/group.com.apple.notes/x.bin", 10_000)
    }

    private func buildOrphans() throws {
        let L = library
        // An app that was dragged to the Trash, leaving everything behind.
        try data(L, "Application Support/com.goneware.OldEditor/projects.db", 1_400_000)
        try data(L, "Caches/com.goneware.OldEditor/Cache.db", 600_000)
        try plist(L, "Preferences/com.goneware.OldEditor.plist")
        try data(L, "Saved Application State/com.goneware.OldEditor.savedState/windows.plist", 8_000)
        try data(L, "Containers/com.goneware.OldEditor/Data/x.bin", 200_000)
        try data(L, "HTTPStorages/com.goneware.OldEditor/h.sqlite", 20_000)
        try launchAgent(L, "LaunchAgents/com.goneware.OldEditor.updater.plist", label: "com.goneware.OldEditor.updater",
                        program: "/Applications/OldEditor.app/Contents/MacOS/Updater")
        try plist(L, "Preferences/io.retired.Snapz.plist")
        try data(L, "Caches/io.retired.Snapz/c.db", 300_000)
        // Deleted a while ago: nothing has written to these for a month.
        let monthAgo = Date().addingTimeInterval(-30 * 86_400)
        for name in ["Application Support/com.goneware.OldEditor", "Caches/com.goneware.OldEditor",
                     "Preferences/com.goneware.OldEditor.plist", "Saved Application State/com.goneware.OldEditor.savedState",
                     "Containers/com.goneware.OldEditor", "HTTPStorages/com.goneware.OldEditor",
                     "LaunchAgents/com.goneware.OldEditor.updater.plist", "Preferences/io.retired.Snapz.plist",
                     "Caches/io.retired.Snapz"] {
            try FileManager.default.setAttributes([.modificationDate: monthAgo], ofItemAtPath: L.appendingPathComponent(name).path)
        }
        // macOS's own launch agent: never listed anywhere.
        try launchAgent(L, "LaunchAgents/com.apple.fixture.example.plist", label: "com.apple.fixture.example", program: "/usr/libexec/example")
        // A tool's launch agent whose program is still there: not an orphan, however old.
        try launchAgent(L, "LaunchAgents/com.toolmaker.agent.plist", label: "com.toolmaker.agent", program: "/bin/sh")
        try FileManager.default.setAttributes([.modificationDate: monthAgo],
                                              ofItemAtPath: L.appendingPathComponent("LaunchAgents/com.toolmaker.agent.plist").path)
        // Looks orphaned, but something wrote to it today: still in use.
        try plist(L, "Preferences/net.activetool.Daemon.plist")

        // Not orphans: same vendor as an installed app, tool namespaces, non-ids, too short.
        try plist(L, "Preferences/com.fixture.cli-tool.plist")
        try launchAgent(L, "LaunchAgents/homebrew.mxcl.redis.plist", label: "homebrew.mxcl.redis", program: "/opt/homebrew/bin/redis-server")
        try plist(L, "Preferences/org.python.python.plist")
        try data(L, "Application Support/MyStuff/a.txt", 1_000)
        try data(L, "Caches/com.shared/c.db", 1_000)
    }

    private func buildJunk() throws {
        let L = library
        try data(L, "Caches/Homebrew/downloads/node.tar.gz", 5_000_000)
        try data(L, "Caches/org.swift.swiftpm/repositories/x.pack", 1_500_000)
        try data(L, "Caches/com.apple.dt.Xcode/Cache.db", 3_000_000)
        try data(L, "Caches/com.apple.bird/cache.db", 500_000)
        try data(L, "Caches/Google/Chrome/cache.bin", 2_500_000)
        try data(L, "Logs/com.apple.xpc.launchd/launchd.log", 10_000)
        try data(L, "Logs/CoreSimulator/2D3C/system.log", 400_000)
        try data(L, "Logs/DiagnosticReports/Grapher-2026-08-02-120000.crash", 15_000)
        let xcode = "Developer/Xcode"
        try data(L, "\(xcode)/DerivedData/MyApp-bxkfjqwmzrdhgnaefyeqtgsaulwo/Build/Products/app.o", 6_000_000)
        try data(L, "\(xcode)/DerivedData/Widgets-aqzkvhtgehdjtuyxtcawbwvhlpqm/Index.noindex/i.db", 2_000_000)
        try data(L, "\(xcode)/DerivedData/ModuleCache.noindex/m.pcm", 1_000_000)
        try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/tmp/tidy-test/home/Projects/Widgets/Widgets.xcodeproj"],
                                           format: .xml, options: 0)
            .write(to: L.appendingPathComponent("\(xcode)/DerivedData/Widgets-aqzkvhtgehdjtuyxtcawbwvhlpqm/info.plist"))
        try data(L, "\(xcode)/DocumentationCache/v1/doc.db", 1_200_000)
        try data(L, "\(xcode)/Archives/2026-05-01/MyApp 5-1-26, 10.00.xcarchive/Info.plist", 2_500_000)
        try data(L, "\(xcode)/iOS DeviceSupport/17.0 (21A329)/Symbols/dyld", 4_000_000)
        try data(L, "\(xcode)/iOS DeviceSupport/18.2 (22C150)/Symbols/dyld", 4_000_000)
        try data(L, "\(xcode)/UserData/Previews/Simulator Devices/p.bin", 1_000_000)
        try data(L, "Developer/CoreSimulator/Caches/dyld/cache.bin", 3_000_000)
        try data(home, ".npm/_cacache/content-v2/x.bin", 2_000_000)
        try data(home, ".gradle/caches/modules-2/x.jar", 1_000_000)
    }

    private func buildLargeFiles(unit: Int64, now: Date) throws {
        let day: TimeInterval = 86_400
        try sparse("Downloads/Installer-2024.dmg", 220 * unit, modified: now.addingTimeInterval(-600 * day))
        try sparse("Movies/Trip to the coast.mov", 150 * unit, modified: now.addingTimeInterval(-3 * day))
        try sparse("Documents/Backups/project-2023.zip", 90 * unit, modified: now.addingTimeInterval(-800 * day))
        try sparse("Desktop/Interview recording.m4a", 60 * unit, modified: now.addingTimeInterval(-200 * day))
        try sparse("Pictures/Panorama.tiff", 30 * unit, modified: now.addingTimeInterval(-400 * day))
        try sparse("Documents/Linux.iso", 1_200 * unit, modified: now.addingTimeInterval(-90 * day))
        try sparse("Documents/Q3 report.pdf", 12 * unit, modified: now.addingTimeInterval(-40 * day))
        try data(home, "Documents/notes.txt", 2_000)
        // Never listed: inside packages, hidden folders, Library.
        try sparse("Downloads/Tool.app/Contents/Resources/big.bin", 200 * unit, modified: now)
        try sparse("Pictures/Photos Library.photoslibrary/originals/IMG_0001.heic", 120 * unit, modified: now)
        try sparse(".hidden/huge.bin", 300 * unit, modified: now)
        try sparse("Library/Application Support/Huge/cache.bin", 300 * unit, modified: now)
    }

    private func buildSystemLibrary() throws {
        let S = systemLibrary
        try launchAgent(S, "LaunchDaemons/com.fixture.Syncer.daemon.plist", label: "com.fixture.Syncer.daemon",
                        program: applications.appendingPathComponent("Syncer.app/Contents/MacOS/Syncer").path)
        try data(S, "PrivilegedHelperTools/com.fixture.Syncer.helper", 120_000)
        try data(S, "Application Support/Syncer/shared.db", 80_000)
        // Like the real /Library: not writable without an administrator.
        for folder in ["LaunchDaemons", "PrivilegedHelperTools", "Application Support"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: S.appendingPathComponent(folder).path)
        }
    }

    // MARK: Helpers

    private func dir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// A file with `bytes` of real data on disk (APFS doesn't compress or dedupe plain writes).
    private func data(_ base: URL, _ relative: String, _ bytes: Int) throws {
        let url = base.appendingPathComponent(relative)
        try dir(url.deletingLastPathComponent())
        try Data(repeating: UInt8(truncatingIfNeeded: relative.utf8.count), count: bytes).write(to: url)
    }

    private func plist(_ base: URL, _ relative: String) throws {
        let url = base.appendingPathComponent(relative)
        try dir(url.deletingLastPathComponent())
        let data = try PropertyListSerialization.data(fromPropertyList: ["Fixture": true, "LastLaunch": "2026-10-01"],
                                                      format: .binary, options: 0)
        try data.write(to: url)
    }

    private func launchAgent(_ base: URL, _ relative: String, label: String, program: String) throws {
        let url = base.appendingPathComponent(relative)
        try dir(url.deletingLastPathComponent())
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "Label": label, "ProgramArguments": [program, "--background"], "RunAtLoad": true,
        ], format: .xml, options: 0)
        try data.write(to: url)
    }

    /// A sparse file: reports `size` but only a few blocks are on disk.
    private func sparse(_ relative: String, _ size: Int64, modified: Date) throws {
        let url = home.appendingPathComponent(relative)
        try dir(url.deletingLastPathComponent())
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 7, count: 4096))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func app(_ name: String, id: String, version: String, payload: Int, executable: String? = nil,
                     folder: String? = nil, embedded: [(String, String)] = []) throws {
        let parent = folder.map { applications.appendingPathComponent($0) } ?? applications
        let url = parent.appendingPathComponent("\(name).app")
        let exec = executable ?? name
        try writeBundle(url, id: id, name: name, version: version, executable: exec)
        try data(url, "Contents/Resources/payload.bin", payload)
        for (relative, embeddedID) in embedded {
            let inner = url.appendingPathComponent(relative)
            try writeBundle(inner, id: embeddedID, name: inner.deletingPathExtension().lastPathComponent, version: version,
                            executable: inner.deletingPathExtension().lastPathComponent)
        }
    }

    private func writeBundle(_ url: URL, id: String, name: String, version: String, executable: String) throws {
        try dir(url.appendingPathComponent("Contents/MacOS"))
        let info: [String: Any] = [
            "CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": version,
            "CFBundleExecutable": executable, "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        let binary = url.appendingPathComponent("Contents/MacOS/\(executable)")
        try Data("#!/bin/sh\n# Tidy test fixture. Does nothing.\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }
}
