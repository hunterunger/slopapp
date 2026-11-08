import Foundation
import Testing
@testable import CommitCore

@Suite struct OpeningTests {
    @Test func subfolderOpensTheTopLevel() async throws {
        let repo = try TestRepo()
        try repo.write("Sources/App/main.swift", "x\n")
        let location = try await Repository.locate(repo.root.appendingPathComponent("Sources/App"), runner: repo.runner)
        #expect(location.root.standardizedFileURL.path == repo.root.standardizedFileURL.path)
        #expect(location.gitDirectory.lastPathComponent == ".git")
    }

    @Test func refusesNonReposBareReposAndGitDirs() async throws {
        let repo = try TestRepo(initialize: false)
        await #expect(throws: OpenProblem.notARepository(repo.root)) {
            _ = try await Repository.locate(repo.root, runner: repo.runner)
        }
        let bare = repo.root.deletingLastPathComponent().appendingPathComponent("bare.git")
        try repo.git(["init", "-q", "--bare", bare.path], in: repo.root.deletingLastPathComponent())
        await #expect(throws: OpenProblem.bare(bare)) { _ = try await Repository.locate(bare, runner: repo.runner) }
        try repo.sh("init", "-q")
        let inside = repo.root.appendingPathComponent(".git/refs")
        await #expect(throws: OpenProblem.insideGitDirectory(inside)) { _ = try await Repository.locate(inside, runner: repo.runner) }
        let missing = repo.root.appendingPathComponent("nope")
        await #expect(throws: OpenProblem.missing(missing)) { _ = try await Repository.locate(missing, runner: repo.runner) }
    }

    @Test func initCreatesARepository() async throws {
        let repo = try TestRepo(initialize: false)
        try await Repository.initialize(repo.root, runner: repo.runner)
        let location = try await Repository.locate(repo.root, runner: repo.runner)
        #expect(location.root.lastPathComponent == "work")
    }
}

