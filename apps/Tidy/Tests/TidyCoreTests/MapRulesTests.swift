import CoreGraphics
import Foundation
import Testing
@testable import TidyCore
import TidyFixtures

@Suite("Map layout")
struct MapLayoutTests {
    let rect = CGRect(x: 0, y: 0, width: 800, height: 500)

    @Test func nestedTilesSitInsideTheirFolderUnderAHeader() {
        let items = [MapLayoutItem(size: 600, children: [300, 200, 50]), MapLayoutItem(size: 300), MapLayoutItem(size: 100)]
        let style = MapLayoutStyle()
        let tiles = MapLayout.tiles(items, in: rect, style: style)
        let folder = tiles.first { $0.level == 1 && $0.index == 0 }!
        let header = try! #require(folder.header)
        #expect(header.height == style.headerHeight)
        let children = tiles.filter { $0.level == 2 && $0.parent == tiles.firstIndex(of: folder)! }
        #expect(children.count >= 3)
        for child in children {
            // Inside the folder, below its header, with the even inset on the sides and bottom.
            #expect(child.rect.minX >= folder.rect.minX + style.inset)
            #expect(child.rect.maxX <= folder.rect.maxX - style.inset)
            #expect(child.rect.minY >= header.maxY)
            #expect(child.rect.maxY <= folder.rect.maxY - style.inset)
        }
        // The folder's unlisted remainder (600 - 550) shows as a smaller-items block.
        #expect(children.contains { $0.isSmaller })
        // Files have no header.
        #expect(tiles.first { $0.level == 1 && $0.index == 1 }?.header == nil)
    }

    @Test func noTilesOverlapAndAreasMatch() {
        let sizes = (1...40).map { Double($0 * $0) }
        let items = sizes.reversed().map { MapLayoutItem(size: $0) }
        let tiles = MapLayout.tiles(items, in: rect)
        let level1 = tiles.filter { $0.level == 1 }
        for (i, a) in level1.enumerated() {
            for b in level1[(i + 1)...] {
                #expect(a.rect.intersection(b.rect).width * a.rect.intersection(b.rect).height < 0.01)
            }
        }
        let total = sizes.reduce(0, +)
        let biggest = level1.first { $0.index == 0 }!
        let expected = sizes.last! / total * Double(rect.width * rect.height)
        let actual = Double((biggest.rect.width + 2) * (biggest.rect.height + 2))
        #expect(abs(actual - expected) / expected < 0.05)
    }

