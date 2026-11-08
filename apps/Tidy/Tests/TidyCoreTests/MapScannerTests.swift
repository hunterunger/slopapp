import Darwin
import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

/// Runs a scan to the end and returns the store.
func mapScan<R: DirectoryReader>(_ reader: R, root: String, threads: Int = 4, excluded: Set<String> = [],
                                 skipped: Set<String> = [], minimum: Int64 = 1_000_000, kept: Int = 64) throws -> MapStore {
    let scanner = try MapScanner(reader: reader, options: MapScanOptions(root: root, excluded: excluded, skipped: skipped,
                                                                          threads: threads, keptFiles: kept,
                                                                          minimumListedSize: minimum))
    scanner.start()
    #expect(scanner.wait() == .finished)
    return scanner.store
}

extension MapStore {
    func item(_ id: String) -> MapItem? {
        guard let index = find(id: id) else { return nil }
        return lock.withLock { itemLocked(index, id: id) }
    }

    /// Every final folder adds up exactly: its listed children plus its folded files.
    func checkFinalFoldersAddUp() -> [String] {
        lock.withLock {
            var problems: [String] = []
            for i in 0..<nodes.count {
                let node = nodes[i]
                guard node.isDirectory && node.isFinal && !node.flags.contains(.package) && !node.flags.contains(.removed) else { continue }
                let children = (node.childStart..<node.childStart + node.childCount).map { nodes[Int($0)] }
                let sum = children.filter { !$0.flags.contains(.removed) }.reduce(0) { $0 + $1.size } + node.aux
                if sum != node.size { problems.append("node \(i): \(node.size) != \(sum)") }
                if children.contains(where: { !$0.isFinal }) { problems.append("node \(i) is final with an unfinished child") }
            }
            return problems
        }
    }
}

@Suite("Map scanner")
struct MapScannerTests {
    @Test func sumsFoldSmallFilesAndKeepTheBiggest() throws {
        var fs = FakeFileSystem()
        fs.file("Movies/a.mov", size: 50_000_000)
        fs.file("Movies/b.mov", size: 20_000_000)
        fs.files("Movies/thumbs", count: 300, size: 4_096)
        fs.file("notes.txt", size: 4_096)
        let store = try mapScan(fs, root: fs.root)
        let root = try #require(store.item(""))
        #expect(root.size == 70_000_000 + 301 * 4_096)
        #expect(root.itemCount == 303)
        #expect(root.flags.contains(.final))
        let movies = try #require(store.item("Movies"))
        #expect(movies.size == 70_000_000 + 300 * 4_096)
        #expect(movies.childCount == 3)   // two films and the thumbs folder
        let thumbs = try #require(store.item("Movies/thumbs"))
        #expect(thumbs.childCount == 0)
        #expect(thumbs.otherCount == 300)
        #expect(thumbs.otherSize == 300 * 4_096)
        #expect(root.otherCount == 1)
        #expect(store.checkFinalFoldersAddUp().isEmpty)
    }

    @Test func keepsOnlyTheTopFilesOfAHugeFolder() throws {
        var fs = FakeFileSystem()
        for i in 0..<200 { fs.file("big/f\(i)", size: Int64(1_000_000 + i * 1_000)) }
        let store = try mapScan(fs, root: fs.root, kept: 64)
        let big = try #require(store.item("big"))
        #expect(big.childCount == 64)
        #expect(big.otherCount == 136)
        let snapshot = store.snapshot(of: big.node!, id: "big")
        // The 64 biggest are the ones listed, biggest first.
        #expect(snapshot.items.first?.name == "f199")
        #expect(snapshot.items.last?.name == "f136")
        #expect(store.checkFinalFoldersAddUp().isEmpty)
    }

