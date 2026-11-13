import Foundation
import Testing
@testable import CommitCore

/// main: base → m1; feature: base → f1 → f2 (on different files, so they combine cleanly).
func divergedRepo() throws -> TestRepo {
    let repo = try TestRepo()
    try repo.write("readme.txt", "hello\n")
    try repo.commitAll("Base")
    try repo.sh("switch", "-q", "-c", "feature")
    try repo.write("feature.txt", "one\n")
    try repo.commitAll("Feature one")
    try repo.write("feature.txt", "one\ntwo\n")
    try repo.commitAll("Feature two")
    try repo.sh("switch", "-q", "main")
    try repo.write("main.txt", "main\n")
    try repo.commitAll("Main one")
    return repo
}

func subjects(_ repo: TestRepo, _ range: String = "HEAD") throws -> [String] {
    try repo.sh("log", "--format=%s", range).split(separator: "\n").map(String.init)
}

@Suite struct IntegrationTests {
    @Test func divergenceCountsBothSides() async throws {
        let repo = try divergedRepo()
        #expect(await repo.repository.divergence(from: "feature") == Divergence(ours: 1, theirs: 2))
        #expect(Divergence.parse("3\t0\n") == Divergence(ours: 3, theirs: 0))
        #expect(Divergence.parse("nonsense") == nil)
    }

    @Test func mergeAndUndo() async throws {
        let repo = try divergedRepo()
        let outcome = try await repo.repository.merge("feature", noFastForward: false, autostash: false)
        guard case .finished(let previous, let head) = outcome else { Issue.record("\(outcome)"); return }
        #expect(try repo.sh("rev-list", "--parents", "-n1", "HEAD").split(separator: " ").count == 3) // a merge commit
        #expect(repo.read("feature.txt") == "one\ntwo\n")
        #expect(try await repo.repository.resolve("HEAD") == head)
        try await repo.repository.undoIntegration(to: previous)
        #expect(try await repo.repository.resolve("HEAD") == previous)
        #expect(!repo.exists("feature.txt"))
        // Already merged: nothing to do.
        _ = try await repo.repository.merge("feature", noFastForward: false, autostash: false)
        #expect(try await repo.repository.merge("feature", noFastForward: false, autostash: false) == .upToDate)
    }

