import CoreText
import Foundation

// Turning library-folder fonts on and off where they are, by registering their files with
// CoreText. Installed fonts (in a Fonts folder) keep using the system switch (`FontSystem`).
//
// - Activate: `.persistent` (CoreText's user scope). Stays on across restarts and logins,
//   from the file where it is. Nothing is copied.
// - Activate Temporarily: `.session` scope, and Specimen unregisters it when it quits. The
//   session scope is the safety net: after a crash it ends at logout at the latest, and the
//   next launch ends it too (`TemporaryStore` remembers what was temporary).

public enum RegistrationScope: String, Codable, Sendable {
    case persistent, session, process

    var coreText: CTFontManagerScope {
        switch self {
        case .persistent: .persistent
        case .session: .session
        case .process: .process
        }
    }

    init?(_ scope: CTFontManagerScope) {
        switch scope {
        case .persistent: self = .persistent
        case .session: self = .session
        case .process: self = .process
        default: return nil
        }
    }
}

public struct RegistrationError: Equatable, Sendable {
    public var path: String?
    public var message: String

    public init(path: String?, message: String) {
        self.path = path
        self.message = message
    }
}

/// Registers font files. `CoreTextRegistrar` in the app; `SessionOnlyRegistrar` around it in
/// test mode; a fake in tests.
public protocol FontRegistrar: Sendable {
    func register(_ paths: [String], scope: RegistrationScope) -> [RegistrationError]
    /// Unregisters from whatever scope each file is registered in.
    func unregister(_ paths: [String]) -> [RegistrationError]
    func scope(of path: String) -> RegistrationScope?
}

public struct CoreTextRegistrar: FontRegistrar {
    public init() {}

    public func register(_ paths: [String], scope: RegistrationScope) -> [RegistrationError] {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return [] }
        return Self.wait { CTFontManagerRegisterFontURLs(urls as CFArray, scope.coreText, true, $0) }
    }

    public func unregister(_ paths: [String]) -> [RegistrationError] {
        var byScope: [CTFontManagerScope: [URL]] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let scope = CTFontManagerGetScopeForURL(url as CFURL)
            if scope != .none { byScope[scope, default: []].append(url) }
        }
        return byScope.flatMap { scope, urls in Self.wait { CTFontManagerUnregisterFontURLs(urls as CFArray, scope, $0) } }
    }

    public func scope(of path: String) -> RegistrationScope? {
        RegistrationScope(CTFontManagerGetScopeForURL(URL(fileURLWithPath: path) as CFURL))
    }

    /// Runs a (un)registration and waits for CoreText's handler to say it's done.
    static func wait(_ start: (@escaping (CFArray, Bool) -> Bool) -> Void) -> [RegistrationError] {
        let box = RegistrationErrorBox()
        let done = DispatchSemaphore(value: 0)
        start { errors, finished in
            box.append((errors as? [NSError] ?? []).map(Self.describe))
            if finished { done.signal() }
            return true
        }
        _ = done.wait(timeout: .now() + 30)
        return box.errors
    }

    static func describe(_ error: NSError) -> RegistrationError {
        let urls = error.userInfo[kCTFontManagerErrorFontURLsKey as String] as? [URL]
        return RegistrationError(path: urls?.first?.path, message: error.localizedDescription)
    }
}

private final class RegistrationErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RegistrationError] = []
    func append(_ errors: [RegistrationError]) { lock.withLock { stored += errors } }
    var errors: [RegistrationError] { lock.withLock { stored } }
}

/// Test mode: never registers anything beyond the session. "Persistent" registrations are
/// session ones that report themselves as persistent, so the app behaves as it would for
/// real, and quitting (or `specimen-fixture clean`) leaves nothing behind.
public final class SessionOnlyRegistrar: FontRegistrar, @unchecked Sendable {
    private let base: any FontRegistrar
    private let lock = NSLock()
    private var pretendPersistent = Set<String>()

    public init(base: any FontRegistrar = CoreTextRegistrar()) {
        self.base = base
    }

    public func register(_ paths: [String], scope: RegistrationScope) -> [RegistrationError] {
        let errors = base.register(paths, scope: scope == .persistent ? .session : scope)
        let failed = Set(errors.compactMap(\.path))
        if scope == .persistent { lock.withLock { pretendPersistent.formUnion(paths.filter { !failed.contains($0) }) } }
        return errors
    }

    public func unregister(_ paths: [String]) -> [RegistrationError] {
        lock.withLock { pretendPersistent.subtract(paths) }
        return base.unregister(paths)
    }

    public func scope(of path: String) -> RegistrationScope? {
        guard let scope = base.scope(of: path) else { return nil }
        return lock.withLock { pretendPersistent.contains(path) } ? .persistent : scope
    }

    /// Everything this run registered (unregistered on quit).
    public var registeredByThisRun: Set<String> { lock.withLock { pretendPersistent } }
}