    @Test func aFolderOfAMillionFilesStaysSmall() throws {
        let fs = GeneratedFileSystem(fanout: 0, depth: 0, filesPerFolder: 1_000_000, bigEvery: 1_000)
        let store = try mapScan(fs, root: fs.root)
        // One folder, at most 64 listed files: the store doesn't grow with the file count.
        #expect(store.count <= 65)
        #expect(store.approximateBytes < 6_000_000)   // one 4 MB node chunk and one 1 MB name chunk
        #expect(store.item("")?.itemCount == 1_000_000)
        #expect(store.item("")?.size == fs.expectedBytes)
    }

    @Test func hardLinksCountOnceAndAreMarked() throws {
        var fs = FakeFileSystem()
        fs.file("one/name-a", size: 30_000_000, links: 2, id: 77)
        fs.file("two/name-b", size: 30_000_000, links: 2, id: 77)
        let store = try mapScan(fs, root: fs.root)
        #expect(store.item("")?.size == 30_000_000)
        let a = try #require(store.item("one/name-a"))
        let b = try #require(store.item("two/name-b"))
        #expect(a.flags.contains(.hardLinked) && b.flags.contains(.hardLinked))
        // Exactly one of them carries the size; the other shows it greyed.
        #expect(a.size + b.size == 30_000_000)
        #expect([a, b].filter { $0.flags.contains(.countedElsewhere) }.count == 1)
        #expect(a.reported == 30_000_000 && b.reported == 30_000_000)
        #expect(store.linkCount(a.node!) == 2)
    }

    @Test func fullClonesCountOncePartialClonesAreFlagged() throws {
        var fs = FakeFileSystem()
        for i in 0..<5 { fs.file("clones/copy-\(i)", size: 10_000_000, cloneID: 900, sharesAll: true) }
        fs.file("edited", size: 8_000_000, cloneID: 901, partialClone: true)
        let store = try mapScan(fs, root: fs.root)
        #expect(store.item("clones")?.size == 10_000_000)
        let copies = (0..<5).compactMap { store.item("clones/copy-\($0)") }
        #expect(copies.allSatisfy { $0.flags.contains(.clone) })
        #expect(copies.filter { $0.flags.contains(.countedElsewhere) }.count == 4)
        let edited = try #require(store.item("edited"))
        #expect(edited.flags.contains(.partialClone))
        #expect(!edited.flags.contains(.clone))
        #expect(edited.size == 8_000_000)
    }

    @Test func cloudPlaceholdersTakeNoSpaceAndAreNeverRead() throws {
        var fs = FakeFileSystem()
        fs.file("Docs/thesis.pdf", size: 0, logical: 300_000_000, dataless: true)
        fs.file("Docs/local.pdf", size: 2_000_000)
        fs.dataless("Docs/Old Projects")
        fs.file("Docs/Old Projects/never-read.bin", size: 9_000_000)
        let store = try mapScan(fs, root: fs.root)
        let docs = try #require(store.item("Docs"))
        #expect(docs.size == 2_000_000)
        #expect(docs.logical == 302_000_000)
        #expect(store.cloudTally(docs.node!) == CloudTally(count: 2, bytes: 300_000_000))
        #expect(store.item("Docs/Old Projects")?.flags.contains(.dataless) == true)
        #expect(!fs.log.reads.contains { $0.hasSuffix("Old Projects") })
        // Every scanner thread turned downloads off before reading.
        #expect(fs.log.preparedThreads == 4)
    }

    @Test func sparseCompressedAndPurgeableAreMarked() throws {
        var fs = FakeFileSystem()
        fs.file("Docker.raw", size: 9_800_000_000, logical: 64_000_000_000, sparse: true)
        fs.file("packed", size: 2_000_000, logical: 6_000_000, compressed: true)
        fs.file("cache.db", size: 3_000_000, purgeable: true)
        let store = try mapScan(fs, root: fs.root)
        let raw = try #require(store.item("Docker.raw"))
        #expect(raw.size == 9_800_000_000 && raw.logical == 64_000_000_000 && raw.flags.contains(.sparse))
        #expect(store.item("packed")?.flags.contains(.compressed) == true)
        #expect(store.item("cache.db")?.flags.contains(.purgeable) == true)
    }

