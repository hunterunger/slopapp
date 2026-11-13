import Foundation

/// What we were doing when git failed: picks the wording.
public enum GitOperation: String, Sendable, Equatable {
    case fetch, pull, push, commit, switchBranch, createBranch, deleteBranch, stage, unstage, discard
    case stash, applyStash, dropStash, continueOperation, abortOperation, open, other
    case clone, merge, rebase, cherryPick, revert, interactiveRebase, undoIntegration, resolve, mergeTool
    case addRemote, renameRemote, removeRemote, editRemote, createTag, deleteTag, pushTag, forcePush, blame

    var failureTitle: String {
        switch self {
        case .fetch: "Couldn't fetch"
        case .pull: "Couldn't pull"
        case .push: "Couldn't push"
        case .commit: "Couldn't commit"
        case .switchBranch: "Couldn't switch branches"
        case .createBranch: "Couldn't create the branch"
        case .deleteBranch: "Couldn't delete the branch"
        case .stage: "Couldn't stage"
        case .unstage: "Couldn't unstage"
        case .discard: "Couldn't discard"
        case .stash: "Couldn't stash"
        case .applyStash: "Couldn't apply the stash"
        case .dropStash: "Couldn't drop the stash"
        case .continueOperation: "Couldn't continue"
        case .abortOperation: "Couldn't abort"
        case .open: "Couldn't open the repository"
        case .other: "Git reported a problem"
        case .clone: "Couldn't clone"
        case .merge: "Couldn't merge"
        case .rebase: "Couldn't rebase"
        case .cherryPick: "Couldn't cherry-pick"
        case .revert: "Couldn't revert"
        case .interactiveRebase: "Couldn't edit the history"
        case .undoIntegration: "Couldn't undo"
        case .resolve: "Couldn't resolve the conflict"
        case .mergeTool: "The merge tool reported a problem"
        case .addRemote: "Couldn't add the remote"
        case .renameRemote: "Couldn't rename the remote"
        case .removeRemote: "Couldn't remove the remote"
        case .editRemote: "Couldn't change the remote"
        case .createTag: "Couldn't create the tag"
        case .deleteTag: "Couldn't delete the tag"
        case .pushTag: "Couldn't push the tag"
        case .forcePush: "Couldn't force push"
        case .blame: "Couldn't show who changed each line"
        }
    }
}

