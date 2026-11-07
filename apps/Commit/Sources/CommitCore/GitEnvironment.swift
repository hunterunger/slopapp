import Foundation

/// The environment every git process gets (research doc, Engine rule 2):
/// the app's environment, the login shell's PATH in front, no terminal prompts, no editor,
/// no optional locks (our reads never take `index.lock`), and the askpass helper.
public struct GitEnvironment: Sendable, Equatable {
    public var base: [String: String]
    /// The user's login-shell PATH, when resolved and enabled.
    public var shellPath: String?
    /// Askpass wiring, when the app is running its prompt server.
    public var askpass: Askpass?

    public struct Askpass: Sendable, Equatable {
        /// The executable git and ssh run to ask (our own app binary in helper mode).
        public var helper: String
        public var socket: String
        public var token: String

        public init(helper: String, socket: String, token: String) {
            self.helper = helper; self.socket = socket; self.token = token
        }
    }

    public init(base: [String: String], shellPath: String? = nil, askpass: Askpass? = nil) {
        self.base = base
        self.shellPath = shellPath
        self.askpass = askpass
    }

    /// GUI apps get this PATH from launchd.
    public static let guiPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The environment for git in the repository identified by `repositoryID` (used to route
    /// askpass prompts to the right window).
    public func variables(repositoryID: String? = nil) -> [String: String] {
        var env = base
        env["PATH"] = Self.mergedPath(shell: shellPath, app: base["PATH"])
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        env["GIT_SEQUENCE_EDITOR"] = "true"
        env["GIT_MERGE_AUTOEDIT"] = "no"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_PAGER"] = "cat"
        env["TERM"] = "dumb"
        // A terminal pinentry or ssh can't ask without a terminal; never leave them waiting.
        env.removeValue(forKey: "GPG_TTY")
        if let askpass {
            env["GIT_ASKPASS"] = askpass.helper
            env["SSH_ASKPASS"] = askpass.helper
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env[AskpassProtocol.socketVariable] = askpass.socket
            env[AskpassProtocol.tokenVariable] = askpass.token
            if let repositoryID { env[AskpassProtocol.repositoryVariable] = repositoryID }
        } else {
            env.removeValue(forKey: "GIT_ASKPASS")
            env.removeValue(forKey: "SSH_ASKPASS")
            env.removeValue(forKey: "SSH_ASKPASS_REQUIRE")
        }
        return env
    }

    /// The shell's PATH first, then anything of the app's not already in it.
    public static func mergedPath(shell: String?, app: String?) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        for component in [shell ?? "", app ?? guiPath, guiPath].flatMap({ $0.split(separator: ":") }) {
            let item = String(component)
            if !item.isEmpty, seen.insert(item).inserted { parts.append(item) }
        }
        return parts.joined(separator: ":")
    }
}

/// Resolves the PATH of the user's login shell (Homebrew, nvm, pnpm…), so hooks, git-lfs
/// and gpg behave as they do in Terminal. Runs the shell once, with markers around the
/// value so greetings and other startup output can't leak in, and a timeout.
public enum ShellPath {
    public static let startMarker = "__COMMIT_PATH_START__"
    public static let endMarker = "__COMMIT_PATH_END__"

    /// Arguments for `<shell> …`: login + interactive (where most people set PATH), run one
    /// command. `printenv` prints the exported, colon-joined value in every shell (fish too).
    public static func arguments() -> [String] {
        ["-l", "-i", "-c", "echo \(startMarker); printenv PATH; echo \(endMarker)"]
    }

    /// The PATH between the markers, or nil if the output doesn't have one.
    public static func parse(_ output: String) -> String? {
        guard let start = output.range(of: startMarker),
              let end = output.range(of: endMarker, range: start.upperBound..<output.endIndex) else { return nil }
        let value = output[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        // Only the last line: an rc file that prints between the markers can't get in.
        let line = value.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        guard line.contains("/"), !line.contains(" ") || line.contains(":") else { return nil }
        return line.isEmpty ? nil : line
    }

    /// Runs `shell` and returns its PATH. nil on timeout, failure or garbage.
    public static func resolve(shell: String, timeout: Duration = .seconds(3)) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        let runner = ProcessGitRunner(executable: URL(fileURLWithPath: shell), environment: env)
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let result = try? await runner.run(GitCommand(arguments(), in: home, timeout: timeout)),
              !result.timedOut else { return nil }
        return parse(result.stdoutString)
    }
}