    @Test func packagesAreOneItem() throws {
        var fs = FakeFileSystem()
        fs.file("Applications/Editor.app/Contents/MacOS/Editor", size: 40_000_000)
        fs.file("Applications/Editor.app/Contents/Resources/a.bin", size: 5_000_000)
        fs.file("Pictures/Photos Library.photoslibrary/originals/1.heic", size: 3_000_000)
        let store = try mapScan(fs, root: fs.root)
        let app = try #require(store.item("Applications/Editor.app"))
        #expect(app.kind == .package)
        #expect(app.isApp)
        #expect(app.size == 45_000_000)
        #expect(app.childCount == 0)
        #expect(app.flags.contains(.final))
        #expect(store.item("Pictures/Photos Library.photoslibrary")?.kind == .package)
        #expect(store.checkFinalFoldersAddUp().isEmpty)
    }

    @Test func showPackageContentsListsItReadOnly() throws {
        var fs = FakeFileSystem()
        fs.file("Editor.app/Contents/MacOS/Editor", size: 40_000_000)
        fs.file("Editor.app/Contents/Resources/a.bin", size: 5_000_000)
        let first = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root, threads: 2))
        first.start()
        first.wait()
        let store = first.store
        let app = try #require(store.find(id: "Editor.app"))
        let rescan = MapScanner(rescanning: app, at: fs.full("Editor.app"), in: store, seen: first, reader: fs,
                                options: first.options, showPackageContents: true)
        rescan.start()
        #expect(rescan.wait() == .finished)
        #expect(store.item("")?.size == 45_000_000)
        let inside = try #require(store.item("Editor.app/Contents/MacOS/Editor"))
        #expect(inside.flags.contains(.insidePackage))
        #expect(store.item("Editor.app")?.childCount == 1)
        #expect(store.item("")?.flags.contains(.final) == true)
    }

    @Test func unreadableFoldersMakeTotalsALowerBound() throws {
        var fs = FakeFileSystem()
        fs.file("ok/a", size: 5_000_000)
        fs.deny("ok/locked")
        fs.file("ok/locked/secret", size: 7_000_000)
        let store = try mapScan(fs, root: fs.root)
        let ok = try #require(store.item("ok"))
        #expect(ok.size == 5_000_000)
        #expect(ok.flags.contains(.partial))
        #expect(ok.isLowerBound)
        #expect(store.item("")?.flags.contains(.partial) == true)
        #expect(store.item("ok/locked")?.flags.contains(.unreadable) == true)
        #expect(store.unreadableCount(ok.node!) == 1)
    }

    @Test func excludedFoldersAreLockedPartialRows() throws {
        var fs = FakeFileSystem()
        fs.file("Documents/big", size: 50_000_000)
        fs.file("Music/song", size: 4_000_000)
        let store = try mapScan(fs, root: fs.root, excluded: [fs.full("Documents")])
        let docs = try #require(store.item("Documents"))
        #expect(docs.flags.contains(.excluded))
        #expect(docs.size == 0)
        #expect(store.item("")?.flags.contains(.partial) == true)
        #expect(!fs.log.reads.contains(fs.full("Documents")))
    }

    @Test func mountPointsAndOtherDevicesAreSkipped() throws {
        var fs = FakeFileSystem()
        fs.file("real", size: 1_000_000)
        fs.mountPoint("Volumes/Backup")
        fs.otherDevice("Elsewhere")
        fs.file("Elsewhere/x", size: 5_000_000)
        fs.file("other-disks/Stick/y", size: 5_000_000)
        let store = try mapScan(fs, root: fs.root, skipped: [fs.full("other-disks/Stick")])
        #expect(store.item("")?.size == 1_000_000)
        #expect(store.item("Volumes/Backup") == nil)
        #expect(store.item("Elsewhere") == nil)
        #expect(store.item("other-disks/Stick") == nil)
        #expect(!fs.log.reads.contains { $0.contains("Backup") || $0.contains("Elsewhere") || $0.contains("Stick") })
    }

    @Test func vanishedEntriesAreSkipped() throws {
        var fs = FakeFileSystem()
        fs.file("here", size: 2_000_000)
        fs.file("gone", size: 3_000_000, entryError: ENOENT)
        let store = try mapScan(fs, root: fs.root)
        #expect(store.item("")?.size == 2_000_000)
        #expect(store.item("gone") == nil)
        #expect(store.item("")?.flags.contains(.partial) == false)
    }

    @Test func rootErrors() {
        let fs = FakeFileSystem()
        #expect(throws: MapScanError.notFound) { try MapScanner(reader: fs, options: MapScanOptions(root: "/nowhere")) }
        var withFile = FakeFileSystem()
        withFile.file("a", size: 1)
        #expect(throws: MapScanError.notAFolder) {
            try MapScanner(reader: withFile, options: MapScanOptions(root: withFile.full("a")))
        }
    }

    @Test func manyThreadsGiveTheSameAnswerAsOne() throws {
        let fs = GeneratedFileSystem(fanout: 5, depth: 4, filesPerFolder: 40, bigEvery: 9)
        let one = try mapScan(fs, root: fs.root, threads: 1)
        let six = try mapScan(fs, root: fs.root, threads: 6)
        #expect(one.item("")?.size == fs.expectedBytes)
        #expect(six.item("")?.size == fs.expectedBytes)
        #expect(six.item("")?.itemCount == fs.fileCount)
        #expect(one.count == six.count)
        #expect(six.checkFinalFoldersAddUp().isEmpty)
    }

    @Test(arguments: [0.002, 0.01, 0.03, 0.08])
    func stoppingAtAnyPointKeepsAConsistentPartialMap(after delay: Double) throws {
        var fs = GeneratedFileSystem(fanout: 6, depth: 5, filesPerFolder: 20, bigEvery: 5)
        fs.readDelay = 0.0002
        let scanner = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root, threads: 4))
        scanner.start()
        Thread.sleep(forTimeInterval: delay)
        let start = Date()
        scanner.cancel()
        let outcome = scanner.wait()
        // Stop budget: the walk stops within 100 ms.
        #expect(Date().timeIntervalSince(start) < 0.1)
        let store = scanner.store
        #expect(store.checkFinalFoldersAddUp().isEmpty)
        if outcome == .stopped {
            // Nothing unfinished is published as final, and what was counted is kept.
            #expect(store.item("")?.flags.contains(.final) == false)
            #expect((store.item("")?.size ?? 0) <= fs.expectedBytes)
        }
    }

    @Test func snapshotsWhileScanningOnlyGrow() throws {
        var fs = GeneratedFileSystem(fanout: 6, depth: 4, filesPerFolder: 30, bigEvery: 4)
        fs.readDelay = 0.0003
        let scanner = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root, threads: 3))
        scanner.start()
        var last: Int64 = 0
        var finals: Set<String> = []
        var count = 0
        while scanner.isRunning {
            let snap = scanner.store.snapshot(of: MapStore.root, id: "")
            #expect(snap.folder.size >= last)
            last = snap.folder.size
            // Biggest first, every time.
            #expect(zip(snap.items, snap.items.dropFirst()).allSatisfy { $0.size >= $1.size })
            // Once final, always final.
            let nowFinal = Set(snap.items.filter { $0.flags.contains(.final) }.map(\.id))
            #expect(finals.isSubset(of: nowFinal))
            finals = nowFinal
            count += 1
            Thread.sleep(forTimeInterval: 0.005)
        }
        #expect(count > 1)
        #expect(scanner.store.item("")?.size == fs.expectedBytes)
        #expect(scanner.store.item("")?.flags.contains(.final) == true)
    }

    @Test func rescanThisFolderSplicesTheNewTotalsIn() throws {
        var fs = FakeFileSystem()
        fs.file("keep/a", size: 3_000_000)
        fs.file("work/b", size: 5_000_000)
        fs.file("work/c", size: 1_000)
        let first = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root, threads: 2))
        first.start()
        first.wait()
        // The folder changed on disk.
        fs.file("work/d", size: 7_000_000)
        let work = try #require(first.store.find(id: "work"))
        let rescan = MapScanner(rescanning: work, at: fs.full("work"), in: first.store, seen: first, reader: fs,
                                options: first.options)
        rescan.start()
        #expect(rescan.wait() == .finished)
        let store = first.store
        #expect(store.item("work")?.size == 12_001_000)
        #expect(store.item("")?.size == 15_001_000)
        #expect(store.item("work/d") != nil)
        #expect(store.item("")?.flags.contains(.final) == true)
        #expect(store.checkFinalFoldersAddUp().isEmpty)
    }

    @Test func rescanCountsItsHardLinksAgain() throws {
        var fs = FakeFileSystem()
        fs.file("only/a", size: 6_000_000, links: 2, id: 55)
        let first = try MapScanner(reader: fs, options: MapScanOptions(root: fs.root, threads: 1))
        first.start()
        first.wait()
        let folder = try #require(first.store.find(id: "only"))
        let rescan = MapScanner(rescanning: folder, at: fs.full("only"), in: first.store, seen: first, reader: fs,
                                options: first.options)
        rescan.start()
        rescan.wait()
        #expect(first.store.item("")?.size == 6_000_000)
    }

    @Test func removedAndRestoredSizesFlowUpTheChain() throws {
        var fs = FakeFileSystem()
        fs.file("a/b/big", size: 40_000_000)
        fs.file("a/other", size: 2_000_000)
        fs.files("a/b", count: 10, size: 1_000)
        let store = try mapScan(fs, root: fs.root)
        let big = try #require(store.find(id: "a/b/big"))
        #expect(store.markRemoved(big))
        #expect(!store.markRemoved(big))
        #expect(store.item("a")?.size == 2_010_000)
        #expect(store.item("")?.size == 2_010_000)
        #expect(store.snapshot(of: store.find(id: "a/b")!, id: "a/b").items.isEmpty)
        #expect(store.restore(big))
        #expect(store.item("")?.size == 42_010_000)
        let b = try #require(store.find(id: "a/b"))
        store.adjustSmallItems(in: b, size: 1_000, logical: 1_000, count: 1, restoring: false)
        #expect(store.item("a/b")?.otherCount == 9)
        #expect(store.item("")?.size == 42_009_000)
        store.adjustSmallItems(in: b, size: 1_000, logical: 1_000, count: 1, restoring: true)
        #expect(store.item("")?.size == 42_010_000)
    }

    @Test func fiveMillionFakeFilesFitTheMemoryBudget() throws {
        // The doc's 5 M budget: retained < 150 MB. Measured on the store itself (the app's
        // footprint check is in the build notes).
        let fs = GeneratedFileSystem.sized(files: 5_000_000)
        #expect(fs.fileCount >= 5_000_000)
        let store = try mapScan(fs, root: fs.root, threads: 6)
        #expect(store.item("")?.itemCount == fs.fileCount)
        #expect(store.item("")?.size == fs.expectedBytes)
        #expect(store.approximateBytes < 150_000_000)
    }
}

