import Foundation
import Testing
@testable import CrateCore

@Suite struct ArchiveTypesTests {
    @Test func recognisesArchivesAndParts() {
        for name in ["a.zip", "a.7z", "a.RAR", "a.tar.gz", "a.tgz", "a.tar.xz", "a.bz2", "a.7z.001", "a.r00", "a.z01", "a.part2.rar", "a.001"] {
            #expect(ArchiveTypes.isArchive(name: name), "\(name)")
        }
        for name in ["a.txt", "a.pdf", "folder", "a.docx", "a.jar", "a.dmg"] {
            #expect(!ArchiveTypes.isArchive(name: name), "\(name)")
        }
        #expect(ArchiveTypes.isArchive(name: "a.jar", explicitOpen: true))
        #expect(ArchiveTypes.isArchive(name: "a.docx", explicitOpen: true))
    }

    @Test func baseNames() {
        #expect(ArchiveTypes.baseName(of: "photos.zip") == "photos")
        #expect(ArchiveTypes.baseName(of: "photos.tar.gz") == "photos")
        #expect(ArchiveTypes.baseName(of: "photos.TAR.XZ") == "photos")
        #expect(ArchiveTypes.baseName(of: "notes.txt.gz") == "notes.txt")
        #expect(ArchiveTypes.baseName(of: "big.7z.001") == "big")
        #expect(ArchiveTypes.baseName(of: "movie.part01.rar") == "movie")
        #expect(ArchiveTypes.baseName(of: "movie.r00") == "movie")
        #expect(ArchiveTypes.baseName(of: "site.z01") == "site")
        #expect(ArchiveTypes.baseName(of: "raw.003") == "raw")
        #expect(ArchiveTypes.baseName(of: "v1.2.zip") == "v1.2")
        #expect(ArchiveTypes.baseName(of: ".zip") == "Archive")
    }
}

@Suite struct VolumeSetTests {
    let folder = URL(fileURLWithPath: "/tmp/crate-test/sets")

    func resolve(_ name: String, _ siblings: [String]) throws -> [String] {
        try VolumeSet.resolve(name: name, in: folder, siblings: Set(siblings)).parts.map(\.lastPathComponent)
    }

    @Test func numberedPartsFromAnyPart() throws {
        let names = ["big.7z.001", "big.7z.002", "big.7z.003", "other.txt"]
        #expect(try resolve("big.7z.002", names) == ["big.7z.001", "big.7z.002", "big.7z.003"])
        let source = try VolumeSet.resolve(name: "big.7z.003", in: folder, siblings: Set(names))
        #expect(source.baseName == "big")
        #expect(source.name == "big.7z.001 (3 parts)")
    }

    @Test func numberedGapNamesTheMissingPart() {
        #expect(throws: CrateError.missingPart(archive: "big.zip", part: "big.zip.002")) {
            try resolve("big.zip.003", ["big.zip.001", "big.zip.003"])
        }
        #expect(throws: CrateError.missingPart(archive: "big.zip", part: "big.zip.001")) {
            try resolve("big.zip.002", ["big.zip.002"])
        }
    }

    @Test func singleNumberedFileIsJustAFile() throws {
        #expect(try resolve("x.001", ["x.001"]) == ["x.001"])
    }

    @Test func rarParts() throws {
        let names = (1...8).map { String(format: "m.part%02d.rar", $0) }
        #expect(try resolve("m.part05.rar", names) == names)
        #expect(throws: CrateError.missingPart(archive: "m.rar", part: "m.part03.rar")) {
            try resolve("m.part01.rar", names.filter { $0 != "m.part03.rar" })
        }
        // Unpadded numbering.
        #expect(try resolve("n.part1.rar", ["n.part1.rar", "n.part2.rar"]) == ["n.part1.rar", "n.part2.rar"])
    }

    @Test func oldStyleRar() throws {
        let names = ["old.rar", "old.r00", "old.r01"]
        #expect(try resolve("old.r01", names) == names)
        #expect(try resolve("old.rar", names) == names)
        #expect(try resolve("solo.rar", ["solo.rar"]) == ["solo.rar"])
        #expect(throws: CrateError.missingPart(archive: "old.rar", part: "old.rar")) {
            try resolve("old.r00", ["old.r00"])
        }
    }

    @Test func spannedZip() throws {
        let names = ["s.z01", "s.z02", "s.zip"]
        #expect(try resolve("s.z02", names) == names)
        let source = try VolumeSet.resolve(name: "s.z01", in: folder, siblings: Set(names))
        #expect(source.displayURL.lastPathComponent == "s.zip")
        #expect(try resolve("plain.zip", ["plain.zip"]) == ["plain.zip"])
        #expect(throws: CrateError.missingPart(archive: "s.zip", part: "s.zip")) {
            try resolve("s.z01", ["s.z01"])
        }
    }

    @Test func caseInsensitiveSiblings() throws {
        #expect(try resolve("A.7Z.001", ["A.7Z.001", "a.7z.002"]) == ["A.7Z.001", "a.7z.002"])
    }
}

