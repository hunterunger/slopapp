import Foundation

/// A touch frame as a value: for replays, tests and the benchmark.
public struct TouchFrame: Codable, Sendable, Equatable {
    public var timestamp: Double
    public var contacts: [Contact]

    public struct Contact: Codable, Sendable, Equatable {
        public var id: Int32
        public var x: Float
        public var y: Float
        public var size: Float?
        public var state: Int32?

        public init(id: Int32, x: Float, y: Float, size: Float? = nil, state: Int32? = nil) {
            self.id = id
            self.x = x
            self.y = y
            self.size = size
            self.state = state
        }

        public var touch: TouchContact { TouchContact(id: id, x: x, y: y, size: size ?? 1, state: state ?? 4) }
    }

    public init(timestamp: Double, contacts: [Contact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }

    public var touches: [TouchContact] { contacts.map(\.touch) }
}

/// Realistic synthetic touch sequences (fingers landing a few ms apart, ~120 Hz frames).
public enum SyntheticTouches {
    public static let frameInterval = 1.0 / 120

    /// Fingers spread across the middle of the pad.
    private static func start(_ finger: Int, of count: Int) -> (Float, Float) {
        (0.35 + Float(finger) * 0.08, 0.45 + Float(finger % 2) * 0.03)
    }

    /// A tap: fingers land within `stagger`, rest `hold`, lift.
    public static func tap(fingers: Int, at start: Double = 0, stagger: Double = 0.01, hold: Double = 0.08, drift: Float = 0) -> [TouchFrame] {
        var frames: [TouchFrame] = []
        var time = start
        let landed = stagger * Double(fingers - 1)
        let end = landed + hold
        var elapsed = 0.0
        while elapsed <= end {
            let down = min(fingers, Int(elapsed / max(stagger, 0.0001)) + 1)
            let progress = Float(elapsed / max(end, 0.001))
            let contacts = (0..<down).map { index -> TouchFrame.Contact in
                let (x, y) = Self.start(index, of: fingers)
                return TouchFrame.Contact(id: Int32(index + 1), x: x + drift * progress, y: y)
            }
            frames.append(TouchFrame(timestamp: time, contacts: contacts))
            elapsed += frameInterval
            time += frameInterval
        }
        frames.append(TouchFrame(timestamp: time, contacts: []))
        return frames
    }

    /// A swipe: fingers land together, travel `distance` (fraction of the pad) over `duration`.
    public static func swipe(fingers: Int, direction: Gesture.Direction, at start: Double = 0, distance: Float = 0.3,
                             duration: Double = 0.18) -> [TouchFrame] {
        var frames: [TouchFrame] = []
        var time = start
        let steps = max(2, Int(duration / frameInterval))
        let (dx, dy): (Float, Float) = switch direction {
        case .left: (-distance, 0)
        case .right: (distance, 0)
        case .up: (0, distance)
        case .down: (0, -distance)
        }
        for step in 0...steps {
            let progress = Float(step) / Float(steps)
            let contacts = (0..<fingers).map { index -> TouchFrame.Contact in
                let (x, y) = Self.start(index, of: fingers)
                return TouchFrame.Contact(id: Int32(index + 1), x: x - dx / 2 + dx * progress, y: y - dy / 2 + dy * progress)
            }
            frames.append(TouchFrame(timestamp: time, contacts: contacts))
            time += frameInterval
        }
        frames.append(TouchFrame(timestamp: time, contacts: []))
        return frames
    }

    /// Any supported gesture, as a recorded hand would make it.
    public static func frames(for gesture: Gesture, at start: Double = 0) -> [TouchFrame] {
        switch gesture.kind {
        case .tap: return tap(fingers: gesture.fingers, at: start)
        case .doubleTap:
            let first = tap(fingers: gesture.fingers, at: start)
            return first + tap(fingers: gesture.fingers, at: (first.last?.timestamp ?? start) + 0.08)
        case .swipe: return swipe(fingers: gesture.fingers, direction: gesture.direction ?? .left, at: start)
        case .pinchIn, .pinchOut: return pinch(fingers: gesture.fingers, spreading: gesture.kind == .pinchOut, at: start)
        case .rotateLeft, .rotateRight: return rotate(clockwise: gesture.kind == .rotateRight, at: start)
        case .cornerTap: return cornerTap(gesture.corner ?? .topLeft, at: start)
        case .edgeSwipe: return edgeSwipe(gesture.edge ?? .left, at: start)
        case .tipTap: return tipTap(side: gesture.direction ?? .right, at: start)
        }
    }

