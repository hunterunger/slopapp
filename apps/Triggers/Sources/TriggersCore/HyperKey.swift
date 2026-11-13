import Foundation

/// The hyper key: Caps Lock acts as ⌃⌥⇧⌘ while held, and as Escape when tapped on its own.
///
/// How: while the setting is on (and Triggers isn't paused and has Accessibility), Caps Lock is
/// remapped to F18 at the HID level (`hidutil`'s `UserKeyMapping`, documented in Apple's
/// TN2450), so it stops toggling caps; Triggers' keyboard tap turns F18 down/up into the four
/// modifiers going down/up. The remap is undone when the setting goes off, on pause, when
/// Accessibility goes away, on quit, and by a watchdog process if Triggers crashes (the remap
/// would otherwise last until the next restart). See `HyperKeyController`.
public enum HyperKey {
    /// HID usages (page 7 = keyboard) for `UserKeyMapping`.
    public static let capsLockUsage: Int64 = 0x7_0000_0039
    public static let f18Usage: Int64 = 0x7_0000_006D
    public static let modifiers: Modifiers = .all
    /// Released within this time with no other key pressed: Escape.
    public static let tapLimit = 1.0
}

/// The keyboard tap's decision for the hyper key, free of system calls (tests construct the
/// events). Runs on the tap thread: constant time, no allocation.
public struct HyperKeyDecider: Sendable {
    public enum EventKind: Sendable { case keyDown, keyUp, flagsChanged }

    public enum Decision: Equatable, Sendable {
        /// Let the event through untouched.
        case pass
        /// Let it through with these flags (a key pressed while hyper is held).
        case passWithFlags(UInt64)
        /// Drop it and post these instead (hyper going down or up).
        case replace(with: [KeyPostPlan.Event])
    }

    public private(set) var isHeld = false
    private var pressedAt = 0.0
    private var used = false

    public init() {}

    public mutating func reset() {
        isHeld = false
        used = false
    }

    /// `clickedSince` says whether a mouse button went down after the given time (a click while
    /// hyper is held means it was used, so no Escape).
    public mutating func decide(_ kind: EventKind, keyCode: Int, flags: UInt64, isRepeat: Bool, time: Double,
                                isOwnEvent: Bool, clickedSince: (Double) -> Bool = { _ in false }) -> Decision {
        guard !isOwnEvent else { return .pass }
        if keyCode == KeyNames.f18, kind != .flagsChanged {
            if kind == .keyDown {
                if isRepeat || isHeld { return .replace(with: []) }
                isHeld = true
                used = false
                pressedAt = time
                return .replace(with: HyperKeyDecider.press(flags: flags))
            }
            guard isHeld else { return .replace(with: []) }
            isHeld = false
            var events = HyperKeyDecider.release(flags: flags)
            if !used, time - pressedAt <= HyperKey.tapLimit, !clickedSince(pressedAt) {
                // After the release above nothing is held, so Escape goes out plain.
                events += KeyPostPlan.events(for: KeyCombo(keyCode: KeyNames.escape, modifiers: []), held: [])
            }
            return .replace(with: events)
        }
        guard isHeld else { return .pass }
        if kind == .keyDown { used = true }
        return .passWithFlags(flags | HyperKey.modifiers.cgFlags)
    }

    /// The four modifiers going down, one flags-changed event each, on top of what's held.
    static func press(flags: UInt64) -> [KeyPostPlan.Event] {
        var current = Modifiers(cgFlags: flags)
        var events: [KeyPostPlan.Event] = []
        for (modifier, code) in KeyPostPlan.modifierKeys where !current.contains(modifier) {
            current.insert(modifier)
            events.append(KeyPostPlan.Event(kind: .flagsChanged, keyCode: code, flags: current.cgFlags))
        }
        return events
    }

    /// Back to what the person holds physically (`flags` of the F18 up, which carry the
    /// window server's view; hyper's own four are let go unless really held).
    static func release(flags: UInt64) -> [KeyPostPlan.Event] {
        var current = HyperKey.modifiers
        var events: [KeyPostPlan.Event] = []
        let physical = Modifiers(cgFlags: flags).subtracting(HyperKey.modifiers)
        for (modifier, code) in KeyPostPlan.modifierKeys.reversed() where !physical.contains(modifier) {
            current.remove(modifier)
            events.append(KeyPostPlan.Event(kind: .flagsChanged, keyCode: code, flags: current.cgFlags))
        }
        return events
    }
}