@Suite struct WorkingCopyTests {
    @Test func statusSeesEveryKindOfChange() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.write("b.txt", "b\n")
        try repo.write("old.txt", "rename me\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "a2\n")
        try repo.sh("add", "a.txt")
        try repo.write("a.txt", "a3\n")
        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("b.txt"))
        try repo.sh("mv", "old.txt", "new.txt")
        try repo.write("dir/untracked.txt", "u\n")
        let status = try await repo.status()
        #expect(status.branch.branch == "main")
        #expect(Set(status.staged.map(\.path)) == ["a.txt", "new.txt"])
        #expect(Set(status.unstaged.map(\.path)) == ["a.txt", "b.txt", "dir/"])
        let noUntracked = try await repo.repository.status(includeUntracked: false)
        #expect(!noUntracked.entries.contains { $0.isUntracked })
    }

    @Test func stagingFilesAndUndoingIt() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "one\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "one\ntwo\n")
        try repo.sh("add", "a.txt")
        try repo.write("a.txt", "one\ntwo\nthree\n")
        try repo.write("new.txt", "new\n")
        // Partly staged a.txt: staging the file and undoing must bring back the partial state.
        let snapshot = try await repo.repository.snapshotIndex(paths: ["a.txt", "new.txt"])
        try await repo.repository.stage(paths: ["a.txt", "new.txt"])
        #expect(try await repo.status().unstaged.isEmpty)
        try await repo.repository.restoreIndex(snapshot)
        #expect(String(decoding: try repo.indexContent("a.txt"), as: UTF8.self) == "one\ntwo\n")
        #expect(try await repo.entry("new.txt").isUntracked)

        try await repo.repository.stageAll()
        #expect(try await repo.status().unstaged.isEmpty)
        try await repo.repository.unstageAll(headExists: true)
        #expect(try await repo.status().staged.isEmpty)
        let whole = try #require(try await repo.repository.snapshotWholeIndex())
        try await repo.repository.stageAll()
        try await repo.repository.restoreIndex(whole)
        #expect(try await repo.status().staged.isEmpty)
    }

    @Test func discardingFilesKeepsStagedPartsAndUndoes() async throws {
        let repo = try TestRepo()
        try repo.write("f.txt", "a\nb\nc\n")
        try repo.write("g.txt", "g\n")
        try repo.write("del.txt", "delete me\n")
        try repo.commitAll("Start")
        try repo.write("f.txt", "a\nB\nc\n")
        try repo.sh("add", "f.txt")
        try repo.write("f.txt", "a\nB\nc\nd\n")   // partly staged
        try repo.write("g.txt", "g\nmore\n")      // only unstaged
        try repo.write("u.txt", "untracked\n")    // untracked
        try FileManager.default.removeItem(at: repo.root.appendingPathComponent("del.txt"))
        let status = try await repo.status()
        let targets = status.unstaged
        #expect(targets.count == 4)
        let record = try await repo.repository.discard(targets, keepStaged: true)
        #expect(repo.read("f.txt") == "a\nB\nc\n")
        #expect(String(decoding: try repo.indexContent("f.txt"), as: UTF8.self) == "a\nB\nc\n")
        #expect(repo.read("g.txt") == "g\n")
        #expect(!repo.exists("u.txt"))
        #expect(repo.read("del.txt") == "delete me\n")
        // The discard is in Stashes.
        let stashes = try await repo.repository.stashes()
        #expect(stashes.first?.message.hasPrefix("Discarded ") == true)

        try await repo.repository.undoDiscard(record)
        #expect(repo.read("f.txt") == "a\nB\nc\nd\n")
        #expect(String(decoding: try repo.indexContent("f.txt"), as: UTF8.self) == "a\nB\nc\n")
        #expect(repo.read("g.txt") == "g\nmore\n")
        #expect(repo.read("u.txt") == "untracked\n")
        #expect(!repo.exists("del.txt"))
        #expect(try await repo.repository.stashes().isEmpty)
    }

    @Test func discardAllAndUndo() async throws {
        let repo = try TestRepo()
        try repo.write("f.txt", "a\n")
        try repo.commitAll("Start")
        try repo.write("f.txt", "staged\n")
        try repo.sh("add", "f.txt")
        try repo.write("f.txt", "staged\nand not\n")
        try repo.write("u.txt", "u\n")
        let record = try await repo.repository.discardAll()
        #expect(try await repo.status().isClean)
        try await repo.repository.undoDiscard(record)
        #expect(repo.read("f.txt") == "staged\nand not\n")
        #expect(String(decoding: try repo.indexContent("f.txt"), as: UTF8.self) == "staged\n")
        #expect(repo.read("u.txt") == "u\n")
    }

    @Test func untrackedDiffAndFolders() async throws {
        let repo = try TestRepo()
        try repo.write("seed", "s\n")
        try repo.commitAll("Start")
        try repo.write("todo.txt", "buy milk\n")
        try repo.write("node_modules/a/index.js", "x\n")
        let file = try #require(try await repo.repository.diff(for: try await repo.entry("todo.txt"), staged: false).file)
        #expect(file.isNew && file.additions == 1)
        let folder = try await repo.repository.diff(for: try await repo.entry("node_modules/"), staged: false)
        #expect(folder.isFolder && folder.file == nil)
    }

    @Test func slowDiffFallsBackToMyers() async throws {
        let repo = try TestRepo()
        let lines = (0..<3000).map { "line \($0)" }
        try repo.write("big.txt", lines.joined(separator: "\n") + "\n")
        try repo.commitAll("Start")
        try repo.write("big.txt", lines.enumerated().map { $0.offset % 5 == 0 ? $0.element + "!" : $0.element }.joined(separator: "\n") + "\n")
        try repo.sh("config", "diff.algorithm", "histogram")
        // A timeout no diff can meet forces the fallback path with real processes.
        let result = try await repo.repository.diff(for: try await repo.entry("big.txt"), staged: false,
                                                    options: DiffOptions(timeout: .microseconds(1)))
        #expect(result.usedFallback)
        #expect(result.file?.additions == 600)
    }

    @Test func fallbackIsTriggeredByATimedOutRun() async throws {
        let runner = ScriptedRunner { command, call in
            if command.arguments.contains("--diff-algorithm=myers") {
                return GitResult(stdout: Data("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n".utf8))
            }
            return GitResult(exitCode: 143, timedOut: true)
        }
        let repository = Repository(location: RepositoryLocation(root: URL(fileURLWithPath: "/tmp"), gitDirectory: URL(fileURLWithPath: "/tmp/.git")),
                                    runner: runner)
        let entry = StatusEntry(path: "x", kind: .ordinary, staged: .unmodified, unstaged: .modified)
        let result = try await repository.diff(for: entry, staged: false)
        #expect(result.usedFallback)
        #expect(result.file?.changedLineCount == 2)
        #expect(runner.commands.count == 2)
    }
}

