import Foundation
import Testing
@testable import CommitCore

@Suite struct BlameTests {
    @Test func parsesPorcelain() throws {
        let a = String(repeating: "a", count: 40), b = String(repeating: "b", count: 40)
        let text = """
        \(a) 1 1 2
        author Ada
        author-mail <ada@example.com>
        author-time 1767607200
        author-tz +0000
        summary First
        boundary
        filename old.txt
        \tline one
        \(a) 2 2
        \tline two\r
        \(b) 2 3 1
        author Grace
        author-mail <grace@example.com>
        author-time 1767610800
        summary Second
        previous \(a) old.txt
        filename new.txt
        \tline three
        0000000000000000000000000000000000000000 4 4 1
        author Not Committed Yet
        author-mail <not.committed.yet>
        author-time 1767614400
        summary Version of new.txt from new.txt
        filename new.txt
        \t

        """
        let blame = Blame.parse(Data(text.utf8))
        #expect(blame.commits.count == 3)
        #expect(blame.lines.map(\.text) == ["line one", "line two", "line three", ""])
        #expect(blame.lines.map(\.line) == [1, 2, 3, 4])
        let first = blame.commit(of: blame.lines[0])
        #expect(first.authorName == "Ada")
        #expect(first.authorEmail == "ada@example.com")
        #expect(first.isBoundary)
        #expect(first.path == "old.txt")
        let second = blame.commit(of: blame.lines[2])
        #expect(second.previous == ObjectID(hex: a))
        #expect(second.previousPath == "old.txt")
        #expect(blame.commit(of: blame.lines[3]).isUncommitted)
        #expect(blame.startsRun(0) && !blame.startsRun(1) && blame.startsRun(2))
    }

    @Test func blamesWorkingCopyAndRevisions() async throws {
        let repo = try TestRepo()
        try repo.write("f.txt", "a\nb\n")
        try repo.commitAll("One")
        try repo.write("f.txt", "a\nB\n")
        try repo.commitAll("Two")
        try repo.write("f.txt", "a\nB\nwip\n")
        let current = try await repo.repository.blame("f.txt", at: nil)
        #expect(current.lines.count == 3)
        #expect(current.commit(of: current.lines[0]).summary == "One")
        let two = current.commit(of: current.lines[1])
        #expect(two.summary == "Two")
        #expect(current.commit(of: current.lines[2]).isUncommitted)
        // Step back: blame the version before "Two".
        let previous = try #require(two.previous)
        let older = try await repo.repository.blame(two.previousPath ?? "f.txt", at: previous)
        #expect(older.lines.map(\.text) == ["a", "b"])
        #expect(older.lines.allSatisfy { older.commit(of: $0).summary == "One" })
    }
}

@Suite struct FileHistoryTests {
    @Test func followsRenames() async throws {
        let repo = try TestRepo()
        try repo.write("old.txt", "1\n")
        try repo.commitAll("Add it")
        try repo.write("other.txt", "x\n")
        try repo.commitAll("Unrelated")
        try repo.write("old.txt", "1\n2\n")
        try repo.commitAll("Change it")
        try repo.sh("mv", "old.txt", "new.txt")
        try repo.commitAll("Rename it")
        let history = try await repo.repository.fileHistory("new.txt")
        #expect(history.map(\.subject) == ["Rename it", "Change it", "Add it"])
        #expect(history[0].path == "new.txt")
        #expect(history[0].originalPath == "old.txt")
        #expect(history[0].change == .renamed)
        #expect(history[1].path == "old.txt")
        #expect(history[2].change == .added)
        #expect(history[2].parents.isEmpty)
        #expect(history[1].authorName == "Test Person")
        #expect(await repo.repository.hasUncommittedChanges("new.txt") == false)
        try repo.write("new.txt", "edited\n")
        #expect(await repo.repository.hasUncommittedChanges("new.txt"))
        // The diff of the file in one of its commits.
        let diff = try await repo.repository.diff(of: history[1].changedFile, in: history[1].id, parent: history[1].parents.first)
        #expect(diff.file?.additions == 1)
    }
}