/// Reads and changes the HID key remap. The real one runs `/usr/bin/hidutil`; tests and test
/// mode use fakes, so the owner's keyboard is never touched by a test.
@MainActor
public protocol KeyRemapper: AnyObject {
    /// What's mapped right now.
    func currentMapping() -> KeyRemapState
    /// Maps Caps Lock to F18 and starts the crash watchdog. False if it didn't take.
    func applyHyper() -> Bool
    /// Clears the mapping and stops the watchdog.
    func removeHyper()
}

public enum KeyRemapState: Equatable, Sendable {
    /// Nothing remapped.
    case none
    /// Only Triggers' own Caps Lock → F18 (on or left over from a crash).
    case ours
    /// Someone else remaps keys this way: Triggers leaves it alone.
    case other
}

/// Turns the remap on and off, safely. Never overwrites someone else's mapping, cleans up a
/// mapping left over from a crash at launch, and reports a one-line problem for Settings.
@MainActor
public final class HyperKeyController {
    public let remapper: KeyRemapper
    public private(set) var isActive = false
    public private(set) var problem: String?

    public init(remapper: KeyRemapper) { self.remapper = remapper }

    /// At launch, before anything else: a mapping of ours with nothing running means the last
    /// run crashed and the watchdog didn't get to it.
    public func cleanUpLeftovers() {
        if !isActive, remapper.currentMapping() == .ours { remapper.removeHyper() }
    }

    public func setActive(_ wanted: Bool) {
        guard wanted != isActive else { return }
        if wanted {
            switch remapper.currentMapping() {
            case .other:
                problem = "Another app or setting already remaps keys with hidutil, so Triggers left Caps Lock alone."
                return
            case .none, .ours:
                break
            }
            guard remapper.applyHyper() else {
                problem = "macOS didn't accept the Caps Lock remap. Caps Lock works as before."
                return
            }
            problem = nil
            isActive = true
        } else {
            remapper.removeHyper()
            isActive = false
        }
    }

    /// A keyboard came or went, or the Mac woke: new keyboards don't have the mapping yet.
    public func reapply() {
        guard isActive else { return }
        if !remapper.applyHyper() { problem = "macOS didn't accept the Caps Lock remap after a keyboard change." }
    }
}

/// `hidutil property --get UserKeyMapping` output, and the JSON for `--set`.
public enum UserKeyMappingText {
    /// The (source, destination) usage pairs in hidutil's output, over every service listed.
    public static func pairs(in output: String) -> [(source: Int64, destination: Int64)] {
        var sources: [Int64] = []
        var destinations: [Int64] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let value = number(after: "HIDKeyboardModifierMappingSrc", in: text) { sources.append(value) }
            if let value = number(after: "HIDKeyboardModifierMappingDst", in: text) { destinations.append(value) }
        }
        return zip(sources, destinations).map { ($0, $1) }
    }

    private static func number(after key: String, in text: String) -> Int64? {
        guard let range = text.range(of: key) else { return nil }
        let rest = text[range.upperBound...].drop { $0 == " " || $0 == "=" || $0 == "\"" || $0 == ":" }
        let digits = rest.prefix { $0.isHexDigit || $0 == "x" || $0 == "X" }
        if digits.hasPrefix("0x") || digits.hasPrefix("0X") { return Int64(digits.dropFirst(2), radix: 16) }
        return Int64(digits)
    }

    public static func state(of output: String) -> KeyRemapState {
        let pairs = pairs(in: output)
        if pairs.isEmpty {
            // No pairs we could read, but something other than "(null)" or an empty list is set.
            let values = output.split(whereSeparator: \.isNewline).dropFirst()
                .filter { $0.contains("UserKeyMapping") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let unreadable = values.contains { !$0.hasSuffix("(null)") && !$0.hasSuffix("()") && !$0.hasSuffix("(") }
            return unreadable ? .other : .none
        }
        return pairs.allSatisfy { $0.source == HyperKey.capsLockUsage && $0.destination == HyperKey.f18Usage } ? .ours : .other
    }

    /// `{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":…,"HIDKeyboardModifierMappingDst":…}]}`.
    public static let hyperJSON =
        "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":\(HyperKey.capsLockUsage),\"HIDKeyboardModifierMappingDst\":\(HyperKey.f18Usage)}]}"
    public static let clearJSON = "{\"UserKeyMapping\":[]}"
}
