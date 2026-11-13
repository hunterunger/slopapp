import Foundation

/// How a merge, rebase, cherry-pick or revert ended.
public enum IntegrationOutcome: Sendable, Equatable {
    /// HEAD moved from `previous` to `head`. Undo resets back to `previous`.
    case finished(previous: ObjectID, head: ObjectID)
    /// Nothing to do ("Already up to date").
    case upToDate
    /// git stopped part way (conflicts, or an empty cherry-pick); the in-progress banner takes over.
    case stopped(InProgressOperation, previous: ObjectID)
}

/// How many commits each side has that the other doesn't (`rev-list --left-right --count`).
public struct Divergence: Sendable, Equatable {
    /// Commits on the current branch only.
    public var ours: Int
    /// Commits on the other ref only.
    public var theirs: Int

    public init(ours: Int, theirs: Int) {
        self.ours = ours
        self.theirs = theirs
    }

    public static func parse(_ output: String) -> Divergence? {
        let parts = output.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" }).compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Divergence(ours: parts[0], theirs: parts[1])
    }
}

// MARK: Interactive rebase

/// What to do with one commit in an interactive rebase.
public enum RebaseAction: String, Sendable, Equatable, CaseIterable, Identifiable {
    case pick, reword, squash, fixup, drop

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pick: "Keep"
        case .reword: "Reword"
        case .squash: "Squash"
        case .fixup: "Fixup"
        case .drop: "Drop"
        }
    }

    /// One line for the action menu.
    public var explanation: String {
        switch self {
        case .pick: "Keep the commit as it is."
        case .reword: "Keep the changes, edit the message."
        case .squash: "Combine into the commit above, keeping both messages."
        case .fixup: "Combine into the commit above, keeping only its message."
        case .drop: "Remove the commit and its changes."
        }
    }

    /// The key that sets it in the editor (as in git's todo list).
    public var key: Character {
        switch self {
        case .pick: "p"
        case .reword: "r"
        case .squash: "s"
        case .fixup: "f"
        case .drop: "d"
        }
    }

    public var combinesWithPrevious: Bool { self == .squash || self == .fixup }
}

/// One commit in the interactive rebase editor.
public struct RebaseStep: Sendable, Equatable, Identifiable {
    public var id: ObjectID
    public var action: RebaseAction
    /// The commit's full message.
    public var message: String
    /// The message the person typed (reword, or the combined message of a squash group).
    public var editedMessage: String?
    public var authorName: String
    public var date: Date

    public init(id: ObjectID, action: RebaseAction = .pick, message: String, editedMessage: String? = nil,
                authorName: String = "", date: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id
        self.action = action
        self.message = message
        self.editedMessage = editedMessage
        self.authorName = authorName
        self.date = date
    }

    public var subject: String { message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "" }
}

/// A commit and the ones combined into it.
public struct RebaseGroup: Sendable, Equatable {
    /// Index of the kept commit in `RebasePlan.steps`.
    public var head: Int
    /// Indexes of the squash and fixup steps folded into it.
    public var members: [Int]
}

/// An interactive rebase: commits oldest first, as git applies them.
public struct RebasePlan: Sendable, Equatable {
    /// The commit the rebased commits go on top of. nil: from the root commit.
    public var base: ObjectID?
    public var steps: [RebaseStep]

    public init(base: ObjectID?, steps: [RebaseStep]) {
        self.base = base
        self.steps = steps
    }

    /// Kept commits and what folds into them, in order. Squash/fixup steps attach to the closest
    /// kept step above them.
    public var groups: [RebaseGroup] {
        var groups: [RebaseGroup] = []
        for (i, step) in steps.enumerated() {
            switch step.action {
            case .drop: continue
            case .squash, .fixup:
                if !groups.isEmpty { groups[groups.count - 1].members.append(i) }
            case .pick, .reword:
                groups.append(RebaseGroup(head: i, members: []))
            }
        }
        return groups
    }

