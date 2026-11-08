import AppKit
import CoreGraphics
import Darwin

enum Keys {
    // US ANSI virtual key codes (Carbon kVK_*).
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "backspace": 51, "escape": 53,
        "esc": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98,
        "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111, "home": 115, "pageup": 116,
        "forwarddelete": 117, "end": 119, "pagedown": 121, "left": 123, "right": 124,
        "down": 125, "up": 126, "enter": 76, "plus": 24, "minus": 27, "comma": 43, "period": 47,
    ]

    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand,
        "shift": .maskShift, "⇧": .maskShift,
        "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate, "⌥": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    /// Parses "cmd+shift+v" into a key code and flags.
    static func parse(_ combo: String) throws -> (CGKeyCode, CGEventFlags) {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        let parts = combo.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        for (i, part) in parts.enumerated() {
            let p = part.isEmpty && i == parts.count - 1 ? "plus" : part
            if let m = modifiers[p], i < parts.count - 1 { flags.insert(m); continue }
            guard let code = codes[p] else {
                throw DriveError("unknown key \(quote(p)) in \(quote(combo)). Keys: letters, digits, return, tab, space, escape, delete, arrows (up/down/left/right), f1-f12, home/end/pageup/pagedown, punctuation. Modifiers: cmd shift opt ctrl fn.")
            }
            key = code
        }
        guard let key else { throw DriveError("no key in \(quote(combo))") }
        return (key, flags)
    }

    /// The modifier keys, in the order a stroke presses them (US ANSI, left-hand keys).
    static let modifierKeys: [(flag: CGEventFlags, code: CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63),
    ]
    static let allModifiers = CGEventFlags(modifierKeys.map(\.flag))

    static func name(of flag: CGEventFlags) -> String {
        switch flag {
        case .maskControl: "ctrl"
        case .maskAlternate: "opt"
        case .maskShift: "shift"
        case .maskCommand: "cmd"
        case .maskSecondaryFn: "fn"
        default: "?"
        }
    }

    /// One event of a stroke: a key going down or up, with the modifier flags held right after it.
    struct Event: Equatable {
        let code: CGKeyCode
        let down: Bool
        let flags: CGEventFlags
        /// A modifier key: posted as a flagsChanged event, like the hardware does.
        let isModifier: Bool
    }

    /// The events of one press of `code` with `flags`: each modifier goes down on its own
    /// (flags building up), then the key goes down and up with every flag set, then the
    /// modifiers come up in reverse until no flag is left. A key event that only carries
    /// flags, with no modifier events around it, can leave the window server thinking
    /// ⌘/⌥/⌃ are still held after a system-wide press.
    static func stroke(_ code: CGKeyCode, flags: CGEventFlags) -> [Event] {
        let mods = modifierKeys.filter { flags.contains($0.flag) }
        var held: CGEventFlags = []
        var events: [Event] = []
        for m in mods {
            held.insert(m.flag)
            events.append(Event(code: m.code, down: true, flags: held, isModifier: true))
        }
        events.append(Event(code: code, down: true, flags: held, isModifier: false))
        events.append(Event(code: code, down: false, flags: held, isModifier: false))
        for m in mods.reversed() {
            held.remove(m.flag)
            events.append(Event(code: m.code, down: false, flags: held, isModifier: true))
        }
        return events
    }

    /// Posts a key press. To a pid by default, so it can't land in another app; `pid: nil`
    /// posts system-wide. Every modifier is released before this returns, also when the
    /// process is interrupted mid-stroke (see `KeyStrokes`). Returns the modifiers a
    /// system-wide press found still registered as held afterwards (and released again),
    /// which should never happen.
    @discardableResult
    static func press(_ code: CGKeyCode, flags: CGEventFlags, pid: pid_t?) throws -> CGEventFlags {
        let src = CGEventSource(stateID: .hidSystemState)
        // Build every event first, so a stroke is posted whole or not at all.
        let events = try stroke(code, flags: flags).map { step -> (Event, CGEvent) in
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: step.code, keyDown: step.down) else {
                throw DriveError("couldn't create a key event (code \(step.code)); nothing was pressed")
            }
            if step.isModifier { e.type = .flagsChanged }
            e.flags = step.flags
            return (step, e)
        }
        KeyStrokes.run(global: pid == nil) { posted in
            for (step, e) in events {
                if let pid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
                if step.isModifier { posted(step) }
                usleep(8_000)
            }
        }
        guard pid == nil, !flags.intersection(allModifiers).isEmpty else { return [] }
        return KeyStrokes.selfCheck(used: flags)
    }

    static func type(_ text: String, pid: pid_t) throws {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text {
            if ch == "\n" { try press(36, flags: [], pid: pid); continue }
            if ch == "\t" { try press(48, flags: [], pid: pid); continue }
            let units = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                e.flags = []
                e.postToPid(pid)
                usleep(4_000)
            }
        }
    }
}

