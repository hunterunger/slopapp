import Foundation
import TidyCore
import TidyFixtures

// tidy-tool: fixtures for walkthroughs and blind tests, and a read-only benchmark.
//
//   tidy-tool fixtures [root]         build a fake Mac at root (default /tmp/tidy-test)
//   tidy-tool remove-fixtures [root]  delete it
//   tidy-tool bench                   time every scan against the environment Tidy would use
//                                     (the real Mac, or TIDY_* test folders). Read-only: it
//                                     never moves anything, and prints only counts, sizes and
//                                     timings, never names or paths.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

func clock<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
}

func ms(_ value: Double) -> String { String(format: "%.0f ms", value) }

func sizeAll(_ urls: [URL]) async -> (Int64, Int) {
    await withTaskGroup(of: DiskUsage?.self) { group in
        var iterator = urls.makeIterator()
        var running = 0
        var bytes: Int64 = 0
        var files = 0
        func add() -> Bool {
            guard let url = iterator.next() else { return false }
            group.addTask { DiskUsage.measure(url) }
            return true
        }
        while running < 8, add() { running += 1 }
        while let result = await group.next() {
            if let result { bytes += result.bytes; files += result.files }
            if !add() { running -= 1 }
        }
        return (bytes, files)
    }
}

switch command {
case "fixtures":
    let root = URL(fileURLWithPath: arguments.dropFirst().first ?? "/tmp/tidy-test")
    do {
        let fixture = try Fixture.create(at: root)
        print("""
        Built a test Mac at \(fixture.root.path)

        export TIDY_HOME=\(fixture.home.path)
        export TIDY_APPS_DIRS=\(fixture.applications.path)
        export TIDY_TRASH_DIR=\(fixture.trash.path)
        export TIDY_SYSTEM_LIBRARY=\(fixture.systemLibrary.path)
        export TIDY_RUNNING_IDS=\(Fixture.runningIDs.sorted().joined(separator: ","))
        """)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }

case "remove-fixtures":
    let root = URL(fileURLWithPath: arguments.dropFirst().first ?? "/tmp/tidy-test")
    do { try Fixture.remove(root) } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }

case "bench":
    let env = TidyEnvironment.current
    let fda = FullDiskAccessProbe.isGranted()
    print("mode=\(env.isTestMode ? "test" : "real") full_disk_access=\(fda)")
    let (apps, tApps) = clock { AppCatalog.scan(env.applicationDirectories) }
    print("apps: \(apps.count) found in \(ms(tApps))")
    let (index, tIndex) = clock { LibraryIndex.build(env) }
    print("library index: \(index.entries.count) entries in \(ms(tIndex))")
    let (finder, tFinder) = clock { LeftoverFinder(apps: apps, index: index) }
    let (reports, tMatch) = clock { apps.map { finder.leftovers(for: $0) } }
    let leftovers = reports.flatMap { $0.dropFirst() }
    print("leftover matching: \(leftovers.count) items for \(apps.count) apps in \(ms(tFinder + tMatch)) (\(ms((tFinder + tMatch) / Double(max(apps.count, 1)))) per app)")
    let measurable = leftovers.filter { fda || !$0.needsFullDiskAccess }.map(\.url)
    let ((leftBytes, leftFiles), tLeftSize) = await { () async -> ((Int64, Int), Double) in
        let start = Date()
        let result = await sizeAll(measurable)
        return (result, Date().timeIntervalSince(start) * 1000)
    }()
    print("leftover sizes: \(measurable.count) items, \(leftFiles) files, \(ByteFormat.string(leftBytes)) in \(ms(tLeftSize))")
    let ((appBytes, appFiles), tAppSize) = await { () async -> ((Int64, Int), Double) in
        let start = Date()
        let result = await sizeAll(apps.map(\.url))
        return (result, Date().timeIntervalSince(start) * 1000)
    }()
    print("app sizes: \(apps.count) apps, \(appFiles) files, \(ByteFormat.string(appBytes)) in \(ms(tAppSize))")
    let orphans = OrphanFinder(finder: finder)
    let (groups, tOrphans) = clock { orphans.find() }
    print("deleted-app leftovers: \(groups.count) groups, \(groups.reduce(0) { $0 + $1.items.count }) items in \(ms(tOrphans)) (no LaunchServices check in the CLI)")
    let (junk, tJunk) = clock { JunkScanner(environment: env).scan() }
    let ((junkBytes, junkFiles), tJunkSize) = await { () async -> ((Int64, Int), Double) in
        let start = Date()
        let result = await sizeAll(junk.map(\.url))
        return (result, Date().timeIntervalSince(start) * 1000)
    }()
    print("junk: \(junk.count) items in \(ms(tJunk)); sized \(junkFiles) files, \(ByteFormat.string(junkBytes)) in \(ms(tJunkSize))")
    var large = LargeFileScanner.forHome(env, minimumSize: 10_000_000)
    if !fda && !env.isTestMode {
        // Without Full Disk Access, walking these makes macOS ask; the benchmark skips them.
        large.excluded += ["Desktop", "Documents", "Downloads"].map { env.home.appendingPathComponent($0) }
        print("large files: skipping Desktop, Documents and Downloads (no Full Disk Access)")
    }
    let visited = LockedCounter()
    let (files, tLarge) = clock { large.scan { visited.set($0) } ?? [] }
    print("large files: walked \(visited.value) entries, \(files.count) files ≥ 10 MB (\(files.filter { $0.size >= 100_000_000 }.count) ≥ 100 MB) in \(ms(tLarge))")

default:
    print("usage: tidy-tool fixtures [root] | remove-fixtures [root] | bench")
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func set(_ value: Int) { lock.withLock { _value = value } }
}
