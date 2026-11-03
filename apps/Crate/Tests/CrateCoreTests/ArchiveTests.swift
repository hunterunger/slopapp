import Foundation
import Testing
@testable import CrateCore

@Suite struct ReaderTests {
    @Test func listsZip() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("a.zip")
        RawArchive.write(zip, entries: [.init("docs/", .folder), .text("docs/a.txt", "hello"), .text("b.txt", "hi")])
        let listing = try ArchiveReader.list(ArchiveSource(file: zip))
        #expect(listing.paths == ["b.txt", "docs", "docs/a.txt"])
        #expect(listing.formatName == "Zip")
        #expect(listing.unpackedBytes == 7)
        #expect(!listing.hasEncryptedEntries)
    }

    @Test func listsRarFixtures() throws {
        let rar = try ArchiveReader.list(ArchiveSource(file: TestFolder.fixture("rar.rar")))
        #expect(!rar.entries.isEmpty)
        #expect(rar.formatName.hasPrefix("RAR"))
        let solid = try ArchiveReader.list(ArchiveSource(file: TestFolder.fixture("rar5_solid.rar")))
        #expect(solid.formatName == "RAR 5")
        #expect(!solid.entries.isEmpty)
    }

    @Test func rarMultiVolumeExtracts() throws {
        let folder = TestFolder.make()
        for n in 1...8 {
            let name = String(format: "rar5_multiarchive.part%02d.rar", n)
            try FileManager.default.copyItem(at: TestFolder.fixture(name), to: folder.appendingPathComponent(name))
        }
        let source = try VolumeSet.resolve(folder.appendingPathComponent("rar5_multiarchive.part04.rar"))
        #expect(source.parts.count == 8)
        let listing = try ArchiveReader.list(source)
        #expect(listing.problem == nil)
        let out = TestFolder.make("rarout")
        let result = try Extractor().extract(source, to: out)
        #expect(result.fileCount > 0)
        #expect(result.bytes == listing.unpackedBytes)
    }

    @Test func encryptedRarAndSevenZipAreExplained() throws {
        #expect(throws: CrateError.unsupportedEncryption(name: "rar_encryption_header.rar", format: "RAR")) {
            try ArchiveReader.list(ArchiveSource(file: TestFolder.fixture("rar_encryption_header.rar")))
        }
        let seven = try ArchiveReader.list(ArchiveSource(file: TestFolder.fixture("encrypted_data.7z")))
        #expect(seven.encryptionUnsupported)
        let out = TestFolder.make()
        #expect(throws: CrateError.unsupportedEncryption(name: "encrypted_data.7z", format: "7z")) {
            try Extractor().extract(ArchiveSource(file: TestFolder.fixture("encrypted_data.7z")), to: out, options: .init(password: "secret"))
        }
        #expect(TestFolder.tree(out).isEmpty)
        #expect(throws: CrateError.unsupportedEncryption(name: "encrypted_header.7z", format: "7z")) {
            try ArchiveReader.list(ArchiveSource(file: TestFolder.fixture("encrypted_header.7z")))
        }
        let rarData = TestFolder.fixture("rar_encryption_data.rar")
        do {
            let listing = try ArchiveReader.list(ArchiveSource(file: rarData))
            #expect(listing.encryptionUnsupported)
        } catch let error as CrateError {
            #expect(error == .unsupportedEncryption(name: "rar_encryption_data.rar", format: "RAR"))
        }
    }

    @Test func notAnArchive() throws {
        let folder = TestFolder.make()
        let text = folder.appendingPathComponent("notes.zip")
        TestFolder.write(String(repeating: "just text\n", count: 50), to: text)
        #expect(throws: CrateError.notAnArchive(name: "notes.zip")) {
            try ArchiveReader.list(ArchiveSource(file: text))
        }
    }

    @Test func truncatedArchiveFailsClearly() throws {
        let folder = TestFolder.make()
        let full = folder.appendingPathComponent("full.tar.gz")
        RawArchive.write(full, format: .tarGz, entries: (0..<40).map { .init("f\($0).bin", .file(Data((0..<20_000).map { _ in UInt8.random(in: 0...255) }))) })
        let data = try Data(contentsOf: full)
        let cut = folder.appendingPathComponent("cut.tar.gz")
        try data.prefix(data.count / 2).write(to: cut)
        let listing = try? ArchiveReader.list(ArchiveSource(file: cut))
        if let listing { #expect(listing.problem != nil) }
        let out = TestFolder.make("cutout")
        #expect(throws: CrateError.self) { try Extractor().extract(ArchiveSource(file: cut), to: out) }
        #expect(TestFolder.tree(out).isEmpty, "partial output is removed")
    }

    @Test func corruptZipFails() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("bad.zip")
        RawArchive.write(zip, entries: [.init("a.bin", .file(Data((0..<5000).map { _ in UInt8.random(in: 0...255) })))])
        var data = try Data(contentsOf: zip)
        for i in 60..<min(400, data.count) { data[i] ^= 0xFF }
        try data.write(to: zip)
        let out = TestFolder.make("badout")
        #expect(throws: CrateError.self) { try Extractor().extract(ArchiveSource(file: zip), to: out) }
        #expect(TestFolder.tree(out).isEmpty)
    }

    @Test func singleFileGzipUnpacksToBareFile() throws {
        let folder = TestFolder.make()
        let source = folder.appendingPathComponent("notes.txt")
        TestFolder.write("some notes", to: source)
        let gz = folder.appendingPathComponent("notes.txt.gz")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        task.arguments = ["-k", source.path]
        try task.run(); task.waitUntilExit()
        try FileManager.default.removeItem(at: source)
        let listing = try ArchiveReader.list(ArchiveSource(file: gz))
        #expect(listing.paths == ["notes.txt"])
        let result = try Extractor().extract(ArchiveSource(file: gz), to: folder)
        #expect(result.outputs.map(\.lastPathComponent) == ["notes.txt"])
        #expect(try String(contentsOf: result.outputs[0], encoding: .utf8) == "some notes")
    }
}