    @Test func tinyItemsMergeIntoOneSmallerBlock() {
        var items = [MapLayoutItem(size: 1_000_000)]
        items += (0..<500).map { _ in MapLayoutItem(size: 1) }
        let tiles = MapLayout.tiles(items, in: rect)
        #expect(tiles.filter { $0.level == 1 }.count <= 2)
        for tile in tiles { #expect(tile.rect.width >= 1 && tile.rect.height >= 1) }
    }

    @Test func emptyAndZeroSizedFoldersDontBreak() {
        #expect(MapLayout.tiles([], in: rect).isEmpty)
        #expect(MapLayout.tiles([MapLayoutItem(size: 0), MapLayoutItem(size: 0)], in: rect).isEmpty)
        #expect(MapLayout.tiles([MapLayoutItem(size: 5)], in: .zero).isEmpty)
    }

    @Test func smallFoldersDontNest() {
        let items = [MapLayoutItem(size: 1_000), MapLayoutItem(size: 1, children: [1])]
        let tiles = MapLayout.tiles(items, in: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(!tiles.contains { $0.level == 2 })
    }

    @Test func hitTestingFindsTheDeepestTileAndHeaders() {
        let items = [MapLayoutItem(size: 600, children: [400, 200]), MapLayoutItem(size: 400)]
        let tiles = MapLayout.tiles(items, in: rect)
        let folderIndex = tiles.firstIndex { $0.level == 1 && $0.index == 0 }!
        let header = tiles[folderIndex].header!
        let onHeader = MapLayout.hit(tiles, at: CGPoint(x: header.midX, y: header.midY))
        #expect(onHeader?.tile == folderIndex && onHeader?.onHeader == true)
        let child = tiles.firstIndex { $0.level == 2 }!
        let inChild = MapLayout.hit(tiles, at: CGPoint(x: tiles[child].rect.midX, y: tiles[child].rect.midY))
        #expect(inChild?.tile == child && inChild?.onHeader == false)
        #expect(MapLayout.hit(tiles, at: CGPoint(x: -5, y: -5)) == nil)
    }

    @Test func arrowKeysMoveToTheNeighbour() {
        let items = [MapLayoutItem(size: 50), MapLayoutItem(size: 25), MapLayoutItem(size: 25)]
        let tiles = MapLayout.tiles(items, in: CGRect(x: 0, y: 0, width: 400, height: 200))
        // The biggest is on the left; the other two are stacked on the right.
        let left = tiles.firstIndex { $0.index == 0 }!
        let right = MapLayout.neighbor(of: left, .right, in: tiles)
        #expect(right != nil && tiles[right!].rect.minX > tiles[left].rect.minX)
        #expect(MapLayout.neighbor(of: left, .left, in: tiles) == nil)
        let below = MapLayout.neighbor(of: right!, .down, in: tiles) ?? MapLayout.neighbor(of: right!, .up, in: tiles)
        #expect(below != nil && below != left)
        #expect(MapLayout.neighbor(of: right!, .left, in: tiles) == left)
    }

    @Test func twoThousandTilesLayOutWellUnderTheBudget() {
        // Budget: < 4 ms for 2 levels and ≤ 2,000 visible tiles.
        let items = (0..<200).map { (i: Int) -> MapLayoutItem in
            let children: [Double] = (0..<10).map { (j: Int) -> Double in Double(900 - j * 50 - i) }
            return MapLayoutItem(size: Double(10_000 - i * 40), children: children)
        }
        var best = Double.infinity
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = MapLayout.tiles(items, in: CGRect(x: 0, y: 0, width: 1400, height: 900))
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        // The budget (< 4 ms) is for release builds (`tidy-tool bench layout`); debug code
        // is several times slower, so it only gets a loose bound here.
        #if DEBUG
        #expect(best < 40)
        #else
        #expect(best < 4)
        #endif
    }
}

@Suite("Checked-items tray")
struct CheckTrayTests {
    func item(_ path: String, size: Int64 = 1_000, folder: Bool = false, shared: Bool = false) -> CheckedItem {
        CheckedItem(path: path, name: (path as NSString).lastPathComponent, size: size, isDirectory: folder, device: 1,
                    fileID: 1, mayFreeNothing: shared)
    }

    @Test func checkingAFolderAbsorbsWhatsCheckedInsideIt() {
        var tray = CheckTray()
        tray.check(item("/h/Movies/a.mov", size: 10))
        tray.check(item("/h/Movies/Old/b.mov", size: 20))
        tray.check(item("/h/Music/c", size: 5))
        #expect(tray.check(item("/h/Movies", size: 100, folder: true)) == .checked(absorbed: 2))
        #expect(tray.count == 2)
        #expect(tray.freeable == 105)
    }

    @Test func checkingInsideACheckedFolderIsRefused() {
        var tray = CheckTray()
        tray.check(item("/h/Movies", size: 100, folder: true))
        #expect(tray.check(item("/h/Movies/a.mov")) == .insideChecked("Movies"))
        #expect(tray.covering("/h/Movies/a.mov")?.path == "/h/Movies")
        // A sibling with a shared prefix isn't inside.
        #expect(tray.check(item("/h/Movies Old/x")) == .checked(absorbed: 0))
        #expect(tray.check(item("/h/Movies", folder: true)) == .alreadyChecked)
    }

    @Test func sharedItemsAddNothingToTheTotal() {
        var tray = CheckTray()
        tray.check(item("/h/a", size: 50))
        tray.check(item("/h/hardlink", size: 70, shared: true))
        #expect(tray.freeable == 50)
        #expect(tray.sharedCount == 1)
    }

    @Test func movedItemsLeaveTheTray() {
        var tray = CheckTray()
        tray.check(item("/h/a/one"))
        tray.check(item("/h/b", folder: true))
        tray.remove(paths: ["/h/a"])
        #expect(tray.items.map(\.path) == ["/h/b"])
        tray.uncheck("/h/b")
        #expect(tray.isEmpty)
    }
}

@Suite("Map safety")
struct MapSafetyTests {
    let env = TidyEnvironment.from(environment: ["TIDY_HOME": "/tmp/tidy-test/safety/home",
                                                 "TIDY_APPS_DIRS": "/tmp/tidy-test/safety/Applications",
                                                 "TIDY_TRASH_DIR": "/tmp/tidy-test/safety/Trash"],
                                   realHome: URL(fileURLWithPath: "/var/empty"))
    var home: String { env.home.path }

    func safety(_ scope: MapScopeKind = .home, volumes: [URL] = [], synced: [(URL, String)] = []) -> MapSafety {
        MapSafety(policy: TrashPolicy(environment: env, allowedVolumeRoots: volumes), scope: scope, syncedFolders: synced)
    }

    @Test func ordinaryHomeItemsCanBeChecked() {
        #expect(safety().lock(path: home + "/Movies/a.mov", kind: .file, flags: []) == nil)
        #expect(safety().lock(path: home + "/Library/Caches/com.example.App", kind: .folder, flags: []) == nil)
    }

    @Test func systemPathsAreRefused() {
        let s = safety(.startupDisk)
        for path in ["/", "/System", "/System/Library/Caches", "/Library", "/usr/local/bin", "/private/var", "/Users", "/Applications"] {
            #expect(s.lock(path: path, kind: .folder, flags: []) == .belongsToMacOS, "\(path)")
        }
        #expect(s.lock(path: "/Users/someone-else/Movies", kind: .folder, flags: []) == .outsideHome)
        // The home folder, its top-level folders and Library stay.
        #expect(s.lock(path: home, kind: .folder, flags: []) != nil)
        #expect(s.lock(path: home + "/Library", kind: .folder, flags: []) == .systemFolder)
        #expect(s.lock(path: home + "/Library/Caches", kind: .folder, flags: []) == .systemFolder)
        #expect(s.lock(path: home + "/Library/Containers/com.apple.mail", kind: .folder, flags: []) == .belongsToMacOS)
    }

    @Test func packageInsidesAreReadOnlyButTheWholePackageIsnt() {
        #expect(safety().lock(path: home + "/Pictures/P.photoslibrary/originals/1.heic", kind: .file, flags: [.insidePackage])
            == .insidePackage)
        #expect(safety().lock(path: home + "/Pictures/P.photoslibrary", kind: .package, flags: []) == nil)
    }

    @Test func syncedFoldersAreReadOnly() {
        let s = safety(synced: [(URL(fileURLWithPath: home + "/Dropbox"), "Dropbox")])
        #expect(s.lock(path: home + "/Library/Mobile Documents/com~apple~CloudDocs/Book.pages", kind: .file, flags: [])
            == .synced("iCloud Drive"))
        #expect(s.lock(path: home + "/Library/CloudStorage/GoogleDrive-x/My Drive/a", kind: .file, flags: [])
            == .synced("a cloud storage service"))
        #expect(s.lock(path: home + "/Dropbox/notes.txt", kind: .file, flags: []) == .synced("Dropbox"))
        // A cloud placeholder anywhere is synced too.
        #expect(s.lock(path: home + "/Movies/x", kind: .file, flags: [.dataless]) == .synced("iCloud"))
    }

    @Test func mailAndMessagesAreRefused() {
        #expect(safety().lock(path: home + "/Library/Mail/V10/x.mbox", kind: .folder, flags: []) == .appData("Mail"))
        #expect(safety().lock(path: home + "/Library/Messages/Attachments/a", kind: .folder, flags: []) == .appData("Messages"))
    }

    @Test func virtualItemsCantBeChecked() {
        for kind in [MapItem.Kind.smaller, .system, .notMapped] {
            #expect(safety().lock(path: home + "/x", kind: kind, flags: []) == .virtualItem)
        }
    }

    @Test func appsGoToTheUninstaller() {
        #expect(safety().lock(path: home + "/Applications/Editor.app", kind: .package, flags: []) == .app)
        #expect(safety(.startupDisk).lock(path: "/Applications/Editor.app", kind: .package, flags: []) == .app)
    }

    @Test func excludedFoldersNeedAccess() {
        #expect(safety().lock(path: home + "/Documents", kind: .folder, flags: [.excluded]) == .needsFullDiskAccess)
    }

    @Test func otherDisksAllowTheirContentsButNotTheirSystemFolders() {
        let stick = URL(fileURLWithPath: "/tmp/tidy-test/safety/Stick")
        let s = safety(.volume(isReadOnly: false), volumes: [stick])
        #expect(s.lock(path: stick.path + "/Footage/a.mov", kind: .file, flags: []) == nil)
        #expect(s.lock(path: stick.path, kind: .folder, flags: []) == .systemFolder)
        #expect(s.lock(path: stick.path + "/.Trashes/501/x", kind: .file, flags: []) == .systemFolder)
        #expect(s.lock(path: stick.path + "/.Spotlight-V100", kind: .folder, flags: []) == .systemFolder)
        #expect(safety(.volume(isReadOnly: true), volumes: [stick]).lock(path: stick.path + "/a", kind: .file, flags: [])
            == .readOnlyDisk)
        // Without the disk allowed, its contents are outside what Tidy moves.
        #expect(safety(.folder).lock(path: stick.path + "/a", kind: .file, flags: []) == .outsideHome)
    }

    @Test func movesAreCheckedAgainAtTheLastMoment() {
        let s = safety()
        let item = CheckedItem(path: home + "/Movies/a.mov", name: "a.mov", size: 5, isDirectory: false, device: 1,
                               fileID: 42, resolvedParent: home + "/Movies")
        let same = ItemInfo(kind: .file, device: 1, fileID: 42)
        let resolve: (String) -> String = { $0 }
        #expect(s.verify(item, kind: .file, flags: [], info: { _ in same }, resolveParent: resolve) == nil)
        #expect(s.verify(item, kind: .file, flags: [], info: { _ in nil }, resolveParent: resolve) == .gone)
        #expect(s.verify(item, kind: .file, flags: [], info: { _ in ItemInfo(kind: .file, device: 1, fileID: 43) },
                         resolveParent: resolve) == .changedSinceScan)
        #expect(s.verify(item, kind: .file, flags: [], info: { _ in ItemInfo(kind: .file, device: 2, fileID: 42) },
                         resolveParent: resolve) == .changedSinceScan)
        // A folder above it was swapped for a symlink.
        #expect(s.verify(item, kind: .file, flags: [], info: { _ in same }, resolveParent: { _ in "/elsewhere" })
            == .changedSinceScan)
        #expect(s.verify(item, kind: .file, flags: [.insidePackage], info: { _ in same }, resolveParent: resolve)
            == .locked(.insidePackage))
    }

    @Test func trashServiceStillRefusesWhatThePolicyRefuses() {
        let service = TrashService(environment: env, trasher: FolderTrasher(folder: env.trashDirectory!))
        let result = service.moveToTrash([(URL(fileURLWithPath: "/System/Library"), 0), (URL(fileURLWithPath: home), 0)])
        #expect(result.moved.isEmpty)
        #expect(result.failures.count == 2)
    }
}