/// Files Specimen activated temporarily, in temporary.json. Written as soon as they change,
/// so a launch after a crash can end them.
public struct TemporaryStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("temporary.json")
    }

    public func load() -> Set<String> {
        guard let data = try? Data(contentsOf: url), let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(paths)
    }

    public func save(_ paths: Set<String>) {
        if paths.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(paths.sorted()).write(to: url, options: .atomic)
    }
}

// MARK: Routing an activation

/// What to ask the system to do for an activation change, per mechanism.
public struct ActivationSteps: Equatable, Sendable {
    /// Library files to unregister (turning their faces off). First.
    public var unregister: [String] = []
    /// Installed faces to switch off. Second.
    public var disable: [FontFace] = []
    public var registerPersistent: [String] = []
    public var registerTemporary: [String] = []
    /// Installed (or registered but switched off) faces to switch on. Last.
    public var enable: [FontFace] = []

    public init() {}

    public var isEmpty: Bool {
        unregister.isEmpty && disable.isEmpty && registerPersistent.isEmpty && registerTemporary.isEmpty && enable.isEmpty
    }
}

public enum ActivationRouter {
    /// Splits faces to turn on and off by how each one is switched.
    /// - `inPlace`: faces in library folders (registered from where they are).
    /// - `registered`: paths CoreText currently has registered (from the registry list).
    /// - `temporaryIDs`: faces in `on` to activate for this session only.
    /// Registration works per file, so a collection's faces go on and off together.
    public static func steps(on: [FontFace], off: [FontFace], temporaryIDs: Set<String>,
                             inPlace: (FontFace) -> Bool, registered: Set<String>) -> ActivationSteps {
        var steps = ActivationSteps()
        var unregister = OrderedPaths(), persistent = OrderedPaths(), temporary = OrderedPaths()
        for face in off {
            guard inPlace(face), let path = face.path else { steps.disable.append(face); continue }
            if registered.contains(path) { unregister.add(path) }
        }
        for face in on {
            guard inPlace(face), let path = face.path else { steps.enable.append(face); continue }
            let wantsTemporary = temporaryIDs.contains(face.id)
            if registered.contains(path) {
                if face.isEnabled, face.isTemporary, !wantsTemporary {
                    // Keep it on after quitting: re-register for good.
                    unregister.add(path)
                    persistent.add(path)
                } else if face.isEnabled, !face.isTemporary, wantsTemporary {
                    // Back to "until you quit" (undoing Keep Active).
                    unregister.add(path)
                    temporary.add(path)
                } else if !face.isEnabled {
                    // Registered but switched off (Font Book): switch it back on.
                    steps.enable.append(face)
                }
            } else if wantsTemporary {
                temporary.add(path)
            } else {
                persistent.add(path)
            }
        }
        steps.unregister = unregister.paths
        steps.registerPersistent = persistent.paths
        steps.registerTemporary = temporary.paths.filter { !persistent.contains($0) }
        return steps
    }
}

/// The undo step for an activation change: every face back as it was before (on,
/// temporarily on, or off). Faces already on that were changed (a temporary one kept, or the
/// reverse) stay on with their old scope instead of being turned off.
public enum ActivationUndo {
    public struct Step: Equatable, Sendable {
        public var on: [FontFace]
        public var off: [FontFace]
        public var temporaryIDs: Set<String>
    }

    /// `on` and `off` as they were *before* the change.
    public static func reverse(on: [FontFace], off: [FontFace]) -> Step {
        let restoreOn = off + on.filter(\.isEnabled)
        return Step(on: restoreOn, off: on.filter { !$0.isEnabled }, temporaryIDs: Set(restoreOn.filter(\.isTemporary).map(\.id)))
    }
}

private struct OrderedPaths {
    private(set) var paths: [String] = []
    private var seen = Set<String>()
    mutating func add(_ path: String) { if seen.insert(path).inserted { paths.append(path) } }
    func contains(_ path: String) -> Bool { seen.contains(path) }
}

/// A registered file that was renamed or moved inside a library folder stays active: the
/// new path is registered in the old one's place.
public enum RegistrationCarryOver {
    public struct Move: Equatable, Sendable {
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Pairs each removed registered file with an added file holding the same PostScript
    /// names (same file name first, then same folder, then anywhere).
    public static func moves(in change: LibraryChange, registered: Set<String>) -> [Move] {
        var candidates = change.added.filter { !$0.value.isEmpty }
        var result: [Move] = []
        for (old, names) in change.removed.sorted(by: { $0.key < $1.key }) where registered.contains(old) && !names.isEmpty {
            let wanted = Set(names)
            let matches = candidates.filter { Set($0.value) == wanted }.map(\.key).sorted()
            guard !matches.isEmpty else { continue }
            let oldName = (old as NSString).lastPathComponent, oldFolder = (old as NSString).deletingLastPathComponent
            let pick = matches.first { ($0 as NSString).lastPathComponent == oldName }
                ?? matches.first { ($0 as NSString).deletingLastPathComponent == oldFolder }
                ?? matches[0]
            candidates[pick] = nil
            result.append(Move(from: old, to: pick))
        }
        return result
    }
}