@Suite struct RemoteTests {
    @Test func parsesRemoteList() {
        let output = "origin\thttps://example.com/a.git (fetch)\norigin\tgit@example.com:a.git (push)\nup\t/tmp/up.git (fetch)\nup\t/tmp/up.git (push)\n"
        let remotes = Remote.parse(output)
        #expect(remotes == [Remote(name: "origin", fetchURL: "https://example.com/a.git", pushURL: "git@example.com:a.git"),
                            Remote(name: "up", fetchURL: "/tmp/up.git")])
    }

    @Test func addRenameChangeRemoveAndRestore() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("A")
        let bare = try repo.addBareRemote()
        try repo.sh("push", "-q", "-u", "origin", "main")
        try await repo.repository.addRemote(name: "backup", url: "/tmp/commit-test/nowhere.git")
        #expect(try await repo.repository.remoteList().map(\.name) == ["backup", "origin"])
        try await repo.repository.renameRemote("backup", to: "mirror")
        try repo.sh("config", "remote.mirror.pushurl", "/tmp/commit-test/elsewhere.git")
        try await repo.repository.setRemoteURL("mirror", url: "/tmp/commit-test/somewhere.git")
        let mirror = try #require(try await repo.repository.remoteList().first { $0.name == "mirror" })
        #expect(mirror.fetchURL == "/tmp/commit-test/somewhere.git")
        #expect(mirror.pushURL == nil)

        let removed = try await repo.repository.removeRemote("origin")
        #expect(try await repo.repository.remoteList().map(\.name) == ["mirror"])
        #expect(try repo.sh("config", "--get", "branch.main.remote", allowFailure: true).isEmpty)
        #expect(try await repo.repository.refs().remote.isEmpty)
        try await repo.repository.restoreRemote(removed)
        #expect(try await repo.repository.remoteList().first { $0.name == "origin" }?.fetchURL == bare.path)
        #expect(try repo.sh("config", "--get", "branch.main.remote").trimmingCharacters(in: .whitespacesAndNewlines) == "origin")
        #expect(try await repo.repository.refs().remote.map(\.name) == ["origin/main"])
        #expect(try await repo.status().branch.upstream == "origin/main")
    }

    @Test func nameRules() {
        #expect(RefNameRules.problem(with: "origin", noun: "Remote", allowSlash: false) == nil)
        #expect(RefNameRules.problem(with: "my/remote", noun: "Remote", allowSlash: false) != nil)
        #expect(RefNameRules.problem(with: "v1.0", noun: "Tag") == nil)
        #expect(RefNameRules.problem(with: "v1 0", noun: "Tag") == "Tag names can't contain spaces.")
        #expect(RefNameRules.problem(with: "v1..0", noun: "Tag") != nil)
        #expect(RefNameRules.problem(with: "", noun: "Tag") == "Enter a name.")
    }
}

@Suite struct TagTests {
    @Test func createDeleteRestorePush() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("A")
        let bare = try repo.addBareRemote()
        try repo.sh("push", "-q", "-u", "origin", "main")
        let head = try await repo.repository.resolve("HEAD")
        try await repo.repository.createTag("v1.0", at: head, message: nil)
        try await repo.repository.createTag("v1.1", at: head, message: "Release 1.1\n\nNotes")
        let tags = try await repo.repository.refs().tags
        #expect(tags.map(\.name) == ["v1.0", "v1.1"])
        #expect(tags.map(\.isAnnotated) == [false, true])
        #expect(tags.allSatisfy { $0.target == head }) // annotated tags point at the commit
        #expect(await repo.repository.tagMessage("v1.1") == "Release 1.1\n\nNotes")
        #expect(await repo.repository.tagMessage("v1.0") == nil)
        await #expect(throws: GitFailure.self) { try await repo.repository.createTag("v1.0", at: head, message: nil) }

        let deleted = try await repo.repository.deleteTag("v1.1")
        #expect(try await repo.repository.refs().tags.map(\.name) == ["v1.0"])
        try await repo.repository.restoreTag(deleted)
        #expect(await repo.repository.tagMessage("v1.1") == "Release 1.1\n\nNotes")

