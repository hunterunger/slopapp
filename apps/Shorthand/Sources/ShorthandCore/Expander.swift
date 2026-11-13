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
    /// Pastes formatted text built from `resolved.pieces`, with `resolved.text` as the
    /// plain-text copy for apps that don't take formatting.
    func pasteFormatted(_ resolved: Resolved, restore: Bool) async
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
    /// Text went in without a typed abbreviation (from the search panel): `tail` is what's
    /// now before the caret.
    func inserted(tail: String)
}

public struct ExpansionSettings: Sendable, Equatable {
    public var insertMode: InsertMode = .automatic
    public var restoreClipboard = true
    public var undoWithBackspace = true
    public init() {}
}

/// A snippet that needs its fill-ins before it can go in. The abbreviation (if it was typed)
/// stays in the app until the form is done; the tap waits.
public struct FillInRequest: Sendable, Equatable {
    /// The typed match, or nil when it came from the search panel.
    public var matchID: UInt64?
    public var snippetID: UUID
    public var fields: [FillField]
    public var typedCase: TypedCase
    /// The abbreviation and any keys typed right after it (deleted before inserting).
    public var backspaces: Int
    /// Keys typed right after the abbreviation, typed again after the snippet.
    public var retype: String
    /// The app the text goes into: nothing is typed if another app is in front by then.
    public var targetPID: Int32?
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
        /// It has fill-ins: show the form (`Report.fillIn`), then `complete` or `cancel`.
        case needsFillIn
        /// Another app came to the front while the form was open: nothing was typed. The
        /// text is in `Report.resolved` so it can be copied instead.
        case targetChanged
    }

    public struct Report: Sendable, Equatable {
        public var outcome: Outcome
        /// Monotonic ns: guards done, placeholders resolved, keys posted (for the latency log).
        public var timings: [UInt64] = []
        public var snippetID: UUID?
        /// A long snippet pasted but the clipboard couldn't be put back (paste privacy).
        public var pastedWithoutRestore = false
        public var clipboardBlocked = false
        public var fillIn: FillInRequest?
        public var resolved: Resolved?
        public var formatted = false
    }

    let tap: TapControl
    let poster: KeyPosting
    let environment: InsertionEnvironment
    public var settings = ExpansionSettings()
    /// Looks up a snippet's current content.
    public var snippet: (UUID) -> Snippet?
    /// Finds a snippet by abbreviation, for `{snippet:…}`.
    public var lookup: (String) -> Snippet? = { _ in nil }

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

    private func guardOutcome() -> Outcome? {
        if environment.secureInputActive { return .blockedSecureInput }
        if environment.focusedFieldIsSecure { return .blockedPasswordField }
        return nil
    }

    private func resolve(_ snippet: Snippet, typedCase: TypedCase, values: FillValues) -> Resolved {
        let privacy = environment.pasteboardPrivacy
        let environment = self.environment
        return PlaceholderResolver(now: environment.date).resolve(snippet, typedCase: typedCase, values: values, lookup: lookup) {
            privacy == .allowed ? environment.readClipboard() : .notAllowed
        }
    }

    public func expand(_ match: Match) async -> Report {
        guard let snippet = snippet(match.snippetID) else {
            tap.cancel(match.id)
            return Report(outcome: .snippetMissing)
        }
        if let blocked = guardOutcome() {
            tap.cancel(match.id)
            return Report(outcome: blocked, snippetID: snippet.id)
        }
        let guardsDone = environment.now()
        let fields = FillIn.fields(for: snippet, lookup: lookup)
        if !fields.isEmpty {
            // Take the keys typed meanwhile now; the tap waits (ignoring keys) until the form
            // is done or cancelled.
            guard let start = tap.beginInsert(match.id) else { return Report(outcome: .dropped, snippetID: snippet.id) }
            let request = FillInRequest(matchID: match.id, snippetID: snippet.id, fields: fields, typedCase: match.typedCase,
                                        backspaces: match.length + start.pending.count, retype: start.pending,
                                        targetPID: environment.frontApp?.pid)
            return Report(outcome: .needsFillIn, snippetID: snippet.id, fillIn: request)
        }
        let resolved = resolve(snippet, typedCase: match.typedCase, values: FillValues())
        // Everything is decided; only now take the keys typed meanwhile (the tap stops
        // remembering them here) and post in one go.
        let resolvedAt = environment.now()
        guard let start = tap.beginInsert(match.id) else { return Report(outcome: .dropped, snippetID: snippet.id) }
        let plan = InsertionPlanner.plan(resolved: resolved, typedLength: match.length, pending: start.pending, mode: settings.insertMode)
        var report = await post(plan, resolved: resolved)
        let undoable = settings.undoWithBackspace && plan.method == .type && plan.leftArrows == 0 && plan.retype.isEmpty
            && plan.text.count <= InsertionPlanner.typeLimit && !plan.text.isEmpty
        lastUndoable = undoable ? Undoable(id: match.id, typed: start.typed, insertedCount: plan.text.count) : nil
        tap.finishInsert(match.id, tail: resolved.textBeforeCursor + plan.retype, undoable: undoable)
        report.timings = [guardsDone, resolvedAt, environment.now()]
        report.snippetID = snippet.id
        return report
    }

    /// Inserts a snippet picked by hand (the search panel) at the caret: nothing to delete.
    /// With fill-ins, returns `.needsFillIn` first.
    public func insert(_ snippetID: UUID) async -> Report {
        guard let snippet = snippet(snippetID) else { return Report(outcome: .snippetMissing) }
        if let blocked = guardOutcome() { return Report(outcome: blocked, snippetID: snippet.id) }
        let fields = FillIn.fields(for: snippet, lookup: lookup)
        if !fields.isEmpty {
            let request = FillInRequest(matchID: nil, snippetID: snippet.id, fields: fields, typedCase: .asWritten,
                                        backspaces: 0, retype: "", targetPID: environment.frontApp?.pid)
            return Report(outcome: .needsFillIn, snippetID: snippet.id, fillIn: request)
        }
        return await insertResolved(snippet, request: nil, values: FillValues())
    }

    /// The form is done: delete the abbreviation, insert the snippet with `values`.
    public func complete(_ request: FillInRequest, values: FillValues) async -> Report {
        guard let snippet = snippet(request.snippetID) else {
            if let id = request.matchID { tap.cancel(id) }
            return Report(outcome: .snippetMissing)
        }
        if let blocked = guardOutcome() {
            if let id = request.matchID { tap.cancel(id) }
            return Report(outcome: blocked, snippetID: snippet.id)
        }
        if let target = request.targetPID, environment.frontApp?.pid != target {
            if let id = request.matchID { tap.cancel(id) }
            var report = Report(outcome: .targetChanged, snippetID: snippet.id)
            report.resolved = resolve(snippet, typedCase: request.typedCase, values: values)
            return report
        }
        return await insertResolved(snippet, request: request, values: values)
    }

    /// The form was cancelled: the abbreviation stays as typed.
    public func cancel(_ request: FillInRequest) {
        if let id = request.matchID { tap.cancel(id) }
    }

    /// What `snippetID` resolves to with `values` (copying instead of inserting).
    public func resolved(_ snippetID: UUID, values: FillValues = FillValues()) -> Resolved? {
        snippet(snippetID).map { resolve($0, typedCase: .asWritten, values: values) }
    }

    private func insertResolved(_ snippet: Snippet, request: FillInRequest?, values: FillValues) async -> Report {
        let start = environment.now()
        let resolved = resolve(snippet, typedCase: request?.typedCase ?? .asWritten, values: values)
        let plan = InsertionPlanner.plan(resolved: resolved, typedLength: request?.backspaces ?? 0, pending: "", mode: settings.insertMode)
        var withRetype = plan
        withRetype.retype = request?.retype ?? ""
        let resolvedAt = environment.now()
        var report = await post(withRetype, resolved: resolved)
        lastUndoable = nil
        let tail = resolved.textBeforeCursor + withRetype.retype
        if let id = request?.matchID {
            tap.finishInsert(id, tail: tail, undoable: false)
        } else {
            tap.inserted(tail: tail)
        }
        report.timings = [start, resolvedAt, environment.now()]
        report.snippetID = snippet.id
        return report
    }

    private func post(_ plan: InsertionPlan, resolved: Resolved) async -> Report {
        let privacy = environment.pasteboardPrivacy
        poster.backspace(plan.backspaces)
        var restored = false
        var pastedWithoutRestore = false
        switch plan.method {
        case .type:
            poster.type(plan.text)
        case .paste:
            restored = settings.restoreClipboard && privacy == .allowed
            pastedWithoutRestore = settings.restoreClipboard && privacy != .allowed
            if plan.formatted {
                await poster.pasteFormatted(resolved, restore: restored)
            } else {
                await poster.paste(plan.text, restore: restored)
            }
        }
        poster.left(plan.leftArrows)
        if !plan.retype.isEmpty { poster.type(plan.retype) }
        var report = Report(outcome: .inserted(plan.method, characters: plan.text.count, restoredClipboard: restored),
                            pastedWithoutRestore: pastedWithoutRestore, clipboardBlocked: resolved.clipboardBlocked)
        report.formatted = plan.formatted
        return report
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
