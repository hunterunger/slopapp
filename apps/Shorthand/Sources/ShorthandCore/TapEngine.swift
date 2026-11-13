import Foundation

/// A match handed from the tap thread to the main actor.
public struct Match: Sendable, Equatable {
    public var id: UInt64
    public var snippetID: UUID
    /// Characters typed for the abbreviation (= Backspaces needed).
    public var length: Int
    public var typedCase: TypedCase
    /// The front-app generation when it fired; the insert is dropped if the app changed.
    public var frontGeneration: UInt64
    /// Monotonic nanoseconds of the key that completed it.
    public var at: UInt64
}

/// What the tap does with one key.
public enum TapDecision: Sendable, Equatable {
    case none
    /// The newest key completed an abbreviation: expand it.
    case expand(Match)
    /// Backspace straight after an expansion: put the abbreviation back.
    case undo(UInt64)
}

/// Why the tap isn't reading keys right now. Any of them means nothing is buffered.
public struct TapGate: Sendable, Equatable {
    public var paused = false
    /// The app in front is in "Don't expand in".
    public var excludedApp = false
    /// An input method (Japanese, Chinese, Korean...) is the current input source.
    public var inputMethod = false
    /// Secure event input is on (macOS delivers nothing anyway).
    public var secureInput = false
    /// Shorthand's own search or fill-in panel has the keyboard (its keys aren't the app's).
    public var ownPanel = false

    public init() {}

    public var isOpen: Bool { !paused && !excludedApp && !inputMethod && !secureInput && !ownPanel }
}

/// The decision logic of the keyboard tap: the rolling buffer, the matcher, the gate, and
/// what happens to keys typed while an expansion is in flight. Runs on the tap thread under
/// a lock; the main actor calls the `take…`/`finish…` methods under the same lock. Pure:
/// times are passed in, nothing is posted. The listen-only tap can't hold keys back, so keys
/// typed between the match and the insert are remembered (≤ 16, in memory, < 0.5 s) and the
/// insert deletes and retypes them after the snippet, in order.
public struct TapEngine: Sendable {
    public static let expansionTimeout: UInt64 = 500_000_000 // ns
    public static let undoWindow: UInt64 = 2_000_000_000 // ns
    public static let maxPending = 16

    public private(set) var buffer = RollingBuffer()
    public var index: AbbreviationIndex = .empty
    public var wordStartOnly = true
    public var undoWithBackspace = true
    public private(set) var gate = TapGate()
    public private(set) var frontGeneration: UInt64 = 0

    enum Phase: Sendable, Equatable {
        case idle
        /// Matched; waiting for the main actor to insert.
        case waiting(Match)
        /// The main actor is posting the insert.
        case posting(UInt64)
    }

    private(set) var phase = Phase.idle
    private var pending = ContiguousArray<UInt32>(repeating: 0, count: TapEngine.maxPending)
    private var pendingCount = 0
    /// A key we can't replay (arrow, Return, Backspace, a click...) came in while waiting.
    private var pendingSpoiled = false
    private var afterDeadKey = false
    private var nextMatchID: UInt64 = 1
    /// The last typed (not pasted) expansion that Backspace may undo.
    private var undoable: (id: UInt64, at: UInt64)?

    // Numbers only, for diagnostics.
    public private(set) var matches = 0
    public private(set) var interleavedKeys = 0
    public private(set) var syntheticSkipped = 0

    public init() {}

    // MARK: Tap thread

    public mutating func handle(_ input: KeyInput, now: UInt64) -> TapDecision {
        if input.origin == .ours || input.kind == .ignored { return .none }
        // Keys typed into Shorthand's own panel belong to it, not to the app behind.
        if gate.ownPanel { return .none }
        switch phase {
        case .posting:
            // A real key landed while we were posting: it may sit inside our text. Count it.
            if input.origin == .hardware { interleavedKeys += 1 }
            return .none
        case .waiting(let match):
            if now &- match.at > Self.expansionTimeout {
                phase = .idle
                reset()
            } else {
                holdWhileWaiting(input)
                return .none
            }
        case .idle:
            break
        }
        guard gate.isOpen else { return .none }
        if input.origin == .synthetic {
            // Someone else typed into the field: we don't know what's before the caret now.
            syntheticSkipped += 1
            undoable = nil
            reset()
            return .none
        }
        switch input.kind {
        case .characters:
            undoable = nil
            if afterDeadKey {
                // The composed letter (é) exists only in the app: don't guess.
                afterDeadKey = false
                buffer.reset(beforeIsWord: true)
                return .none
            }
            for i in 0..<input.count { buffer.append(input[i]) }
            guard let hit = index.match(buffer, wordStartOnly: wordStartOnly) else { return .none }
            let match = Match(id: nextMatchID, snippetID: index.entries[hit.entry].snippetID, length: hit.length,
                              typedCase: hit.typedCase, frontGeneration: frontGeneration, at: now)
            nextMatchID &+= 1
            matches += 1
            phase = .waiting(match)
            pendingCount = 0
            pendingSpoiled = false
            return .expand(match)
        case .backspace:
            if undoWithBackspace, let undoable, now &- undoable.at <= Self.undoWindow {
                self.undoable = nil
                return .undo(undoable.id)
            }
            undoable = nil
            buffer.removeLast()
            return .none
        case .boundary, .reset:
            undoable = nil
            reset()
            return .none
        case .deadKey:
            undoable = nil
            reset()
            afterDeadKey = true
            return .none
        case .ignored:
            return .none
        }
    }