    @Test func fastForwardOrNot() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("A")
        try repo.sh("branch", "ahead")
        try repo.sh("switch", "-q", "ahead")
        try repo.write("a.txt", "a\nb\n")
        try repo.commitAll("B")
        try repo.sh("switch", "-q", "main")
        _ = try await repo.repository.merge("ahead", noFastForward: true, autostash: false)
        #expect(try subjects(repo).first == "Merge branch 'ahead'")
    }

    @Test func mergeConflictStopsWithTheBanner() async throws {
        let repo = try TestRepo()
        try repo.write("s.txt", "a\nb\nc\n")
        try repo.commitAll("Base")
        try repo.sh("switch", "-q", "-c", "other")
        try repo.write("s.txt", "a\nTHEIRS\nc\n")
        try repo.commitAll("Theirs")
        try repo.sh("switch", "-q", "main")
        try repo.write("s.txt", "a\nOURS\nc\n")
        try repo.commitAll("Ours")
        let before = try await repo.repository.resolve("HEAD")
        let outcome = try await repo.repository.merge("other", noFastForward: false, autostash: false)
        #expect(outcome == .stopped(.merge, previous: before))
        #expect(try await repo.status().conflicted.map(\.path) == ["s.txt"])
    }

    @Test func mergeRefusesToOverwriteLocalChanges() async throws {
        let repo = try divergedRepo()
        try repo.write("feature.txt", "mine, not committed\n") // untracked, would be overwritten
        await #expect(throws: GitFailure.self) {
            _ = try await repo.repository.merge("feature", noFastForward: false, autostash: false)
        }
        #expect(repo.repository.inProgressOperation() == nil)
    }

    @Test func rebaseOntoAndUndo() async throws {
        let repo = try divergedRepo()
        try repo.sh("switch", "-q", "feature")
        let outcome = try await repo.repository.rebase(onto: "main", autostash: false)
        guard case .finished(let previous, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(try subjects(repo) == ["Feature two", "Feature one", "Main one", "Base"])
        try await repo.repository.undoIntegration(to: previous)
        #expect(try subjects(repo) == ["Feature two", "Feature one", "Base"])
    }

    @Test func rebaseWithLocalChangesUsesAutostash() async throws {
        let repo = try divergedRepo()
        try repo.sh("switch", "-q", "feature")
        try repo.write("readme.txt", "hello\nlocal edit\n")
        _ = try await repo.repository.rebase(onto: "main", autostash: true)
        #expect(repo.read("readme.txt") == "hello\nlocal edit\n")
        #expect(try subjects(repo).count == 4)
    }

    @Test func cherryPickSeveralInOrder() async throws {
        let repo = try divergedRepo()
        let one = try await repo.repository.resolve("feature~1")
        let two = try await repo.repository.resolve("feature")
        let outcome = try await repo.repository.cherryPick([one, two])
        guard case .finished = outcome else { Issue.record("\(outcome)"); return }
        #expect(try subjects(repo) == ["Feature two", "Feature one", "Main one", "Base"])
        #expect(repo.read("feature.txt") == "one\ntwo\n")
    }

    @Test func cherryPickConflictStops() async throws {
        let repo = try TestRepo()
        try repo.write("s.txt", "a\n")
        try repo.commitAll("Base")
        try repo.sh("switch", "-q", "-c", "other")
        try repo.write("s.txt", "theirs\n")
        try repo.commitAll("Theirs")
        try repo.sh("switch", "-q", "main")
        try repo.write("s.txt", "ours\n")
        try repo.commitAll("Ours")
        let pick = try await repo.repository.resolve("other")
        let outcome = try await repo.repository.cherryPick([pick])
        guard case .stopped(.cherryPick, _) = outcome else { Issue.record("\(outcome)"); return }
        try await repo.repository.abortOperation(.cherryPick)
        #expect(repo.read("s.txt") == "ours\n")
    }

    @Test func revertMakesANewCommit() async throws {
        let repo = try divergedRepo()
        let target = try await repo.repository.resolve("HEAD")
        let outcome = try await repo.repository.revert(target, isMerge: false)
        guard case .finished = outcome else { Issue.record("\(outcome)"); return }
        #expect(try subjects(repo).first == "Revert \"Main one\"")
        #expect(!repo.exists("main.txt"))
    }

    @Test func revertAMerge() async throws {
        let repo = try divergedRepo()
        _ = try await repo.repository.merge("feature", noFastForward: true, autostash: false)
        let merge = try await repo.repository.resolve("HEAD")
        _ = try await repo.repository.revert(merge, isMerge: true)
        #expect(!repo.exists("feature.txt"))
        #expect(repo.exists("main.txt"))
    }

    @Test func undoRefusesToLoseLocalChanges() async throws {
        let repo = try divergedRepo()
        guard case .finished(let previous, _) = try await repo.repository.merge("feature", noFastForward: false, autostash: false) else {
            Issue.record("no merge"); return
        }
        try repo.write("feature.txt", "edited after the merge\n")
        await #expect(throws: GitFailure.self) { try await repo.repository.undoIntegration(to: previous) }
        #expect(repo.read("feature.txt") == "edited after the merge\n")
    }
}

@Suite struct RebasePlanTests {
    func step(_ n: Int, _ action: RebaseAction = .pick, edited: String? = nil) -> RebaseStep {
        let hex = String(repeating: String(n), count: 40)
        return RebaseStep(id: ObjectID(hex: hex)!, action: action, message: "Commit \(n)\n\nBody \(n)", editedMessage: edited)
    }

    @Test func groupsAndMessages() {
        let plan = RebasePlan(base: nil, steps: [step(1), step(2, .squash), step(3, .fixup), step(4, .drop), step(5, .reword, edited: "New five")])
        #expect(plan.groups == [RebaseGroup(head: 0, members: [1, 2]), RebaseGroup(head: 4, members: [])])
        #expect(plan.message(of: plan.groups[0]) == "Commit 1\n\nBody 1\n\nCommit 2\n\nBody 2")
        #expect(plan.message(of: plan.groups[1]) == "New five")
        #expect(plan.problem == nil)
        #expect(plan.summary == "5 commits become 2. Drops 1 commit and its changes.")
    }

