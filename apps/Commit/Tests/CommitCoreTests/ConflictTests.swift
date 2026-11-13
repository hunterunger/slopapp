import Foundation
import Testing
@testable import CommitCore

@Suite struct ConflictParsingTests {
    let simple = "a\n<<<<<<< HEAD\nOURS\n=======\nTHEIRS\n>>>>>>> feature\nc\n"

    @Test func parsesASimpleConflict() throws {
        let file = try #require(ConflictFile.parse(Data(simple.utf8)))
        #expect(file.conflicts.count == 1)
        let c = file.conflicts[0]
        #expect(c.oursLabel == "HEAD")
        #expect(c.theirsLabel == "feature")
        #expect(c.ours == [Data("OURS\n".utf8)])
        #expect(c.theirs == [Data("THEIRS\n".utf8)])
        #expect(c.base == nil)
        #expect(c.startLine == 1)
        #expect(file.segments.count == 3)
        #expect(file.isUTF8)
    }

    @Test func resolvesEachWay() throws {
        let file = try #require(ConflictFile.parse(Data(simple.utf8)))
        func text(_ choice: ConflictChoice?) -> String {
            String(decoding: file.resolved(choice.map { [0: $0] } ?? [:]), as: UTF8.self)
        }
        #expect(text(.ours) == "a\nOURS\nc\n")
        #expect(text(.theirs) == "a\nTHEIRS\nc\n")
        #expect(text(.both) == "a\nOURS\nTHEIRS\nc\n")
        #expect(text(.bothTheirsFirst) == "a\nTHEIRS\nOURS\nc\n")
        #expect(text(.neither) == "a\nc\n")
        #expect(text(nil) == simple) // no choice: markers stay exactly as they were
        #expect(!file.isFullyResolved([:]))
        #expect(file.isFullyResolved([0: .ours]))
    }

    @Test func diff3BaseAndSeveralConflicts() throws {
        let text = """
        top
        <<<<<<< ours
        one
        ||||||| base
        zero
        =======
        uno
        >>>>>>> theirs
        middle
        <<<<<<< ours
        two
        =======
        dos
        >>>>>>> theirs
        end

        """
        let file = try #require(ConflictFile.parse(Data(text.utf8)))
        #expect(file.conflicts.count == 2)
        #expect(file.conflicts[0].baseLabel == "base")
        #expect(file.conflicts[0].base == [Data("zero\n".utf8)])
        #expect(file.conflicts[1].startLine == 9)
        let resolved = String(decoding: file.resolved([0: .base, 1: .theirs]), as: UTF8.self)
        #expect(resolved == "top\nzero\nmiddle\ndos\nend\n")
        // Unresolved second conflict keeps its markers; the first is replaced.
        let partial = String(decoding: file.resolved([0: .ours]), as: UTF8.self)
        #expect(partial.hasPrefix("top\none\nmiddle\n<<<<<<< ours\n"))
        #expect(ConflictMarkers.present(in: Data(partial.utf8)))
    }

    @Test func keepsCRLFAndBytes() throws {
        var data = Data("a\r\n<<<<<<< HEAD\r\nOURS\r\n=======\r\n".utf8)
        data.append(contentsOf: [0xE9, 0x0D, 0x0A]) // "é" in Latin-1, not UTF-8
        data.append(Data(">>>>>>> other\r\nz\r\n".utf8))
        let file = try #require(ConflictFile.parse(data))
        #expect(!file.isUTF8)
        let theirs = file.resolved([0: .theirs])
        #expect(theirs == Data([0x61, 0x0D, 0x0A, 0xE9, 0x0D, 0x0A, 0x7A, 0x0D, 0x0A]))
        #expect(String(decoding: file.resolved([0: .ours]), as: UTF8.self) == "a\r\nOURS\r\nz\r\n")
    }

    @Test func joinsSidesWithoutAFinalNewline() throws {
        // A side whose last line has no newline (the very end of a file), joined with "both".
        let file = ConflictFile(segments: [.conflict(0)], conflicts: [ConflictFile.Conflict(
            oursLabel: "HEAD", theirsLabel: "x", baseLabel: nil, ours: [Data("one".utf8)], base: nil,
            theirs: [Data("two\n".utf8)], markerLines: [Data("<<<<<<< HEAD\n".utf8), Data("=======\n".utf8), Data(">>>>>>> x\n".utf8)],
            startLine: 0)], isUTF8: true)
        #expect(String(decoding: file.resolved([0: .both]), as: UTF8.self) == "one\ntwo\n")
    }

    @Test func ignoresIncompleteAndOtherSizedMarkers() {
        #expect(ConflictFile.parse(Data("a\n<<<<<<< HEAD\nno end\n".utf8)) == nil)
        #expect(ConflictFile.parse(Data("<<<<<<<< eight\nx\n========\ny\n>>>>>>>> eight\n".utf8)) == nil)
        #expect(ConflictFile.parse(Data("plain text\n=======\nnot a conflict\n".utf8)) == nil)
        let ten = "<<<<<<<<<< HEAD\nx\n==========\ny\n>>>>>>>>>> b\n"
        #expect(ConflictFile.parse(Data(ten.utf8), markerSize: 10)?.conflicts.count == 1)
    }

