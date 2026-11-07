import Foundation
import Testing
@testable import CommitCore

@Suite struct ObjectIDTests {
    @Test func roundTripsSHA1AndSHA256() throws {
        let sha1 = "27f1a8b0128262dd257ce8ffe6ae36613ef2ba48"
        let id = try #require(ObjectID(hex: sha1))
        #expect(id.hex == sha1)
        #expect(id.short == "27f1a8b")
        #expect(id.length == 40)
        let sha256 = String(repeating: "0123456789abcdef", count: 4)
        let long = try #require(ObjectID(hex: sha256))
        #expect(long.hex == sha256)
        #expect(long != id)
    }

    @Test func acceptsUppercaseAndRejectsGarbage() {
        #expect(ObjectID(hex: "27F1A8B0128262DD257CE8FFE6AE36613EF2BA48")?.hex == "27f1a8b0128262dd257ce8ffe6ae36613ef2ba48")
        #expect(ObjectID(hex: "xyz") == nil)
        #expect(ObjectID(hex: String(repeating: "g", count: 40)) == nil)
        #expect(ObjectID(hex: String(repeating: "a", count: 41)) == nil)
    }
}

@Suite struct StatusParserTests {
    static let sample: Data = {
        var s = ""
        s += "# branch.oid b8f45929644c923c57d9aeda5b9b2b1ce9f85f49\0"
        s += "# branch.head main\0"
        s += "# branch.upstream origin/main\0"
        s += "# branch.ab +1 -2\0"
        s += "1 MM N... 100644 100644 100644 de980441c3ab03a8c07dda1ad27b8a11f39deb1e 7be73ce3c1b1cdaea86e8168dfee8575175953bf notes.txt\0"
        s += "2 R. N... 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb 587be6b4c3f93f93c489c0111bba5596147a26cb R100 new name.txt\0old-name.txt\0"
        s += "1 .M S.M. 160000 160000 160000 aaaa0441c3ab03a8c07dda1ad27b8a11f39deb1e aaaa0441c3ab03a8c07dda1ad27b8a11f39deb1e lib\0"
        s += "u UU N... 100644 100644 100644 100644 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 3333333333333333333333333333333333333333 shared.txt\0"
        s += "? todo list.txt\0"
        s += "? node_modules/\0"
        return Data(s.utf8)
    }()

    @Test func parsesEveryKindOfEntry() throws {
        let status = StatusParser.parse(Self.sample)
        #expect(status.branch.branch == "main")
        #expect(status.branch.upstream == "origin/main")
        #expect(status.branch.ahead == 1)
        #expect(status.branch.behind == 2)
        #expect(status.branch.head?.short == "b8f4592")
        #expect(status.entries.count == 6)

        let notes = status.entries[0]
        #expect(notes.staged == .modified && notes.unstaged == .modified)
        #expect(notes.hasStagedChanges && notes.hasUnstagedChanges)
        #expect(notes.hashes.count == 2)

        let renamed = status.entries[1]
        #expect(renamed.path == "new name.txt")
        #expect(renamed.originalPath == "old-name.txt")
        #expect(renamed.hasStagedChanges && !renamed.hasUnstagedChanges)

        #expect(status.entries[2].isSubmodule)
        let conflict = status.entries[3]
        #expect(conflict.isConflicted)
        #expect(!conflict.hasStagedChanges && !conflict.hasUnstagedChanges)
        #expect(status.entries[4].path == "todo list.txt" && status.entries[4].isUntracked)
        #expect(status.entries[5].path == "node_modules/")
        #expect(status.staged.map(\.path) == ["notes.txt", "new name.txt"])
        #expect(status.unstaged.map(\.path) == ["notes.txt", "lib", "todo list.txt", "node_modules/"])
        #expect(status.conflicted.map(\.path) == ["shared.txt"])
    }

    @Test func unbornAndDetachedHeads() {
        let unborn = StatusParser.parse(Data("# branch.oid (initial)\0# branch.head main\0".utf8))
        #expect(unborn.branch.isUnborn)
        #expect(unborn.branch.branch == "main")
        #expect(unborn.isClean)
        let detached = StatusParser.parse(Data("# branch.oid b8f45929644c923c57d9aeda5b9b2b1ce9f85f49\0# branch.head (detached)\0".utf8))
        #expect(detached.branch.isDetached)
    }