    /// Pad size the generators assume (millimetres), the recognizer's default.
    static let padWidth: Float = 156
    static let padHeight: Float = 96

    /// Fingers around a centre, `radius` millimetres out, starting at `angle` radians.
    private static func ring(_ fingers: Int, radius: Float, angle: Float, centreX: Float = 78, centreY: Float = 48) -> [TouchFrame.Contact] {
        (0..<fingers).map { index in
            let a = angle + Float(index) * 2 * .pi / Float(fingers)
            return TouchFrame.Contact(id: Int32(index + 1), x: (centreX + radius * cos(a)) / padWidth,
                                      y: (centreY + radius * sin(a)) / padHeight)
        }
    }

    /// Fingers land together and pinch in (or spread out) by half their spread.
    public static func pinch(fingers: Int, spreading: Bool, at start: Double = 0, duration: Double = 0.25) -> [TouchFrame] {
        let steps = max(2, Int(duration / frameInterval))
        let (from, to): (Float, Float) = spreading ? (14, 30) : (30, 14)
        var frames: [TouchFrame] = []
        for step in 0...steps {
            let progress = Float(step) / Float(steps)
            frames.append(TouchFrame(timestamp: start + Double(step) * frameInterval,
                                     contacts: ring(fingers, radius: from + (to - from) * progress, angle: 0.3)))
        }
        frames.append(TouchFrame(timestamp: start + Double(steps + 1) * frameInterval, contacts: []))
        return frames
    }

    /// Two fingers turn 60° around their centre.
    public static func rotate(clockwise: Bool, at start: Double = 0, duration: Double = 0.3) -> [TouchFrame] {
        let steps = max(2, Int(duration / frameInterval))
        let turn: Float = (clockwise ? -1 : 1) * .pi / 3
        var frames: [TouchFrame] = []
        for step in 0...steps {
            let progress = Float(step) / Float(steps)
            frames.append(TouchFrame(timestamp: start + Double(step) * frameInterval,
                                     contacts: ring(2, radius: 20, angle: 0.4 + turn * progress)))
        }
        frames.append(TouchFrame(timestamp: start + Double(steps + 1) * frameInterval, contacts: []))
        return frames
    }

    /// One finger taps near a corner.
    public static func cornerTap(_ corner: Gesture.Corner, at start: Double = 0) -> [TouchFrame] {
        let x: Float = corner == .topLeft || corner == .bottomLeft ? 0.07 : 0.93
        let y: Float = corner == .topLeft || corner == .topRight ? 0.92 : 0.08
        var frames: [TouchFrame] = []
        for step in 0..<10 {
            frames.append(TouchFrame(timestamp: start + Double(step) * frameInterval, contacts: [TouchFrame.Contact(id: 1, x: x, y: y)]))
        }
        frames.append(TouchFrame(timestamp: start + 10 * frameInterval, contacts: []))
        return frames
    }

    /// Two fingers land at an edge and move into the pad.
    public static func edgeSwipe(_ edge: Gesture.Edge, at start: Double = 0, distance: Float = 0.3, duration: Double = 0.2) -> [TouchFrame] {
        let steps = max(2, Int(duration / frameInterval))
        var frames: [TouchFrame] = []
        for step in 0...steps {
            let travel = distance * Float(step) / Float(steps)
            let contacts: [TouchFrame.Contact]
            switch edge {
            case .left: contacts = [TouchFrame.Contact(id: 1, x: 0.03 + travel, y: 0.45), TouchFrame.Contact(id: 2, x: 0.04 + travel, y: 0.6)]
            case .right: contacts = [TouchFrame.Contact(id: 1, x: 0.97 - travel, y: 0.45), TouchFrame.Contact(id: 2, x: 0.96 - travel, y: 0.6)]
            case .top: contacts = [TouchFrame.Contact(id: 1, x: 0.45, y: 0.97 - travel), TouchFrame.Contact(id: 2, x: 0.55, y: 0.96 - travel)]
            case .bottom: contacts = [TouchFrame.Contact(id: 1, x: 0.45, y: 0.03 + travel), TouchFrame.Contact(id: 2, x: 0.55, y: 0.04 + travel)]
            }
            frames.append(TouchFrame(timestamp: start + Double(step) * frameInterval, contacts: contacts))
        }
        frames.append(TouchFrame(timestamp: start + Double(steps + 1) * frameInterval, contacts: []))
        return frames
    }

