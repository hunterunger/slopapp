import Foundation
import Testing
@testable import SpecimenCore

private let ciSlack: Double = ProcessInfo.processInfo.environment["CI"] == nil ? 1 : 4

@Suite struct LibraryPathTests {
    @Test func insideAndHidden() {
        #expect(LibraryPaths.isInside("/a/b/c.otf", folder: "/a/b"))
        #expect(!LibraryPaths.isInside("/a/bc/c.otf", folder: "/a/b"))
        #expect(!LibraryPaths.isInside("/a/b", folder: "/a/b"))
        #expect(LibraryPaths.isInside("/a/b", folder: "/a/b", orEqual: true))
        #expect(LibraryPaths.isHidden("/a/b/.git/x.otf", below: "/a/b"))
        #expect(LibraryPaths.isHidden("/a/b/._x.otf", below: "/a/b"))
        #expect(!LibraryPaths.isHidden("/a/b/x.otf", below: "/a/b"))
        #expect(LibraryPaths.isFontFile("/x/Inter.OTF"))
        #expect(!LibraryPaths.isFontFile("/x/readme.txt"))
        #expect(LibraryPaths.trimmed("/a/b/") == "/a/b")
    }

    @Test func eventsAreRebasedToTheFolderAsAdded() {
        #expect(LibraryPaths.rebase("/private/tmp/lib/a.otf", real: "/private/tmp/lib", root: "/tmp/lib") == "/tmp/lib/a.otf")
        #expect(LibraryPaths.rebase("/private/tmp/lib", real: "/private/tmp/lib", root: "/tmp/lib") == "/tmp/lib")
        #expect(LibraryPaths.rebase("/private/tmp/library/a.otf", real: "/private/tmp/lib", root: "/tmp/lib") == nil)
    }

    @Test func addingFolders() {
        let fonts = LibraryFolder(path: "/Users/me/Fonts")
        let existing = [fonts, LibraryFolder(path: "/Volumes/Work/Clients/Acme")]
        let installed = ["/Library/Fonts", "/Users/me/Library/Fonts"]
        #expect(FolderAddition.plan("/Users/me/Fonts/Projects", existing: existing, installed: installed) == .alreadyIncluded(folder: fonts.id))
        #expect(FolderAddition.plan("/Users/me/Fonts/", existing: existing, installed: installed) == .alreadyIncluded(folder: fonts.id))
        #expect(FolderAddition.plan("/Users/me/Library/Fonts", existing: existing, installed: installed) == .installedFonts)
        #expect(FolderAddition.plan("/Library/Fonts/Sub", existing: existing, installed: installed) == .installedFonts)
        // A parent folds the folders inside it into itself.
        #expect(FolderAddition.plan("/Volumes/Work", existing: existing, installed: installed) == .add(path: "/Volumes/Work", replacing: [existing[1].id]))
        #expect(FolderAddition.plan("/Volumes/Other", existing: existing, installed: installed) == .add(path: "/Volumes/Other", replacing: []))
    }

    @Test func storeRoundTrips() throws {
        let store = FoldersStore(directory: temporaryDirectory())
        #expect(store.load().isEmpty)
        let folders = [LibraryFolder(path: "/a", added: Date(timeIntervalSince1970: 1000)), LibraryFolder(path: "/b", added: Date(timeIntervalSince1970: 2000))]
        try store.save(folders)
        #expect(store.load() == folders)
        try Data("{".utf8).write(to: store.url)
        #expect(store.load().isEmpty)
    }

    @Test func folderTreeShowsOnlyFoldersWithFonts() {
        let tree = FolderNode.tree(root: "/L", files: ["/L/a.otf", "/L/Clients/Acme/Fonts/b.otf", "/L/Clients/Beta/c.otf", "/L/Zeta/d.otf"])
        #expect(tree.name == "L")
        #expect(tree.children?.map(\.name) == ["Clients", "Zeta"])
        #expect(tree.children?.first?.children?.map(\.name) == ["Acme", "Beta"])
        #expect(tree.children?.first?.children?.first?.children?.map(\.path) == ["/L/Clients/Acme/Fonts"])
        #expect(tree.children?.last?.children == nil)
        #expect(tree.allPaths.count == 6)
    }