@Suite("Map volumes")
struct MapVolumeTests {
    @Test func testVolumesParse() {
        let volumes = TestVolumes("/tmp/tidy-test|Fixture HD|startup|2000|600|150|400;/tmp/tidy-test/disks/Stick|Stick|external|64|50;bad;/x|RO|readonly|10|5").list
        #expect(volumes.count == 3)
        #expect(volumes[0].kind == .startup && volumes[0].name == "Fixture HD" && volumes[0].systemBytes == 400)
        #expect(volumes[0].freeForImportantUse == 750)
        #expect(volumes[1].kind == .external && volumes[1].systemBytes == 0)
        #expect(volumes[2].isReadOnly)
    }

    @Test func figuresAddUpToTheDisk() {
        let volume = MapVolume(root: URL(fileURLWithPath: "/"), name: "HD", kind: .startup, total: 1_000, free: 200,
                               freeForImportantUse: 260, systemBytes: 90)
        let figures = VolumeFigures(volume: volume, mapped: 500)
        #expect(figures.mapped == 500)
        #expect(figures.purgeable == 60)
        #expect(figures.other == 240)
        #expect(figures.system == 90)
        #expect(figures.notMapped == 150)
        #expect(figures.mapped + figures.other + figures.purgeable + figures.free == figures.total)
    }

