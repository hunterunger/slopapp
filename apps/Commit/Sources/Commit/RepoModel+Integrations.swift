import AppKit
import CommitCore
import SlopKit

/// Which integration a sheet starts.
enum IntegrationKind: Equatable {
    case merge, rebase
}

extension RepoModel {
    var currentBranchName: String { status.branch.branch ?? "HEAD" }

    /// Merge, rebase, cherry-pick and history editing need a branch with commits, nothing
    /// else running, and no operation already stopped part way.
    var canIntegrate: Bool {
        repository != nil && activity == nil && inProgress == nil && !status.branch.isUnborn && status.conflicted.isEmpty
    }

    var canIntegrateOnBranch: Bool { canIntegrate && !status.branch.isDetached }

    // MARK: Merge and rebase

    func showIntegrate(_ kind: IntegrationKind, preselected: GitRef? = nil) {
        guard canIntegrateOnBranch else { NSSound.beep(); return }
        sheet = .integrate(kind, preselected: preselected?.name)
    }

    func merge(_ ref: String, noFastForward: Bool) {
        guard let repository else { return }
        let dirty = !status.isClean
        let branch = currentBranchName
        integrate(.merge, title: "Merging \(ref)", undoName: "Merge") {
            try await repository.merge(ref, noFastForward: noFastForward, autostash: dirty)
        } finished: { _ in
            "Merged \(ref) into \(branch)"
        }
    }

    func rebase(onto ref: String) {
        guard let repository else { return }
        let dirty = !status.isClean
        let branch = currentBranchName
        integrate(.rebase, title: "Rebasing onto \(ref)", undoName: "Rebase") {
            try await repository.rebase(onto: ref, autostash: dirty)
        } finished: { _ in
            "Rebased \(branch) onto \(ref)"
        }
    }

    // MARK: Cherry-pick and revert

    /// Commits in history order, oldest first (the order to apply them in).
    func oldestFirst(_ ids: [ObjectID]) -> [ObjectID] {
        var position: [ObjectID: Int] = [:]
        let wanted = Set(ids)
        for (i, row) in history.rows.enumerated() where wanted.contains(row.id) { position[row.id] = i }
        return ids.sorted { (position[$0] ?? 0) > (position[$1] ?? 0) }
    }

    var cherryPickTitle: String {
        let n = selectedCommits.count
        return n > 1 ? "Cherry-pick \(n) Commits onto \(currentBranchName)" : "Cherry-pick onto \(currentBranchName)"
    }

    var canCherryPickSelection: Bool { canIntegrate && isShowingHistory && !selectedCommits.isEmpty }

    func cherryPickSelection() { cherryPick(selectedCommits) }

    func cherryPick(_ ids: [ObjectID]) {
        guard let repository, canIntegrate, !ids.isEmpty else { return }
        let ordered = oldestFirst(ids)
        let branch = currentBranchName
        integrate(.cherryPick, title: ordered.count == 1 ? "Cherry-picking \(ordered[0].short)" : "Cherry-picking \(ordered.count) commits",
                  undoName: "Cherry-pick") {
            var picks: [ObjectID] = []
            for id in ordered where !(await repository.headContains(id)) { picks.append(id) }
            guard !picks.isEmpty else {
                throw OpenProblem.git(ordered.count == 1 ? "That commit is already on \(branch)." : "Those commits are already on \(branch).")
            }
            return try await repository.cherryPick(picks)
        } finished: { _ in
            ordered.count == 1 ? "Cherry-picked \(ordered[0].short) onto \(branch)" : "Cherry-picked \(ordered.count) commits onto \(branch)"
        }
    }

    /// Commit hashes dropped on a branch in the sidebar (dragged from History).
    func dropCommits(_ strings: [String], onto ref: GitRef) -> Bool {
        let ids = strings.flatMap { $0.split(whereSeparator: \.isWhitespace) }.compactMap { ObjectID(hex: String($0)) }
        guard !ids.isEmpty, ref.kind == .local else { return false }
        guard ref.isHead else {
            HUD.show("Switch to \(ref.name) to cherry-pick onto it.", systemImage: "arrow.triangle.branch")
            return false
        }
        guard canIntegrate else { NSSound.beep(); return false }
        cherryPick(ids)
        return true
    }

