import Foundation
import os

/// How git and ssh ask for credentials without a terminal (research doc, Engine rule 5).
///
/// git and ssh run `$GIT_ASKPASS "<prompt>"` / `$SSH_ASKPASS "<prompt>"` and read the answer
/// from its stdout. Commit points both at its own executable, which notices the socket
/// variable and runs as a tiny helper: it sends the prompt to the running app over a
/// Unix socket (with a per-launch token), the app shows a sheet on the right repository
/// window, and the helper prints what was typed. Nothing is stored by us; git's credential
/// helper (osxkeychain) keeps what it's given.
public enum AskpassProtocol {
    public static let socketVariable = "COMMIT_ASKPASS_SOCKET"
    public static let tokenVariable = "COMMIT_ASKPASS_TOKEN"
    public static let repositoryVariable = "COMMIT_ASKPASS_REPOSITORY"

    public struct Request: Codable, Sendable, Equatable {
        public var token: String
        public var repository: String?
        public var prompt: String

        public init(token: String, repository: String?, prompt: String) {
            self.token = token
            self.repository = repository
            self.prompt = prompt
        }
    }

    public struct Response: Codable, Sendable, Equatable {
        /// nil: the person cancelled (the helper exits non-zero and git gives up).
        public var answer: String?

        public init(answer: String?) { self.answer = answer }
    }
}

/// A prompt from git or ssh, classified for the sheet.
public struct AskpassPrompt: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Plain text (an HTTPS username).
        case username
        /// Hidden text (password, token, passphrase, PIN).
        case secret
        /// Yes or No (ssh's unknown host key question).
        case confirmation
    }

    public let id: UUID
    public var text: String
    public var kind: Kind
    public var repositoryID: String?

    public init(id: UUID = UUID(), text: String, repositoryID: String? = nil) {
        self.id = id
        self.text = text
        self.kind = Self.classify(text)
        self.repositoryID = repositoryID
    }

    public static func classify(_ prompt: String) -> Kind {
        let lower = prompt.lowercased()
        if lower.contains("(yes/no") || lower.contains("continue connecting") { return .confirmation }
        if lower.hasPrefix("username") || lower.contains("username for") { return .username }
        return .secret
    }

    /// A short title for the sheet.
    public var title: String {
        switch kind {
        case .confirmation:
            return "Trust This Server?"
        case .username:
            return host.map { "Sign In to \($0)" } ?? "Sign In"
        case .secret:
            let lower = text.lowercased()
            if lower.contains("passphrase") {
                return keyName.map { "Passphrase for \($0)" } ?? "Key Passphrase"
            }
            if lower.contains("pin") && !lower.contains("password") { return "PIN" }
            return host.map { "Password for \($0)" } ?? "Password"
        }
    }

    /// The host in "Password for 'https://user@github.com': ".
    public var host: String? {
        guard let start = text.firstIndex(of: "'"), let end = text[text.index(after: start)...].firstIndex(of: "'") else { return nil }
        let url = String(text[text.index(after: start)..<end])
        if let components = URLComponents(string: url), let host = components.host { return host }
        return nil
    }

    /// "id_ed25519" in "Enter passphrase for key '/Users/x/.ssh/id_ed25519': ".
    public var keyName: String? {
        guard let start = text.firstIndex(of: "'"), let end = text[text.index(after: start)...].firstIndex(of: "'") else { return nil }
        let path = String(text[text.index(after: start)..<end])
        return path.contains("/") ? (path as NSString).lastPathComponent : nil
    }

    /// The answer git expects for a confirmation.
    public static func confirmationAnswer(_ yes: Bool) -> String { yes ? "yes" : "no" }
}

/// The helper side: runs inside the short-lived process git starts.
public enum AskpassClient {
    /// Sends the prompt and waits for the answer. nil when cancelled or the app is gone.
    public static func ask(prompt: String, environment: [String: String]) -> String? {
        guard let path = environment[AskpassProtocol.socketVariable],
              let token = environment[AskpassProtocol.tokenVariable] else { return nil }
        let request = AskpassProtocol.Request(token: token, repository: environment[AskpassProtocol.repositoryVariable],
                                              prompt: prompt)
        guard var payload = try? JSONEncoder().encode(request) else { return nil }
        payload.append(10)
        guard let fd = UnixSocket.connect(path: path) else { return nil }
        defer { close(fd) }
        guard UnixSocket.writeAll(fd, payload), let line = UnixSocket.readLine(fd),
              let response = try? JSONDecoder().decode(AskpassProtocol.Response.self, from: line) else { return nil }
        return response.answer
    }

    /// Entry point for the helper mode: prints the answer and returns the exit code.
    public static func main(arguments: [String], environment: [String: String]) -> Int32 {
        let prompt = arguments.dropFirst().joined(separator: " ")
        guard let answer = ask(prompt: prompt, environment: environment) else { return 1 }
        FileHandle.standardOutput.write(Data((answer + "\n").utf8))
        return 0
    }
}

/// The app side: a Unix socket in a private temporary folder. Each request is checked
/// against the launch's token, then handed to `handler` (which shows the sheet).
public final class AskpassServer: @unchecked Sendable {
    public typealias Handler = @Sendable (AskpassPrompt) async -> String?

    public let socketPath: String
    public let token: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private let directory: URL

    public init(directory: URL, token: String = UUID().uuidString, handler: @escaping Handler) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        self.socketPath = directory.appendingPathComponent("askpass.sock").path
        self.token = token
        self.handler = handler
        unlink(socketPath)
        guard let fd = UnixSocket.listen(path: socketPath) else {
            throw SpawnError(errno: errno, path: socketPath)
        }
        listenFD = fd
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "Commit askpass"
        thread.start()
    }

    public func stop() {
        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    deinit { stop() }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            let handler = self.handler
            let token = self.token
            DispatchQueue.global(qos: .userInitiated).async {
                defer { close(client) }
                guard let line = UnixSocket.readLine(client),
                      let request = try? JSONDecoder().decode(AskpassProtocol.Request.self, from: line),
                      request.token == token else { return }
                let prompt = AskpassPrompt(text: request.prompt, repositoryID: request.repository)
                let answer = BlockingTask.run { await handler(prompt) }
                if var data = try? JSONEncoder().encode(AskpassProtocol.Response(answer: answer)) {
                    data.append(10)
                    _ = UnixSocket.writeAll(client, data)
                }
            }
        }
    }
}

/// Waits on a background thread for an async result (the socket thread isn't async).
enum BlockingTask {
    static func run<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = OSAllocatedUnfairLock<T?>(initialState: nil)
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let value = await body()
            box.withLock { $0 = value }
            semaphore.signal()
        }
        semaphore.wait()
        return box.withLock { $0 }!
    }
}

/// Minimal blocking Unix-domain socket helpers.
enum UnixSocket {
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func listen(path: String) -> Int32? {
        guard var address = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else { close(fd); return nil }
        return fd
    }

    static func connect(path: String) -> Int32? {
        guard var address = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(fd); return nil }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 { if errno == EINTR { continue }; return false }
                offset += n
            }
            return true
        }
    }

    /// Reads up to the first newline (max 64 KB).
    static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < 65_536 {
            let n = read(fd, &byte, 1)
            if n < 0 { if errno == EINTR { continue }; return nil }
            if n == 0 { return data.isEmpty ? nil : data }
            if byte == 10 { return data }
            data.append(byte)
        }
        return data
    }
}