@Suite struct NamingTests {
    @Test func candidates() {
        #expect(Naming.candidate("photos", number: 1, isFolder: true) == "photos")
        #expect(Naming.candidate("photos", number: 2, isFolder: true) == "photos 2")
        #expect(Naming.candidate("a.zip", number: 3, isFolder: false) == "a 3.zip")
        #expect(Naming.candidate("a.tar.gz", number: 2, isFolder: false) == "a 2.tar.gz")
        #expect(Naming.candidate("v1.2", number: 2, isFolder: true) == "v1.2 2")
        #expect(Naming.candidate(".hidden", number: 2, isFolder: false) == ".hidden 2")
    }

    @Test func moveIntoPlaceNeverReplaces() throws {
        let folder = TestFolder.make()
        TestFolder.write("old", to: folder.appendingPathComponent("a.txt"))
        TestFolder.write("new", to: folder.appendingPathComponent("tmp1"))
        TestFolder.write("newer", to: folder.appendingPathComponent("tmp2"))
        let first = try Naming.moveIntoPlace(folder.appendingPathComponent("tmp1"), named: "a.txt", in: folder, isFolder: false)
        let second = try Naming.moveIntoPlace(folder.appendingPathComponent("tmp2"), named: "a.txt", in: folder, isFolder: false)
        #expect(first.lastPathComponent == "a 2.txt")
        #expect(second.lastPathComponent == "a 3.txt")
        #expect(try String(contentsOf: folder.appendingPathComponent("a.txt"), encoding: .utf8) == "old")
    }

    @Test func trashOverrideMovesIntoFolder() throws {
        let folder = TestFolder.make()
        let file = folder.appendingPathComponent("a.zip")
        TestFolder.write("x", to: file)
        let trash = folder.appendingPathComponent("trash")
        try SystemFileSystem(trashOverride: trash).trash(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("a.zip").path))
    }

    @Test func ledgerCleansOnlyEarlierLeftovers() throws {
        let folder = TestFolder.make()
        let leftover = folder.appendingPathComponent(".crate-old")
        let unrelated = folder.appendingPathComponent("keep")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("ledger.txt")
        try [leftover.path, unrelated.path].joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        let ledger = WorkFolderLedger()
        ledger.configure(file: file)
        let inUse = folder.appendingPathComponent(".crate-now")
        try FileManager.default.createDirectory(at: inUse, withIntermediateDirectories: true)
        ledger.add(inUse)
        ledger.cleanUpLeftovers()
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path), "only .crate- folders")
        #expect(FileManager.default.fileExists(atPath: inUse.path), "never one in use now")
        #expect(try String(contentsOf: file, encoding: .utf8) == inUse.path)
    }
}

@Suite struct RoutingTests {
    let dir = URL(fileURLWithPath: "/tmp/crate-test/route")
    func u(_ n: String) -> URL { dir.appendingPathComponent(n) }
    let noFolders: (URL) -> Bool = { $0.pathExtension.isEmpty }

    @Test func oneArchiveBrowses() {
        #expect(Router.route([u("a.zip")], extractRightAway: false, isFolder: noFolders) == .browse(u("a.zip")))
        #expect(Router.route([u("a.zip")], extractRightAway: true, isFolder: noFolders) == .extract([u("a.zip")]))
    }

    @Test func severalArchivesExtract() {
        #expect(Router.route([u("a.zip"), u("b.7z")], extractRightAway: false, isFolder: noFolders) == .extract([u("a.zip"), u("b.7z")]))
    }