    @Test func mergeAddsUnregisteredLibraryFacesAsInactive() {
        let registered = SystemFace(postScriptName: "A", familyName: "A", styleName: "Regular", path: "/L/a.otf", isEnabled: true)
        let installed = SystemFace(postScriptName: "Sys", familyName: "Sys", styleName: "Regular", path: "/System/Library/Fonts/s.ttc")
        let libraryA = SystemFace(postScriptName: "A", familyName: "A", styleName: "Regular", path: "/L/a.otf", isEnabled: false)
        let libraryB = SystemFace(postScriptName: "B", familyName: "B", styleName: "Regular", path: "/L/b.otf", isEnabled: true)
        let merged = LibraryMerge.merge(registry: [registered, installed], library: [libraryA, libraryB], temporaryPaths: ["/L/a.otf"])
        #expect(merged.count == 3)
        #expect(merged[0].isEnabled && merged[0].isTemporary)
        #expect(!merged[1].isTemporary)
        #expect(merged[2].postScriptName == "B" && !merged[2].isEnabled && !merged[2].isTemporary)
    }

    @Test func changesMergeAcrossBatches() {
        var first = LibraryChange()
        first.added["/a"] = ["A"]
        first.removed["/b"] = ["B"]
        var second = LibraryChange()
        second.removed["/a"] = ["A"]
        second.added["/b"] = ["B"]
        first.merge(second)
        #expect(first.added.isEmpty)
        #expect(first.removed.isEmpty)
        #expect(first.changed == ["/b"])
    }
}

@Suite struct LibraryScanTests {
    func makeLibrary() -> FakeLibraryFileSystem {
        let fileSystem = FakeLibraryFileSystem()
        fileSystem.add("/L/Alpha.otf")
        fileSystem.add("/L/Clients/Acme/Beta.ttf")
        fileSystem.add("/L/Clients/Acme/Pair.ttc", names: ["Pair-Regular", "Pair-Bold"], family: "Pair")
        fileSystem.add("/L/.hidden/Gamma.otf")
        return fileSystem
    }

    @Test func firstScanReadsEveryFontOnce() {
        let fileSystem = makeLibrary()
        var scan = LibraryScan()
        let change = scan.rescan("/L", fileSystem: fileSystem)
        #expect(Set(change.added.keys) == ["/L/Alpha.otf", "/L/Clients/Acme/Beta.ttf", "/L/Clients/Acme/Pair.ttc"])
        #expect(change.added["/L/Clients/Acme/Pair.ttc"] == ["Pair-Regular", "Pair-Bold"])
        #expect(scan.faces(in: ["/L"]).count == 4)
        // Nothing changed: no reads.
        fileSystem.resetCounters()
        #expect(scan.rescan("/L", fileSystem: fileSystem).isEmpty)
        #expect(fileSystem.reads.isEmpty)
    }

    @Test func fileEventsAreIncremental() {
        let fileSystem = makeLibrary()
        var scan = LibraryScan()
        _ = scan.rescan("/L", fileSystem: fileSystem)
        fileSystem.resetCounters()

        // Added.
        fileSystem.add("/L/Clients/Acme/New.otf")
        var change = scan.apply([FolderEvent(path: "/L/Clients/Acme/New.otf", flags: [.created, .isFile])], roots: ["/L"], fileSystem: fileSystem)
        #expect(Array(change.added.keys) == ["/L/Clients/Acme/New.otf"])
        #expect(fileSystem.reads == ["/L/Clients/Acme/New.otf"])
        #expect(fileSystem.listings == 0)

        // Modified: re-read.
        fileSystem.touch("/L/Alpha.otf", modified: 5)
        change = scan.apply([FolderEvent(path: "/L/Alpha.otf", flags: [.modified, .isFile])], roots: ["/L"], fileSystem: fileSystem)
        #expect(change.changed == ["/L/Alpha.otf"])

        // Renamed: FSEvents sends the old and new paths.
        fileSystem.remove("/L/Alpha.otf")
        fileSystem.add("/L/Alpha Renamed.otf", names: ["Alpha"])
        change = scan.apply([FolderEvent(path: "/L/Alpha.otf", flags: [.renamed, .isFile]),
                             FolderEvent(path: "/L/Alpha Renamed.otf", flags: [.renamed, .isFile])], roots: ["/L"], fileSystem: fileSystem)
        #expect(change.removed == ["/L/Alpha.otf": ["Alpha"]])
        #expect(change.added == ["/L/Alpha Renamed.otf": ["Alpha"]])

        // Removed.
        fileSystem.remove("/L/Clients/Acme/Beta.ttf")
        change = scan.apply([FolderEvent(path: "/L/Clients/Acme/Beta.ttf", flags: [.removed, .isFile])], roots: ["/L"], fileSystem: fileSystem)
        #expect(Array(change.removed.keys) == ["/L/Clients/Acme/Beta.ttf"])
        #expect(scan.files["/L/Clients/Acme/Beta.ttf"] == nil)
    }