    @Test func todoAmendsAfterEachGroupThatNeedsAMessage() {
        let plan = RebasePlan(base: nil, steps: [step(1), step(2, .squash), step(3, .fixup), step(4), step(5, .reword, edited: "Five"), step(6, .drop)])
        let (todo, messages) = plan.todo(git: "/usr/bin/git") { URL(fileURLWithPath: "/tmp/m\($0)") }
        let lines = todo.split(separator: "\n").map(String.init)
        #expect(lines[0] == "pick " + String(repeating: "1", count: 40))
        #expect(lines[1].hasPrefix("squash "))
        #expect(lines[2].hasPrefix("fixup "))
        #expect(lines[3] == "exec '/usr/bin/git' commit --amend --only --allow-empty --quiet -F '/tmp/m0'")
        #expect(lines[4].hasPrefix("pick 4"))
        #expect(lines[5].hasPrefix("pick 5")) // reword: a pick, then the amend
        #expect(lines[6].contains("-F '/tmp/m2'"))
        #expect(lines[7].hasPrefix("drop 6"))
        #expect(lines.count == 8)
        #expect(messages[URL(fileURLWithPath: "/tmp/m2")] == "Five")
        #expect(messages.count == 2)
    }

    @Test func problems() {
        #expect(RebasePlan(base: nil, steps: [step(1, .squash), step(2)]).problem != nil)
        #expect(RebasePlan(base: nil, steps: [step(1, .drop), step(2, .fixup)]).problem != nil)
        #expect(RebasePlan(base: nil, steps: [step(1, .reword, edited: "  ")]).problem != nil)
        #expect(RebasePlan(base: nil, steps: [step(1, .drop), step(2, .drop)]).summary.contains("Every commit is dropped"))
    }

    @Test func moving() {
        var plan = RebasePlan(base: nil, steps: [step(1), step(2), step(3)])
        plan.originalOrder = plan.steps.map(\.id)
        #expect(plan.isUnchanged)
        plan.move(from: IndexSet(integer: 2), to: 0)
        #expect(plan.steps.map(\.message.first) == ["C", "C", "C"])
        #expect(plan.steps.map { $0.id.hex.first } == ["3", "1", "2"])
        #expect(!plan.isUnchanged)
        plan.move(0, by: 1)
        #expect(plan.steps.map { $0.id.hex.first } == ["1", "3", "2"])
        plan.move(0, by: -1) // already at the top
        #expect(plan.steps.map { $0.id.hex.first } == ["1", "3", "2"])
        #expect(RebaseAction.allCases.map(\.key) == ["p", "r", "s", "f", "d"])
    }

    @Test func shellQuoting() {
        #expect(RebasePlan.shellQuote("/a b/it's") == "'/a b/it'\\''s'")
    }
}

@Suite struct InteractiveRebaseTests {
    func fourCommits() throws -> TestRepo {
        let repo = try TestRepo()
        for n in 1...4 {
            try repo.write("file\(n).txt", "\(n)\n")
            try repo.commitAll("Commit \(n)")
        }
        return repo
    }

    @Test func loadsTheRangeOldestFirst() async throws {
        let repo = try fourCommits()
        let second = try await repo.repository.resolve("HEAD~2")
        let plan = try await repo.repository.rebasePlan(from: second)
        #expect(plan.steps.map(\.subject) == ["Commit 2", "Commit 3", "Commit 4"])
        #expect(plan.base == (try await repo.repository.resolve("HEAD~3")))
        #expect(plan.isUnchanged)
        let root = try await repo.repository.resolve("HEAD~3")
        let fromRoot = try await repo.repository.rebasePlan(from: root)
        #expect(fromRoot.base == nil)
        #expect(fromRoot.steps.count == 4)
    }