@Suite("Map scanner on real folders")
struct BulkReaderTests {
    @Test func realReaderMatchesTheFileSystem() throws {
        let root = URL(fileURLWithPath: "/tmp/tidy-test/unit/bulk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("deep/er/still"), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: root.appendingPathComponent("deep/big.bin"))
        try Data(count: 10).write(to: root.appendingPathComponent("deep/er/still/small.txt"))
        // A hard link (two names), a clone and a sparse file.
        try Data(count: 2_000_000).write(to: root.appendingPathComponent("linked.bin"))
        #expect(link(root.appendingPathComponent("linked.bin").path, root.appendingPathComponent("deep/linked-again.bin").path) == 0)
        try Data(repeating: 7, count: 4_000_000).write(to: root.appendingPathComponent("original.bin"))
        let cloned = clonefile(root.appendingPathComponent("original.bin").path, root.appendingPathComponent("deep/clone.bin").path, 0) == 0
        let sparse = open(root.appendingPathComponent("sparse.img").path, O_CREAT | O_WRONLY, 0o644)
        ftruncate(sparse, 500_000_000)
        close(sparse)
        try fm.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)

        let store = try mapScan(BulkDirectoryReader(), root: root.path, minimum: 0)
        let expected = try #require(DiskUsage.measure(root))
        let rootItem = try #require(store.item(""))
        // fts counts hard links once but clones twice; the map counts both once.
        let cloneBytes = cloned ? (store.item("original.bin")?.reported ?? 0) : 0
        #expect(rootItem.size == expected.bytes - cloneBytes)
        #expect(store.item("linked.bin").map { $0.flags.contains(.hardLinked) } == true)
        if cloned {
            #expect(store.item("deep/clone.bin")?.flags.contains(.clone) == true)
        }
        let image = try #require(store.item("sparse.img"))
        #expect(image.logical == 500_000_000)
        #expect(image.size < 1_000_000)
        #expect(store.item("loop")?.kind == .symlink || store.item("loop") == nil)
        #expect(rootItem.flags.contains(.final))
    }