    @Test func figuresNeverGoNegative() {
        // The walk found more than the volume says is used (clones counted elsewhere, a
        // stale figure): mapped is capped and nothing else goes below zero.
        let volume = MapVolume(root: URL(fileURLWithPath: "/V"), name: "V", kind: .external, total: 1_000, free: 400,
                               freeForImportantUse: 700)
        let figures = VolumeFigures(volume: volume, mapped: 900)
        #expect(figures.mapped == 600 && figures.other == 0 && figures.purgeable == 0)
        #expect(figures.mapped + figures.other + figures.purgeable + figures.free == figures.total)
    }

    @Test func firmlinkedPathsShowLikeFinder() {
        let links = Firmlinks("/Applications\tApplications\n/Users\tUsers\n/System/Library/Caches\tSystem/Library/Caches\n/usr/local\tusr/local\n")
        #expect(links.shownPath(forDataRelative: "Users/me/Movies") == "/Users/me/Movies")
        #expect(links.shownPath(forDataRelative: "Users") == "/Users")
        #expect(links.shownPath(forDataRelative: "System/Library/Caches/x") == "/System/Library/Caches/x")
        #expect(links.shownPath(forDataRelative: "usr/local/bin") == "/usr/local/bin")
        #expect(links.shownPath(forDataRelative: ".Spotlight-V100") == "/System/Volumes/Data/.Spotlight-V100")
        #expect(links.shownPath(forDataRelative: "UsersExtra") == "/System/Volumes/Data/UsersExtra")
        #expect(links.shownPath(forDataRelative: "") == "/")
    }