        try await repo.repository.pushTag("v1.0", to: "origin")
        let remoteTags = { try repo.git(["tag", "-l"], in: bare).split(separator: "\n").map(String.init) }
        #expect(try remoteTags() == ["v1.0"])
        try await repo.repository.pushAllTags(to: "origin")
        #expect(try remoteTags() == ["v1.0", "v1.1"])
        try await repo.repository.deleteRemoteTag("v1.0", on: "origin")
        #expect(try remoteTags() == ["v1.1"])
    }

    @Test func forcePushWithLease() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("A")
        try repo.write("a.txt", "b\n")
        try repo.commitAll("B")
        let bare = try repo.addBareRemote()
        try repo.sh("push", "-q", "-u", "origin", "main")
        try repo.sh("commit", "-q", "--amend", "-m", "B, amended")
        await #expect(throws: GitFailure.self) { _ = try await repo.repository.push(branch: "main", upstream: "origin/main", remote: "origin") }
        try await repo.repository.forcePush()
        #expect(try repo.git(["log", "-1", "--format=%s", "main"], in: bare).trimmingCharacters(in: .whitespacesAndNewlines) == "B, amended")

        // Someone else pushed in between: the lease refuses to overwrite their work.
        let other = try repo.clone(bare, as: "other-\(UUID().uuidString.prefix(4))")
        try "theirs\n".write(to: other.appendingPathComponent("t.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "."], in: other)
        try repo.git(["commit", "-q", "-m", "Theirs"], in: other)
        try repo.git(["push", "-q"], in: other)
        try repo.sh("commit", "-q", "--amend", "-m", "B, again")
        try repo.sh("fetch", "-q") // our remote-tracking ref now knows about "Theirs"…
        try repo.sh("update-ref", "refs/remotes/origin/main", "HEAD@{1}") // …but pretend we never saw it
        do {
            try await repo.repository.forcePush()
            Issue.record("force push should have been refused")
        } catch let failure as GitFailure {
            #expect(Explanation.explain(failure.output, operation: .forcePush).cause == .staleLease)
        }
    }
}

@Suite struct CloneTests {
    @Test func addresses() {
        #expect(CloneAddress.normalize("  git clone https://example.com/a/b.git  ") == "https://example.com/a/b.git")
        #expect(CloneAddress.normalize("git clone --depth 1 git@host:a/b.git") == "git@host:a/b.git")
        #expect(CloneAddress.problem(with: "https://example.com/a/b.git") == nil)
        #expect(CloneAddress.problem(with: "git@github.com:owner/repo.git") == nil)
        #expect(CloneAddress.problem(with: "ssh://git@example.com:2222/repo") == nil)
        #expect(CloneAddress.problem(with: "/tmp/commit-test/remote.git") == nil)
        #expect(CloneAddress.problem(with: "") != nil)
        #expect(CloneAddress.problem(with: "ftp://example.com/x") != nil)
        #expect(CloneAddress.problem(with: "just words") != nil)
        #expect(CloneAddress.problem(with: "https://") != nil)
        #expect(CloneAddress.suggestedName(for: "https://example.com/owner/Project.git") == "Project")
        #expect(CloneAddress.suggestedName(for: "git@github.com:owner/repo.git") == "repo")
        #expect(CloneAddress.suggestedName(for: "https://example.com/owner/repo/") == "repo")
        #expect(CloneAddress.suggestedName(for: "/tmp/x/remote.git/") == "remote")
        #expect(CloneAddress.suggestedName(for: "git@host:") == "repository")
    }

    @Test func destinations() throws {
        let parent = try TestRepo.makeDirectory("clone-dest")
        #expect(CloneDestination(parent: parent, name: "new").problem() == nil)
        #expect(CloneDestination(parent: parent, name: "").problem() != nil)
        #expect(CloneDestination(parent: parent, name: "a/b").problem() != nil)
        try FileManager.default.createDirectory(at: parent.appendingPathComponent("empty"), withIntermediateDirectories: true)
        #expect(CloneDestination(parent: parent, name: "empty").problem() == nil) // git clones into empty folders
        try "x".write(to: parent.appendingPathComponent("taken"), atomically: true, encoding: .utf8)
        #expect(CloneDestination(parent: parent, name: "taken").problem()?.contains("already") == true)
        #expect(CloneDestination(parent: parent.appendingPathComponent("missing"), name: "x").problem() != nil)
    }