    /// The message a group ends up with: what was typed, else git's rule (the kept commit's
    /// message, then each squash's; fixups add nothing).
    public func message(of group: RebaseGroup) -> String {
        if let edited = steps[group.head].editedMessage { return edited }
        let squashed = group.members.filter { steps[$0].action == .squash }.map { steps[$0].message }
        return ([steps[group.head].message] + squashed).joined(separator: "\n\n")
    }

    /// A group whose message comes from the editor (reword, or squashes to combine).
    public func needsMessage(_ group: RebaseGroup) -> Bool {
        steps[group.head].action == .reword || group.members.contains { steps[$0].action == .squash }
            || steps[group.head].editedMessage != nil
    }

    /// Why the plan can't run, in one sentence (nil when it can).
    public var problem: String? {
        guard let first = steps.firstIndex(where: { $0.action != .drop }) else { return nil }
        if steps[first].action.combinesWithPrevious {
            return "The first commit can't be squashed or fixed up: there's no commit above it to combine with."
        }
        for group in groups where needsMessage(group) {
            if message(of: group).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "“\(steps[group.head].subject)” needs a message."
            }
        }
        return nil
    }

    /// Nothing would change.
    public var isUnchanged: Bool {
        steps.allSatisfy { $0.action == .pick && $0.editedMessage == nil } && steps.map(\.id) == originalOrder
    }

    /// The order git listed the commits in (set by the loader; reordering is a change).
    public var originalOrder: [ObjectID] = []

    /// "5 commits become 3." / "Drops 1 commit."
    public var summary: String {
        let before = steps.count
        let after = groups.count
        let dropped = steps.filter { $0.action == .drop }.count
        if after == 0 { return "Every commit is dropped. The branch goes back to its base." }
        var parts: [String] = []
        if after != before { parts.append("\(before) \(before == 1 ? "commit becomes" : "commits become") \(after).") }
        if dropped > 0 { parts.append("Drops \(dropped) \(dropped == 1 ? "commit" : "commits") and \(dropped == 1 ? "its" : "their") changes.") }
        if parts.isEmpty { parts.append(isUnchanged ? "No changes yet." : "\(after) \(after == 1 ? "commit" : "commits"), rewritten.") }
        return parts.joined(separator: " ")
    }

    /// git's todo list. Messages are written by amending after each group (`exec git commit
    /// --amend --only -F <file>`), so git never opens an editor; `messageFile(groupIndex)`
    /// names each message file and the returned dictionary holds their contents.
    public func todo(git: String, messageFile: (Int) -> URL) -> (todo: String, messages: [URL: String]) {
        var lines: [String] = []
        var messages: [URL: String] = [:]
        let groups = groups
        var groupOfHead: [Int: Int] = [:]
        var lastOfGroup: [Int: Int] = [:]
        for (g, group) in groups.enumerated() {
            groupOfHead[group.head] = g
            lastOfGroup[group.members.last ?? group.head] = g
        }
        for (i, step) in steps.enumerated() {
            switch step.action {
            case .drop: lines.append("drop \(step.id.hex)")
            case .squash: lines.append("squash \(step.id.hex)")
            case .fixup: lines.append("fixup \(step.id.hex)")
            case .pick, .reword: lines.append("pick \(step.id.hex)") // reword is done by the exec below
            }
            if let g = lastOfGroup[i], needsMessage(groups[g]) {
                let file = messageFile(g)
                messages[file] = message(of: groups[g])
                lines.append("exec \(Self.shellQuote(git)) commit --amend --only --allow-empty --quiet -F \(Self.shellQuote(file.path))")
            }
        }
        if lines.isEmpty { lines.append("noop") }
        return (lines.joined(separator: "\n") + "\n", messages)
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Editing

    public mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { steps[$0] }
        var remaining = steps.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(remaining.count, insertAt)))
        steps = remaining
    }

    /// Moves one step up (-1) or down (+1).
    public mutating func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }
}

/// `git log` rows for the interactive rebase editor.
public enum RebaseLog {
    /// hash, parents, author name, author time, full message.
    public static let format = "--format=%H%x1f%P%x1f%an%x1f%at%x1f%B"