    @Test func directoryEventsRescanThatFolder() {
        let fileSystem = makeLibrary()
        var scan = LibraryScan()
        _ = scan.rescan("/L", fileSystem: fileSystem)
        // A whole folder dragged in.
        fileSystem.add("/L/Clients/Zed/One.otf")
        fileSystem.add("/L/Clients/Zed/Two.otf")
        var change = scan.apply([FolderEvent(path: "/L/Clients/Zed", flags: [.created, .isDirectory])], roots: ["/L"], fileSystem: fileSystem)
        #expect(change.added.count == 2)
        // A folder deleted: everything below goes.
        fileSystem.removeDirectory("/L/Clients/Acme")
        change = scan.apply([FolderEvent(path: "/L/Clients/Acme", flags: [.removed, .isDirectory])], roots: ["/L"], fileSystem: fileSystem)
        #expect(Set(change.removed.keys) == ["/L/Clients/Acme/Beta.ttf", "/L/Clients/Acme/Pair.ttc"])
        // Coalesced events: rescan.
        fileSystem.add("/L/Clients/Zed/Three.otf")
        change = scan.apply([FolderEvent(path: "/L/Clients", flags: [.mustRescan])], roots: ["/L"], fileSystem: fileSystem)
        #expect(Array(change.added.keys) == ["/L/Clients/Zed/Three.otf"])
    }

    @Test func ignoresHiddenNonFontsAndOtherFolders() {
        let fileSystem = makeLibrary()
        var scan = LibraryScan()
        _ = scan.rescan("/L", fileSystem: fileSystem)
        fileSystem.add("/Elsewhere/x.otf")
        let change = scan.apply([
            FolderEvent(path: "/L/.hidden/Gamma.otf", flags: [.modified, .isFile]),
            FolderEvent(path: "/L/notes.txt", flags: [.created, .isFile]),
            FolderEvent(path: "/Elsewhere/x.otf", flags: [.created, .isFile]),
        ], roots: ["/L"], fileSystem: fileSystem)
        #expect(change.isEmpty)
    }

    @Test func rootChangedAndRemovedFolders() {
        let fileSystem = makeLibrary()
        var scan = LibraryScan()
        _ = scan.rescan("/L", fileSystem: fileSystem)
        // The folder is gone (a disk unplugged): its files are kept, for when it's back.
        fileSystem.removeDirectory("/L")
        let change = scan.apply([FolderEvent(path: "/L", flags: [.rootChanged])], roots: ["/L"], fileSystem: fileSystem)
        #expect(change.isEmpty)
        #expect(scan.files.count == 3)
        // Back again, with a file changed: the root is rescanned.
        let back = makeLibrary()
        back.touch("/L/Alpha.otf", modified: 9)
        #expect(scan.apply([FolderEvent(path: "/L", flags: [.rootChanged])], roots: ["/L"], fileSystem: back).changed == ["/L/Alpha.otf"])
        _ = scan.rescan("/L", fileSystem: makeLibrary())
        #expect(scan.remove("/L").removed.count == 3)
        #expect(scan.files.isEmpty)
    }

    @Test func cacheRoundTrips() throws {
        let fileSystem = makeLibrary()
        var scan = LibraryScan()
        _ = scan.rescan("/L", fileSystem: fileSystem)
        let url = temporaryDirectory().appendingPathComponent("library.plist")
        try scan.save(to: url)
        #expect(LibraryScan.load(from: url) == scan)
        try Data("junk".utf8).write(to: url)
        #expect(LibraryScan.load(from: url).files.isEmpty)
    }

    @Test func oneEventInABigLibraryIsFast() {
        let fileSystem = FakeLibraryFileSystem()
        for index in 0..<5000 { fileSystem.add("/Big/Project \(index % 50)/Font \(index).otf") }
        var scan = LibraryScan()
        _ = scan.rescan("/Big", fileSystem: fileSystem)
        #expect(scan.files.count == 5000)
        fileSystem.add("/Big/Project 3/Fresh.otf")
        let clock = ContinuousClock()
        var change = LibraryChange()
        let elapsed = clock.measure {
            change = scan.apply([FolderEvent(path: "/Big/Project 3/Fresh.otf", flags: [.created, .isFile])], roots: ["/Big"], fileSystem: fileSystem)
        }
        #expect(change.added.count == 1)
        #expect(elapsed < .milliseconds(20 * ciSlack))
        let tree = clock.measure { _ = FolderNode.tree(root: "/Big", files: scan.files.keys) }
        #expect(tree < .milliseconds(100 * ciSlack))
    }