    @Test func downloadsAreTurnedOffOnScannerThreadsOnly() async {
        let before = DatalessPolicy.currentThreadSetting()
        let setting = await ScannerThread.run(reader: BulkDirectoryReader()) { DatalessPolicy.currentThreadSetting() }
        #expect(setting == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        #expect(DatalessPolicy.currentThreadSetting() == before)
    }

    @Test func pathsLongerThanPathMaxStillOpen() throws {
        let root = URL(fileURLWithPath: "/tmp/tidy-test/unit/long-\(UUID().uuidString)")
        defer {
            // Remove from the bottom up with relative paths (too long for one call).
            _ = try? FileManager.default.removeItem(at: root)
        }
        var path = root.path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let name = String(repeating: "n", count: 200)
        var fd = open(path, O_RDONLY | O_DIRECTORY)
        for _ in 0..<6 {
            mkdirat(fd, name, 0o755)
            let next = openat(fd, name, O_RDONLY | O_DIRECTORY)
            close(fd)
            fd = next
            path += "/" + name
        }
        let file = openat(fd, "deepest.bin", O_CREAT | O_WRONLY, 0o644)
        _ = [UInt8](repeating: 1, count: 2_000_000).withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
        close(file)
        close(fd)
        #expect(path.utf8.count > Int(PATH_MAX))
        let store = try mapScan(BulkDirectoryReader(), root: root.path)
        #expect((store.item("")?.size ?? 0) >= 2_000_000)
        #expect(store.item("")?.flags.contains(.partial) == false)
    }

    @Test func smallItemsAreReadAgainOnDemand() throws {
        var fs = FakeFileSystem()
        fs.file("folder/big", size: 5_000_000)
        for i in 0..<30 { fs.file("folder/s\(i)", size: Int64(1_000 + i)) }
        fs.dir("folder/sub")
        let items = try SmallItemsReader.read(fs.full("folder"), excluding: ["big"], reader: fs).get()
        #expect(items.count == 30)
        #expect(items.first?.name == "s29")
        #expect(!items.contains { $0.name == "sub" || $0.name == "big" })
        #expect(throws: DirectoryReadError.vanished) { try SmallItemsReader.read(fs.full("nope"), excluding: [], reader: fs).get() }
    }
}