    /// Parses `git log -z --reverse <format>`. Returns nil if a merge commit is in the range
    /// (rebasing would flatten it).
    public static func parse(_ data: Data) -> (steps: [RebaseStep], hasMerges: Bool) {
        var steps: [RebaseStep] = []
        var merges = false
        for record in data.split(separator: 0) {
            let fields = String(decoding: record, as: UTF8.self)
                .split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5, let id = ObjectID(hex: fields[0].trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            if fields[1].split(separator: " ").count > 1 { merges = true }
            steps.append(RebaseStep(id: id, message: fields[4].trimmingCharacters(in: .whitespacesAndNewlines),
                                    authorName: fields[2],
                                    date: Date(timeIntervalSince1970: TimeInterval(Int(fields[3]) ?? 0))))
        }
        return (steps, merges)
    }
}

// MARK: Repository

/// Why an integration can't start.
public enum IntegrationProblem: Error, Sendable, Equatable {
    case notAnAncestor
    case hasMerges
    case nothingToEdit
    case detached

    public var message: String {
        switch self {
        case .notAnAncestor: "That commit isn't part of the current branch, so its history can't be edited from here."
        case .hasMerges: "These commits include a merge. Editing them here would flatten it, so Commit leaves merges alone."
        case .nothingToEdit: "There are no commits to edit after that one."
        case .detached: "Switch to a branch first."
        }
    }
}

public extension Repository {
    /// Commits each side has that the other doesn't.
    func divergence(from ref: String) async -> Divergence? {
        guard let result = try? await read(["rev-list", "--left-right", "--count", "HEAD...\(ref)"]) else { return nil }
        return Divergence.parse(result.stdoutString)
    }

    /// The current HEAD commit, if any.
    func head() async -> ObjectID? { try? await resolve("HEAD") }

    /// Merges `ref` into the current branch.
    func merge(_ ref: String, noFastForward: Bool, autostash: Bool) async throws -> IntegrationOutcome {
        var arguments = ["merge", "--no-edit"]
        if noFastForward { arguments.append("--no-ff") }
        if autostash { arguments.append("--autostash") }
        arguments.append(ref)
        return try await integrate(arguments, operation: .merge)
    }

    /// Rebases the current branch onto `ref`.
    func rebase(onto ref: String, autostash: Bool) async throws -> IntegrationOutcome {
        var arguments = ["rebase"]
        if autostash { arguments.append("--autostash") }
        arguments.append(ref)
        return try await integrate(arguments, operation: .rebase)
    }

    /// Applies `commits` (oldest first) on top of the current branch.
    func cherryPick(_ commits: [ObjectID]) async throws -> IntegrationOutcome {
        try await integrate(["cherry-pick"] + commits.map(\.hex), operation: .cherryPick)
    }

    /// A new commit that undoes `commit`. Merge commits are reverted against their first parent.
    func revert(_ commit: ObjectID, isMerge: Bool) async throws -> IntegrationOutcome {
        var arguments = ["revert", "--no-edit"]
        if isMerge { arguments += ["-m", "1"] }
        arguments.append(commit.hex)
        return try await integrate(arguments, operation: .revert)
    }

    /// Commits from `commit` (inclusive) to HEAD, oldest first, for the interactive rebase editor.
    func rebasePlan(from commit: ObjectID) async throws -> RebasePlan {
        let ancestor = try await runner.run(command(["merge-base", "--is-ancestor", commit.hex, "HEAD"]))
        guard ancestor.exitCode == 0 else { throw IntegrationProblem.notAnAncestor }
        let detail = try await commitDetail(commit)
        let base = detail.parents.first
        let range = base.map { "\($0.hex)..HEAD" } ?? "HEAD"
        let result = try await read(["log", "-z", "--reverse", "--topo-order", RebaseLog.format, range, "--"])
        let parsed = RebaseLog.parse(result.stdout)
        if parsed.hasMerges { throw IntegrationProblem.hasMerges }
        guard !parsed.steps.isEmpty else { throw IntegrationProblem.nothingToEdit }
        var plan = RebasePlan(base: base, steps: parsed.steps)
        plan.originalOrder = parsed.steps.map(\.id)
        return plan
    }