    @Test func folderLibrarySnapshotsOnlineFolders() async {
        let fileSystem = makeLibrary()
        let library = FolderLibrary(fileSystem: fileSystem)
        let first = await library.sync(roots: ["/L", "/Offline"])
        #expect(first.faces.count == 4)
        #expect(first.offline == ["/Offline"])
        #expect(first.trees["/L"]?.children?.map(\.name) == ["Clients"])
        fileSystem.add("/L/Late.otf")
        let second = await library.apply([FolderEvent(path: "/L/Late.otf", flags: [.created, .isFile])], roots: ["/L"])
        #expect(second.faces.count == 5)
        #expect(second.change.added.count == 1)
        let removed = await library.remove("/L", roots: [])
        #expect(removed.faces.isEmpty)
    }
}

@Suite struct LibraryFilterFolderTests {
    @Test func folderAndDocumentSidebarItems() {
        let a = face("A-Regular", family: "A", path: "/L/Clients/Acme/A.otf", enabled: false)
        let b = face("B-Regular", family: "B", path: "/L/Other/B.otf", enabled: false)
        let c = face("C-Regular", family: "C", path: "/System/Library/Fonts/C.ttc")
        let families = FontFamily.group([a, b, c])
        var query = LibraryQuery(sidebar: .folder("/L/Clients"), folderPaths: ["/L", "/L/Clients", "/L/Clients/Acme", "/L/Other"])
        #expect(LibraryFilter.items(in: families, query: query).map(\.family.name) == ["A"])
        query.sidebar = .folder("/L")
        #expect(LibraryFilter.items(in: families, query: query).map(\.family.name) == ["A", "B"])
        let document = UUID()
        query.documentFaceIDs = [document: [b.id, c.id]]
        query.sidebar = .document(document)
        #expect(LibraryFilter.items(in: families, query: query).map(\.family.name) == ["B", "C"])
        let counts = LibraryFilter.counts(in: families, query: query)
        #expect(counts[.folder("/L")] == 2)
        #expect(counts[.folder("/L/Clients/Acme")] == 1)
        #expect(counts[.folder("/L/Other")] == 1)
        #expect(counts[.document(document)] == 2)
    }

    @Test func storageKeysRoundTrip() {
        let id = UUID()
        for item in [SidebarItem.folder("/Users/me/Fonts/Acme"), .document(id), .all, .tag("x")] {
            #expect(SidebarItem(storageKey: item.storageKey) == item)
        }
    }

    @Test func temporaryState() {
        var on = face("A", family: "A")
        on.isTemporary = true
        let off = face("B", family: "A", enabled: false)
        #expect(ActivationState(faces: [on]) == .temporary)
        #expect(ActivationState(faces: [on, face("C", family: "A")]) == .active)
        #expect(ActivationState(faces: [on, off]) == .mixed)
        #expect(ActivationState(faces: [on]).isOn)
        let rules = SmartRules(state: .temporary)
        #expect(LibraryFilter.smartFacePasses(on, rules: rules))
        #expect(!LibraryFilter.smartFacePasses(face("C", family: "A"), rules: rules))
    }

    @Test func folderCountsAreFastForBigLibraries() {
        var faces: [FontFace] = []
        for index in 0..<6000 {
            faces.append(face("F\(index)", family: "Family \(index / 3)", path: "/Big/Client \(index % 40)/Project \(index % 7)/F\(index).otf", enabled: false))
        }
        let families = FontFamily.group(faces)
        var folders = ["/Big"]
        for client in 0..<40 {
            folders.append("/Big/Client \(client)")
            for project in 0..<7 { folders.append("/Big/Client \(client)/Project \(project)") }
        }
        let clock = ContinuousClock()
        var counts: [SidebarItem: Int] = [:]
        let elapsed = clock.measure { counts = LibraryFilter.folderCounts(in: families, folders: folders) }
        #expect(counts[.folder("/Big")] == 2000)
        #expect(elapsed < .milliseconds(150 * ciSlack))
    }
}