    @Test func conflictKindsFromStatusCodes() {
        #expect(ConflictKind(code: "UU") == .bothModified)
        #expect(ConflictKind(code: "UD") == .deletedByThem)
        #expect(ConflictKind(code: "UD").theirsMissing)
        #expect(!ConflictKind(code: "UD").oursMissing)
        #expect(ConflictKind(code: "DU").oursMissing)
        #expect(ConflictKind(code: "AA") == .bothAdded)
        #expect(ConflictKind(code: "DD").oursMissing && ConflictKind(code: "DD").theirsMissing)
    }

    @Test func mergeToolSettings() {
        #expect(!MergeToolSetting(name: nil).isUsable)
        #expect(MergeToolSetting(name: "opendiff").isUsable)
        #expect(MergeToolSetting(name: "vimdiff").needsTerminal)
        #expect(!MergeToolSetting(name: "vimdiff").isUsable)
    }
}

@Suite struct ConflictResolutionTests {
    /// main and theirs both change line 2 of shared.txt; theirs deletes gone.txt, which main changes.
    func conflictedRepo() throws -> TestRepo {
        let repo = try TestRepo()
        try repo.write("shared.txt", "alpha\nbeta\ngamma\n")
        try repo.write("gone.txt", "keep\n")
        try repo.commitAll("Base")
        try repo.sh("switch", "-q", "-c", "theirs")
        try repo.write("shared.txt", "alpha\nTHEIRS\ngamma\n")
        try repo.sh("rm", "-q", "gone.txt")
        try repo.commitAll("Theirs")
        try repo.sh("switch", "-q", "main")
        try repo.write("shared.txt", "alpha\nOURS\ngamma\n")
        try repo.write("gone.txt", "changed\n")
        try repo.commitAll("Ours")
        try repo.sh("merge", "-q", "theirs", allowFailure: true)
        return repo
    }

    @Test func resolveByChoiceThenUndo() async throws {
        let repo = try conflictedRepo()
        let file = try #require(await repo.repository.conflictFile("shared.txt"))
        let before = try #require(repo.readData("shared.txt"))
        let snapshot = try await repo.repository.snapshotConflict("shared.txt")
        #expect(snapshot.stages.count == 3)
        try await repo.repository.resolveConflict("shared.txt", with: file.resolved([0: .both]))
        #expect(repo.read("shared.txt") == "alpha\nOURS\nTHEIRS\ngamma\n")
        #expect(try await repo.entry("shared.txt").isConflicted == false)
        #expect(try await repo.entry("shared.txt").staged == .modified)

        try await repo.repository.restoreConflict(snapshot)
        #expect(repo.readData("shared.txt") == before)
        #expect(try await repo.entry("shared.txt").isConflicted)
        #expect(try repo.sh("ls-files", "-u", "--", "shared.txt").split(separator: "\n").count == 3)
    }

    @Test func wholeFileSidesAndDeletions() async throws {
        let repo = try conflictedRepo()
        let shared = try await repo.entry("shared.txt")
        try await repo.repository.resolveConflict(shared, takingOurs: false)
        #expect(repo.read("shared.txt") == "alpha\nTHEIRS\ngamma\n")

        let gone = try await repo.entry("gone.txt")
        #expect(gone.conflictKind == .deletedByThem)
        let snapshot = try await repo.repository.snapshotConflict("gone.txt")
        try await repo.repository.resolveConflict(gone, takingOurs: false) // theirs deleted it
        #expect(!repo.exists("gone.txt"))
        #expect(try await repo.status().conflicted.isEmpty)

        try await repo.repository.restoreConflict(snapshot)
        #expect(repo.read("gone.txt") == "changed\n")
        #expect(try await repo.entry("gone.txt").isConflicted)
        try await repo.repository.resolveConflict(try await repo.entry("gone.txt"), takingOurs: true)
        #expect(repo.read("gone.txt") == "changed\n")
        #expect(try await repo.status().conflicted.isEmpty)
    }

    @Test func mergeToolComesFromConfig() async throws {
        let repo = try conflictedRepo()
        #expect(await repo.repository.mergeTool().name == nil)
        try repo.sh("config", "merge.tool", "opendiff")
        #expect(await repo.repository.mergeTool() == MergeToolSetting(name: "opendiff"))
    }

    @Test func mergeToolRunsTheConfiguredCommand() async throws {
        // A stand-in tool that takes theirs, as a real tool would after the person saves.
        let repo = try conflictedRepo()
        try repo.sh("config", "merge.tool", "standin")
        try repo.sh("config", "mergetool.standin.cmd", "cp \"$REMOTE\" \"$MERGED\"")
        try repo.sh("config", "mergetool.standin.trustExitCode", "true")
        try repo.sh("config", "mergetool.keepBackup", "false")
        try await repo.repository.runMergeTool("shared.txt")
        #expect(repo.read("shared.txt") == "alpha\nTHEIRS\ngamma\n")
        #expect(try await repo.entry("shared.txt").isConflicted == false)
    }

    @Test func markerSizeFromAttributes() async throws {
        let repo = try TestRepo()
        try repo.write(".gitattributes", "*.md conflict-marker-size=12\n")
        #expect(await repo.repository.conflictMarkerSize("notes.md") == 12)
        #expect(await repo.repository.conflictMarkerSize("notes.txt") == 7)
    }
}