    func revert(_ id: ObjectID) {
        guard let repository, canIntegrate else { return }
        let isMerge = history.rows.first { $0.id == id }?.isMerge ?? false
        integrate(.revert, title: "Reverting \(id.short)", undoName: "Revert") {
            try await repository.revert(id, isMerge: isMerge)
        } finished: { _ in
            "Reverted \(id.short) with a new commit"
        }
    }

    // MARK: Interactive rebase

    func editHistory(from id: ObjectID) {
        guard let repository, canIntegrateOnBranch else { NSSound.beep(); return }
        Task {
            do {
                let plan = try await repository.rebasePlan(from: id)
                let pushed = await repository.pushedCount(plan.steps.map(\.id))
                sheet = .interactiveRebase(plan, pushedCount: pushed)
            } catch {
                showIntegrationProblem(error, operation: .interactiveRebase)
            }
        }
    }

    var canEditUnpushed: Bool { canIntegrateOnBranch && status.branch.upstream != nil && status.branch.ahead > 0 }

    func editUnpushedCommits() {
        guard let repository, let upstream = status.branch.upstream, canIntegrateOnBranch else { NSSound.beep(); return }
        Task {
            do {
                let plan = try await repository.rebasePlanForUnpushed(upstream: upstream)
                sheet = .interactiveRebase(plan, pushedCount: 0)
            } catch {
                showIntegrationProblem(error, operation: .interactiveRebase)
            }
        }
    }