@Suite struct CommittingTests {
    @Test func commitAmendAndUndo() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.sh("add", "a.txt")
        // First commit on an unborn branch.
        let first = try await repo.repository.commit(message: CommitMessage(subject: "First").text, amend: false)
        #expect(try await repo.status().branch.head == first)
        try repo.write("a.txt", "a\nb\n")
        try repo.sh("add", "a.txt")
        let second = try await repo.repository.commit(message: "Second\n\n# kept, not a comment\n", amend: false)
        #expect(try await repo.repository.headMessage() == "Second\n\n# kept, not a comment")
        // Message-only amend.
        let amended = try await repo.repository.commit(message: "Second, reworded\n", amend: true)
        #expect(amended != second)
        #expect(try await repo.repository.headMessage() == "Second, reworded")
        // Undo commit: the change goes back to staged.
        try await repo.repository.softReset(to: first)
        #expect(try await repo.status().staged.map(\.path) == ["a.txt"])
        // Undo the first commit too: back to unborn with everything staged.
        try await repo.repository.softReset(to: nil)
        let status = try await repo.status()
        #expect(status.branch.isUnborn)
        #expect(status.staged.map(\.path) == ["a.txt"])
    }

    @Test func missingIdentityIsExplained() async throws {
        let repo = try TestRepo(identity: false)
        try repo.sh("config", "user.useConfigOnly", "true")
        try repo.write("a.txt", "a\n")
        try repo.sh("add", "a.txt")
        #expect(await repo.repository.identity().isComplete == false)
        do {
            _ = try await repo.repository.commit(message: "Hi\n", amend: false)
            Issue.record("commit should fail without an identity")
        } catch let failure as GitFailure {
            #expect(Explanation.explain(failure.output, operation: .commit).cause == .missingIdentity)
        }
        try await repo.repository.setIdentity(name: "Ada", email: "ada@example.com", global: true)
        #expect(await repo.repository.identity() == .init(name: "Ada", email: "ada@example.com"))
        let config = try String(contentsOf: repo.home.appendingPathComponent(".gitconfig"), encoding: .utf8)
        #expect(config.contains("ada@example.com"))
        _ = try await repo.repository.commit(message: "Hi\n", amend: false)
    }

    @Test func failingHookKeepsOutput() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        let hook = repo.root.appendingPathComponent(".git/hooks/pre-commit")
        try "#!/bin/sh\necho 'lint: 2 problems found' >&2\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try repo.write("a.txt", "b\n")
        try repo.sh("add", "a.txt")
        do {
            _ = try await repo.repository.commit(message: "Blocked\n", amend: false)
            Issue.record("the hook should stop the commit")
        } catch let failure as GitFailure {
            let explanation = Explanation.explain(failure.output, operation: .commit)
            #expect(explanation.cause == .hookOrOther)
            #expect(explanation.output.contains("lint: 2 problems found"))
        }
    }

    @Test func pushedHeadIsDetected() async throws {
        let repo = try TestRepo()
        _ = try repo.addBareRemote()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        #expect(await repo.repository.isHeadPushed() == false)
        try repo.sh("push", "-q", "-u", "origin", "main")
        #expect(await repo.repository.isHeadPushed())
        try repo.write("a.txt", "b\n")
        try repo.commitAll("Local")
        #expect(await repo.repository.isHeadPushed() == false)
    }

    @Test func sshSigningWithAPassphraseAsksThroughAskpass() async throws {
        let probe = try TestRepo()
        let keyDir = probe.home.appendingPathComponent("keys")
        try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true)
        let key = keyDir.appendingPathComponent("signing")
        let keygen = try TestRepo.syncRun(["-q", "-t", "ed25519", "-N", "open sesame", "-C", "test", "-f", key.path],
                                          in: keyDir, environment: ["PATH": GitEnvironment.guiPath], executable: "/usr/bin/ssh-keygen")
        #expect(keygen.succeeded)
        let askpass = keyDir.appendingPathComponent("askpass.sh")
        try "#!/bin/sh\necho \"$1\" >> \"\(keyDir.path)/prompts.log\"\necho 'open sesame'\n".write(to: askpass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: askpass.path)
        let repo = try TestRepo(extraEnvironment: ["SSH_ASKPASS": askpass.path, "SSH_ASKPASS_REQUIRE": "force", "SSH_AUTH_SOCK": "",
                                                   "DISPLAY": ":0"])
        try repo.sh("config", "gpg.format", "ssh")
        try repo.sh("config", "user.signingkey", key.path)
        try repo.sh("config", "commit.gpgsign", "true")
        try repo.write("a.txt", "a\n")
        try repo.sh("add", "a.txt")
        _ = try await repo.repository.commit(message: "Signed\n", amend: false)
        let raw = try repo.sh("cat-file", "commit", "HEAD")
        #expect(raw.contains("-----BEGIN SSH SIGNATURE-----"))
        let prompts = try String(contentsOf: keyDir.appendingPathComponent("prompts.log"), encoding: .utf8)
        #expect(AskpassPrompt(text: prompts).kind == .secret)
    }

    @Test func httpsCredentialPromptsGoToAskpass() async throws {
        let repo = try TestRepo()
        let dir = repo.root.deletingLastPathComponent()
        let askpass = dir.appendingPathComponent("askpass.sh")
        try "#!/bin/sh\ncase \"$1\" in Username*) echo ada ;; *) echo token123 ;; esac\n".write(to: askpass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: askpass.path)
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: "/usr/bin/git"),
                                      environment: TestRepo.environment(home: repo.home, extra: ["GIT_ASKPASS": askpass.path]))
        let result = try await runner.run(GitCommand(["credential", "fill"], in: repo.root,
                                                     stdin: Data("protocol=https\nhost=example.com\n\n".utf8)))
        #expect(result.stdoutString.contains("username=ada"))
        #expect(result.stdoutString.contains("password=token123"))
        // Without askpass, git fails fast instead of waiting on a terminal.
        let clock = ContinuousClock()
        let start = clock.now
        let bare = try await repo.runner.run(GitCommand(["credential", "fill"], in: repo.root,
                                                        stdin: Data("protocol=https\nhost=example.com\n\n".utf8)))
        #expect(!bare.succeeded)
        #expect(clock.now - start < .seconds(5 * ciSlack))
    }
}

