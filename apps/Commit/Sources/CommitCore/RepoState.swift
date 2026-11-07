import Foundation

/// An operation git stopped in the middle of (research doc, Flow 8).
public enum InProgressOperation: String, Sendable, Equatable, CaseIterable {
    case merge, rebase, cherryPick, revert

    public var noun: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .cherryPick: "Cherry-pick"
        case .revert: "Revert"
        }
    }

    /// git's subcommand for --continue / --abort.
    public var subcommand: String {
        switch self {
        case .merge: "merge"
        case .rebase: "rebase"
        case .cherryPick: "cherry-pick"
        case .revert: "revert"
        }
    }

    /// Reads the markers git leaves in the git directory.
    public static func detect(gitDirectory: URL, fileManager: FileManager = .default) -> InProgressOperation? {
        func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: gitDirectory.appendingPathComponent(name).path) }
        if exists("rebase-merge") || (exists("rebase-apply") && !exists("rebase-apply/applying")) { return .rebase }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return nil
    }
}

/// Whether a file still has conflict markers (asked before Mark Resolved).
public enum ConflictMarkers {
    public static func present(in data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        var sawStart = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.hasPrefix("<<<<<<< ") || line == "<<<<<<<" { sawStart = true }
            if sawStart && (line.hasPrefix(">>>>>>> ") || line == ">>>>>>>") { return true }
        }
        return false
    }
}

/// Where a repository is, from `git rev-parse`.
public struct RepositoryLocation: Sendable, Equatable {
    public var root: URL
    public var gitDirectory: URL

    public init(root: URL, gitDirectory: URL) {
        self.root = root
        self.gitDirectory = gitDirectory
    }
}

/// Why a folder can't be opened.
public enum OpenProblem: Error, Sendable, Equatable {
    case notARepository(URL)
    case bare(URL)
    case insideGitDirectory(URL)
    case missing(URL)
    case git(String)

    public var message: String {
        switch self {
        case .notARepository(let url): "“\(url.lastPathComponent)” isn't a Git repository."
        case .bare(let url): "“\(url.lastPathComponent)” is a bare repository. It has no working files to commit; open a clone of it instead."
        case .insideGitDirectory(let url): "“\(url.lastPathComponent)” is inside a .git folder. Open the project folder that contains it."
        case .missing(let url): "There's no folder at \(url.path)."
        case .git(let output): output
        }
    }
}