    /// One finger rests; a second taps on its left or right; the first lifts after.
    public static func tipTap(side: Gesture.Direction, at start: Double = 0, rest: Double = 0.3) -> [TouchFrame] {
        let resting = TouchFrame.Contact(id: 1, x: 0.5, y: 0.45)
        let tapper = TouchFrame.Contact(id: 2, x: side == .left ? 0.38 : 0.62, y: 0.5)
        var frames: [TouchFrame] = []
        var time = start
        while time - start < rest {
            frames.append(TouchFrame(timestamp: time, contacts: [resting]))
            time += frameInterval
        }
        for _ in 0..<8 {
            frames.append(TouchFrame(timestamp: time, contacts: [resting, tapper]))
            time += frameInterval
        }
        for _ in 0..<10 {
            frames.append(TouchFrame(timestamp: time, contacts: [resting]))
            time += frameInterval
        }
        frames.append(TouchFrame(timestamp: time, contacts: []))
        return frames
    }

    /// Two-finger scrolling, for the CPU benchmark (never a gesture).
    public static func scroll(seconds: Double, at start: Double = 0) -> [TouchFrame] {
        var frames: [TouchFrame] = []
        var time = start
        var y: Float = 0.2
        while time - start < seconds {
            frames.append(TouchFrame(timestamp: time, contacts: [
                TouchFrame.Contact(id: 1, x: 0.4, y: y), TouchFrame.Contact(id: 2, x: 0.5, y: y + 0.02),
            ]))
            y += 0.004
            if y > 0.8 { y = 0.2 }
            time += frameInterval
        }
        frames.append(TouchFrame(timestamp: time, contacts: []))
        return frames
    }
}

/// A scripted sequence of inputs, fed into the real recognizer and router in the running app
/// (`TRIGGERS_REPLAY`). In-process only: nothing reaches the system event stream.
public struct ReplayTimeline: Codable, Sendable, Equatable {
    public var steps: [Step]

    public struct Step: Codable, Sendable, Equatable {
        /// Seconds after the previous step.
        public var after: Double?
        /// Synthetic touches: a tap or swipe, recognized by the real recognizer.
        public var tap: Int?
        public var swipe: SwipeStep?
        /// Raw frames, for recorded sequences.
        public var frames: [TouchFrame]?
        /// A mouse button press (CoreGraphics numbering, 2 = middle), run through the tap's decision.
        public var mouseButton: Int?
        /// A key combination, as if its hotkey fired.
        public var keyCode: Int?
        /// Modifiers for the mouse button or key (raw `Modifiers`).
        public var modifiers: Int?
        /// Two-finger scrolling for this many seconds (CPU measurement; never a gesture).
        public var scrollSeconds: Double?
        /// Any gesture, as synthetic touches (`{"kind": "pinchOut", "fingers": 2}`).
        public var gesture: Gesture?
        /// Key presses for key sequences, fed into the real sequence matcher.
        public var keys: [ReplayKey]?

        public init(after: Double? = nil, tap: Int? = nil, swipe: SwipeStep? = nil, frames: [TouchFrame]? = nil,
                    mouseButton: Int? = nil, keyCode: Int? = nil, modifiers: Int? = nil, scrollSeconds: Double? = nil,
                    gesture: Gesture? = nil, keys: [ReplayKey]? = nil) {
            self.after = after
            self.tap = tap
            self.swipe = swipe
            self.frames = frames
            self.mouseButton = mouseButton
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.scrollSeconds = scrollSeconds
            self.gesture = gesture
            self.keys = keys
        }
    }

    /// One press for a key sequence: a key (`keyCode` with `modifiers`) or a lone modifier tap
    /// (`modifierTap`, raw `Modifiers`), `after` seconds after the previous press.
    public struct ReplayKey: Codable, Sendable, Equatable {
        public var keyCode: Int?
        public var modifiers: Int?
        public var modifierTap: Int?
        public var after: Double?