    @Test func partsOfOneSetCountOnce() {
        let parts = [u("m.part1.rar"), u("m.part2.rar"), u("m.part3.rar")]
        #expect(Router.route(parts, extractRightAway: false, isFolder: noFolders) == .browse(u("m.part1.rar")))
        #expect(Router.route([u("b.7z.001"), u("b.7z.002")], extractRightAway: false, isFolder: noFolders) == .browse(u("b.7z.001")))
    }

    @Test func anythingElseCreates() {
        #expect(Router.route([u("a.zip"), u("notes.txt")], extractRightAway: false, isFolder: noFolders) == .create([u("a.zip"), u("notes.txt")]))
        #expect(Router.route([u("Folder")], extractRightAway: false, isFolder: noFolders) == .create([u("Folder")]))
        #expect(Router.route([u("a.docx")], extractRightAway: false, isFolder: noFolders) == .create([u("a.docx")]))
        #expect(Router.route([u("a.docx")], extractRightAway: false, explicitOpen: true, isFolder: noFolders) == .browse(u("a.docx")))
        #expect(Router.route([], extractRightAway: false) == nil)
    }

    @Test func settingsAndOption() {
        var settings = CrateSettings()
        #expect(!settings.extractsRightAway(optionHeld: false))
        #expect(settings.extractsRightAway(optionHeld: true))
        settings.openBehavior = .extract
        #expect(settings.extractsRightAway(optionHeld: false))
        #expect(!settings.extractsRightAway(optionHeld: true))
    }

    @Test func settingsDecodeWithMissingKeys() throws {
        let decoded = try JSONDecoder().decode(CrateSettings.self, from: Data(#"{"revealAfterExtracting":true}"#.utf8))
        #expect(decoded.revealAfterExtracting)
        #expect(decoded.destination == .nextToArchive)
        var settings = CrateSettings()
        settings.destination = .folder("/tmp/x")
        let round = try JSONDecoder().decode(CrateSettings.self, from: JSONEncoder().encode(settings))
        #expect(round == settings)
    }
}

@Suite struct TreeTests {
    @Test func buildsFoldersFromPaths() {
        let tree = ArchiveTree(entries: [
            ArchiveEntryInfo(path: "b/z.txt", kind: .file, size: 10),
            ArchiveEntryInfo(path: "b/a/1.txt", kind: .file, size: 5),
            ArchiveEntryInfo(path: "c.txt", kind: .file, size: 1),
            ArchiveEntryInfo(path: "a", kind: .directory),
            ArchiveEntryInfo(path: "file10.txt", kind: .file, size: 1),
            ArchiveEntryInfo(path: "file9.txt", kind: .file, size: 1),
        ])
        #expect(tree.roots.map(\.name) == ["a", "b", "c.txt", "file9.txt", "file10.txt"])
        let b = tree.node(at: "b")!
        #expect(b.isFolder)
        #expect(b.size == 15)
        #expect(b.itemCount == 3)
        #expect(b.children!.map(\.name) == ["a", "z.txt"])
        #expect(tree.fileCount == 5)
        #expect(tree.folderCount == 3)
        #expect(tree.totalBytes == 18)
    }

    @Test func filterKeepsAncestors() {
        let tree = ArchiveTree(entries: [
            ArchiveEntryInfo(path: "docs/Résumé.pdf", kind: .file, size: 3),
            ArchiveEntryInfo(path: "docs/other.txt", kind: .file, size: 1),
            ArchiveEntryInfo(path: "img/logo.png", kind: .file, size: 2),
        ])
        let filtered = tree.filtered("resume")
        #expect(filtered.roots.map(\.name) == ["docs"])
        #expect(filtered.roots[0].children!.map(\.name) == ["Résumé.pdf"])
        #expect(filtered.fileCount == 1)
        #expect(tree.filtered("  ").roots.count == 2)
    }

    @Test func largeTreesBuildQuickly() {
        let entries = (0..<20_000).map { ArchiveEntryInfo(path: "d\($0 % 50)/sub\($0 % 7)/file\($0).txt", kind: .file, size: 100) }
        let start = Date()
        let tree = ArchiveTree(entries: entries)
        #expect(tree.fileCount == 20_000)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
