import CoreServices
import Foundation
import os

/// Coalesces "something changed" signals into status refreshes (research doc, File
/// watching): wait `debounce` after the first event, never more than one refresh in flight
/// and one queued, and at least `minimumInterval` between starts, so an event storm costs at
/// most two refreshes a second and the repo is idle again right after it ends.
@MainActor
public final class RefreshScheduler {
    public let debounce: Duration
    public let minimumInterval: Duration
    private let refresh: @MainActor () async -> Void
    private let clock = ContinuousClock()

    private var scheduled: Task<Void, Never>?
    private var inFlight = false
    private var queued = false
    private var lastStart: ContinuousClock.Instant?

    /// How many refreshes have run (tests and diagnostics).
    public private(set) var runCount = 0

    public init(debounce: Duration = .milliseconds(250), minimumInterval: Duration = .milliseconds(500),
                refresh: @escaping @MainActor () async -> Void) {
        self.debounce = debounce
        self.minimumInterval = minimumInterval
        self.refresh = refresh
    }

    /// Nothing running, scheduled or queued.
    public var isIdle: Bool { scheduled == nil && !inFlight && !queued }

    /// A file system event (or anything else that might have changed the repo).
    public func signal() {
        if inFlight { queued = true; return }
        guard scheduled == nil else { return }
        schedule(after: max(debounce, remainingInterval()))
    }

    /// Refresh as soon as possible (⌘R, window activation, after our own changes).
    public func refreshNow() {
        if inFlight { queued = true; return }
        scheduled?.cancel()
        scheduled = nil
        Task { await self.start() }
    }

    /// Stop everything (window closed).
    public func cancel() {
        scheduled?.cancel()
        scheduled = nil
        queued = false
    }

    private func remainingInterval() -> Duration {
        guard let lastStart else { return .zero }
        let elapsed = clock.now - lastStart
        return elapsed >= minimumInterval ? .zero : minimumInterval - elapsed
    }

    private func schedule(after delay: Duration) {
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.scheduled = nil
            await self.start()
        }
    }

    private func start() async {
        guard !inFlight else { queued = true; return }
        inFlight = true
        lastStart = clock.now
        runCount += 1
        await refresh()
        inFlight = false
        if queued {
            queued = false
            if scheduled == nil { schedule(after: max(debounce, remainingInterval())) }
        }
    }
}

/// What a changed path means for the open repository.
public enum RepoEvent: Sendable, Equatable {
    /// Objects, logs, locks, hooks: nothing to show.
    case ignore
    /// A file in the working tree: refresh status.
    case worktree
    /// HEAD, refs, index, MERGE_HEAD…: refresh status and branches.
    case gitState
}

/// Classifies FSEvents paths (directory-level events) for one repository.
public struct RepoEventClassifier: Sendable {
    public let root: String
    public let gitDirectory: String

    public init(root: URL, gitDirectory: URL) {
        // FSEvents reports real paths (/private/tmp, not /tmp).
        self.root = Self.realPath(root.path)
        self.gitDirectory = Self.realPath(gitDirectory.path)
    }

    public static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public func classify(_ rawPath: String) -> RepoEvent {
        let path = rawPath.hasSuffix("/") && rawPath.count > 1 ? String(rawPath.dropLast()) : rawPath
        if path == gitDirectory || path.hasPrefix(gitDirectory + "/") {
            let inner = path == gitDirectory ? "" : String(path.dropFirst(gitDirectory.count + 1))
            for ignored in ["objects", "logs", "lfs", "hooks", "info", "fsmonitor--daemon"]
            where inner == ignored || inner.hasPrefix(ignored + "/") {
                return .ignore
            }
            if inner.hasPrefix("modules/") { return .ignore }
            return .gitState
        }
        if path == root || path.hasPrefix(root + "/") { return .worktree }
        return .ignore
    }
}

/// An FSEvents stream on a repository's folders (directory-level events, ~0.25 s latency).
public final class FileWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([String]) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Commit file watcher", qos: .utility)
    private let handler: Handler

    public init(paths: [String], latency: TimeInterval = 0.25, handler: @escaping Handler) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: NSArray.self)
            var changed: [String] = []
            for i in 0..<count {
                if let path = cfPaths[i] as? String { changed.append(path) }
            }
            if !changed.isEmpty { watcher.handler(changed) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
