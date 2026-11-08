import CoreGraphics
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
//   tidy-tool fixtures [root] --map   also add space-map content and stand-in disks; prints
//                                     TIDY_VOLUMES
//   tidy-tool map-tree [root] [--files N]   synthetic tree for the map benchmark
//                                     (default /tmp/tidy-test/maptree, 200,000 files)
//   tidy-tool bench map [root] [--threads N] [--runs N]   time the map walk (read-only;
//                                     counts and timings only)
//   tidy-tool bench fake [--files N] [--threads N]   the walk over a generated in-memory tree:
//                                     speed, peak and retained memory
//   tidy-tool bench stop              how fast Stop stops a walk
//   tidy-tool volumes                 the volume figures behind the volume bar (sizes only,
//                                     no names)

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
    let root = URL(fileURLWithPath: arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "/tmp/tidy-test")
    do {
        let fixture = try Fixture.create(at: root)
        if arguments.contains("--map") {
            let volumes = try MapFixture.addMapExtras(to: fixture)
            print("export TIDY_VOLUMES='\(volumes)'")
        }
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

case "bench" where arguments.dropFirst().first == "map":
    let root = arguments.dropFirst(2).first { !$0.hasPrefix("--") } ?? "/tmp/tidy-test/maptree"
    let threads = option("--threads").flatMap(Int.init) ?? MapScanOptions.defaultThreads
    let runs = option("--runs").flatMap(Int.init) ?? 3
    var best = Double.infinity
    for run in 1...runs {
        let before = Footprint.current
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let scanner = try MapScanner(reader: BulkDirectoryReader(), options: MapScanOptions(root: root, threads: threads))
            scanner.start()
            scanner.wait()
            let t = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            best = min(best, t)
            let (items, bytes) = scanner.store.progress
            let rootNode = scanner.store.node(MapStore.root)
            print("run \(run): \(items) entries, \(rootNode.itemCount) files, \(ByteFormat.string(bytes)) in \(ms(t)) (\(Int(Double(items) / t * 1000)) entries/s), \(threads) threads, \(scanner.store.count) nodes, store \(scanner.store.approximateBytes / 1_000_000) MB, footprint +\((Footprint.current - before) / 1_000_000) MB\(rootNode.flags.contains(.partial) ? ", partial" : "")")
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }
    print("best: \(ms(best))")

case "bench" where arguments.dropFirst().first == "fake":
    let files = option("--files").flatMap(Int.init) ?? 5_000_000
    let threads = option("--threads").flatMap(Int.init) ?? MapScanOptions.defaultThreads
    let fs = GeneratedFileSystem.sized(files: files)
    let baseline = Footprint.current
    let peak = PeakSampler()
    peak.start()
    let start = DispatchTime.now().uptimeNanoseconds
    var store: MapStore? = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root, threads: threads)).run()
    let t = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    let peakBytes = peak.stop()
    let beforeRelief = Footprint.current - baseline
    malloc_zone_pressure_relief(nil, 0)
    let retained = Footprint.current - baseline
    print("before malloc relief: +\(beforeRelief / 1_000_000) MB")
    print("fake tree: \(fs.fileCount) files in \(fs.folderCount) folders, \(store!.count) nodes in \(ms(t)); store \(store!.approximateBytes / 1_000_000) MB; peak +\((peakBytes - baseline) / 1_000_000) MB, retained +\(retained / 1_000_000) MB above baseline \(baseline / 1_000_000) MB")
    store = nil
    malloc_zone_pressure_relief(nil, 0)
    usleep(500_000)
    print("after release: +\(max(0, Footprint.current - baseline) / 1_000_000) MB")
    if arguments.contains("--hold") { print("pid \(getpid())"); fflush(stdout); sleep(30) }

case "bench" where arguments.dropFirst().first == "layout":
    // 200 folders × 10 nested items (2,200 tiles), the budget's case.
    let items = (0..<200).map { (i: Int) -> MapLayoutItem in
        MapLayoutItem(size: Double(10_000 - i * 40), children: (0..<10).map { (j: Int) -> Double in Double(900 - j * 50 - i) })
    }
    var best = Double.infinity
    var count = 0
    for _ in 0..<50 {
        let (tiles, t) = clock { MapLayout.tiles(items, in: CGRect(x: 0, y: 0, width: 1400, height: 900)) }
        best = min(best, t)
        count = tiles.count
    }
    print("layout: \(count) tiles, best \(String(format: "%.2f", best)) ms")

case "bench" where arguments.dropFirst().first == "stop":
    var fs = GeneratedFileSystem.sized(files: 2_000_000)
    fs.readDelay = 0.0001
    var worst = 0.0
    for delay in [0.05, 0.2, 0.5, 1.0] {
        let scanner = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root))
        scanner.start()
        usleep(useconds_t(delay * 1_000_000))
        let start = DispatchTime.now().uptimeNanoseconds
        scanner.cancel()
        let outcome = scanner.wait()
        let t = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        worst = max(worst, t)
        print("stop after \(Int(delay * 1000)) ms: \(outcome) in \(String(format: "%.1f", t)) ms, kept \(scanner.store.count) nodes")
    }
    // A real folder of 100,000 entries being read when Stop comes.
    print("worst: \(String(format: "%.1f", worst)) ms")

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

case "map-tree":
    let root = URL(fileURLWithPath: arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "/tmp/tidy-test/maptree")
    let files = option("--files").flatMap(Int.init) ?? 200_000
    do {
        let ((), t) = try clock { try MapFixture.createTree(at: root, files: files) }
        print("built \(files) files in \(ms(t))")
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }

case "volumes":
    // The purgeable spike: compare the two free-space figures. Sizes only, no names.
    for volume in SystemVolumes().volumes() {
        let figures = VolumeFigures(volume: volume, mapped: 0)
        print("\(volume.kind.rawValue) \(volume.format.isEmpty ? "?" : volume.format) read_only=\(volume.isReadOnly) total=\(volume.total) free=\(volume.free) free_important=\(volume.freeForImportantUse) purgeable=\(figures.purgeable) system=\(volume.systemBytes) data_used=\(volume.kind == .startup ? SystemVolumes.spaceUsed(of: volume.walkRoot.path) : SystemVolumes.spaceUsed(of: volume.root.path))")
    }

default:
    print("usage: tidy-tool fixtures [root] [--map] | remove-fixtures [root] | map-tree [root] [--files N] | bench [map|fake|stop] | volumes")
}

func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func set(_ value: Int) { lock.withLock { _value = value } }
}

extension MapScanner {
    func run() -> MapStore {
        start()
        wait()
        return store
    }
}

/// This process's memory footprint (Activity Monitor's "Memory").
enum Footprint {
    static var current: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}

/// Samples the footprint every 5 ms until stopped; returns the highest.
final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = 0
    private var running = true
    func start() {
        Thread {
            while self.lock.withLock({ self.running }) {
                let now = Footprint.current
                self.lock.withLock { self.peak = max(self.peak, now) }
                Thread.sleep(forTimeInterval: 0.005)
            }
        }.start()
    }
    func stop() -> Int {
        lock.withLock { running = false; return peak }
    }
}