    @Test func splitsNameAndFolder() {
        #expect(StatusEntry.split("Sources/App/main.swift") == ("main.swift", "Sources/App"))
        #expect(StatusEntry.split("README.md") == ("README.md", ""))
        #expect(StatusEntry.split("node_modules/") == ("node_modules", ""))
    }
}

@Suite struct DiffParserTests {
    @Test func parsesHunksAndLineNumbers() throws {
        let text = """
        diff --git a/notes.txt b/notes.txt
        index 1111111..2222222 100644
        --- a/notes.txt
        +++ b/notes.txt
        @@ -1,4 +1,5 @@ heading
         one
        -two
        +TWO
        +two and a half
         three
         four
        @@ -10 +11 @@
        -ten
        +TEN

        """
        let file = try #require(DiffParser.parseSingle(Data(text.utf8)))
        #expect(file.oldPath == "notes.txt" && file.newPath == "notes.txt")
        #expect(file.hunks.count == 2)
        let h = file.hunks[0]
        #expect(h.oldStart == 1 && h.oldCount == 4 && h.newStart == 1 && h.newCount == 5)
        #expect(h.heading == "heading")
        #expect(h.lines.map(\.kind) == [.context, .removed, .added, .added, .context, .context])
        #expect(h.lines.map(\.oldNumber) == [1, 2, 0, 0, 3, 4])
        #expect(h.lines.map(\.newNumber) == [1, 0, 2, 3, 4, 5])
        #expect(file.text(of: h.lines[2]) == "TWO")
        #expect(file.hunks[1].oldCount == 1 && file.hunks[1].newStart == 11)
        #expect(file.additions == 3 && file.deletions == 2)
    }