        public init(keyCode: Int? = nil, modifiers: Int? = nil, modifierTap: Int? = nil, after: Double? = nil) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.modifierTap = modifierTap
            self.after = after
        }
    }

    public struct SwipeStep: Codable, Sendable, Equatable {
        public var fingers: Int
        public var direction: Gesture.Direction

        public init(fingers: Int, direction: Gesture.Direction) {
            self.fingers = fingers
            self.direction = direction
        }
    }

    public init(steps: [Step]) { self.steps = steps }

    public static func decode(_ data: Data) throws -> ReplayTimeline {
        try JSONDecoder().decode(ReplayTimeline.self, from: data)
    }

    /// The touch frames a step produces, starting at `time`.
    public static func frames(for step: Step, at time: Double) -> [TouchFrame] {
        if let gesture = step.gesture { return SyntheticTouches.frames(for: gesture, at: time) }
        if let fingers = step.tap { return SyntheticTouches.tap(fingers: fingers, at: time) }
        if let swipe = step.swipe { return SyntheticTouches.swipe(fingers: swipe.fingers, direction: swipe.direction, at: time) }
        if let seconds = step.scrollSeconds { return SyntheticTouches.scroll(seconds: seconds, at: time) }
        if let frames = step.frames {
            guard let first = frames.first?.timestamp else { return [] }
            return frames.map { TouchFrame(timestamp: $0.timestamp - first + time, contacts: $0.contacts) }
        }
        return []
    }
}

/// Plans the key events for "Press Keys". Modifiers are pressed and released as their own
/// events around the key, so the system's modifier state ends where it started: posting only
/// a key with modifier flags leaves the window server thinking those modifiers are still held
/// (seen on macOS 27.2: every later keystroke picked them up). The key itself carries exactly
/// the combo's modifiers, whatever the person is holding from the trigger (posting ⌘[ while ⌥
/// is held arrives as ⌘[, not ⌥⌘[); afterwards the held ones are put back.
public enum KeyPostPlan {
    public enum Kind: Equatable, Sendable { case flagsChanged, keyDown, keyUp }

    public struct Event: Equatable, Sendable {
        public var kind: Kind
        public var keyCode: Int
        public var flags: UInt64

        public var isDown: Bool { kind == .keyDown }
    }

    /// Left-hand modifier key codes, in the order macOS presses them.
    static let modifierKeys: [(Modifiers, Int)] = [(.control, 59), (.option, 58), (.shift, 56), (.command, 55)]

    public static func events(for combo: KeyCombo, held: Modifiers = []) -> [Event] {
        var events: [Event] = []
        // Let go of what the person holds, so the app sees exactly the combo.
        var current = held.intersection(.all)
        for (modifier, code) in modifierKeys.reversed() where current.contains(modifier) {
            current.remove(modifier)
            events.append(Event(kind: .flagsChanged, keyCode: code, flags: current.cgFlags))
        }
        for (modifier, code) in modifierKeys where combo.modifiers.contains(modifier) {
            current.insert(modifier)
            events.append(Event(kind: .flagsChanged, keyCode: code, flags: current.cgFlags))
        }
        events.append(Event(kind: .keyDown, keyCode: combo.keyCode, flags: combo.modifiers.cgFlags))
        events.append(Event(kind: .keyUp, keyCode: combo.keyCode, flags: combo.modifiers.cgFlags))
        for (modifier, code) in modifierKeys.reversed() where combo.modifiers.contains(modifier) {
            current.remove(modifier)
            events.append(Event(kind: .flagsChanged, keyCode: code, flags: current.cgFlags))
        }
        // Put back what the person is still holding.
        for (modifier, code) in modifierKeys where held.contains(modifier) {
            current.insert(modifier)
            events.append(Event(kind: .flagsChanged, keyCode: code, flags: current.cgFlags))
        }
        return events
    }

    /// The modifier state after the plan runs (should equal `held`).
    public static func finalModifiers(_ events: [Event]) -> Modifiers {
        events.last.map { Modifiers(cgFlags: $0.flags) } ?? []
    }
}