@Suite struct BranchTests {
    @Test func switchCreateDeleteAndRestore() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        let start = try await repo.repository.resolve("HEAD")
        try repo.write("a.txt", "b\n")
        try repo.commitAll("Second")
        try await repo.repository.createBranch("feature/x", from: start, checkout: true)
        #expect(try await repo.status().branch.branch == "feature/x")
        #expect(try await repo.repository.resolve("HEAD") == start)
        try await repo.repository.createBranch("other", from: nil, checkout: false)
        try await repo.repository.switchBranch("main")
        let refs = try await repo.repository.refs()
        #expect(refs.local.map(\.name).sorted() == ["feature/x", "main", "other"])
        #expect(refs.current?.name == "main")
        let other = try #require(refs.local.first { $0.name == "other" })
        let tip = try #require(try await repo.repository.deleteBranch(other, force: false))
        #expect(try await repo.repository.refs().local.count == 2)
        try await repo.repository.restoreBranch("other", at: tip)
        #expect(try await repo.repository.refs().local.count == 3)
    }

    @Test func switchingWithConflictingChangesOffersStashAndSwitch() async throws {
        let repo = try TestRepo()
        try repo.write("notes.txt", "base\n")
        try repo.commitAll("Start")
        try repo.sh("switch", "-q", "-c", "topic")
        try repo.write("notes.txt", "topic\n")
        try repo.commitAll("Topic")
        try repo.sh("switch", "-q", "main")
        try repo.write("notes.txt", "local edit\n")
        try repo.write("scratch.txt", "untracked\n")
        do {
            try await repo.repository.switchBranch("topic")
            Issue.record("switch should refuse")
        } catch let failure as GitFailure {
            #expect(Explanation.explain(failure.output, operation: .switchBranch).action == .stashAndSwitch)
        }
        let cleanly = try await repo.repository.stashAndSwitch(to: "topic")
        #expect(try await repo.status().branch.branch == "topic")
        // The edit conflicts with topic's version, so it stays in the stash.
        #expect(!cleanly)
        #expect(try await repo.repository.stashes().count == 1)
    }

    @Test func stashAndSwitchBringsChangesAlong() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.write("b.txt", "b\n")
        try repo.commitAll("Start")
        try repo.sh("switch", "-q", "-c", "topic")
        try repo.write("b.txt", "b on topic\n")
        try repo.commitAll("Topic")
        try repo.sh("switch", "-q", "main")
        try repo.write("a.txt", "edited a\n")
        try repo.sh("add", "a.txt")
        let cleanly = try await repo.repository.stashAndSwitch(to: "topic")
        #expect(cleanly)
        #expect(repo.read("a.txt") == "edited a\n")
        #expect(try await repo.status().staged.map(\.path) == ["a.txt"])
        #expect(try await repo.repository.stashes().isEmpty)
    }

    @Test func checksOutRemoteBranchesAsTracking() async throws {
        let repo = try TestRepo()
        let remote = try repo.addBareRemote()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        try repo.sh("push", "-q", "-u", "origin", "main")
        let other = try repo.clone(remote, as: "other")
        try repo.git(["switch", "-q", "-c", "feature/remote"], in: other)
        try "r\n".write(to: other.appendingPathComponent("r.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "."], in: other)
        try repo.git(["commit", "-q", "-m", "Remote work"], in: other)
        try repo.git(["push", "-q", "-u", "origin", "feature/remote"], in: other)
        try await repo.repository.fetch()
        let refs = try await repo.repository.refs()
        let remoteRef = try #require(refs.remote.first { $0.name == "origin/feature/remote" })
        let local = try await repo.repository.switchToRemote(remoteRef, localBranches: refs.local)
        #expect(local == "feature/remote")
        let status = try await repo.status()
        #expect(status.branch.branch == "feature/remote" && status.branch.upstream == "origin/feature/remote")
        // Again: switches to the existing local branch.
        try await repo.repository.switchBranch("main")
        _ = try await repo.repository.switchToRemote(remoteRef, localBranches: try await repo.repository.refs().local)
        #expect(try await repo.status().branch.branch == "feature/remote")
    }
}

@Suite struct SyncTests {
    @Test func firstPushSetsUpstreamThenRejectedPushAndDivergentPull() async throws {
        let repo = try TestRepo()
        let remote = try repo.addBareRemote()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        let outcome = try await repo.repository.push(branch: "main", upstream: nil, remote: "origin")
        #expect(outcome.setUpstream && outcome.remote == "origin")
        #expect(try await repo.status().branch.upstream == "origin/main")

        // Someone else pushes.
        let other = try repo.clone(remote, as: "other")
        try "other\n".write(to: other.appendingPathComponent("o.txt"), atomically: true, encoding: .utf8)
        try repo.git(["add", "."], in: other)
        try repo.git(["commit", "-q", "-m", "Other"], in: other)
        try repo.git(["push", "-q"], in: other)
        // We commit too, then push: rejected.
        try repo.write("b.txt", "b\n")
        try repo.commitAll("Ours")
        do {
            _ = try await repo.repository.push(branch: "main", upstream: "origin/main", remote: "origin")
            Issue.record("push should be rejected")
        } catch let failure as GitFailure {
            let explanation = Explanation.explain(failure.output, operation: .push, remote: "origin")
            #expect(explanation.cause == .rejectedPush && explanation.action == .pull)
        }
        // Pull with no pull.rebase set: divergent.
        try repo.sh("config", "--unset-all", "pull.rebase", allowFailure: true)
        try repo.sh("config", "pull.ff", "only")
        do {
            try await repo.repository.pull(strategy: .configured, autostash: false)
            Issue.record("pull should ask how to reconcile")
        } catch let failure as GitFailure {
            #expect(Explanation.explain(failure.output, operation: .pull).cause == .divergentBranches)
        }
        try repo.sh("config", "--unset", "pull.ff")
        // Merge, with a dirty tree (autostash).
        try repo.write("a.txt", "dirty\n")
        try await repo.repository.pull(strategy: .merge, autostash: true)
        #expect(repo.exists("o.txt"))
        #expect(repo.read("a.txt") == "dirty\n")
        try await repo.repository.rememberPullStrategy(.rebase)
        #expect(try repo.sh("config", "pull.rebase").trimmingCharacters(in: .whitespacesAndNewlines) == "true")
        try repo.sh("checkout", "--", "a.txt")
        _ = try await repo.repository.push(branch: "main", upstream: "origin/main", remote: "origin")
        #expect(try await repo.status().branch.ahead == 0)
    }

    @Test func fetchReportsProgressAndCanBeCancelled() async throws {
        let repo = try TestRepo()
        let remote = try repo.addBareRemote()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        try repo.sh("push", "-q", "-u", "origin", "main")
        let other = try repo.clone(remote, as: "other")
        for i in 0..<200 { try "file \(i)\n".write(to: other.appendingPathComponent("f\(i).txt"), atomically: true, encoding: .utf8) }
        try repo.git(["add", "."], in: other)
        try repo.git(["commit", "-q", "-m", "Many"], in: other)
        try repo.git(["push", "-q"], in: other)
        try await repo.repository.fetch()
        let status = try await repo.status()
        #expect(status.branch.behind == 1)
    }

    @Test func pullRequestURLsAreFound() {
        let output = "remote: \nremote: Create a pull request for 'feature' on GitHub by visiting:\nremote:      https://github.com/o/r/pull/new/feature\nremote: \n"
        #expect(Repository.pullRequestURL(in: output)?.absoluteString == "https://github.com/o/r/pull/new/feature")
        #expect(Repository.pullRequestURL(in: "To /tmp/x.git\n   abc..def  main -> main") == nil)
    }
}

@Suite struct StashTests {
    @Test func stashListApplyPopDropAndRestore() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("Start")
        try repo.write("a.txt", "staged\n")
        try repo.sh("add", "a.txt")
        try repo.write("u.txt", "untracked\n")
        try await repo.repository.stash(message: "Work in progress", includeUntracked: true)
        #expect(try await repo.status().isClean)
        var stashes = try await repo.repository.stashes()
        #expect(stashes.count == 1 && stashes[0].message == "Work in progress")
        let files = try await repo.repository.stashFiles(stashes[0])
        #expect(Set(files.map(\.path)) == ["a.txt", "u.txt"])
        #expect(files.first { $0.path == "u.txt" }?.fromUntrackedStash == true)
        let untrackedDiff = try await repo.repository.stashDiff(stashes[0], file: files.first { $0.path == "u.txt" }!)
        #expect(untrackedDiff.file?.additions == 1)
        let trackedDiff = try await repo.repository.stashDiff(stashes[0], file: files.first { $0.path == "a.txt" }!)
        #expect(trackedDiff.file?.changedLineCount == 2)

        try await repo.repository.applyStash(stashes[0], pop: false)
        #expect(try await repo.status().staged.map(\.path) == ["a.txt"])
        #expect(try await repo.repository.stashes().count == 1)
        try repo.sh("reset", "-q", "--hard")
        try repo.sh("clean", "-fdq")
        try await repo.repository.applyStash(stashes[0], pop: true)
        #expect(try await repo.repository.stashes().isEmpty)
        #expect(repo.read("u.txt") == "untracked\n")

        try await repo.repository.stash(message: "", includeUntracked: false)
        stashes = try await repo.repository.stashes()
        let dropped = stashes[0]
        try await repo.repository.dropStash(dropped)
        #expect(try await repo.repository.stashes().isEmpty)
        try await repo.repository.restoreStash(dropped)
        let restored = try await repo.repository.stashes()
        #expect(restored.first?.id == dropped.id && restored.first?.summary == dropped.summary)
    }
}