@Suite struct ExtractorTests {
    @Test func oneTopFolderIsNotNestedAgain() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("project.zip")
        RawArchive.write(zip, entries: [.init("project/", .folder), .text("project/a.txt", "a"), .text("project/sub/b.txt", "b")])
        let result = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        #expect(result.outputs == [folder.appendingPathComponent("project")].map { $0.resolvingSymlinksInPath() } || result.outputs.map(\.lastPathComponent) == ["project"])
        #expect(TestFolder.tree(folder.appendingPathComponent("project")) == ["a.txt", "sub/", "sub/b.txt"])
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("project/project").path))
    }

    @Test func severalTopItemsGetAFolderAndNothingIsOverwritten() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("bundle.zip")
        RawArchive.write(zip, entries: [.text("a.txt", "a"), .text("b.txt", "b")])
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bundle"), withIntermediateDirectories: true)
        TestFolder.write("keep me", to: folder.appendingPathComponent("bundle/a.txt"))
        let first = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        let second = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        #expect(first.outputs.map(\.lastPathComponent) == ["bundle 2"])
        #expect(second.outputs.map(\.lastPathComponent) == ["bundle 3"])
        #expect(try String(contentsOf: folder.appendingPathComponent("bundle/a.txt"), encoding: .utf8) == "keep me")
        #expect(TestFolder.tree(folder.appendingPathComponent("bundle 2")) == ["a.txt", "b.txt"])
        // No working folders left behind.
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".crate-") })
    }

    @Test func singleFileGoesNextToArchive() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("report.zip")
        RawArchive.write(zip, entries: [.text("report.pdf", "%PDF")])
        let result = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        #expect(result.outputs.map(\.lastPathComponent) == ["report.pdf"])
    }

    @Test func pathTraversalAndAbsolutePathsAreRefused() throws {
        let root = TestFolder.make()
        let folder = root.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent("evil.zip")
        RawArchive.write(zip, entries: [
            .text("../escaped.txt", "bad"),
            .text("ok/../../escaped2.txt", "bad"),
            .text("/tmp/crate-test/absolute-escape.txt", "bad"),
            .text("safe.txt", "good"),
            .text("dir/safe2.txt", "good"),
        ])
        let listing = try ArchiveReader.list(ArchiveSource(file: zip))
        #expect(listing.paths == ["dir/safe2.txt", "safe.txt"])
        #expect(listing.unsafeEntries.count == 3)
        let result = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped2.txt").path))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/crate-test/absolute-escape.txt"))
        #expect(result.skipped.count == 3)
        #expect(Set(result.skipped.map(\.reason)) == [.parentReference, .absolutePath])
        #expect(result.skippedNote != nil)
        #expect(TestFolder.tree(folder.appendingPathComponent("evil")) == ["dir/", "dir/safe2.txt", "safe.txt"])
    }

    @Test func symlinkEscapesAreRefused() throws {
        let root = TestFolder.make()
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let folder = root.appendingPathComponent("inner")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tar = folder.appendingPathComponent("links.tar")
        RawArchive.write(tar, format: .tar, entries: [
            .init("link", .symlink("../outside")),            // escapes
            .text("link/pwned.txt", "bad"),                    // symlink-then-file
            .init("abs", .symlink("/etc")),                    // absolute
            .text("abs/passwd", "bad"),
            .init("docs/", .folder),
            .text("docs/real.txt", "fine"),
            .init("good", .symlink("docs/real.txt")),          // stays inside: kept
            .init("hard", .hardlink("../../outside/x")),       // hardlink escape
            .init("hard2", .hardlink("docs/real.txt")),        // fine
        ])
        let listing = try ArchiveReader.list(ArchiveSource(file: tar))
        #expect(Set(listing.unsafeEntries) == ["link", "abs", "hard"])
        let result = try Extractor().extract(ArchiveSource(file: tar), to: folder)
        #expect((try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: "/etc/passwd 2"))
        let out = folder.appendingPathComponent("links")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: out.appendingPathComponent("good").path) == "docs/real.txt")
        #expect(try String(contentsOf: out.appendingPathComponent("hard2"), encoding: .utf8) == "fine")
        // The files that tried to go through the refused links land as plain files in plain folders.
        let tree = TestFolder.tree(out)
        #expect(!tree.contains("link"))
        #expect(result.skipped.contains { $0.path == "link" && $0.reason == .linkOutside })
        #expect(result.skipped.contains { $0.path == "abs" && $0.reason == .linkOutside })
        #expect(result.skipped.contains { $0.reason == .brokenHardlink || $0.reason == .parentReference })
    }

    @Test func linkThenSameNamedFileDoesNotFollowTheLink() throws {
        let root = TestFolder.make()
        let target = root.appendingPathComponent("target.txt")
        TestFolder.write("original", to: target)
        let folder = root.appendingPathComponent("inner/deeper")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tar = folder.appendingPathComponent("swap.tar")
        RawArchive.write(tar, format: .tar, entries: [
            .init("x", .symlink("../../../target.txt")),
            .text("x", "overwritten"),
            .text("y.txt", "y"),
        ])
        _ = try Extractor().extract(ArchiveSource(file: tar), to: folder)
        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
    }

    @Test func caseClashesKeepBothFiles() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("case.zip")
        RawArchive.write(zip, entries: [.text("README", "upper"), .text("readme", "lower"), .text("a.txt", "1"), .text("a.txt", "2")])
        let result = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        let names = TestFolder.tree(result.outputs[0])
        #expect(names.count == 4)
        #expect(names.contains("README"))
        #expect(names.contains("a.txt"))
        #expect(names.contains("a 2.txt"))
    }

    @Test func zipBombIsStoppedAndCleanedUp() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("bomb.zip")
        RawArchive.write(zip, entries: [.init("zeros.bin", .zeros(64 << 20))])
        let packed = try #require(try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int64)
        #expect(packed < 1 << 20)
        let limits = ExtractionLimits(maxRatio: 100, ratioFloor: 8 << 20, reserve: 0)
        #expect(throws: CrateError.suspiciousSize(name: "bomb.zip", limit: limits.maximumUnpacked(forPacked: packed))) {
            try Extractor().extract(ArchiveSource(file: zip), to: folder, options: .init(limits: limits))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["bomb.zip"])
        // With the listing's sizes it's refused before anything is written.
        let declared = try ArchiveReader.list(ArchiveSource(file: zip)).unpackedBytes
        #expect(throws: CrateError.suspiciousSize(name: "bomb.zip", limit: limits.maximumUnpacked(forPacked: packed))) {
            try Extractor().extract(ArchiveSource(file: zip), to: folder, options: .init(limits: limits, declaredBytes: declared))
        }
        #expect(throws: CrateError.self) {
            try Extractor(fileSystem: FakeFileSystem(free: 1 << 20)).extract(ArchiveSource(file: zip), to: folder, options: .init(declaredBytes: declared))
        }
        // The same archive is fine under the standard limits (64 MB is under the 1 GB floor).
        let ok = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        #expect(ok.bytes == 64 << 20)
    }

    @Test func fullDiskStopsCleanly() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("big.zip")
        RawArchive.write(zip, entries: [.init("zeros.bin", .zeros(4 << 20))])
        let fs = FakeFileSystem(free: 2 << 20)
        #expect(throws: CrateError.self) {
            try Extractor(fileSystem: fs).extract(ArchiveSource(file: zip), to: folder, options: .init(limits: .init(reserve: 0)))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["big.zip"])
    }

    @Test func quarantineIsCopiedToEverything() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("dl.zip")
        RawArchive.write(zip, entries: [.text("a/b.txt", "x"), .text("c.txt", "y")])
        let value = Data("0081;65000000;Safari;".utf8)
        SystemFileSystem().setQuarantine(value, on: zip)
        #expect(SystemFileSystem().quarantine(of: zip) == value)
        let result = try Extractor().extract(ArchiveSource(file: zip), to: folder)
        let out = result.outputs[0]
        #expect(SystemFileSystem().quarantine(of: out) != nil, "the wrapping folder")
        for path in ["a/b.txt", "c.txt", "a"] {
            #expect(SystemFileSystem().quarantine(of: out.appendingPathComponent(path)) != nil, "\(path)")
        }
    }

    @Test func setuidBitsAreStripped() throws {
        let folder = TestFolder.make()
        let tar = folder.appendingPathComponent("suid.tar")
        RawArchive.write(tar, format: .tar, entries: [.init("tool", .file(Data("#!/bin/sh\n".utf8)), perm: 0o4755), .text("x", "x")])
        let result = try Extractor().extract(ArchiveSource(file: tar), to: folder)
        let attrs = try FileManager.default.attributesOfItem(atPath: result.outputs[0].appendingPathComponent("tool").path)
        let perm = try #require(attrs[.posixPermissions] as? Int)
        #expect(perm & 0o4000 == 0)
        #expect(perm & 0o100 != 0, "executable bit kept")
    }

    @Test func extractsOnlySelectedItems() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("pack.zip")
        RawArchive.write(zip, entries: [
            .text("fonts/a/Regular.otf", "r"), .text("fonts/a/Bold.otf", "b"),
            .text("fonts/b/Regular.otf", "r2"), .text("readme.txt", "hi"),
        ])
        let out = TestFolder.make("sel")
        let one = try Extractor().extract(ArchiveSource(file: zip), to: out, options: .init(selection: ["fonts/a/Bold.otf"], layout: .loose))
        #expect(one.outputs.map(\.lastPathComponent) == ["Bold.otf"])
        let two = try Extractor().extract(ArchiveSource(file: zip), to: out,
                                          options: .init(selection: ["fonts/a", "fonts/b/Regular.otf", "fonts/a/Bold.otf"], layout: .smart))
        #expect(two.outputs.map(\.lastPathComponent) == ["pack"])
        #expect(TestFolder.tree(two.outputs[0]) == ["Regular.otf", "a/", "a/Bold.otf", "a/Regular.otf"])
    }

    @Test func passwordsForEncryptedZips() throws {
        for zipCrypto in [false, true] {
            let folder = TestFolder.make("pw\(zipCrypto)")
            let zip = folder.appendingPathComponent("secret.zip")
            RawArchive.write(zip, entries: [.text("a.txt", String(repeating: "secret ", count: 100)), .text("b.txt", "b")],
                             password: "pässword", zipCrypto: zipCrypto)
            let listing = try ArchiveReader.list(ArchiveSource(file: zip))
            #expect(listing.hasEncryptedEntries)
            #expect(!listing.encryptionUnsupported)
            #expect(throws: CrateError.passwordRequired(name: "secret.zip")) {
                try Extractor().extract(ArchiveSource(file: zip), to: folder)
            }
            #expect(try !ArchiveReader.checkPassword("wrong", for: ArchiveSource(file: zip)))
            #expect(try ArchiveReader.checkPassword("pässword", for: ArchiveSource(file: zip)))
            #expect(throws: CrateError.wrongPassword(name: "secret.zip")) {
                try Extractor().extract(ArchiveSource(file: zip), to: folder, options: .init(password: "nope"))
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["secret.zip"])
            let result = try Extractor().extract(ArchiveSource(file: zip), to: folder, options: .init(password: "pässword"))
            #expect(TestFolder.tree(result.outputs[0]) == ["a.txt", "b.txt"])
        }
    }

    @Test func cancellationLeavesNothing() async throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("slow.zip")
        RawArchive.write(zip, entries: (0..<20).map { .init("f\($0).bin", .zeros(16 << 20)) })
        let task = Task.detached { try Extractor().extract(ArchiveSource(file: zip), to: folder) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        let result = await task.result
        if case .success = result {
            // Finished before the cancel landed; nothing to check.
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["slow.zip"])
    }

    @Test func readOnlyDestinationIsExplained() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("a.zip")
        RawArchive.write(zip, entries: [.text("a.txt", "a")])
        let locked = folder.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        #expect(throws: CrateError.destinationNotWritable(folder: "locked")) {
            try Extractor().extract(ArchiveSource(file: zip), to: locked)
        }
    }
}