    @Test func newDeletedBinaryRenamedAndModeChanges() throws {
        let text = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..2222222
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1 @@
        +hello
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        index 2222222..0000000
        --- a/gone.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -bye
        diff --git a/logo.png b/logo.png
        index 1111111..2222222 100644
        Binary files a/logo.png and b/logo.png differ
        diff --git a/old name.txt b/new name.txt
        similarity index 100%
        rename from old name.txt
        rename to new name.txt
        diff --git a/run.sh b/run.sh
        old mode 100644
        new mode 100755

        """
        let files = DiffParser.parse(Data(text.utf8))
        #expect(files.count == 5)
        #expect(files[0].isNew && files[0].oldPath == nil && files[0].newPath == "new.txt")
        #expect(files[1].isDeleted && files[1].path == "gone.txt")
        #expect(files[2].isBinary)
        #expect(files[3].isRename && files[3].oldPath == "old name.txt" && files[3].newPath == "new name.txt")
        #expect(files[4].isModeChangeOnly)
    }

    @Test func keepsCRLFAndNoNewlineMarkers() throws {
        var data = Data("diff --git a/w.txt b/w.txt\n--- a/w.txt\n+++ b/w.txt\n@@ -1,2 +1,2 @@\n first\r\n-second\r\n+SECOND\r\n".utf8)
        data.append(Data("diff --git a/n.txt b/n.txt\n--- a/n.txt\n+++ b/n.txt\n@@ -1 +1 @@\n-last\n\\ No newline at end of file\n+last\n".utf8))
        let files = DiffParser.parse(data)
        let crlf = files[0]
        #expect(crlf.hasCarriageReturn(crlf.hunks[0].lines[1]))
        #expect(crlf.text(of: crlf.hunks[0].lines[2]) == "SECOND")
        #expect(crlf.bytes(of: crlf.hunks[0].lines[2]) == Data("SECOND\r".utf8))
        let noNewline = files[1]
        #expect(noNewline.hunks[0].lines[0].noNewlineAtEnd)
        #expect(!noNewline.hunks[0].lines[1].noNewlineAtEnd)
    }

    @Test func unquotesPaths() {
        #expect(DiffParser.unquote("\"a\\tb\"") == "a\tb")
        #expect(DiffParser.unquote("\"caf\\303\\251\"") == "café")
        #expect(DiffParser.unquote("plain") == "plain")
        #expect(DiffParser.headerPath("\"b/sp ace\\\"q\"", prefix: "b/") == "sp ace\"q")
        #expect(DiffParser.parseGitHeaderPaths("a/x y b/x y").old == "x y")
    }

    @Test func hunkHeaderVariants() throws {
        let a = try #require(DiffParser.parseHunkHeader("@@ -5,0 +6,2 @@"))
        #expect(a.oldStart == 5 && a.oldCount == 0 && a.newStart == 6 && a.newCount == 2 && a.heading.isEmpty)
        let b = try #require(DiffParser.parseHunkHeader("@@ -1 +1 @@ func x() {"))
        #expect(b.oldCount == 1 && b.newCount == 1 && b.heading == "func x() {")
        #expect(b.headerText == "@@ -1 +1 @@ func x() {")
    }
}

@Suite struct LogParserTests {
    static func record(_ hash: String, parents: [String], author: String = "Ada", time: Int = 1_700_000_000,
                       decorations: String = "", subject: String) -> String {
        [hash, parents.joined(separator: " "), author, "\(author.lowercased())@example.com", "\(time)", decorations, subject]
            .joined(separator: "\u{1f}") + "\0"
    }

    static func hash(_ n: Int) -> String { String(format: "%040x", n) }

    @Test func parsesRecordsSplitAcrossChunks() {
        let text = Self.record(Self.hash(3), parents: [Self.hash(2), Self.hash(1)], decorations: "HEAD -> refs/heads/main, tag: refs/tags/v1",
                               subject: "Merge stuff")
            + Self.record(Self.hash(2), parents: [Self.hash(1)], author: "Grace", subject: "Two: with a \u{1f}? no")
            + Self.record(Self.hash(1), parents: [], subject: "Root")
        let data = Data(text.utf8)
        var parser = LogParser()
        var rows: [CommitRow] = []
        var i = 0
        while i < data.count {
            let end = min(data.count, i + 7)
            rows += parser.feed(data[i..<end])
            i = end
        }
        rows += parser.finish()
        #expect(rows.count == 3)
        #expect(rows[0].isMerge)
        #expect(rows[0].refLabels == [RefLabel(kind: .localBranch, name: "main", isCurrent: true), RefLabel(kind: .tag, name: "v1")])
        #expect(rows[1].subject == "Two: with a \u{1f}? no")
        #expect(parser.authors.name(rows[1].author) == "Grace")
        #expect(rows[2].parents.isEmpty)
        #expect(rows[0].author == rows[2].author)
    }

    @Test func refLabelsSkipRemoteHEADAndStash() {
        let labels = RefLabel.parse("refs/remotes/origin/main, refs/remotes/origin/HEAD, refs/stash, HEAD")
        #expect(labels == [RefLabel(kind: .remoteBranch, name: "origin/main"), RefLabel(kind: .head, name: "HEAD")])
    }

    @Test func commitDetailAndNameStatus() throws {
        let detail = try #require(CommitDetail.parse(Data(([Self.hash(9), Self.hash(8), "Ada", "ada@example.com", "1700000000",
                                                            "Ada", "ada@example.com", "1700000100", "", "Subject line\n\nBody text\n"]
                                                            .joined(separator: "\u{1f}")).utf8)))
        #expect(detail.subject == "Subject line")
        #expect(detail.body == "Body text")
        #expect(detail.parents.count == 1)
        let files = ChangedFile.parseNameStatus(Data("M\0a.txt\0R100\0old.txt\0new.txt\0D\0gone.txt\0".utf8))
        #expect(files == [ChangedFile(path: "a.txt", change: .modified),
                          ChangedFile(path: "new.txt", originalPath: "old.txt", change: .renamed),
                          ChangedFile(path: "gone.txt", change: .deleted)])
    }
}

@Suite struct RefParserTests {
    @Test func parsesBranchesRemotesAndTags() {
        let text = [
            "refs/heads/feature/search\u{1f}27f1a8b0128262dd257ce8ffe6ae36613ef2ba48\u{1f}refs/remotes/origin/feature/search\u{1f} \u{1f}",
            "refs/heads/main\u{1f}b8f45929644c923c57d9aeda5b9b2b1ce9f85f49\u{1f}refs/remotes/origin/main\u{1f}*\u{1f}",
            "refs/remotes/origin/HEAD\u{1f}cc5581e4d7d4e6f57f7261196164684f4eba72a1\u{1f}\u{1f} \u{1f}refs/remotes/origin/main",
            "refs/remotes/origin/feature/search\u{1f}27f1a8b0128262dd257ce8ffe6ae36613ef2ba48\u{1f}\u{1f} \u{1f}",
            "refs/tags/v0.1\u{1f}aaaaaaa0128262dd257ce8ffe6ae36613ef2ba48\u{1f}\u{1f} \u{1f}",
        ].joined(separator: "\n") + "\n"
        let refs = RefList.parse(Data(text.utf8))
        #expect(refs.local.map(\.name) == ["feature/search", "main"])
        #expect(refs.current?.name == "main")
        #expect(refs.current?.upstreamName == "origin/main")
        #expect(refs.remote.map(\.name) == ["origin/feature/search"])
        #expect(refs.remote[0].remoteName == "origin")
        #expect(refs.remote[0].nameOnRemote == "feature/search")
        #expect(refs.tags.map(\.name) == ["v0.1"])
        #expect(refs.remoteNames == ["origin"])
        #expect(RefList.filter(refs.local, "SEAR").map(\.name) == ["feature/search"])
    }

    @Test func parsesStashes() {
        let text = "8f0b893a4d037475369ca80135c22b80a378ce4c\u{1f}stash@{0}\u{1f}On main: WIP: scratch file\u{1f}1794072038\0"
            + "3f8219255d7d4e35ad45d9c5df2285ab40393d6b\u{1f}stash@{1}\u{1f}WIP on feature/x: 1234567 Subject\u{1f}1794072000\0"
        let stashes = StashEntry.parse(Data(text.utf8))
        #expect(stashes.count == 2)
        #expect(stashes[0].message == "WIP: scratch file")
        #expect(stashes[0].branch == "main")
        #expect(stashes[1].branch == "feature/x")
        #expect(stashes[1].selector == "stash@{1}")
    }

    @Test func validatesBranchNames() {
        #expect(BranchName.problem(with: "feature/search") == nil)
        #expect(BranchName.problem(with: "") != nil)
        #expect(BranchName.problem(with: "has space") != nil)
        #expect(BranchName.problem(with: "a..b") != nil)
        #expect(BranchName.problem(with: "x.lock") != nil)
        #expect(BranchName.problem(with: "-x") != nil)
        #expect(BranchName.problem(with: "a//b") != nil)
        #expect(BranchName.problem(with: "a/.b") != nil)
        #expect(BranchName.problem(with: "what?") != nil)
        #expect(BranchName.suggest(from: " fix the bug ") == "fix-the-bug")
    }
}

@Suite struct MessageAndFormattingTests {
    @Test func countsAndHints() {
        var m = CommitMessage(subject: String(repeating: "a", count: 42))
        #expect(m.counterText == "42/50" && m.subjectLength == .fine && m.subjectHint == nil)
        m.subject = String(repeating: "a", count: 60)
        #expect(m.counterText == "60/72" && m.subjectLength == .long)
        m.subject = String(repeating: "a", count: 80)
        #expect(m.subjectLength == .tooLong && m.subjectHint != nil)
    }

    @Test func buildsAndSplitsMessages() {
        let m = CommitMessage(subject: " Fix the bug ", body: "\nBecause.\n# not a comment\n")
        #expect(m.text == "Fix the bug\n\nBecause.\n# not a comment\n")
        #expect(CommitMessage(subject: "Only").text == "Only\n")
        let split = CommitMessage(text: "Subject\n\nBody line 1\nBody line 2\n")
        #expect(split.subject == "Subject" && split.body == "Body line 1\nBody line 2")
        #expect(CommitMessage(subject: "", body: "  ").isEmpty)
        #expect(CommitMessage(subject: "x", body: String(repeating: "b", count: 80)).longBodyLines == [1])
    }

    @Test func buttonTitles() {
        #expect(CommitButtonTitle.title(stagedFiles: 0, amend: false) == "Commit")
        #expect(CommitButtonTitle.title(stagedFiles: 1, amend: false) == "Commit 1 File")
        #expect(CommitButtonTitle.title(stagedFiles: 3, amend: false) == "Commit 3 Files")
        #expect(CommitButtonTitle.title(stagedFiles: 0, amend: true) == "Amend Message")
    }

    @Test func recentRepositories() {
        var recents = RecentRepositories()
        for i in 0..<20 { recents.add("/r\(i)") }
        #expect(recents.paths.count == RecentRepositories.limit)
        #expect(recents.paths.first == "/r19")
        recents.add("/r15")
        #expect(recents.paths.first == "/r15" && recents.paths.filter { $0 == "/r15" }.count == 1)
        recents.remove("/r15")
        #expect(!recents.paths.contains("/r15"))
    }

    @Test func draftsPersist() throws {
        let dir = try TestRepo.makeDirectory("drafts")
        let store = DraftStore(directory: dir)
        store.save(CommitMessage(subject: "Half done", body: "more"), for: "/repo")
        #expect(DraftStore(directory: dir).draft(for: "/repo") == CommitMessage(subject: "Half done", body: "more"))
        store.save(CommitMessage(), for: "/repo")
        #expect(DraftStore(directory: dir).draft(for: "/repo") == nil)
    }

    @Test func relativeDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_767_607_200) // Mon 5 Jan 2026 10:00 UTC
        #expect(RelativeDate.string(for: now.addingTimeInterval(-30), now: now, calendar: calendar, locale: locale) == "Just now")
        #expect(RelativeDate.string(for: now.addingTimeInterval(-300), now: now, calendar: calendar, locale: locale) == "5 min ago")
        #expect(RelativeDate.string(for: now.addingTimeInterval(-7200), now: now, calendar: calendar, locale: locale) == "2 hr ago")
        #expect(RelativeDate.string(for: now.addingTimeInterval(-86_400), now: now, calendar: calendar, locale: locale) == "Yesterday")
        #expect(RelativeDate.string(for: now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar, locale: locale) == "Friday")
        #expect(RelativeDate.string(for: now.addingTimeInterval(-400 * 86_400), now: now, calendar: calendar, locale: locale) == "Dec 1, 2024")
    }
}

@Suite struct ExplanationTests {
    @Test func recognisesCommonFailures() {
        func cause(_ output: String, _ op: GitOperation = .push) -> Explanation.Cause {
            Explanation.explain(output, operation: op, remote: "origin").cause
        }
        #expect(cause(" ! [rejected]        main -> main (fetch first)\nerror: failed to push some refs") == .rejectedPush)
        #expect(Explanation.explain(" ! [rejected] main -> main (non-fast-forward)", operation: .push, remote: "origin").action == .pull)
        #expect(cause("fatal: Need to specify how to reconcile divergent branches.", .pull) == .divergentBranches)
        #expect(cause("Author identity unknown\n*** Please tell me who you are.", .commit) == .missingIdentity)
        #expect(cause("fatal: Unable to create '/r/.git/index.lock': File exists.", .stage) == .indexLocked)
        #expect(cause("error: Your local changes to the following files would be overwritten by checkout:\n\tnotes.txt", .switchBranch) == .wouldOverwrite)
        #expect(Explanation.explain("error: Your local changes would be overwritten by checkout", operation: .switchBranch).action == .stashAndSwitch)
        #expect(cause("error: gpg failed to sign the data\nfatal: failed to write commit object", .commit) == .signing)
        #expect(cause("fatal: could not read Username for 'https://github.com': terminal prompts disabled", .fetch) == .authentication)
        #expect(cause("git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.", .fetch) == .authentication)
        #expect(cause("fatal: unable to access 'https://x/': Could not resolve host: x", .fetch) == .unreachable)
        #expect(cause("CONFLICT (content): Merge conflict in a.txt\nAutomatic merge failed", .pull) == .conflicts)
        #expect(cause("pre-commit hook: lint failed", .commit) == .hookOrOther)
        #expect(cause("fatal: cannot open '.git/FETCH_HEAD': Operation not permitted", .fetch) == .permissionDenied)
        #expect(Explanation.explain("fatal: something odd happened", operation: .stash).message == "Something odd happened")
    }

    @Test func progressLines() {
        let p = GitProgress.parse("Counting objects: 100% (3/3), done.\rReceiving objects:  45% (450/1000), 1.2 MiB | 2 MiB/s\r")
        #expect(p == GitProgress(phase: "Receiving objects", fraction: 0.45))
        #expect(GitProgress.parse("remote: Compressing objects: 100% (2/2), done.\n")?.fraction == 1)
        #expect(GitProgress.parse("To /tmp/remote.git\n") == nil)
    }
}

@Suite struct AskpassPromptTests {
    @Test func classifiesPrompts() {
        let user = AskpassPrompt(text: "Username for 'https://github.com': ")
        #expect(user.kind == .username && user.title == "Sign In to github.com")
        let password = AskpassPrompt(text: "Password for 'https://ada@github.com': ")
        #expect(password.kind == .secret && password.title == "Password for github.com")
        let passphrase = AskpassPrompt(text: "Enter passphrase for key '/Users/ada/.ssh/id_ed25519': ")
        #expect(passphrase.kind == .secret && passphrase.title == "Passphrase for id_ed25519")
        let host = AskpassPrompt(text: "The authenticity of host 'example.com' can't be established.\nAre you sure you want to continue connecting (yes/no/[fingerprint])? ")
        #expect(host.kind == .confirmation && host.title == "Trust This Server?")
        #expect(AskpassPrompt.confirmationAnswer(true) == "yes")
    }

    @Test func socketRoundTrip() async throws {
        let dir = try TestRepo.makeDirectory("askpass")
        let server = try AskpassServer(directory: dir, token: "secret-token") { prompt in
            prompt.kind == .username ? "ada" : "hunter2-\(prompt.repositoryID ?? "?")"
        }
        defer { server.stop() }
        let env = [AskpassProtocol.socketVariable: server.socketPath, AskpassProtocol.tokenVariable: "secret-token",
                   AskpassProtocol.repositoryVariable: "repo-1"]
        let answer = await Task.detached { AskpassClient.ask(prompt: "Password for 'https://x.com': ", environment: env) }.value
        #expect(answer == "hunter2-repo-1")
        let user = await Task.detached { AskpassClient.ask(prompt: "Username for 'https://x.com': ", environment: env) }.value
        #expect(user == "ada")
        // A wrong token gets nothing.
        var bad = env
        bad[AskpassProtocol.tokenVariable] = "wrong"
        let refused = await Task.detached { AskpassClient.ask(prompt: "Password: ", environment: bad) }.value
        #expect(refused == nil)
    }

    @Test func cancelledPromptReturnsNil() async throws {
        let dir = try TestRepo.makeDirectory("askpass")
        let server = try AskpassServer(directory: dir, token: "t") { _ in nil }
        defer { server.stop() }
        let env = [AskpassProtocol.socketVariable: server.socketPath, AskpassProtocol.tokenVariable: "t"]
        let answer = await Task.detached { AskpassClient.ask(prompt: "Password: ", environment: env) }.value
        #expect(answer == nil)
    }
}

@Suite struct EnvironmentTests {
    @Test func gitEnvironmentNeverPromptsOnATerminal() {
        let env = GitEnvironment(base: ["PATH": "/usr/bin:/bin", "GPG_TTY": "/dev/ttys001", "HOME": "/Users/x"],
                                 shellPath: "/opt/homebrew/bin:/usr/bin",
                                 askpass: .init(helper: "/Applications/Commit.app/Contents/MacOS/Commit", socket: "/tmp/s", token: "t"))
        let vars = env.variables(repositoryID: "r1")
        #expect(vars["GIT_TERMINAL_PROMPT"] == "0")
        #expect(vars["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(vars["GIT_EDITOR"] == "true")
        #expect(vars["GPG_TTY"] == nil)
        #expect(vars["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(vars["GIT_ASKPASS"] == "/Applications/Commit.app/Contents/MacOS/Commit")
        #expect(vars["SSH_ASKPASS_REQUIRE"] == "force")
        #expect(vars[AskpassProtocol.repositoryVariable] == "r1")
        #expect(GitEnvironment(base: ["GIT_ASKPASS": "/x"]).variables()["GIT_ASKPASS"] == nil)
    }

    @Test func shellPathParsing() {
        let output = "Welcome to fish!\n\(ShellPath.startMarker)\n/opt/homebrew/bin:/usr/bin:/bin\n\(ShellPath.endMarker)\n"
        #expect(ShellPath.parse(output) == "/opt/homebrew/bin:/usr/bin:/bin")
        #expect(ShellPath.parse("no markers here") == nil)
        #expect(ShellPath.parse("\(ShellPath.startMarker)\n\(ShellPath.endMarker)") == nil)
        #expect(ShellPath.parse("\(ShellPath.startMarker)\nhello from rc\n/a/bin:/usr/bin\n\(ShellPath.endMarker)") == "/a/bin:/usr/bin")
    }

    @Test func shellPathResolvesFromAShell() async throws {
        let dir = try TestRepo.makeDirectory("shell")
        let shell = dir.appendingPathComponent("fake-shell")
        // A stand-in login shell that greets and then runs the command it was given.
        try "#!/bin/sh\necho 'greetings from rc'\nexport PATH=/fake/bin:/usr/bin\nshift 3\n/bin/sh -c \"$*\"\n"
            .write(to: shell, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
        #expect(await ShellPath.resolve(shell: shell.path) == "/fake/bin:/usr/bin")
        let slow = dir.appendingPathComponent("slow-shell")
        try "#!/bin/sh\nsleep 10\n".write(to: slow, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slow.path)
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await ShellPath.resolve(shell: slow.path, timeout: .milliseconds(300)) == nil)
        #expect(clock.now - start < .seconds(3))
        #expect(await ShellPath.resolve(shell: "/no/such/shell") == nil)
    }
}

@Suite struct LocatorTests {
    struct FakeProbe: GitProbe {
        var executables: Set<String>
        var tools: Bool
        var versions: [String: String]
        func isExecutable(_ path: String) -> Bool { executables.contains(path) }
        func hasDeveloperTools() async -> Bool { tools }
        func versionOutput(of path: String) async -> String? { versions[path] }
    }

    @Test func prefersOverrideThenCLTThenHomebrew() async {
        let all = FakeProbe(executables: ["/usr/bin/git", "/opt/homebrew/bin/git", "/custom/git"], tools: true,
                            versions: ["/usr/bin/git": "git version 2.39.5 (Apple Git-154)", "/opt/homebrew/bin/git": "git version 2.47.0",
                                       "/custom/git": "git version 2.50.1"])
        #expect(await GitLocator(probe: all).locate(override: nil) == .found(path: "/usr/bin/git", version: GitVersion(2, 39, 5)))
        #expect(await GitLocator(probe: all).locate(override: "/custom/git") == .found(path: "/custom/git", version: GitVersion(2, 50, 1)))
        #expect(await GitLocator(probe: all).locate(override: "/nope") == .badOverride(path: "/nope"))
        var noTools = all
        noTools.tools = false
        #expect(await GitLocator(probe: noTools).locate(override: nil) == .found(path: "/opt/homebrew/bin/git", version: GitVersion(2, 47, 0)))
    }

    @Test func missingAndTooOld() async {
        let none = FakeProbe(executables: ["/usr/bin/git"], tools: false, versions: [:])
        #expect(await GitLocator(probe: none).locate(override: nil) == .missing)
        let old = FakeProbe(executables: ["/usr/local/bin/git"], tools: false, versions: ["/usr/local/bin/git": "git version 2.20.1"])
        #expect(await GitLocator(probe: old).locate(override: nil) == .tooOld(path: "/usr/local/bin/git", version: GitVersion(2, 20, 1)))
    }

    @Test func realGitOnThisMac() async {
        let found = await GitLocator(probe: SystemGitProbe()).locate(override: nil)
        if case .found(_, let version) = found { #expect(version >= GitVersion.minimum) }
    }
}
