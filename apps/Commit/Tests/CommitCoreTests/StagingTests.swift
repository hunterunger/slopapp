import Foundation
import Testing
@testable import CommitCore

/// Hunk and line staging against real git, from the exact bytes of the diff.
@Suite struct StagingTests {
    func unstagedDiff(_ repo: TestRepo, _ path: String, context: Int = 3) async throws -> FileDiff {
        let entry = try await repo.entry(path)
        return try #require(try await repo.repository.diff(for: entry, staged: false, options: DiffOptions(contextLines: context)).file)
    }

    func stagedDiff(_ repo: TestRepo, _ path: String) async throws -> FileDiff {
        let entry = try await repo.entry(path)
        return try #require(try await repo.repository.diff(for: entry, staged: true).file)
    }

    /// Refs of the changed lines whose text is in `texts`.
    func refs(_ file: FileDiff, _ texts: Set<String>) -> Set<LineRef> {
        var out = Set<LineRef>()
        for (h, hunk) in file.hunks.enumerated() {
            for (l, line) in hunk.lines.enumerated() where line.isChange && texts.contains(file.text(of: line)) {
                out.insert(LineRef(hunk: h, line: l))
            }
        }
        return out
    }

    @Test func stagesOneAddedLineOfSeveral() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "one\ntwo\nthree\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "one\nnew A\ntwo\nnew B\nthree\n")
        let file = try await unstagedDiff(repo, "a.txt")
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["new B"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("a.txt"), as: UTF8.self) == "one\ntwo\nnew B\nthree\n")
        #expect(repo.read("a.txt") == "one\nnew A\ntwo\nnew B\nthree\n")
    }

    @Test func stagesOneRemovedLineAndUnstagesIt() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "one\ntwo\nthree\nfour\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "one\nfour\n")
        let file = try await unstagedDiff(repo, "a.txt")
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["three"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("a.txt"), as: UTF8.self) == "one\ntwo\nfour\n")

        // Unstage it again from the staged diff.
        let staged = try await stagedDiff(repo, "a.txt")
        let back = try #require(PatchBuilder.patch(for: staged, selecting: PatchBuilder.allChanges(in: staged), direction: .reverse))
        try await repo.repository.apply(back, cached: true, reverse: true)
        #expect(String(decoding: try repo.indexContent("a.txt"), as: UTF8.self) == "one\ntwo\nthree\nfour\n")
    }

    @Test func unstagesSomeStagedLines() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\nb\nc\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "a\nB\nc\nd\n")
        try repo.sh("add", "a.txt")
        let staged = try await stagedDiff(repo, "a.txt")
        let patch = try #require(PatchBuilder.patch(for: staged, selecting: refs(staged, ["d"]), direction: .reverse))
        try await repo.repository.apply(patch, cached: true, reverse: true)
        #expect(String(decoding: try repo.indexContent("a.txt"), as: UTF8.self) == "a\nB\nc\n")
        #expect(repo.read("a.txt") == "a\nB\nc\nd\n")
    }

    @Test func discardsLinesFromTheWorkingTreeAndUndoes() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "keep\nold\nkeep\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "keep\nnew\nkeep\ndebug print\n")
        let file = try await unstagedDiff(repo, "a.txt")
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["debug print"]), direction: .reverse))
        try await repo.repository.apply(patch, cached: false, reverse: true)
        #expect(repo.read("a.txt") == "keep\nnew\nkeep\n")
        // ⌘Z: apply the same patch forwards.
        try await repo.repository.apply(patch, cached: false, reverse: false)
        #expect(repo.read("a.txt") == "keep\nnew\nkeep\ndebug print\n")
    }

    @Test func crlfFilesRoundTrip() async throws {
        let repo = try TestRepo()
        try repo.write("w.txt", "first\r\nsecond\r\nthird\r\n")
        try repo.commitAll("Start")
        try repo.write("w.txt", "first\r\nSECOND\r\nthird\r\nfourth\r\n")
        let file = try await unstagedDiff(repo, "w.txt")
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["fourth"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(try repo.indexContent("w.txt") == Data("first\r\nsecond\r\nthird\r\nfourth\r\n".utf8))
    }

    @Test func noTrailingNewline() async throws {
        let repo = try TestRepo()
        try repo.write("n.txt", "a\nb\nc")
        try repo.commitAll("Start")
        // Change a middle line of a file without a final newline: stage just that.
        try repo.write("n.txt", "a\nB\nc\nd")
        let file = try await unstagedDiff(repo, "n.txt")
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["b", "B"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("n.txt"), as: UTF8.self) == "a\nB\nc")
        // Then the rest (the end of the file changes).
        let rest = try await unstagedDiff(repo, "n.txt")
        let all = try #require(PatchBuilder.patch(for: rest, selecting: PatchBuilder.allChanges(in: rest), direction: .forward))
        try await repo.repository.apply(all, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("n.txt"), as: UTF8.self) == "a\nB\nc\nd")
    }

    @Test func nonUTF8Bytes() async throws {
        let repo = try TestRepo()
        let latin1: [UInt8] = [0x63, 0x61, 0x66, 0xE9] // "café" in Latin-1
        try repo.write("l.txt", Data(Array("one\n".utf8) + latin1 + [10] + Array("three\n".utf8)))
        try repo.commitAll("Start")
        try repo.write("l.txt", Data(Array("one\n".utf8) + latin1 + Array("!".utf8) + [10] + Array("three\nfour\n".utf8)))
        let file = try await unstagedDiff(repo, "l.txt")
        var selection = Set<LineRef>()
        for (l, line) in file.hunks[0].lines.enumerated() where line.isChange && file.bytes(of: line).contains(0xE9) {
            selection.insert(LineRef(hunk: 0, line: l))
        }
        #expect(selection.count == 2)
        let patch = try #require(PatchBuilder.patch(for: file, selecting: selection, direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(try repo.indexContent("l.txt") == Data(Array("one\n".utf8) + latin1 + Array("!".utf8) + [10] + Array("three\n".utf8)))
    }

    @Test func partOfANewFile() async throws {
        let repo = try TestRepo()
        try repo.write("seed.txt", "x\n")
        try repo.commitAll("Start")
        try repo.write("new.txt", "alpha\nbeta\ngamma\n")
        let file = try await unstagedDiff(repo, "new.txt")
        #expect(file.isNew)
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["alpha", "gamma"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("new.txt"), as: UTF8.self) == "alpha\ngamma\n")
        // Unstage one line of the now-staged new file: it stays a (smaller) new file.
        let staged = try await stagedDiff(repo, "new.txt")
        let back = try #require(PatchBuilder.patch(for: staged, selecting: refs(staged, ["gamma"]), direction: .reverse))
        try await repo.repository.apply(back, cached: true, reverse: true)
        #expect(String(decoding: try repo.indexContent("new.txt"), as: UTF8.self) == "alpha\n")
    }

    @Test func partOfADeletion() async throws {
        let repo = try TestRepo()
        try repo.write("gone.txt", "1\n2\n3\n")
        try repo.commitAll("Start")
        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("gone.txt"))
        let file = try await unstagedDiff(repo, "gone.txt")
        #expect(file.isDeleted)
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["2"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("gone.txt"), as: UTF8.self) == "1\n3\n")
    }

    @Test func selectionInALaterHunkOnly() async throws {
        let repo = try TestRepo()
        let lines = (1...40).map { "line \($0)" }
        try repo.write("m.txt", lines.joined(separator: "\n") + "\n")
        try repo.commitAll("Start")
        var changed = lines
        changed.insert("inserted at top", at: 1)
        changed.insert("inserted near top", at: 2)
        changed[30] = "changed 29"
        changed.append("appended")
        try repo.write("m.txt", changed.joined(separator: "\n") + "\n")
        let file = try await unstagedDiff(repo, "m.txt")
        #expect(file.hunks.count == 3)
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["appended", "changed 29", "line 29"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        var expected = lines
        expected[28] = "changed 29"
        expected.append("appended")
        #expect(String(decoding: try repo.indexContent("m.txt"), as: UTF8.self) == expected.joined(separator: "\n") + "\n")
    }

    /// Random edits and random selections, staged and discarded, checked against a model of
    /// what the result should be.
    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func randomSelectionsMatchTheModel(seed: Int) async throws {
        var rng = SeededGenerator(seed: UInt64(seed))
        let repo = try TestRepo()
        let base = (0..<60).map { "base \($0)" }
        try repo.write("r.txt", base.joined(separator: "\n") + "\n")
        try repo.commitAll("Start")
        var edited: [String] = []
        for (i, line) in base.enumerated() {
            let r = Int.random(in: 0..<10, using: &rng)
            if r == 0 { continue } // delete
            if r == 1 { edited.append("changed \(i)"); continue }
            edited.append(line)
            if r == 2 { edited.append("added after \(i)") }
        }
        try repo.write("r.txt", edited.joined(separator: "\n") + "\n")
        let context = [1, 3][seed % 2]
        let file = try await unstagedDiff(repo, "r.txt", context: context)
        var selection = Set<LineRef>()
        for ref in PatchBuilder.allChanges(in: file) where Bool.random(using: &rng) { selection.insert(ref) }
        guard !selection.isEmpty else { return }

        // Model: walk the old file; in each change block the i-th addition pairs with the
        // i-th removal.
        func blocks(_ hunk: DiffHunk) -> [(context: Int?, removals: [Int], additions: [Int])] {
            var out: [(Int?, [Int], [Int])] = []
            var l = 0
            while l < hunk.lines.count {
                if hunk.lines[l].kind == .context { out.append((l, [], [])); l += 1; continue }
                var r: [Int] = [], a: [Int] = []
                while l < hunk.lines.count, hunk.lines[l].kind != .context {
                    if hunk.lines[l].kind == .removed { r.append(l) } else { a.append(l) }
                    l += 1
                }
                out.append((nil, r, a))
            }
            return out
        }
        func staged(_ file: FileDiff, _ selection: Set<LineRef>, old: [String]) -> [String] {
            var out: [String] = []
            var cursor = 0
            for (h, hunk) in file.hunks.enumerated() {
                let start = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1
                while cursor < start { out.append(old[cursor]); cursor += 1 }
                func sel(_ l: Int) -> Bool { selection.contains(LineRef(hunk: h, line: l)) }
                for block in blocks(hunk) {
                    if let c = block.context { out.append(file.text(of: hunk.lines[c])); cursor += 1; continue }
                    let moving = block.additions.filter(sel)
                    for (i, r) in block.removals.enumerated() {
                        cursor += 1
                        if !sel(r) { out.append(file.text(of: hunk.lines[r])) }
                        if i < moving.count { out.append(file.text(of: hunk.lines[moving[i]])) }
                    }
                    for a in moving.dropFirst(block.removals.count) { out.append(file.text(of: hunk.lines[a])) }
                }
            }
            while cursor < old.count { out.append(old[cursor]); cursor += 1 }
            return out
        }
        let patch = try #require(PatchBuilder.patch(for: file, selecting: selection, direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        let expected = staged(file, selection, old: base)
        #expect(String(decoding: try repo.indexContent("r.txt"), as: UTF8.self) == expected.joined(separator: "\n") + "\n")

        // Discard a random selection of what's left from the working tree.
        let remaining = try await unstagedDiff(repo, "r.txt", context: context)
        guard remaining.changedLineCount > 0 else { return }
        var discard = Set<LineRef>()
        for ref in PatchBuilder.allChanges(in: remaining) where Bool.random(using: &rng) { discard.insert(ref) }
        guard !discard.isEmpty, let reverse = PatchBuilder.patch(for: remaining, selecting: discard, direction: .reverse) else { return }
        try await repo.repository.apply(reverse, cached: false, reverse: true)
        // Model for discarding: selected changes are undone, the rest stay; the i-th restored
        // removal goes before the i-th addition.
        let indexLines = expected
        var worktree: [String] = []
        var cursor = 0
        for (h, hunk) in remaining.hunks.enumerated() {
            let start = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1
            while cursor < start { worktree.append(indexLines[cursor]); cursor += 1 }
            func sel(_ l: Int) -> Bool { discard.contains(LineRef(hunk: h, line: l)) }
            for block in blocks(hunk) {
                if let c = block.context { worktree.append(remaining.text(of: hunk.lines[c])); cursor += 1; continue }
                cursor += block.removals.count
                let moving = block.removals.filter(sel)
                for (i, a) in block.additions.enumerated() {
                    if i < moving.count { worktree.append(remaining.text(of: hunk.lines[moving[i]])) }
                    if !sel(a) { worktree.append(remaining.text(of: hunk.lines[a])) }
                }
                for r in moving.dropFirst(block.additions.count) { worktree.append(remaining.text(of: hunk.lines[r])) }
            }
        }
        while cursor < indexLines.count { worktree.append(indexLines[cursor]); cursor += 1 }
        #expect(repo.read("r.txt") == worktree.joined(separator: "\n") + "\n")
    }

    @Test func replacingALineInABlockKeepsItsPlace() async throws {
        let repo = try TestRepo()
        try repo.write("p.txt", "a\nx\ny\nz\n")
        try repo.commitAll("Start")
        try repo.write("p.txt", "a\nX\nY\nZ\n")
        let file = try await unstagedDiff(repo, "p.txt")
        let patch = try #require(PatchBuilder.patch(for: file, selecting: refs(file, ["x", "X", "z", "Z"]), direction: .forward))
        try await repo.repository.apply(patch, cached: true, reverse: false)
        #expect(String(decoding: try repo.indexContent("p.txt"), as: UTF8.self) == "a\nX\ny\nZ\n")
        // Discard Y (restoring y) from the working tree.
        let rest = try await unstagedDiff(repo, "p.txt")
        let discard = try #require(PatchBuilder.patch(for: rest, selecting: refs(rest, ["y", "Y"]), direction: .reverse))
        try await repo.repository.apply(discard, cached: false, reverse: true)
        #expect(repo.read("p.txt") == "a\nX\ny\nZ\n")
    }

    @Test func binaryFilesHaveNoLinePatches() async throws {
        let repo = try TestRepo()
        try repo.write("b.bin", Data([0, 1, 2, 3, 0, 255]))
        try repo.commitAll("Start")
        try repo.write("b.bin", Data([0, 1, 2, 3, 0, 255, 7, 7]))
        let entry = try await repo.entry("b.bin")
        let result = try await repo.repository.diff(for: entry, staged: false)
        let file = try #require(result.file)
        #expect(file.isBinary)
        #expect(result.oldSize == 6 && result.newSize == 8)
        #expect(PatchBuilder.patch(for: file, selecting: [LineRef(hunk: 0, line: 0)], direction: .forward) == nil)
    }
}

/// SplitMix64: deterministic randomness for the model tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