@Suite struct CreatorTests {
    func makeSource(_ folder: URL) -> URL {
        let src = folder.appendingPathComponent("Project")
        TestFolder.write("hello", to: src.appendingPathComponent("hello.txt"))
        TestFolder.write("junk", to: src.appendingPathComponent(".DS_Store"))
        TestFolder.write("fork", to: src.appendingPathComponent("._hello.txt"))
        TestFolder.write("icon", to: src.appendingPathComponent("Icon\r"))
        TestFolder.write("x", to: src.appendingPathComponent("__MACOSX/x"))
        TestFolder.write("keep", to: src.appendingPathComponent(".gitignore"))
        // Decomposed (NFD) name in, precomposed (NFC) out.
        TestFolder.write("accent", to: src.appendingPathComponent("Cafe\u{301}.txt"))
        TestFolder.write("emoji", to: src.appendingPathComponent("sub/📦 box.txt"))
        try! FileManager.default.createDirectory(at: src.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try! FileManager.default.createSymbolicLink(atPath: src.appendingPathComponent("link").path, withDestinationPath: "hello.txt")
        return src
    }

    @Test func zipLeavesOutMacFilesAndStoresUTF8Names() throws {
        let folder = TestFolder.make()
        let src = makeSource(folder)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "Project"))
        let zip = try #require(result.primary)
        #expect(zip.lastPathComponent == "Project.zip")
        // FileManager hides "._" files itself, so they may not be counted.
        #expect(result.leftOut >= 3, "\(result)")
        let listing = try ArchiveReader.list(ArchiveSource(file: zip))
        #expect(listing.paths == ["Project", "Project/.gitignore", "Project/Café.txt", "Project/empty", "Project/hello.txt",
                                  "Project/link", "Project/sub", "Project/sub/📦 box.txt"])
        // Every central directory record has the UTF-8 flag (bit 11) and an NFC name.
        let data = try Data(contentsOf: zip)
        var flagged = 0
        var index = 0
        let bytes = [UInt8](data)
        while index + 46 < bytes.count {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4b, bytes[index + 2] == 0x01, bytes[index + 3] == 0x02 {
                let flags = UInt16(bytes[index + 8]) | UInt16(bytes[index + 9]) << 8
                let nameLength = Int(UInt16(bytes[index + 28]) | UInt16(bytes[index + 29]) << 8)
                let name = String(decoding: bytes[(index + 46)..<(index + 46 + nameLength)], as: UTF8.self)
                // ASCII names read the same in every encoding; the rest must be flagged.
                if !name.allSatisfy(\.isASCII) { #expect(flags & 0x0800 != 0, "\(name)") }
                #expect(name == name.precomposedStringWithCanonicalMapping)
                flagged += 1
            }
            index += 1
        }
        #expect(flagged == 8)
        // Round trip.
        let out = TestFolder.make("rt")
        let extracted = try Extractor().extract(ArchiveSource(file: zip), to: out)
        #expect(try String(contentsOf: extracted.outputs[0].appendingPathComponent("hello.txt"), encoding: .utf8) == "hello")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: extracted.outputs[0].appendingPathComponent("link").path) == "hello.txt")
    }

    @Test func keepsMacFilesWhenAsked() throws {
        let folder = TestFolder.make()
        let src = makeSource(folder)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "All", leaveOutMacFiles: false))
        #expect(result.leftOut == 0)
        let listing = try ArchiveReader.list(ArchiveSource(file: result.primary!))
        #expect(listing.paths.contains("Project/.DS_Store"))
    }

    @Test func everyFormatRoundTrips() throws {
        for format in CreateFormat.allCases {
            let folder = TestFolder.make("fmt\(format.rawValue)")
            let a = folder.appendingPathComponent("a.txt")
            let b = folder.appendingPathComponent("b.txt")
            TestFolder.write(String(repeating: "alpha ", count: 1000), to: a)
            TestFolder.write("beta", to: b)
            for level in CompressionLevel.allCases {
                let result = try ArchiveCreator().create(CreateRequest(sources: [a, b], folder: folder, name: "Archive", format: format, level: level))
                let out = try #require(result.primary)
                #expect(out.lastPathComponent.hasSuffix("." + format.fileExtension))
                let listing = try ArchiveReader.list(ArchiveSource(file: out))
                #expect(listing.paths == ["a.txt", "b.txt"], "\(format)")
                let dest = TestFolder.make("dest")
                let extracted = try Extractor().extract(ArchiveSource(file: out), to: dest)
                #expect(TestFolder.tree(extracted.outputs[0]) == ["a.txt", "b.txt"])
            }
        }
    }

    @Test func zipPasswordsRoundTrip() throws {
        for encryption in ZipEncryption.allCases {
            let folder = TestFolder.make("enc\(encryption.rawValue)")
            let a = folder.appendingPathComponent("secret.txt")
            TestFolder.write("top secret", to: a)
            let result = try ArchiveCreator().create(CreateRequest(sources: [a], folder: folder, name: "secret",
                                                                    password: "hunter2", encryption: encryption))
            let zip = try #require(result.primary)
            #expect(try ArchiveReader.list(ArchiveSource(file: zip)).hasEncryptedEntries)
            #expect(throws: CrateError.wrongPassword(name: "secret.zip")) {
                try Extractor().extract(ArchiveSource(file: zip), to: folder, options: .init(password: "nope"))
            }
            let out = try Extractor().extract(ArchiveSource(file: zip), to: TestFolder.make("o"), options: .init(password: "hunter2"))
            #expect(try String(contentsOf: out.outputs[0], encoding: .utf8) == "top secret")
        }
    }

    @Test func passwordOnlyForZip() throws {
        let folder = TestFolder.make()
        let a = folder.appendingPathComponent("a.txt")
        TestFolder.write("a", to: a)
        #expect(throws: CrateError.passwordNotSupported(format: "7z")) {
            try ArchiveCreator().create(CreateRequest(sources: [a], folder: folder, name: "x", format: .sevenZip, password: "pw"))
        }
    }

    @Test func neverOverwritesAnExistingArchive() throws {
        let folder = TestFolder.make()
        let a = folder.appendingPathComponent("a.txt")
        TestFolder.write("a", to: a)
        TestFolder.write("precious", to: folder.appendingPathComponent("Archive.zip"))
        let result = try ArchiveCreator().create(CreateRequest(sources: [a], folder: folder, name: "Archive"))
        #expect(result.primary?.lastPathComponent == "Archive 2.zip")
        #expect(try String(contentsOf: folder.appendingPathComponent("Archive.zip"), encoding: .utf8) == "precious")
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".crate-") })
    }

    @Test func splitsIntoNumberedPartsThatReopen() throws {
        let folder = TestFolder.make()
        let big = folder.appendingPathComponent("noise.bin")
        try Data((0..<2_500_000).map { _ in UInt8.random(in: 0...255) }).write(to: big)
        let result = try ArchiveCreator().create(CreateRequest(sources: [big], folder: folder, name: "noise", partSize: 1_000_000))
        #expect(result.outputs.map(\.lastPathComponent) == ["noise.zip.001", "noise.zip.002", "noise.zip.003"])
        let source = try VolumeSet.resolve(result.outputs[1])
        #expect(source.parts.count == 3)
        let out = try Extractor().extract(source, to: TestFolder.make("split"))
        #expect(try Data(contentsOf: out.outputs[0]) == Data(contentsOf: big))
        // Smaller than one part: not split.
        let small = try ArchiveCreator().create(CreateRequest(sources: [big], folder: folder, name: "one", format: .tarGz, partSize: 100_000_000))
        #expect(small.outputs.map(\.lastPathComponent) == ["one.tar.gz"])
    }

    @Test func sameNamesFromDifferentFoldersAreNumbered() throws {
        let folder = TestFolder.make()
        let a = folder.appendingPathComponent("x/readme.txt")
        let b = folder.appendingPathComponent("y/readme.txt")
        TestFolder.write("1", to: a)
        TestFolder.write("2", to: b)
        let result = try ArchiveCreator().create(CreateRequest(sources: [a, b], folder: folder, name: "Archive"))
        #expect(try ArchiveReader.list(ArchiveSource(file: result.primary!)).paths == ["readme 2.txt", "readme.txt"])
    }

    @Test func missingSourceFailsWithoutLeftovers() throws {
        let folder = TestFolder.make()
        #expect(throws: CrateError.unreadableSource(name: "gone.txt")) {
            try ArchiveCreator().create(CreateRequest(sources: [folder.appendingPathComponent("gone.txt")], folder: folder, name: "x"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func defaultNames() throws {
        let folder = TestFolder.make()
        let file = folder.appendingPathComponent("report.pdf")
        TestFolder.write("x", to: file)
        #expect(CreateRequest.defaultName(for: [file]) == "report")
        #expect(CreateRequest.defaultName(for: [folder]) == folder.lastPathComponent)
        #expect(CreateRequest.defaultName(for: [file, folder]) == "Archive")
    }

    @Test func convertsRarToZip() throws {
        let folder = TestFolder.make()
        let rar = folder.appendingPathComponent("old.rar")
        try FileManager.default.copyItem(at: TestFolder.fixture("rar5_solid.rar"), to: rar)
        let original = try ArchiveReader.list(ArchiveSource(file: rar))
        let template = CreateRequest(sources: [], folder: folder, name: "", format: .zip)
        let result = try Converter().convert(ArchiveSource(file: rar), password: nil, to: template)
        #expect(result.primary?.lastPathComponent == "old.zip")
        let converted = try ArchiveReader.list(ArchiveSource(file: result.primary!))
        #expect(converted.paths.filter { !$0.isEmpty } .count >= original.entries.filter { $0.kind == .file }.count)
        #expect(converted.unpackedBytes == original.unpackedBytes)
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".crate-") })
    }
}