    @Test func theRealFirmlinksFileParses() {
        let links = Firmlinks.system
        #expect(links.links.contains { $0.shown == "/Users" && $0.data == "Users" })
    }
}

@Suite("Map paths")
struct MapPathsTests {
    @Test func plainRootsRoundTrip() {
        let paths = MapPaths(walkRoot: "/tmp/tidy-test/home/")
        #expect(paths.path("") == "/tmp/tidy-test/home")
        #expect(paths.path("Movies/a.mov") == "/tmp/tidy-test/home/Movies/a.mov")
        #expect(paths.id(for: "/tmp/tidy-test/home/Movies/a.mov") == "Movies/a.mov")
        #expect(paths.id(for: "/tmp/tidy-test/home") == "")
        #expect(paths.id(for: "/tmp/tidy-test/homework") == nil)
    }

    @Test func theStartupDiskUsesFirmlinkedPaths() {
        let paths = MapPaths(walkRoot: "/System/Volumes/Data", firmlinks: Firmlinks("/Users\tUsers\n/Applications\tApplications\n"))
        #expect(paths.path("Users/me/Movies") == "/Users/me/Movies")
        #expect(paths.id(for: "/Users/me/Movies") == "Users/me/Movies")
        #expect(paths.path(".Spotlight-V100") == "/System/Volumes/Data/.Spotlight-V100")
        #expect(paths.id(for: "/System/Volumes/Data/.Spotlight-V100") == ".Spotlight-V100")
        #expect(paths.id(for: "/Library/Caches") == nil)
    }
}