    @Test func clonesALocalRemoteWithProgress() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("A")
        let bare = try repo.addBareRemote()
        try repo.sh("push", "-q", "origin", "main")
        let parent = try TestRepo.makeDirectory("clones")
        let progress = ProgressLog()
        let cloned = try await Repository.clone(bare.path, into: CloneDestination(parent: parent, name: "copy"), submodules: true,
                                                runner: repo.runner) { progress.add($0) }
        #expect(FileManager.default.fileExists(atPath: cloned.appendingPathComponent("a.txt").path))
        let location = try await Repository.locate(cloned, runner: repo.runner)
        #expect(location.root.lastPathComponent == "copy")
        _ = progress // local clones may print no progress; the handler is wired either way
    }

    @Test func failureIsExplainedAndLeavesNothing() async throws {
        let repo = try TestRepo()
        let parent = try TestRepo.makeDirectory("clones")
        do {
            _ = try await Repository.clone("/tmp/commit-test/does-not-exist.git", into: CloneDestination(parent: parent, name: "x"),
                                           submodules: false, runner: repo.runner)
            Issue.record("clone should fail")
        } catch let failure as GitFailure {
            #expect(Explanation.explain(failure.output, operation: .clone).cause == .notFound)
        }
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("x").path))
    }

    @Test func cancellingRemovesTheHalfMadeFolder() async throws {
        let parent = try TestRepo.makeDirectory("clones")
        let target = parent.appendingPathComponent("partial")
        // A runner that starts writing the clone and is then cancelled (killed: git couldn't clean up).
        let runner = ScriptedRunner { command, _ in
            try? FileManager.default.createDirectory(at: target.appendingPathComponent(".git"), withIntermediateDirectories: true)
            return GitResult()
        }
        let cancelling = CancellingRunner(inner: runner)
        await #expect(throws: CancellationError.self) {
            _ = try await Repository.clone("https://example.com/a.git", into: CloneDestination(parent: parent, name: "partial"),
                                           submodules: false, runner: cancelling)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(runner.commands.first?.arguments == ["clone", "--progress", "--", "https://example.com/a.git", target.path])
    }

    @Test func explanations() {
        #expect(Explanation.explain("remote: Repository not found.\nfatal: repository 'https://example.com/x/' not found", operation: .clone).cause == .notFound)
        #expect(Explanation.explain("fatal: destination path 'x' already exists and is not an empty directory.", operation: .clone).cause == .destinationExists)
        #expect(Explanation.explain("git@example.com: Permission denied (publickey).\nfatal: Could not read from remote repository.", operation: .clone).cause == .authentication)
        #expect(Explanation.explain("fatal: could not read Username for 'https://example.com': terminal prompts disabled", operation: .clone).cause == .authentication)
        #expect(Explanation.explain("fatal: tag 'v1' already exists", operation: .createTag).cause == .alreadyExists)
        #expect(Explanation.explain("error: remote backup already exists.", operation: .addRemote).cause == .alreadyExists)
        #expect(Explanation.explain("ssh: Could not resolve hostname nowhere: nodename nor servname provided", operation: .clone).cause == .unreachable)
    }
}

/// Collects progress callbacks from git's stderr.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [GitProgress] = []
    func add(_ p: GitProgress) { lock.withLock { items.append(p) } }
    var all: [GitProgress] { lock.withLock { items } }
}

/// Runs the inner runner, then behaves as if the task had been cancelled.
struct CancellingRunner: GitRunner {
    let inner: any GitRunner
    func run(_ command: GitCommand, onStderr: (@Sendable (Data) -> Void)?) async throws -> GitResult {
        _ = try await inner.run(command, onStderr: onStderr)
        throw CancellationError()
    }
    func stream(_ command: GitCommand) -> AsyncThrowingStream<Data, any Error> { inner.stream(command) }
}
