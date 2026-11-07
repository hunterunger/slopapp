import Foundation
import Testing
@testable import CrateCore

/// Checks encrypted 7z against the reference 7-Zip, both ways. Opt-in, because 7-Zip isn't
/// part of macOS: `CRATE_7ZZ=/path/to/7zz scripts/test.sh Crate` (or `swift test`).
enum SevenZipTool {
    static let path = ProcessInfo.processInfo.environment["CRATE_7ZZ"].flatMap { $0.isEmpty ? nil : $0 }
}

@Suite(.enabled(if: SevenZipTool.path != nil, "set CRATE_7ZZ to a 7zz binary"))
struct SevenZipInteropTests {
    static var tool: String? { SevenZipTool.path }

    /// Runs 7zz through the shell, reading each argument from a file: `Process` passes
    /// arguments and environment values decomposed (NFD), which changes non-ASCII passwords.
    @discardableResult
    func run(_ arguments: [String], in folder: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        let argumentFolder = TestFolder.make("args")
        var script = "exec \"$TOOL\""
        for (index, argument) in arguments.enumerated() {
            let file = argumentFolder.appendingPathComponent("\(index)")
            try Data(argument.utf8).write(to: file)
            script += " \"$(cat '\(file.path)')\""
        }
        process.arguments = ["-c", script]
        process.environment = ["LANG": "en_US.UTF-8", "TOOL": Self.tool!]
        process.currentDirectoryURL = folder
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func makeTree(_ folder: URL) -> URL {
        let src = folder.appendingPathComponent("tree")
        TestFolder.write("hello", to: src.appendingPathComponent("hello.txt"))
        TestFolder.write("ümlaut", to: src.appendingPathComponent("sub/ünïcode 📦.txt"))
        TestFolder.write(String(repeating: "line of text\n", count: 100_000), to: src.appendingPathComponent("big.txt"))
        var state: UInt64 = 88_172_645_463_325_252
        var bytes = [UInt8](repeating: 0, count: 1_500_000)
        for index in bytes.indices {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            bytes[index] = UInt8(truncatingIfNeeded: state)
        }
        try! Data(bytes).write(to: src.appendingPathComponent("random.bin"))
        FileManager.default.createFile(atPath: src.appendingPathComponent("empty.txt").path, contents: Data())
        try! FileManager.default.createDirectory(at: src.appendingPathComponent("emptydir"), withIntermediateDirectories: true)
        return src
    }

    func sameContents(_ a: URL, _ b: URL) -> Bool {
        let names = ["hello.txt", "sub/ünïcode 📦.txt", "big.txt", "random.bin", "empty.txt"]
        return names.allSatisfy { name in
            (try? Data(contentsOf: a.appendingPathComponent(name))) == (try? Data(contentsOf: b.appendingPathComponent(name)))
        }
    }

    @Test(arguments: [true, false])
    func sevenZipReadsOurs(hideNames: Bool) throws {
        let folder = TestFolder.make("ours\(hideNames)")
        let src = makeTree(folder)
        let result = try ArchiveCreator().create(CreateRequest(sources: [src], folder: folder, name: "ours", format: .sevenZip,
                                                                password: "s3cret ünï", hideNames: hideNames))
        let archive = try #require(result.primary)
        let list = try run(["l", "-slt", "-ps3cret ünï", archive.path], in: folder)
        #expect(list.status == 0, "\(list.output)")
        #expect(list.output.contains("7zAES"), "\(list.output)")
        let wrong = try run(["t", "-pwrong", archive.path], in: folder)
        #expect(wrong.status != 0)
        let test = try run(["t", "-ps3cret ünï", archive.path], in: folder)
        #expect(test.status == 0, "\(test.output)")
        let out = folder.appendingPathComponent("x")
        let extract = try run(["x", "-ps3cret ünï", "-o\(out.path)", archive.path], in: folder)
        #expect(extract.status == 0, "\(extract.output)")
        #expect(sameContents(src, out.appendingPathComponent("tree")))
        if hideNames {
            let blind = try run(["l", "-p", archive.path], in: folder)
            #expect(!blind.output.contains("hello.txt"))
        }
    }

    @Test(arguments: [
        ["-m0=lzma2", "-mhe=on"],
        ["-m0=lzma", "-mhe=on"],
        ["-m0=lzma2", "-mhe=off"],
        ["-m0=ppmd", "-mhe=on"],
        ["-m0=bcj", "-m1=lzma", "-mhe=on"],
        ["-m0=lzma2", "-ms=off", "-mhe=on"],
        ["-m0=copy", "-mhe=on"],
        ["-m0=lzma2", "-mhe=on", "-mhc=off"],
        ["-m0=deflate", "-mhe=on"],
    ])
    func weReadSevenZips(options: [String]) throws {
        let folder = TestFolder.make("theirs")
        let src = makeTree(folder)
        let archive = folder.appendingPathComponent("theirs.7z")
        let made = try run(["a", "-t7z", "-pp4ss wörd"] + options + [archive.path, "tree"], in: folder)
        try #require(made.status == 0, "\(made.output)")
        let source = ArchiveSource(file: archive)
        #expect(try !ArchiveReader.checkPassword("wrong", for: source))
        #expect(try ArchiveReader.checkPassword("p4ss wörd", for: source))
        let listing = try ArchiveReader.list(source, password: "p4ss wörd")
        #expect(listing.entries.contains { $0.path == "tree/sub/ünïcode 📦.txt" })
        let out = try Extractor().extract(source, to: TestFolder.make("theirsout"), options: .init(password: "p4ss wörd"))
        #expect(out.skipped.isEmpty)
        #expect(sameContents(src, try #require(out.primary)), "\(options)")
    }

    @Test func weReadSevenZipVolumes() throws {
        let folder = TestFolder.make("volumes")
        _ = makeTree(folder)
        let made = try run(["a", "-t7z", "-ppw", "-mhe=on", "-v700k", "vol.7z", "tree"], in: folder)
        try #require(made.status == 0, "\(made.output)")
        let source = try VolumeSet.resolve(folder.appendingPathComponent("vol.7z.002"))
        #expect(source.parts.count >= 2)
        let out = try Extractor().extract(source, to: TestFolder.make("volout"), options: .init(password: "pw"))
        #expect(sameContents(folder.appendingPathComponent("tree"), try #require(out.primary)))
    }
}
