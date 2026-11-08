import Foundation

/// The app in front, as far as insertion cares.
public struct FrontApp: Sendable, Equatable {
    public var pid: Int32
    public var bundleID: String?
    public var name: String?

    public init(pid: Int32, bundleID: String?, name: String?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}

/// Posts keys into the app in front. The real one wraps SlopKit's `SyntheticKeyboard` and
/// `ClipboardPaster`; tests record.
@MainActor
public protocol KeyPosting: AnyObject {
    func backspace(_ count: Int)
    func left(_ count: Int)
    /// Types without touching the clipboard.
    func type(_ text: String)
    /// Pastes; `restore`: put the old clipboard back afterwards. Returns once ⌘V is posted.
    func paste(_ text: String, restore: Bool) async
}

/// What the expander asks the system just before inserting.
@MainActor
public protocol InsertionEnvironment: AnyObject {
    var frontApp: FrontApp? { get }
    var secureInputActive: Bool { get }
    /// The focused element is a password field (AXSecureTextField).
    var focusedFieldIsSecure: Bool { get }
    var pasteboardPrivacy: PasteboardAccessState { get }
    /// The clipboard's plain text, read only when a snippet needs it.
    func readClipboard() -> ClipboardValue
    /// Monotonic nanoseconds.
    func now() -> UInt64
    var date: Date { get }
}

/// "Paste from Other Apps", as Core sees it.
public enum PasteboardAccessState: Sendable, Equatable {
    case allowed
    case asks
    case denied
}

/// The tap side the expander talks to (the real one locks; tests use the engine directly).
@MainActor
public protocol TapControl: AnyObject {
    func beginInsert(_ id: UInt64) -> TapEngine.InsertStart?
    func finishInsert(_ id: UInt64, tail: String, undoable: Bool)
    func cancel(_ id: UInt64)
    func beginUndo()
    func finishUndo(abbreviation: String)
}

public struct ExpansionSettings: Sendable, Equatable {
    public var insertMode: InsertMode = .automatic
    public var restoreClipboard = true
    public var undoWithBackspace = true
    public init() {}
}

/// Turns a match into text in the app: checks the guards, resolves placeholders, plans, posts.
@MainActor
public final class Expander {
    public enum Outcome: Sendable, Equatable {
        case inserted(InsertMethod, characters: Int, restoredClipboard: Bool)
        /// The match is stale, the app changed, or keys we can't replay came in.
        case dropped
        case blockedSecureInput
        case blockedPasswordField
        case snippetMissing
    }

    public struct Report: Sendable, Equatable {
        public var outcome: Outcome
        /// Monotonic ns: guards done, placeholders resolved, keys posted (for the latency log).
        public var timings: [UInt64] = []
        public var snippetID: UUID?
        /// A long snippet pasted but the clipboard couldn't be put back (paste privacy).
        public var pastedWithoutRestore = false
        public var clipboardBlocked = false
    }

    let tap: TapControl
    let poster: KeyPosting
    let environment: InsertionEnvironment
    public var settings = ExpansionSettings()
    /// Looks up a snippet's current content.
    public var snippet: (UUID) -> Snippet?

    struct Undoable {
        var id: UInt64
        var typed: String
        var insertedCount: Int
    }
    private var lastUndoable: Undoable?

    public init(tap: TapControl, poster: KeyPosting, environment: InsertionEnvironment, snippet: @escaping (UUID) -> Snippet?) {
        self.tap = tap
        self.poster = poster
        self.environment = environment
        self.snippet = snippet
    }

    public func expand(_ match: Match) async -> Report {
        guard let snippet = snippet(match.snippetID) else {
            tap.cancel(match.id)
            return Report(outcome: .snippetMissing)
        }
        if environment.secureInputActive {
            tap.cancel(match.id)
            return Report(outcome: .blockedSecureInput, snippetID: snippet.id)
        }
        if environment.focusedFieldIsSecure {
            tap.cancel(match.id)
            return Report(outcome: .blockedPasswordField, snippetID: snippet.id)
        }
        let guardsDone = environment.now()
        let privacy = environment.pasteboardPrivacy
        let resolver = PlaceholderResolver(now: environment.date)
        let environment = self.environment
        let resolved = resolver.resolve(snippet.content, typedCase: match.typedCase) {
            privacy == .allowed ? environment.readClipboard() : .notAllowed
        }
        // Everything is decided; only now take the keys typed meanwhile (the tap stops
        // remembering them here) and post in one go.
        let resolvedAt = environment.now()
        guard let start = tap.beginInsert(match.id) else { return Report(outcome: .dropped, snippetID: snippet.id) }
        let plan = InsertionPlanner.plan(resolved: resolved, typedLength: match.length, pending: start.pending, mode: settings.insertMode)
        poster.backspace(plan.backspaces)
        var restored = false
        var pastedWithoutRestore = false
        switch plan.method {
        case .type:
            poster.type(plan.text)
        case .paste:
            restored = settings.restoreClipboard && privacy == .allowed
            pastedWithoutRestore = settings.restoreClipboard && privacy != .allowed
            await poster.paste(plan.text, restore: restored)
        }
        poster.left(plan.leftArrows)
        if !plan.retype.isEmpty { poster.type(plan.retype) }
        let undoable = settings.undoWithBackspace && plan.method == .type && plan.leftArrows == 0 && plan.retype.isEmpty
            && plan.text.count <= InsertionPlanner.typeLimit && !plan.text.isEmpty
        lastUndoable = undoable ? Undoable(id: match.id, typed: start.typed, insertedCount: plan.text.count) : nil
        tap.finishInsert(match.id, tail: resolved.textBeforeCursor + plan.retype, undoable: undoable)
        return Report(outcome: .inserted(plan.method, characters: plan.text.count, restoredClipboard: restored),
                      timings: [guardsDone, resolvedAt, environment.now()],
                      snippetID: snippet.id, pastedWithoutRestore: pastedWithoutRestore, clipboardBlocked: resolved.clipboardBlocked)
    }

    /// Backspace right after a typed expansion: the person's Backspace already removed the
    /// last character, so remove the rest and type the abbreviation back.
    @discardableResult
    public func undo(_ id: UInt64) -> Bool {
        guard let last = lastUndoable, last.id == id else { return false }
        lastUndoable = nil
        guard !environment.secureInputActive else { return false }
        tap.beginUndo()
        poster.backspace(max(0, last.insertedCount - 1))
        poster.type(last.typed)
        tap.finishUndo(abbreviation: last.typed)
        return true
    }
}
