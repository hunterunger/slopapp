import Foundation
import Testing
@testable import CommitCore

/// The research doc's budgets that the core can measure. Release figures are the budgets;
/// `swift test` builds debug, which is several times slower, so debug bounds are looser.
/// Run `swift test -c release --filter Performance` for the real numbers. Fixture tests
/// skip when /tmp/commit-fixtures hasn't been built (Tests/Fixtures/make-fixtures.sh --big).
@Suite(.serialized) struct PerformanceTests {
    /// A synthetic history shaped like the `big` fixture: one main line, ~7,000 topic
    /// branches forking off and merging back, newest first.
    static func syntheticHistory(commits: Int) -> [(ObjectID, [ObjectID])] {
        var rng = SeededGenerator(seed: 7)
        func id(_ n: Int) -> ObjectID { ObjectID(w0: UInt64(n) &* 0x9E3779B97F4A7C15, w1: UInt64(n), w2: 0, w3: 0, length: 40) }
        // Build oldest-first, then reverse.
        var rows: [(ObjectID, [ObjectID])] = [(id(0), [])]
        var main = 0
        var active: [Int] = []
        for n in 1..<commits {
            let r = Double(rng.next() % 1000) / 1000
            if r < 0.085, !active.isEmpty {
                let tip = active.remove(at: Int(rng.next() % UInt64(active.count)))
                rows.append((id(n), [id(main), id(tip)])); main = n
            } else if r < 0.16 {
                rows.append((id(n), [id(main)])); active.append(n)
            } else if r < 0.5, !active.isEmpty {
                let i = Int(rng.next() % UInt64(active.count))
                rows.append((id(n), [id(active[i])])); active[i] = n
            } else {
                rows.append((id(n), [id(main)])); main = n
            }
        }
        return rows.reversed()
    }

    @Test func laneLayoutOf100kRows() {
        let rows = Self.syntheticHistory(commits: 100_000)
        var lanes = 0
        let ms = medianMillis(runs: 3) {
            var layout = GraphLayout()
            layout.reserve(rows.count)
            for (id, parents) in rows { layout.append(id: id, parents: parents) }
            lanes = layout.maxLanes
        }
        print("COMMIT_PERF lane_layout_100k_ms=\(String(format: "%.1f", ms)) max_lanes=\(lanes)")
        #expect(ms < budget(release: 50, debug: 1500))
    }

    @Test func parsingA100kRowLog() {
        let rows = Self.syntheticHistory(commits: 100_000)
        var text = Data()
        text.reserveCapacity(rows.count * 160)
        for (i, (id, parents)) in rows.enumerated() {
            let fields = [id.hex, parents.map(\.hex).joined(separator: " "), ["Ada", "Grace", "Alan"][i % 3], "x@example.com",
                          "\(1_700_000_000 + i)", i % 500 == 0 ? "refs/heads/b\(i)" : "", "Change number \(i) on the main line"]
            text.append(Data(fields.joined(separator: "\u{1f}").utf8))
            text.append(0)
        }
        var count = 0
        let ms = medianMillis(runs: 3) {
            var parser = LogParser()
            count = 0
            var offset = 0
            while offset < text.count { // 64 KB pipe reads
                let end = min(text.count, offset + 65_536)
                count += parser.feed(text[offset..<end]).count
                offset = end
            }
            count += parser.finish().count
        }
        print("COMMIT_PERF log_parse_100k_ms=\(String(format: "%.1f", ms)) bytes=\(text.count)")
        #expect(count == 100_000)
        #expect(ms < budget(release: 400, debug: 4000))
    }

    @Test func parsingAn8MBDiff() {
        var text = "diff --git a/huge.txt b/huge.txt\nindex 1111111..2222222 100644\n--- a/huge.txt\n+++ b/huge.txt\n"
        var hunks: [String] = []
        hunks.reserveCapacity(30_000)
        for i in stride(from: 0, to: 200_000, by: 7) {
            hunks.append("@@ -\(i + 1),1 +\(i + 1),1 @@\n-line \(i) of a very long file\n+line \(i) of a very long file (edited)\n")
        }
        text += hunks.joined()
        let data = Data(text.utf8)
        var lines = 0
        let ms = medianMillis(runs: 3) {
            lines = DiffParser.parseSingle(data)?.lineCount ?? 0
        }
        print("COMMIT_PERF diff_parse_ms=\(String(format: "%.1f", ms)) bytes=\(data.count) lines=\(lines)")
        #expect(lines == 57_144)
        #expect(ms < budget(release: 150, debug: 2500))
    }