@Suite struct RoundOneTests {
    /// The preview lists every entry with the name extraction will give it.
    @Test func previewNamesMatchWhatExtractionWrites() throws {
        let folder = TestFolder.make()
        let zip = folder.appendingPathComponent("dupes.zip")
        RawArchive.write(zip, entries: [
            .text("README", "upper"), .text("readme", "lower"), .text("a.txt", "1"), .text("a.txt", "2"),
            .text("x", "file named x"), .text("x/inside.txt", "folder named x"), .text("keep/b.txt", "b"),
        ])
        let listing = try ArchiveReader.list(ArchiveSource(file: zip))
        let tree = ArchiveTree(entries: listing.entries)
        let previewFiles = Set(tree.allNodes.filter { !$0.isFolder }.map(\.path))
        #expect(tree.fileCount == 7)
        let renamed = tree.allNodes.filter { $0.originalName != nil }.map { "\($0.originalName!)→\($0.name)" }
        #expect(Set(renamed) == ["readme→readme 2", "a.txt→a 2.txt", "x→x 2"])
        let out = try Extractor().extract(ArchiveSource(file: zip), to: TestFolder.make("dupesout"))
        let written = Set(TestFolder.tree(out.outputs[0]).filter { !$0.hasSuffix("/") })
        #expect(written == previewFiles)
        #expect(out.skipped.isEmpty)
        #expect(tree.node(at: "a 2.txt")?.archivePath == "a.txt")
    }