@Suite struct HistoryTests {
    @Test func streamsHistoryWithGraphAndDetail() async throws {
        let repo = try TestRepo()
        try repo.write("a.txt", "a\n")
        try repo.commitAll("One")
        try repo.sh("tag", "v1")
        try repo.sh("switch", "-q", "-c", "side")
        try repo.write("s.txt", "s\n")
        try repo.commitAll("Side")
        try repo.sh("switch", "-q", "main")
        try repo.write("a.txt", "b\n")
        try repo.commitAll("Two")
        try repo.sh("merge", "-q", "--no-ff", "side", "-m", "Merge side")
        var parser = LogParser()
        var rows: [CommitRow] = []
        for try await chunk in repo.repository.history(scope: .current(upstream: nil)) { rows += parser.feed(chunk) }
        rows += parser.finish()
        #expect(rows.map(\.subject) == ["Merge side", "Side", "Two", "One"] || rows.map(\.subject) == ["Merge side", "Two", "Side", "One"])
        #expect(rows[0].isMerge)
        #expect(rows[0].refLabels.contains(RefLabel(kind: .localBranch, name: "main", isCurrent: true)))
        #expect(rows.last?.refLabels.contains(RefLabel(kind: .tag, name: "v1")) == true)
        var layout = GraphLayout()
        for row in rows { layout.append(id: row.id, parents: row.parents) }
        #expect(layout.maxLanes == 2)

        let detail = try await repo.repository.commitDetail(rows[0].id)
        #expect(detail.subject == "Merge side" && detail.parents.count == 2)
        let files = try await repo.repository.changedFiles(in: rows[0].id, parent: detail.parents[0])
        #expect(files.map(\.path) == ["s.txt"])
        let root = rows.last!
        let rootFiles = try await repo.repository.changedFiles(in: root.id, parent: nil)
        #expect(rootFiles.map(\.path) == ["a.txt"])
        let diff = try await repo.repository.diff(of: rootFiles[0], in: root.id, parent: nil)
        #expect(diff.file?.isNew == true)
    }