    @Test func reorderSquashRewordDropAndUndo() async throws {
        let repo = try fourCommits()
        let original = try await repo.repository.resolve("HEAD")
        var plan = try await repo.repository.rebasePlan(from: try await repo.repository.resolve("HEAD~2"))
        // 2, 3, 4 → 4 (reworded), 2 + 3 squashed with a typed message; then drop nothing else.
        plan.move(from: IndexSet(integer: 2), to: 0)
        plan.steps[0].action = .reword
        plan.steps[0].editedMessage = "Four, reworded\n\nWith a body"
        plan.steps[2].action = .squash
        plan.steps[1].editedMessage = "Two and three"
        let work = TestRepo.base.appendingPathComponent("rebase-\(UUID().uuidString.prefix(6))")
        let outcome = try await repo.repository.interactiveRebase(plan, git: "/usr/bin/git", workDirectory: work, autostash: false)
        guard case .finished(let previous, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(previous == original)
        #expect(try subjects(repo) == ["Two and three", "Four, reworded", "Commit 1"])
        #expect(try repo.sh("log", "-1", "--format=%B", "HEAD~1").trimmingCharacters(in: .whitespacesAndNewlines) == "Four, reworded\n\nWith a body")
        for n in 1...4 { #expect(repo.read("file\(n).txt") == "\(n)\n") }
        try await repo.repository.undoIntegration(to: previous)
        #expect(try subjects(repo) == ["Commit 4", "Commit 3", "Commit 2", "Commit 1"])
    }

    @Test func dropAndFixup() async throws {
        let repo = try fourCommits()
        var plan = try await repo.repository.rebasePlan(from: try await repo.repository.resolve("HEAD~2"))
        plan.steps[1].action = .drop
        plan.steps[2].action = .fixup
        _ = try await repo.repository.interactiveRebase(plan, git: "/usr/bin/git",
                                                        workDirectory: TestRepo.base.appendingPathComponent("rb-\(UUID().uuidString.prefix(6))"),
                                                        autostash: false)
        #expect(try subjects(repo) == ["Commit 2", "Commit 1"])
        #expect(!repo.exists("file3.txt"))
        #expect(repo.read("file4.txt") == "4\n")
    }

    @Test func refusesMergesAndOtherBranches() async throws {
        let repo = try divergedRepo()
        _ = try await repo.repository.merge("feature", noFastForward: true, autostash: false)
        let base = try await repo.repository.resolve("HEAD~1~1")
        await #expect(throws: IntegrationProblem.hasMerges) { _ = try await repo.repository.rebasePlan(from: base) }
        try repo.sh("switch", "-q", "-c", "elsewhere", "HEAD~1")
        let notMine = try await repo.repository.resolve("feature")
        await #expect(throws: IntegrationProblem.notAnAncestor) { _ = try await repo.repository.rebasePlan(from: notMine) }
    }

    @Test func pushedCommitsAreCounted() async throws {
        let repo = try fourCommits()
        _ = try repo.addBareRemote()
        try repo.sh("push", "-q", "-u", "origin", "main")
        try repo.write("file5.txt", "5\n")
        try repo.commitAll("Commit 5")
        let ids = try await [repo.repository.resolve("HEAD~1"), repo.repository.resolve("HEAD")]
        #expect(await repo.repository.pushedCount(ids) == 1)
        let plan = try await repo.repository.rebasePlanForUnpushed(upstream: "origin/main")
        #expect(plan.steps.map(\.subject) == ["Commit 5"])
    }

    @Test func conflictStopsAndContinueFinishesWithTheMessages() async throws {
        let repo = try TestRepo()
        try repo.write("s.txt", "a\n")
        try repo.commitAll("One")
        try repo.write("s.txt", "b\n")
        try repo.commitAll("Two")
        try repo.write("s.txt", "c\n")
        try repo.commitAll("Three")
        var plan = try await repo.repository.rebasePlan(from: try await repo.repository.resolve("HEAD~1"))
        plan.move(0, by: 1) // Three before Two: conflicts
        plan.steps[1].action = .reword
        plan.steps[1].editedMessage = "Two, later"
        let outcome = try await repo.repository.interactiveRebase(plan, git: "/usr/bin/git",
                                                                  workDirectory: TestRepo.base.appendingPathComponent("rb-\(UUID().uuidString.prefix(6))"),
                                                                  autostash: false)
        guard case .stopped(.rebase, _) = outcome else { Issue.record("\(outcome)"); return }
        try repo.write("s.txt", "c\n")
        try await repo.repository.stage(paths: ["s.txt"])
        try await repo.repository.continueOperation(.rebase)
        // Two now conflicts too (its change is from "a" to "b" on top of "c").
        if repo.repository.inProgressOperation() == .rebase {
            try repo.write("s.txt", "b\n")
            try await repo.repository.stage(paths: ["s.txt"])
            try await repo.repository.continueOperation(.rebase)
        }
        #expect(repo.repository.inProgressOperation() == nil)
        #expect(try subjects(repo).first == "Two, later")
    }
}
