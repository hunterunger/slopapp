import Foundation

/// Turns raw key events into the presses sequences are made of: a key with its modifiers, or a
/// modifier pressed and released on its own (no other key, no click, not held long). Shared by
/// the matcher (the keyboard tap) and the recorder (the editor).
public struct KeyStepReader: Sendable {
    /// A modifier held longer than this isn't a tap (it was held for something else).
    public var maxModifierHold: Double = 0.5
    private var flags: Modifiers = []
    private var lone: (modifier: Modifiers, since: Double)?

    public init() {}

    public mutating func reset() {
        flags = []
        lone = nil
    }

    /// A key went down. Autorepeats aren't presses.
    public mutating func keyDown(keyCode: Int, modifiers: Modifiers, isRepeat: Bool) -> KeyStep? {
        lone = nil
        guard !isRepeat else { return nil }
        return .key(KeyCombo(keyCode: keyCode, modifiers: modifiers.intersection(.all)))
    }

    /// The modifier keys changed. `clickedSince` says whether a mouse button went down while the
    /// modifier was held (⌘-click isn't a ⌘ tap); the tap asks the system.
    public mutating func flagsChanged(_ modifiers: Modifiers, time: Double, clickedSince: (Double) -> Bool = { _ in false }) -> KeyStep? {
        let new = modifiers.intersection(.all)
        defer { flags = new }
        if flags.isEmpty, new.rawValue.nonzeroBitCount == 1 {
            lone = (new, time)
            return nil
        }
        if new.isEmpty, let held = lone, held.modifier == flags {
            lone = nil
            guard time - held.since <= maxModifierHold, !clickedSince(held.since) else { return nil }
            return .modifierTap(held.modifier)
        }
        // A second modifier joined (a chord), or one of several let go: not a lone tap.
        lone = nil
        return nil
    }
}

/// Watches presses for the sequences bound in the front app. Pure and allocation-light: the
/// keyboard tap calls it for every key event, so it does a few comparisons and returns.
/// Sequences never swallow keys; when one completes, the history starts over (so ⌘ ⌘ ⌘ fires
/// "⌘ twice" once, not twice).
public struct KeySequenceMatcher: Sendable {
    public private(set) var sequences: [KeySequence] = []
    private var reader = KeyStepReader()
    private var history: [(step: KeyStep, time: Double)] = []
    private var longest = 0

    public init() { history.reserveCapacity(KeySequence.maxSteps + 1) }

    /// The sequences to watch, longest first (so ⌘ three times wins over ⌘ twice when both match).
    public mutating func set(_ sequences: [KeySequence]) {
        self.sequences = sequences.filter(\.isUsable).sorted { $0.steps.count > $1.steps.count }
        longest = self.sequences.first?.steps.count ?? 0
        history.removeAll(keepingCapacity: true)
        reader.reset()
    }

    public var isEmpty: Bool { sequences.isEmpty }

    public mutating func keyDown(keyCode: Int, modifiers: Modifiers, isRepeat: Bool, time: Double) -> KeySequence? {
        guard !sequences.isEmpty, let step = reader.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat) else { return nil }
        return add(step, time: time)
    }

    public mutating func flagsChanged(_ modifiers: Modifiers, time: Double, clickedSince: (Double) -> Bool = { _ in false }) -> KeySequence? {
        guard !sequences.isEmpty, let step = reader.flagsChanged(modifiers, time: time, clickedSince: clickedSince) else { return nil }
        return add(step, time: time)
    }

    private mutating func add(_ step: KeyStep, time: Double) -> KeySequence? {
        history.append((step, time))
        if history.count > longest { history.removeFirst(history.count - longest) }
        for sequence in sequences where matches(sequence) {
            history.removeAll(keepingCapacity: true)
            return sequence
        }
        return nil
    }

    private func matches(_ sequence: KeySequence) -> Bool {
        let steps = sequence.steps
        guard history.count >= steps.count else { return false }
        let tail = history.suffix(steps.count)
        var previous: Double?
        for (entry, step) in zip(tail, steps) {
            guard entry.step == step else { return false }
            if let previous, entry.time - previous > sequence.timeout { return false }
            previous = entry.time
        }
        return true
    }
}

/// Records a sequence in the editor: presses collect until a pause longer than the sequence's
/// timeout, then the recording is finished. A single key with ⌘, ⌥ or ⌃ on its own stays a
/// key combination (the common case); a second press within the timeout makes it a sequence.
public struct KeySequenceRecorder: Sendable {
    public private(set) var steps: [KeyStep] = []
    public private(set) var lastPress: Double?
    /// The longest pause between presses so far, so the saved sequence allows it.
    public private(set) var longestGap: Double = 0
    public var timeout: Double
    private var reader = KeyStepReader()

    public init(timeout: Double = KeySequence.defaultTimeout) { self.timeout = timeout }

    public enum Result: Equatable, Sendable {
        /// Still listening; this is what's been pressed so far.
        case recording([KeyStep])
        /// Nothing usable yet.
        case nothing
    }

    public mutating func reset() {
        steps = []
        lastPress = nil
        longestGap = 0
        reader.reset()
    }

    public mutating func keyDown(keyCode: Int, modifiers: Modifiers, isRepeat: Bool, time: Double) -> Result {
        guard let step = reader.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat) else { return current }
        return add(step, time: time)
    }

    public mutating func flagsChanged(_ modifiers: Modifiers, time: Double) -> Result {
        guard let step = reader.flagsChanged(modifiers, time: time) else { return current }
        return add(step, time: time)
    }

    private var current: Result { steps.isEmpty ? .nothing : .recording(steps) }

    private mutating func add(_ step: KeyStep, time: Double) -> Result {
        if let lastPress, time - lastPress > timeout {
            steps = []
            longestGap = 0
        } else if let lastPress {
            longestGap = max(longestGap, time - lastPress)
        }
        steps.append(step)
        if steps.count > KeySequence.maxSteps { steps.removeFirst(steps.count - KeySequence.maxSteps) }
        lastPress = time
        return .recording(steps)
    }

    /// Whether the pause since the last press means the recording is done.
    public func isFinished(at time: Double) -> Bool {
        guard let lastPress else { return false }
        return time - lastPress > timeout
    }

    /// What was recorded: a key combination (one key with ⌘, ⌥ or ⌃, or a function key), a key
    /// sequence, or nil when it's neither (a single plain key: that's typing).
    public var trigger: Trigger? {
        if steps.count == 1, case .key(let combo) = steps[0] {
            return combo.isUsableAsTrigger ? .keyCombo(combo) : nil
        }
        // The shortest offered timeout that comfortably allows the recorded pauses.
        let needed = longestGap * 1.3
        let saved = KeySequence.timeouts.first { $0 >= max(needed, KeySequence.defaultTimeout) } ?? KeySequence.timeouts.last ?? timeout
        let sequence = KeySequence(steps, timeout: saved)
        return sequence.isUsable ? .keySequence(sequence) : nil
    }
}