/// One plain sentence and one next step for the failures everyone hits (research doc,
/// "Plain-language errors"). Git's own output always stays available.
public struct Explanation: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case pull
        case stashAndSwitch
        case setIdentity
        case chooseMergeOrRebase
        case openPrivacySettings
        case none
    }

    public enum Cause: Sendable, Equatable {
        case rejectedPush, divergentBranches, authentication, unreachable, missingIdentity, indexLocked
        case notFound, destinationExists, staleLease, alreadyExists
        case wouldOverwrite, conflicts, signing, permissionDenied, nothingToCommit, lfsMissing, noUpstream
        case hookOrOther
    }

    public var cause: Cause
    public var title: String
    public var message: String
    public var action: Action
    /// Git's own words.
    public var output: String

    public init(cause: Cause, title: String, message: String, action: Action, output: String) {
        self.cause = cause
        self.title = title
        self.message = message
        self.action = action
        self.output = output
    }

    public static func explain(_ output: String, operation: GitOperation, remote: String? = nil) -> Explanation {
        let text = output.lowercased()
        let remoteName = remote ?? "the remote"
        func make(_ cause: Cause, _ message: String, _ action: Action = .none, title: String? = nil) -> Explanation {
            Explanation(cause: cause, title: title ?? operation.failureTitle, message: message, action: action, output: output)
        }
        if text.contains("stale info") || (text.contains("[rejected]") && operation == .forcePush) {
            return make(.staleLease, "\(remoteName.capitalizedFirst) has commits you haven't fetched, so Commit didn't overwrite them. Fetch, check what's new, then try again.")
        }
        if text.contains("already exists and is not an empty directory") {
            return make(.destinationExists, "There's already a folder with that name there. Choose another name or location.")
        }
        if operation == .createTag && text.contains("already exists") {
            return make(.alreadyExists, "A tag with that name already exists.")
        }
        if (operation == .addRemote || operation == .renameRemote) && text.contains("already exists") {
            return make(.alreadyExists, "A remote with that name already exists.")
        }
        if text.contains("[rejected]") || text.contains("non-fast-forward") || text.contains("fetch first")
            || text.contains("updates were rejected") {
            return make(.rejectedPush, "\(remoteName.capitalizedFirst) has commits you don't have. Pull them in, then push again.", .pull)
        }
        if text.contains("divergent branches") || text.contains("not possible to fast-forward") {
            return make(.divergentBranches, "Your branch and \(remoteName) both have new commits. Choose whether to merge them or rebase yours on top.", .chooseMergeOrRebase)
        }
        if text.contains("please tell me who you are") || text.contains("author identity unknown")
            || text.contains("empty ident name") || text.contains("unable to auto-detect email address") {
            return make(.missingIdentity, "Git doesn't know your name and email yet. Add them below; they're saved in your Git config.", .setIdentity)
        }
        if text.contains("index.lock") || text.contains("another git process seems to be running") {
            return make(.indexLocked, "Another Git process is using this repository. Wait for it to finish, then try again.")
        }
        if text.contains("would be overwritten by checkout") || text.contains("would be overwritten by switch")
            || (text.contains("your local changes to the following files would be overwritten") && operation == .switchBranch) {
            return make(.wouldOverwrite, "You have changes that would be overwritten by switching.", .stashAndSwitch)
        }
        if text.contains("your local changes to the following files would be overwritten") {
            return make(.wouldOverwrite, "You have local changes to files this would change. Commit or stash them first.")
        }
        if text.contains("gpg failed to sign") || text.contains("gpg: signing failed") {
            return make(.signing, "Git couldn't sign the commit with GPG. If your key has a passphrase, set up pinentry-mac in gpg-agent so it can ask outside a terminal.")
        }
        if text.contains("couldn't load public key") || text.contains("incorrect passphrase supplied")
            || text.contains("no private key found") || text.contains("ssh-keygen") && text.contains("sign") {
            return make(.signing, "Git couldn't sign the commit with your SSH key. Add the key to ssh-agent (ssh-add) or check user.signingkey.")
        }
        if text.contains("git-lfs") && (text.contains("not found") || text.contains("command not found")) {
            return make(.lfsMissing, "This repository uses Git LFS, but git-lfs isn't installed. Install it (for example with Homebrew), then try again.")
        }
        if text.contains("operation not permitted") {
            return make(.permissionDenied, "macOS didn't let Git read this folder. Allow Commit in System Settings › Privacy & Security › Files and Folders.", .openPrivacySettings)
        }
        if text.contains("authentication failed") || text.contains("could not read username") || text.contains("could not read password")
            || text.contains("terminal prompts disabled") || text.contains("permission denied (publickey")
            || text.contains("host key verification failed") || text.contains("invalid username or password")
            || text.contains("403") && text.contains("unable to access") {
            return make(.authentication, "Git couldn't sign in to \(remoteName). Check your credentials or SSH key, then try again.")
        }
        if text.contains("repository not found") || text.contains("not found") && text.contains("repository")
            || text.contains("does not exist") && operation == .clone
            || text.contains("does not appear to be a git repository") && operation == .clone {
            return make(.notFound, "There's no repository at that address, or your account can't see it. Check the address and that you have access.")
        }
        if text.contains("could not resolve host") || text.contains("could not read from remote repository")
            || text.contains("unable to access") || text.contains("connection refused") || text.contains("network is unreachable")
            || text.contains("operation timed out") || text.contains("does not appear to be a git repository") {
            return make(.unreachable, "Couldn't reach \(remoteName). Check your connection and the remote's address.")
        }
        if text.contains("has no upstream branch") || text.contains("no tracking information") {
            return make(.noUpstream, "This branch isn't connected to a remote branch yet. Push it first.")
        }
        if text.contains("conflict") || text.contains("automatic merge failed") || text.contains("could not apply") {
            return make(.conflicts, "Some files have conflicts. Resolve them in Changes, then continue.")
        }
        if text.contains("nothing to commit") || text.contains("no changes added to commit") {
            return make(.nothingToCommit, "There's nothing staged to commit.")
        }
        if operation == .commit {
            return make(.hookOrOther, "Git stopped the commit. If a hook failed, its output is below. Your message is kept.",
                        title: "The commit didn't go through")
        }
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? output
        return make(.hookOrOther, firstLine.isEmpty ? "Git exited with an error." : Self.clean(firstLine))
    }

    /// Strips git's "fatal: " / "error: " prefixes.
    static func clean(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["fatal: ", "error: ", "warning: "] where s.lowercased().hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        return s.capitalizedFirst
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// Progress from git's stderr ("Receiving objects:  45% (450/1000)"), lines split on \r or \n.
public struct GitProgress: Sendable, Equatable {
    public var phase: String
    /// 0...1 when git printed a percentage.
    public var fraction: Double?

    public init(phase: String, fraction: Double?) {
        self.phase = phase
        self.fraction = fraction
    }

    /// The latest progress line in a chunk of stderr.
    public static func parse(_ chunk: String) -> GitProgress? {
        let lines = chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        for line in lines.reversed() {
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("remote: ") { text = String(text.dropFirst(8)) }
            guard let colon = text.firstIndex(of: ":") else { continue }
            let phase = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !phase.isEmpty, phase.count < 40, !phase.contains("/") else { continue }
            let rest = text[text.index(after: colon)...]
            var fraction: Double?
            if let percent = rest.range(of: #"\d+%"#, options: .regularExpression) {
                fraction = (Double(rest[percent].dropLast()) ?? 0) / 100
            }
            if fraction != nil || rest.contains("done") { return GitProgress(phase: phase, fraction: fraction ?? 1) }
            return GitProgress(phase: phase, fraction: nil)
        }
        return nil
    }
}