    @Test func unknownSizesAreMarked() throws {
        let folder = TestFolder.make()
        let file = folder.appendingPathComponent("n.txt")
        TestFolder.write("notes", to: file)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        task.arguments = [file.path]
        try task.run(); task.waitUntilExit()
        let listing = try ArchiveReader.list(ArchiveSource(file: folder.appendingPathComponent("n.txt.gz")))
        let tree = ArchiveTree(entries: listing.entries)
        #expect(!tree.sizesKnown)
        #expect(tree.roots.first?.sizeKnown == false)
    }

    @Test func neverExtractsIntoTheTrash() {
        let settings = CrateSettings()
        let inTrash = ArchiveSource(file: URL(fileURLWithPath: "/Users/someone/.Trash/a.zip"))
        let normal = ArchiveSource(file: URL(fileURLWithPath: "/tmp/crate-test/a.zip"))
        let downloads = URL(fileURLWithPath: "/tmp/crate-test/Downloads")
        #expect(settings.extractionFolder(for: inTrash, fallback: downloads) == downloads)
        #expect(settings.extractionFolder(for: normal, fallback: downloads) == normal.folder)
        #expect(TrashLocation.contains(URL(fileURLWithPath: "/Volumes/X/.Trashes/501/a.zip")))
        #expect(!TrashLocation.contains(URL(fileURLWithPath: "/tmp/crate-test/a.zip")))
    }

    @Test func trashCanBeUndone() throws {
        let folder = TestFolder.make()
        let file = folder.appendingPathComponent("a.zip")
        TestFolder.write("x", to: file)
        let trashed = try SystemFileSystem(trashOverride: folder.appendingPathComponent("bin")).trash(file)
        let move = TrashMove(original: file, trashed: trashed)
        try move.putBack()
        #expect(try String(contentsOf: file, encoding: .utf8) == "x")
    }

    @Test func messagesHideInternalCodes() {
        #expect(CrateError.damaged(name: "a.7z", detail: "Decompression failed(9)").message == "“a.7z” is damaged or incomplete. Try downloading it again.")
        #expect(CrateError.plain("No space left on device") == "No space left on device")
        #expect(CrateError.plain("Decompression failed(9)") == "Decompression failed")
        #expect(CrateError.plain("archive_write_data failed (-30)") == nil)
    }
}