    @Test func unbornRepositoryHasNoHistory() async throws {
        let repo = try TestRepo()
        var count = 0
        do {
            for try await _ in repo.repository.history(scope: .current(upstream: nil)) { count += 1 }
            Issue.record("log on an unborn branch fails")
        } catch {
            #expect(count == 0)
        }
        #expect(try await repo.status().branch.isUnborn)
    }

    @Test func historyStreamCanBeCancelled() async throws {
        guard let big = fixture("big") else { return }
        let repository = Repository(location: RepositoryLocation(root: big, gitDirectory: big.appendingPathComponent(".git")),
                                    runner: fixtureRunner())
        var bytes = 0
        for try await chunk in repository.history(scope: .all) {
            bytes += chunk.count
            if bytes > 100_000 { break }
        }
        #expect(bytes > 100_000)
    }
}

@Suite struct ConflictTests {
    @Test func mergeInProgressCanBeAbortedOrContinued() async throws {
        let repo = try TestRepo()
        try repo.write("shared.txt", "alpha\nbeta\ngamma\n")
        try repo.commitAll("Base")
        try repo.sh("switch", "-q", "-c", "theirs")
        try repo.write("shared.txt", "alpha\nTHEIRS\ngamma\n")
        try repo.commitAll("Theirs")
        try repo.sh("switch", "-q", "main")
        try repo.write("shared.txt", "alpha\nOURS\ngamma\n")
        try repo.commitAll("Ours")
        try repo.sh("merge", "-q", "theirs", allowFailure: true)
        #expect(repo.repository.inProgressOperation() == .merge)
        let status = try await repo.status()
        #expect(status.conflicted.map(\.path) == ["shared.txt"])
        #expect(repo.repository.hasConflictMarkers("shared.txt"))
        try await repo.repository.abortOperation(.merge)
        #expect(repo.repository.inProgressOperation() == nil)

        try repo.sh("merge", "-q", "theirs", allowFailure: true)
        try repo.write("shared.txt", "alpha\nBOTH\ngamma\n")
        #expect(!repo.repository.hasConflictMarkers("shared.txt"))
        try await repo.repository.stage(paths: ["shared.txt"]) // Mark Resolved
        try await repo.repository.continueOperation(.merge)
        #expect(repo.repository.inProgressOperation() == nil)
        #expect(try await repo.repository.commitDetail(try await repo.repository.resolve("HEAD")).parents.count == 2)
    }

