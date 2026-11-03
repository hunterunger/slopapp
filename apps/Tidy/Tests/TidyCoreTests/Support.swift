import Foundation
import TidyCore
import TidyFixtures

/// A fresh fixture per test, under /tmp/tidy-test/unit so nothing outside it is touched.
func makeFixture(unit: Int64 = 1_000, now: Date = Date()) throws -> Fixture {
    let root = URL(fileURLWithPath: "/tmp/tidy-test/unit/\(UUID().uuidString)")
    return try Fixture.create(at: root, unit: unit, now: now)
}

extension Fixture {
    func cleanUp() { try? Fixture.remove(root) }

    func app(_ name: String, in subfolder: String? = nil) -> InstalledApp {
        let folder = subfolder.map { applications.appendingPathComponent($0) } ?? applications
        return AppCatalog.read(folder.appendingPathComponent("\(name).app"))!
    }

    var finder: LeftoverFinder {
        LeftoverFinder(apps: AppCatalog.scan(environment.applicationDirectories), index: LibraryIndex.build(environment))
    }

    /// Leftover paths relative to the fixture root, app bundle excluded.
    func leftoverPaths(_ app: InstalledApp) -> Set<String> {
        Set(finder.leftovers(for: app).filter { $0.kind != .application && !$0.reason.isPossibleMatch }.map { relative($0.url) })
    }

    /// Possible (unchecked) matches, relative paths.
    func possiblePaths(_ app: InstalledApp) -> Set<String> {
        Set(finder.leftovers(for: app).filter(\.reason.isPossibleMatch).map { relative($0.url) })
    }

    func relative(_ url: URL) -> String {
        let base = root.resolvingSymlinksInPath().path + "/"
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }
}