    /// The commits not on the upstream yet (Edit Unpushed Commits…).
    func rebasePlanForUnpushed(upstream: String) async throws -> RebasePlan {
        let base = try await read(["merge-base", "HEAD", upstream]).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseID = ObjectID(hex: base) else { throw IntegrationProblem.nothingToEdit }
        let result = try await read(["log", "-z", "--reverse", "--topo-order", RebaseLog.format, "\(baseID.hex)..HEAD", "--"])
        let parsed = RebaseLog.parse(result.stdout)
        if parsed.hasMerges { throw IntegrationProblem.hasMerges }
        guard !parsed.steps.isEmpty else { throw IntegrationProblem.nothingToEdit }
        var plan = RebasePlan(base: baseID, steps: parsed.steps)
        plan.originalOrder = parsed.steps.map(\.id)
        return plan
    }

    /// How many of `commits` are already on the upstream (rewriting them means a force push).
    func pushedCount(_ commits: [ObjectID]) async -> Int {
        guard (try? await read(["rev-parse", "--verify", "--quiet", "@{upstream}"])) != nil else { return 0 }
        var count = 0
        for commit in commits {
            if let r = try? await runner.run(command(["merge-base", "--is-ancestor", commit.hex, "@{upstream}"])), r.exitCode == 0 {
                count += 1
            }
        }
        return count
    }

    /// Runs the plan: git gets our todo list through GIT_SEQUENCE_EDITOR and never opens an editor.
    /// `git` is the executable the exec lines run (the one Commit uses); `workDirectory` holds
    /// the todo and message files (kept until the rebase finishes, also across a conflict stop).
    func interactiveRebase(_ plan: RebasePlan, git: String, workDirectory: URL, autostash: Bool) async throws -> IntegrationOutcome {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let (todo, messages) = plan.todo(git: git) { workDirectory.appendingPathComponent("message-\($0).txt") }
        let todoFile = workDirectory.appendingPathComponent("todo.txt")
        try Data(todo.utf8).write(to: todoFile)
        for (url, text) in messages { try Data((text + "\n").utf8).write(to: url) }
        var arguments = ["rebase", "-i"]
        if autostash { arguments.append("--autostash") }
        arguments.append(plan.base?.hex ?? "--root")
        let environment = ["GIT_SEQUENCE_EDITOR": "cp \(RebasePlan.shellQuote(todoFile.path))", "GIT_EDITOR": "true"]
        return try await integrate(arguments, operation: .rebase, environment: environment)
    }

    /// Moves the branch back after an integration (Undo Merge, Undo Rebase…). `--keep` refuses
    /// rather than lose local changes.
    func undoIntegration(to previous: ObjectID) async throws {
        try await exclusive { try await self.write(["reset", "--keep", "-q", previous.hex], environment: Self.english) }
    }

    private func integrate(_ arguments: [String], operation: InProgressOperation,
                           environment: [String: String] = [:]) async throws -> IntegrationOutcome {
        guard let previous = await head() else { throw OpenProblem.git("There are no commits yet.") }
        let env = Self.english.merging(environment) { _, new in new }
        let result = try await exclusive { try await self.runner.run(self.command(arguments, environment: env)) }
        if result.succeeded {
            let now = await head() ?? previous
            return now == previous ? .upToDate : .finished(previous: previous, head: now)
        }
        if let stopped = inProgressOperation() { return .stopped(stopped, previous: previous) }
        throw GitFailure(command: command(arguments), result: result)
    }
}

public extension Repository {
    /// Whether `commit` is already on the current branch.
    func headContains(_ commit: ObjectID) async -> Bool {
        guard let r = try? await runner.run(command(["merge-base", "--is-ancestor", commit.hex, "HEAD"])) else { return false }
        return r.exitCode == 0
    }
}