/// Makes sure a system-wide stroke never leaves a modifier held.
///
/// A stroke runs under a lock and tracks which modifier keys it has put down. SIGINT,
/// SIGTERM, SIGHUP and SIGQUIT are caught (from the first stroke on): the handler waits for
/// the lock, so a stroke always finishes (modifiers back up) before the process exits, and
/// releases anything still marked held. SIGKILL can't be caught: `release-modifiers` is the
/// way back from that.
enum KeyStrokes {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var held: [CGKeyCode] = []      // global modifier keys down right now
        var installed = false
    }
    private static let state = State()

    static func run(global: Bool, _ body: (_ posted: (Keys.Event) -> Void) -> Void) {
        installSignalHandlers()
        state.lock.lock()
        defer {
            releaseHeld()
            state.lock.unlock()
        }
        body { step in
            guard global else { return }
            if step.down { state.held.append(step.code) } else { state.held.removeAll { $0 == step.code } }
        }
    }

    /// Posts an up for every modifier still marked held. Call with the lock taken.
    private static func releaseHeld() {
        guard !state.held.isEmpty else { return }
        release(Keys.modifierKeys.filter { state.held.contains($0.code) }.map(\.code))
        state.held = []
    }

    /// System-wide flagsChanged ups for these modifier keys, ending with no flags set.
    static func release(_ codes: [CGKeyCode]) {
        let src = CGEventSource(stateID: .hidSystemState)
        var remaining = CGEventFlags(Keys.modifierKeys.filter { codes.contains($0.code) }.map(\.flag))
        for m in Keys.modifierKeys.reversed() where codes.contains(m.code) {
            remaining.remove(m.flag)
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: m.code, keyDown: false) else { continue }
            e.type = .flagsChanged
            e.flags = remaining
            e.post(tap: .cghidEventTap)
            usleep(8_000)
        }
    }

    /// After a system-wide stroke: if the session still reports any of its modifiers as
    /// held, release them again. Returns what was stuck.
    static func selfCheck(used flags: CGEventFlags) -> CGEventFlags {
        usleep(20_000)
        let stuck = CGEventSource.flagsState(.combinedSessionState).intersection(flags).intersection(Keys.allModifiers)
        guard !stuck.isEmpty else { return [] }
        release(Keys.modifierKeys.filter { stuck.contains($0.flag) }.map(\.code))
        return stuck
    }

    private static func installSignalHandlers() {
        state.lock.lock()
        defer { state.lock.unlock() }
        guard !state.installed else { return }
        state.installed = true
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                // Waits for a stroke in progress to finish, so its modifiers come back up first.
                state.lock.lock()
                releaseHeld()
                exit(128 + sig)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Kept alive for the life of the process. Only touched under `state.lock`.
    nonisolated(unsafe) private static var signalSources: [any DispatchSourceSignal] = []
}

enum Mouse {
    /// Puts the cursor back where the user had it, once the window server has seen the
    /// button go up. Warping while it still thinks the button is down drags whatever was
    /// grabbed (a window, a selection) over to the old cursor position.
    static func restore(_ saved: CGPoint?, button: CGMouseButton = .left) {
        guard let saved else { return }
        for _ in 0..<50 where CGEventSource.buttonState(.combinedSessionState, button: button) {
            usleep(10_000)
        }
        usleep(50_000)
        CGWarpMouseCursorPosition(saved)
    }

    /// Points a drag passes through (start, `steps` samples, end), in order.
    static func path(from a: CGPoint, to b: CGPoint, steps: Int = 20) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// `check` runs right before each button press, so a window that pops up after the
    /// up-front check still stops the click.
    static func click(at p: CGPoint, right: Bool, count: Int, check: (CGPoint) throws -> Void) throws {
        let saved = CGEvent(source: nil)?.location
        defer { restore(saved, button: right ? .right : .left) }
        let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
            right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        for n in 1...max(1, count) {
            try check(p)
            for type in [down, up] {
                let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                e?.post(tap: .cghidEventTap)
                usleep(20_000)
            }
        }
    }

    /// Drags along `points`. `checkStart` runs before the press, `checkStep` before every
    /// later step; if that throws, the button is released at the last point that passed and
    /// the error is rethrown.
    static func drag(along points: [CGPoint], checkStart: (CGPoint) throws -> Void, checkStep check: (CGPoint) throws -> Void) throws {
        guard let a = points.first else { return }
        let saved = CGEvent(source: nil)?.location
        defer { restore(saved) }
        try checkStart(a)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
        var last = a
        for p in points.dropFirst() {
            do { try check(p) } catch {
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: last, mouseButton: .left)?.post(tap: .cghidEventTap)
                throw error
            }
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            last = p
            usleep(12_000)
        }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: last, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

/// CPU time and memory for a pid, from proc_pid_rusage (precise, unlike `ps %cpu`).
struct Usage {
    let cpuNanoseconds: UInt64
    let footprintBytes: UInt64   // what Activity Monitor calls "Memory"
    let residentBytes: UInt64

    static func of(_ pid: pid_t) -> Usage? {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard ok == 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = info.ri_user_time + info.ri_system_time
        let ns = ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
        return Usage(cpuNanoseconds: ns, footprintBytes: info.ri_phys_footprint, residentBytes: info.ri_resident_size)
    }
}