    private mutating func holdWhileWaiting(_ input: KeyInput) {
        guard input.origin == .hardware else {
            pendingSpoiled = true
            return
        }
        guard input.kind == .characters, pendingCount + input.count <= Self.maxPending else {
            pendingSpoiled = true
            return
        }
        for i in 0..<input.count {
            pending[pendingCount] = input[i]
            pendingCount += 1
        }
    }

    // MARK: Main actor

    public struct InsertStart: Sendable, Equatable {
        /// The abbreviation exactly as typed (for undo).
        public var typed: String
        /// Keys typed after the match, to retype after the snippet.
        public var pending: String
    }

    /// What was typed for and after the match, if the match is still current and can go
    /// ahead. Moves to "posting". Nil: drop it (timed out, superseded, or a key that can't be
    /// replayed came in), and the abbreviation stays as typed.
    public mutating func beginInsert(_ id: UInt64, now: UInt64) -> InsertStart? {
        guard case .waiting(let match) = phase, match.id == id else { return nil }
        guard now &- match.at <= Self.expansionTimeout, !pendingSpoiled, match.frontGeneration == frontGeneration else {
            phase = .idle
            reset()
            return nil
        }
        var scalars = String.UnicodeScalarView()
        for i in 0..<pendingCount { if let scalar = Unicode.Scalar(pending[i]) { scalars.append(scalar) } }
        var typed = String.UnicodeScalarView()
        for i in stride(from: min(match.length, buffer.count) - 1, through: 0, by: -1) {
            if let scalar = Unicode.Scalar(buffer.fromEnd(i)) { typed.append(scalar) }
        }
        clearPending()
        phase = .posting(id)
        return InsertStart(typed: String(typed), pending: String(scalars))
    }

    /// The insert is done. `tail` is the text now before the caret (the snippet up to the
    /// cursor, plus any retyped keys), so the next abbreviation sees the right context.
    /// `undoable`: Backspace right now may undo it.
    public mutating func finishInsert(_ id: UInt64, tail: String, undoable: Bool, now: UInt64) {
        guard case .posting(let current) = phase, current == id else { return }
        phase = .idle
        seed(tail)
        self.undoable = undoable ? (id, now) : nil
    }

    /// The main actor gave up on a match (a guard failed): the abbreviation stays as typed.
    public mutating func cancel(_ id: UInt64) {
        switch phase {
        case .waiting(let match) where match.id == id: break
        case .posting(let current) where current == id: break
        default: return
        }
        phase = .idle
        clearPending()
        reset()
    }

    /// Text went in without a typed abbreviation (the search panel): `tail` is now before the caret.
    public mutating func inserted(tail: String) {
        guard phase == .idle else { return }
        undoable = nil
        seed(tail)
    }

    /// Undo is being posted (Backspaces + the abbreviation): ignore keys until it's done.
    public mutating func beginUndo() { phase = .posting(0) }

    public mutating func finishUndo(abbreviation: String) {
        if case .posting(0) = phase { phase = .idle }
        seed(abbreviation)
    }

    public mutating func setGate(_ gate: TapGate) {
        guard gate != self.gate else { return }
        self.gate = gate
        if !gate.isOpen {
            reset()
            if case .waiting = phase { phase = .idle }
            clearPending()
            undoable = nil
        }
    }

    /// The front app or window changed: start over, and drop any match in flight.
    public mutating func frontChanged() {
        frontGeneration &+= 1
        undoable = nil
        reset()
    }

    /// Mouse-down, input source change: the caret may be anywhere.
    public mutating func reset() {
        buffer.reset()
        afterDeadKey = false
    }

    private mutating func seed(_ tail: String) {
        buffer.reset()
        afterDeadKey = false
        for scalar in tail.unicodeScalars.suffix(RollingBuffer.capacity) {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                buffer.reset()
            } else {
                buffer.append(scalar.value)
            }
        }
    }

    private mutating func clearPending() {
        for i in 0..<pending.count { pending[i] = 0 }
        pendingCount = 0
        pendingSpoiled = false
    }

    public var isBusy: Bool { phase != .idle }
}