    @Test func detectsEveryOperation() throws {
        let dir = try TestRepo.makeDirectory("state")
        #expect(InProgressOperation.detect(gitDirectory: dir) == nil)
        for (marker, op) in [("MERGE_HEAD", InProgressOperation.merge), ("CHERRY_PICK_HEAD", .cherryPick), ("REVERT_HEAD", .revert)] {
            let file = dir.appendingPathComponent(marker)
            try Data().write(to: file)
            #expect(InProgressOperation.detect(gitDirectory: dir) == op)
            try FileManager.default.removeItem(at: file)
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("rebase-merge"), withIntermediateDirectories: true)
        #expect(InProgressOperation.detect(gitDirectory: dir) == .rebase)
    }

    @Test func conflictMarkers() {
        #expect(ConflictMarkers.present(in: Data("a\n<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> theirs\n".utf8)))
        #expect(!ConflictMarkers.present(in: Data("a\n<<<<<<< not closed\n".utf8)))
    }
}

/// A runner that answers from a closure and records every command.
final class ScriptedRunner: GitRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [GitCommand] = []
    private let respond: @Sendable (GitCommand, Int) -> GitResult

    init(_ respond: @escaping @Sendable (GitCommand, Int) -> GitResult) {
        self.respond = respond
    }

    var commands: [GitCommand] { lock.withLock { recorded } }

    func run(_ command: GitCommand, onStderr: (@Sendable (Data) -> Void)?) async throws -> GitResult {
        let index = lock.withLock { recorded.append(command); return recorded.count - 1 }
        return respond(command, index)
    }

    func stream(_ command: GitCommand) -> AsyncThrowingStream<Data, any Error> {
        let result = respond(command, lock.withLock { recorded.append(command); return recorded.count - 1 })
        return AsyncThrowingStream { $0.yield(result.stdout); $0.finish() }
    }
}

@Suite struct ConflictDiffTests {
    @Test func conflictedFilesShowTheirMarkers() async throws {
        let repo = try TestRepo()
        try repo.write("shared.txt", "alpha\nbeta\ngamma\n")
        try repo.commitAll("Base")
        try repo.sh("switch", "-q", "-c", "theirs")
        try repo.write("shared.txt", "alpha\nTHEIRS\ngamma\n")
        try repo.commitAll("Theirs")
        try repo.sh("switch", "-q", "main")
        try repo.write("shared.txt", "alpha\nOURS\ngamma\n")
        try repo.commitAll("Ours")
        try repo.sh("merge", "-q", "theirs", allowFailure: true)
        let entry = try await repo.entry("shared.txt")
        let file = try #require(try await repo.repository.diff(for: entry, staged: false).file)
        let added = file.hunks.flatMap(\.lines).filter { $0.kind == .added }.map { file.text(of: $0) }
        #expect(added.contains("<<<<<<< HEAD"))
        #expect(added.contains("THEIRS"))
    }
}