    func runInteractiveRebase(_ plan: RebasePlan) {
        guard let repository, let git = app.gitPath else { return }
        let dirty = !status.isClean
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("commit-rebase", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let before = plan.steps.count, after = plan.groups.count
        integrate(.interactiveRebase, title: "Rewriting history", undoName: "Edit History") {
            try await repository.interactiveRebase(plan, git: git, workDirectory: work, autostash: dirty)
        } finished: { _ in
            before == after ? "Rewrote \(after) \(after == 1 ? "commit" : "commits")" : "\(before) commits became \(after)"
        }
    }

    // MARK: Running

    /// Runs an integration with the activity in the toolbar. Finished: a HUD and ⌘Z (back to
    /// the old tip with `reset --keep`). Stopped: Changes with the first conflict selected.
    private func integrate(_ operation: GitOperation, title: String, undoName: String,
                           _ body: @escaping @MainActor () async throws -> IntegrationOutcome,
                           finished: @escaping @MainActor (IntegrationOutcome) -> String) {
        activityTask = Task {
            activity = Activity(title: title, progress: nil, isCancellable: false)
            var stopped = false
            do {
                let outcome = try await body()
                activity = nil
                switch outcome {
                case .finished(let previous, let head):
                    HUD.show(finished(outcome), systemImage: "checkmark.circle")
                    registerUndo(undoName) { [weak self] in self?.undoIntegration(previous: previous, head: head, name: undoName) }
                case .upToDate:
                    HUD.show("Already up to date", systemImage: "checkmark.circle")
                case .stopped(let op, _):
                    stopped = true
                    HUD.show("\(op.noun) stopped: resolve the conflicts to continue", systemImage: "exclamationmark.triangle")
                }
            } catch {
                activity = nil
                showIntegrationProblem(error, operation: operation)
            }
            await refresh(includeRefs: true)
            if stopped {
                sidebarSelection = .changes
                if let first = status.conflicted.first { fileSelection = [FileRowID(path: first.path, area: .conflicted)] }
            }
        }
    }

    private func undoIntegration(previous: ObjectID, head: ObjectID, name: String) {
        guard let repository else { return }
        Task {
            guard status.branch.head == head else {
                HUD.show("The branch moved on, so this can't be undone here.", systemImage: "exclamationmark.triangle")
                return
            }
            do {
                try await repository.undoIntegration(to: previous)
                HUD.show("\(name) undone", systemImage: "arrow.uturn.backward")
            } catch {
                show(error, operation: .undoIntegration)
            }
            await refresh(includeRefs: true)
        }
    }

    func showIntegrationProblem(_ error: any Error, operation: GitOperation) {
        if let problem = error as? IntegrationProblem {
            self.problem = Problem(explanation: Explanation(cause: .hookOrOther, title: Explanation.explain("", operation: operation).title,
                                                            message: problem.message, action: .none, output: ""), command: "")
        } else {
            show(error, operation: operation)
        }
    }

    // MARK: Force push

    var canForcePush: Bool { canPush && status.branch.upstream != nil }

    func confirmForcePush() {
        guard let repository, canForcePush, let upstream = status.branch.upstream else { return }
        let branch = currentBranchName
        let remoteTip = refs.remote.first { $0.name == upstream }?.target?.short
        confirmation = Confirmation(
            title: "Force push \(branch) to \(upstream)?",
            message: "This replaces \(upstream) with your branch, removing remote commits that aren't on it. Commit stops if someone pushed since you last fetched (--force-with-lease)."
                + (remoteTip.map { " The remote's current tip is \($0), in case you need it back." } ?? "")
                + " This can't be undone from here.",
            confirmTitle: "Force Push", isDestructive: true
        ) { [weak self] in
            self?.perform(.forcePush, title: "Force pushing", cancellable: true, progress: true) { progress in
                try await repository.forcePush(onProgress: progress)
            } success: {
                HUD.show("Force pushed \(branch)" + (remoteTip.map { ". Old tip: \($0)" } ?? ""), systemImage: "arrow.up.circle")
            }
        }
    }

    // MARK: Tags

    func showNewTag(at commit: ObjectID?) {
        guard let target = commit ?? status.branch.head else { return }
        let label: String
        if let row = history.rows.first(where: { $0.id == target }) {
            label = "\(target.short) \(row.subject)"
        } else if commit == nil {
            label = "\(currentBranchName) (\(target.short))"
        } else {
            label = target.short
        }
        sheet = .newTag(at: target, label: label)
    }

    var defaultRemote: String? {
        let names = refs.remoteNames
        if let upstream = status.branch.upstream, let remote = upstream.split(separator: "/").first.map(String.init),
           names.contains(remote) { return remote }
        return names.contains("origin") ? "origin" : names.first
    }

    func createTag(_ name: String, at commit: ObjectID, message: String?, push: Bool) {
        guard let repository else { return }
        let remote = defaultRemote
        mutate(.createTag, undoName: "New Tag") { [weak self] in
            try await repository.createTag(name, at: commit, message: message)
            HUD.show("Tagged \(commit.short) as \(name)", systemImage: "tag")
            if push, let remote, let self {
                self.perform(.pushTag, title: "Pushing \(name)", cancellable: true, progress: true) { progress in
                    try await repository.pushTag(name, to: remote, onProgress: progress)
                } success: {
                    HUD.show("Pushed \(name) to \(remote)", systemImage: "arrow.up.circle")
                }
            }
            return { [weak self] in
                guard let repository = self?.repository else { return }
                self?.mutate(.deleteTag, undoName: "New Tag", isUndo: true) {
                    _ = try await repository.deleteTag(name)
                    return nil
                }
            }
        }
    }

    func confirmDeleteTag(_ ref: GitRef) {
        guard let repository, ref.kind == .tag else { return }
        let name = ref.name
        confirmation = Confirmation(
            title: "Delete the tag “\(name)”?",
            message: "This deletes it here only; remotes keep their copy. You can undo this right after.",
            confirmTitle: "Delete Tag", isDestructive: true
        ) { [weak self] in
            self?.mutate(.deleteTag, undoName: "Delete Tag") {
                let deleted = try await repository.deleteTag(name)
                return { [weak self] in
                    guard let repository = self?.repository else { return }
                    self?.mutate(.createTag, undoName: "Delete Tag", isUndo: true) {
                        try await repository.restoreTag(deleted)
                        return nil
                    }
                }
            }
        }
    }

    func confirmDeleteRemoteTag(_ ref: GitRef) {
        guard let repository, ref.kind == .tag, let remote = defaultRemote else { return }
        let name = ref.name
        confirmation = Confirmation(
            title: "Delete “\(name)” from \(remote)?",
            message: "Everyone who fetches from \(remote) stops seeing this tag. Your local tag stays, so you can push it again; Undo can't bring it back on the remote.",
            confirmTitle: "Delete from \(remote)", isDestructive: true
        ) { [weak self] in
            self?.perform(.deleteTag, title: "Deleting \(name) from \(remote)", cancellable: true) { _ in
                try await repository.deleteRemoteTag(name, on: remote)
            } success: {
                HUD.show("Deleted \(name) from \(remote)", systemImage: "tag.slash")
            }
        }
    }

    func pushTag(_ ref: GitRef) {
        guard let repository, let remote = defaultRemote else { return }
        let name = ref.name
        perform(.pushTag, title: "Pushing \(name)", cancellable: true, progress: true) { progress in
            try await repository.pushTag(name, to: remote, onProgress: progress)
        } success: {
            HUD.show("Pushed \(name) to \(remote)", systemImage: "arrow.up.circle")
        }
    }

    var canPushTags: Bool { canSync && !refs.tags.isEmpty }

    func pushAllTags() {
        guard let repository, let remote = defaultRemote else { return }
        perform(.pushTag, title: "Pushing tags", cancellable: true, progress: true) { progress in
            try await repository.pushAllTags(to: remote, onProgress: progress)
        } success: {
            HUD.show("Pushed tags to \(remote)", systemImage: "arrow.up.circle")
        }
    }

    // MARK: Remotes

    func showRemotes() { sheet = .remotes }

    func loadRemotes() async -> [Remote] {
        (try? await repository?.remoteList()) ?? []
    }

    /// Runs a remote change; returns whether it worked (the sheet stays open on failure).
    func changeRemotes(_ operation: GitOperation, _ body: @escaping @MainActor (Repository) async throws -> Void) async -> Bool {
        guard let repository else { return false }
        do {
            try await body(repository)
            await refresh(includeRefs: true)
            return true
        } catch {
            show(error, operation: operation)
            return false
        }
    }

    func removeRemote(_ name: String) async -> Bool {
        guard let repository else { return false }
        do {
            let removed = try await repository.removeRemote(name)
            registerUndo("Remove Remote") { [weak self] in
                guard let repository = self?.repository else { return }
                self?.mutate(.addRemote, undoName: "Remove Remote", isUndo: true) {
                    try await repository.restoreRemote(removed)
                    return nil
                }
            }
            HUD.show("Removed \(name). Undo puts it back.", systemImage: "trash")
            await refresh(includeRefs: true)
            return true
        } catch {
            show(error, operation: .removeRemote)
            return false
        }
    }
}

// MARK: File history

extension RepoModel {
    /// Opens a file's history (or blame) in its own window, optionally at a commit.
    func openFileHistory(_ path: String, blame: Bool, at commit: ObjectID? = nil) {
        guard let root = repository?.root else { return }
        app.openFileHistory(FileHistoryTarget(root: root.path, path: path, blame: blame, revision: commit?.hex))
    }

    /// The file the menu's Show File History / Show Blame act on.
    var fileForHistory: String? {
        switch diff.source {
        case .workingCopy(let entry, _):
            return entry.isUntracked || entry.path.hasSuffix("/") ? nil : entry.path
        case .commit(_, let file), .stash(_, let file):
            return file.path
        default:
            return nil
        }
    }

    func showHistoryOfSelectedFile(blame: Bool) {
        guard let path = fileForHistory else { NSSound.beep(); return }
        var at: ObjectID?
        if case .commit(let id, _) = diff.source { at = id }
        openFileHistory(path, blame: blame, at: at)
    }
}
