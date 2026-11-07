import Foundation
import Testing
@testable import CrateCore

@Suite struct SplitJoinTests {
    func randomFile(_ url: URL, size: Int) -> Data {
        var state: UInt64 = 0xDEAD_BEEF_CAFE_F00D
        var bytes = [UInt8](repeating: 0, count: size)
        for index in bytes.indices {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            bytes[index] = UInt8(truncatingIfNeeded: state)
        }
        let data = Data(bytes)
        try! data.write(to: url)
        return data
    }

    @Test func splitThenJoinGivesTheSameBytes() throws {
        let folder = TestFolder.make()
        let movie = folder.appendingPathComponent("movie.mkv")
        let data = randomFile(movie, size: 1_050_000)
        let parts = try FileSplitter.split(movie, partSize: 400_000)
        #expect(parts.map(\.lastPathComponent) == ["movie.mkv.001", "movie.mkv.002", "movie.mkv.003"])
        #expect(try Data(contentsOf: parts[2]).count == 250_000)
        // The original stays; joining never overwrites it.
        let joined = try FileSplitter.join(parts)
        #expect(joined.lastPathComponent == "movie 2.mkv")
        #expect(try Data(contentsOf: joined) == data)
        #expect(try Data(contentsOf: movie) == data)
        // Joining from any part works through VolumeSet.
        let set = try VolumeSet.resolve(parts[1])
        #expect(try Data(contentsOf: try FileSplitter.join(set.parts, in: TestFolder.make("j"))) == data)
    }

    @Test func splittingTwiceNumbersTheSecondSet() throws {
        let folder = TestFolder.make()
        let file = folder.appendingPathComponent("a.bin")
        _ = randomFile(file, size: 300_000)
        _ = try FileSplitter.split(file, partSize: 100_000)
        let second = try FileSplitter.split(file, partSize: 100_000)
        #expect(second.first?.lastPathComponent == "a 2.bin.001")
    }

    @Test func splitRules() throws {
        let folder = TestFolder.make()
        let file = folder.appendingPathComponent("small.txt")
        TestFolder.write("tiny", to: file)
        #expect(throws: CrateError.partTooSmall(minimum: FileSplitter.minimumPartSize)) {
            try FileSplitter.split(file, partSize: 10)
        }
        #expect(throws: CrateError.nothingToSplit(name: "small.txt")) {
            try FileSplitter.split(file, partSize: 1_000_000)
        }
        #expect(throws: CrateError.notASplitSet(name: "small.txt")) { try FileSplitter.join([file]) }
        #expect(FileSplitter.isNumberedSet(URL(fileURLWithPath: "/x/a.zip.001")))
        #expect(!FileSplitter.isNumberedSet(URL(fileURLWithPath: "/x/a.part1.rar")))
    }

    @Test func splitArchiveStillOpens() throws {
        let folder = TestFolder.make()
        let src = folder.appendingPathComponent("noise.bin")
        let data = randomFile(src, size: 600_000)
        let zip = try #require(try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "n", level: .none)).primary)
        let parts = try FileSplitter.split(zip, partSize: 250_000)
        let out = try Extractor().extract(try VolumeSet.resolve(parts[0]), to: TestFolder.make("o"))
        #expect(try Data(contentsOf: try #require(out.primary)) == data)
    }
}

@Suite struct SavedPasswordTests {
    @Test func remembersNewestFirstWithoutDuplicates() {
        let saved = SavedPasswords(store: MemoryPasswordStore())
        saved.remember("one")
        saved.remember("two")
        saved.remember("one")
        saved.remember("")
        #expect(saved.all == ["one", "two"])
        saved.forgetAll()
        #expect(saved.all.isEmpty)
    }

    @Test func findsTheOneThatOpensTheArchive() throws {
        let folder = TestFolder.make()
        let a = folder.appendingPathComponent("a.txt")
        TestFolder.write("secret", to: a)
        let zip = try #require(try ArchiveCreator().create(CreateRequest(sources: [a], folder: folder, name: "z", password: "right")).primary)
        let seven = try #require(try ArchiveCreator().create(CreateRequest(sources: [a], folder: folder, name: "s", format: .sevenZip,
                                                                            password: "right")).primary)
        let saved = SavedPasswords(store: MemoryPasswordStore(["wrong1", "right", "wrong2"]))
        #expect(saved.find(for: ArchiveSource(file: zip)) == "right")
        #expect(saved.all.first == "right")
        #expect(saved.find(for: ArchiveSource(file: seven)) == "right")
        #expect(SavedPasswords(store: MemoryPasswordStore(["nope"])).find(for: ArchiveSource(file: zip)) == nil)
    }

    @Test func fileStoreRoundTrips() throws {
        let url = TestFolder.make().appendingPathComponent("passwords.json")
        let saved = SavedPasswords(store: FilePasswordStore(url: url))
        saved.remember("pässword")
        #expect(SavedPasswords(store: FilePasswordStore(url: url)).all == ["pässword"])
    }

    @Test func settingsRememberRecentFolders() {
        var settings = CrateSettings()
        for name in ["a", "b", "c", "d", "e", "f", "b"] {
            settings.noteRecentFolder(URL(fileURLWithPath: "/tmp/\(name)"))
        }
        #expect(settings.recentFolders == ["/tmp/b", "/tmp/f", "/tmp/e", "/tmp/d", "/tmp/c"])
        let decoded = try? JSONDecoder().decode(CrateSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(!CrateSettings().rememberPasswords)
    }
}