    @Test func firstHistoryPageOfTheBigFixture() async throws {
        guard let big = fixture("big") else { return }
        let repository = Repository(location: RepositoryLocation(root: big, gitDirectory: big.appendingPathComponent(".git")),
                                    runner: fixtureRunner())
        let clock = ContinuousClock()
        let start = clock.now
        var parser = LogParser()
        var layout = GraphLayout()
        var rows = 0
        var firstPage: Duration?
        for try await chunk in repository.history(scope: .current(upstream: nil)) {
            for row in parser.feed(chunk) {
                layout.append(id: row.id, parents: row.parents)
                rows += 1
            }
            if rows >= 300, firstPage == nil { firstPage = clock.now - start }
        }
        for row in parser.finish() { layout.append(id: row.id, parents: row.parents); rows += 1 }
        let total = clock.now - start
        let first = try #require(firstPage)
        print("COMMIT_PERF big_first_300_rows_ms=\(String(format: "%.0f", millis(first))) big_all_rows_ms=\(String(format: "%.0f", millis(total))) rows=\(rows) max_lanes=\(layout.maxLanes)")
        #expect(millis(first) < budget(release: 300, debug: 1500))
        #expect(millis(total) < budget(release: 1500, debug: 10000))
    }

    @Test func statusOfTheWideFixture() async throws {
        guard let wide = fixture("wide") else { return }
        let repository = Repository(location: RepositoryLocation(root: wide, gitDirectory: wide.appendingPathComponent(".git")),
                                    runner: fixtureRunner())
        _ = try await repository.status() // warm the file system cache
        let clock = ContinuousClock()
        var times: [Double] = []
        var status = WorkingTreeStatus()
        for _ in 0..<3 {
            let start = clock.now
            status = try await repository.status()
            times.append(millis(clock.now - start))
        }
        let median = times.sorted()[1]
        print("COMMIT_PERF wide_status_ms=\(String(format: "%.0f", median)) entries=\(status.entries.count)")
        #expect(status.entries.contains { $0.path == "node_modules/" })
        #expect(median < 300)
    }

    @Test func branchesOfTheBigFixture() async throws {
        guard let big = fixture("big") else { return }
        let repository = Repository(location: RepositoryLocation(root: big, gitDirectory: big.appendingPathComponent(".git")),
                                    runner: fixtureRunner())
        let clock = ContinuousClock()
        let start = clock.now
        let refs = try await repository.refs()
        let loaded = millis(clock.now - start)
        let filterMs = medianMillis(runs: 5) { _ = RefList.filter(refs.local, "b12") }
        print("COMMIT_PERF big_refs_ms=\(String(format: "%.0f", loaded)) branches=\(refs.local.count) filter_ms=\(String(format: "%.2f", filterMs))")
        #expect(refs.local.count > 7000)
        #expect(loaded < 500)
        #expect(filterMs < budget(release: 50, debug: 150))
    }

    @Test func hugeDiffOfTheBigFixture() async throws {
        guard let big = fixture("big") else { return }
        let repository = Repository(location: RepositoryLocation(root: big, gitDirectory: big.appendingPathComponent(".git")),
                                    runner: fixtureRunner())
        let entry = try #require(try await repository.status().entries.first { $0.path == "huge.txt" })
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await repository.diff(for: entry, staged: false)
        let ms = millis(clock.now - start)
        print("COMMIT_PERF huge_diff_ms=\(String(format: "%.0f", ms)) changed=\(result.file?.changedLineCount ?? 0)")
        #expect(result.file?.changedLineCount == 57_144)
        #expect(ms < budget(release: 500, debug: 2500))
    }

    @Test func stagingALineIsQuick() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", (0..<200).map { "line \($0)" }.joined(separator: "\n") + "\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", (0..<200).map { $0 % 20 == 0 ? "LINE \($0)" : "line \($0)" }.joined(separator: "\n") + "\n")
        let clock = ContinuousClock()
        let start = clock.now
        // apply + status + diff: what the UI does after a click.
        let entry = try await repo.entry("a.txt")
        let file = try #require(try await repo.repository.diff(for: entry, staged: false).file)
        let patch = try #require(PatchBuilder.patch(for: file, selecting: PatchBuilder.changes(inHunk: 0, of: file), direction: .forward))
        let afterDiff = clock.now
        try await repo.repository.apply(patch, cached: true, reverse: false)
        _ = try await repo.status()
        _ = try await repo.repository.diff(for: entry, staged: false)
        let ms = millis(clock.now - afterDiff)
        print("COMMIT_PERF stage_hunk_roundtrip_ms=\(String(format: "%.0f", ms)) first_diff_ms=\(String(format: "%.0f", millis(afterDiff - start)))")
        #expect(ms < 150 * ciSlack)
    }
}
