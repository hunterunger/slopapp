import Foundation

/// One finger in a touch frame, in our own terms (the private framework's struct never leaves
/// TouchSource.swift).
public struct TouchContact: Sendable, Equatable {
    /// Stable while the finger stays down.
    public var id: Int32
    /// 0…1 across the pad, origin bottom left.
    public var x: Float
    public var y: Float
    /// Contact size (capacitance total), in the device's own units. Only compared to other
    /// contacts in the same frame, never to a fixed number.
    public var size: Float
    /// The framework's touch state: 1–2 hovering, 3 landing, 4 touching, 5–7 lifting.
    public var state: Int32

    public init(id: Int32, x: Float, y: Float, size: Float = 1, state: Int32 = 4) {
        self.id = id
        self.x = x
        self.y = y
        self.size = size
        self.state = state
    }

    var isTouching: Bool { state == 3 || state == 4 }
}

/// How strict recognition is. Settings map Relaxed / Standard / Strict and Short / Standard /
/// Long onto these.
public struct GestureTuning: Sendable, Equatable {
    /// All fingers must land within this time of the first one, for taps and swipes. Keeps a
    /// two-finger scroll that gains a third finger from becoming a three-finger gesture.
    public var landingWindow: Double = 0.12
    /// A tap lifts within this time of the first finger landing.
    public var tapMaxDuration: Double = 0.30
    /// A tap moves less than this (centroid, millimetres).
    public var tapMaxMovement: Float = 5
    /// A swipe fires once the fingers have travelled this far together (millimetres).
    public var swipeDistance: Float = 18
    /// The swipe's main axis must beat the other by this much, so diagonals don't fire.
    public var swipeAxisRatio: Float = 1.4
    /// A contact this many times bigger than the smallest one in the frame is a palm.
    public var palmRatio: Float = 3.5
    /// A double tap's second tap lands within this time of the first one lifting. Single taps
    /// of a finger count only wait this long when a double tap of that count is bound.
    public var doubleTapWindow: Double = 0.25
    /// Pinch and spread: the fingers' spread changes by this much (millimetres)…
    public var pinchDistance: Float = 8
    /// …and by this factor.
    public var pinchRatio: Float = 1.35
    /// Rotate: the fingers turn this far together (radians, about 30°).
    public var rotateAngle: Float = 0.52
    /// Corner taps land and lift within this fraction of the pad from both edges.
    public var cornerSize: Float = 0.2
    /// Edge swipes start within this fraction of the pad from the edge.
    public var edgeBand: Float = 0.1
    /// Tip-taps: the resting finger has been down this long before the other one taps.
    public var restTime: Double = 0.15

    public init() {}

    public enum TapSensitivity: String, CaseIterable, Sendable, Codable { case relaxed, standard, strict }
    public enum SwipeDistance: String, CaseIterable, Sendable, Codable { case short, standard, long }

    public init(tap: TapSensitivity, swipe: SwipeDistance) {
        self.init()
        switch tap {
        case .relaxed: landingWindow = 0.16; tapMaxDuration = 0.40; tapMaxMovement = 8; doubleTapWindow = 0.35
        case .standard: break
        case .strict: landingWindow = 0.08; tapMaxDuration = 0.22; tapMaxMovement = 3; doubleTapWindow = 0.2
        }
        switch swipe {
        case .short: swipeDistance = 12; pinchDistance = 6
        case .standard: break
        case .long: swipeDistance = 28; pinchDistance = 12
        }
    }
}

/// Which gestures the recognizer looks for: the ones bound somewhere (everything while
/// recording). Looking only for bound gestures keeps an unbound one (a pinch) from using up a
/// touch that was meant for a bound one (a swipe), and keeps single taps instant unless a
/// double tap with the same fingers is bound. Bit masks by finger count: no allocation.
public struct GestureInterests: Sendable, Equatable {
    var taps: UInt8 = 0
    var doubleTaps: UInt8 = 0
    var swipes: UInt8 = 0
    var pinches: UInt8 = 0
    var rotates: UInt8 = 0
    var corners = false
    var edges = false
    var tipTaps = false

    public init() {}

    public init<S: Sequence>(_ gestures: S) where S.Element == Gesture {
        for gesture in gestures { add(gesture) }
    }

    /// Everything, double taps included (recording).
    public static let all: GestureInterests = {
        var interests = GestureInterests()
        for gesture in Gesture.supported { interests.add(gesture) }
        return interests
    }()

    /// Everything that fires without waiting: all but double taps (the recognizer's default).
    public static let immediate: GestureInterests = {
        var interests = GestureInterests.all
        interests.doubleTaps = 0
        return interests
    }()

    public mutating func add(_ gesture: Gesture) {
        let bit: UInt8 = gesture.fingers >= 0 && gesture.fingers < 8 ? 1 << UInt8(gesture.fingers) : 0
        switch gesture.kind {
        case .tap: taps |= bit
        case .doubleTap: doubleTaps |= bit; taps |= bit
        case .swipe: swipes |= bit
        case .pinchIn, .pinchOut: pinches |= bit
        case .rotateLeft, .rotateRight: rotates |= bit
        case .cornerTap: corners = true
        case .edgeSwipe: edges = true
        case .tipTap: tipTaps = true
        }
    }

    static func has(_ mask: UInt8, _ fingers: Int) -> Bool { fingers > 0 && fingers < 8 && mask & (1 << UInt8(fingers)) != 0 }

    public var isEmpty: Bool { self == GestureInterests() }
}

/// What a frame produced.
public struct RecognizerOutput: Sendable, Equatable {
    /// A gesture that completed on this frame.
    public var gesture: Gesture?
    /// A single tap that was held back (in case it became a double tap) and is now let go;
    /// it happened before `gesture`.
    public var earlier: Gesture?
    /// Fingers touching right now (for the recognize-only pad).
    public var fingers: Int
    /// A single tap is being held back until this time (call `flush` then).
    public var pendingUntil: Double?

    public init(gesture: Gesture? = nil, earlier: Gesture? = nil, fingers: Int, pendingUntil: Double? = nil) {
        self.gesture = gesture
        self.earlier = earlier
        self.fingers = fingers
        self.pendingUntil = pendingUntil
    }

    /// Both, oldest first.
    public var gestures: [Gesture] { [earlier, gesture].compactMap { $0 } }
}

/// Frames → gestures. A pure state machine, one state per device (mixing a built-in and a
/// Magic Trackpad would see six fingers where there are three). No allocation per frame
/// once a device has been seen. Not thread-safe: the touch source serializes calls.
///
/// Taps fire on lift (or after the double-tap window when a double tap of the same finger
/// count is bound). Swipes, pinches, rotations and edge swipes fire once per touch session, as
/// soon as the fingers have moved far enough. Tip-taps can repeat while the resting finger
/// stays down.
public struct GestureRecognizer: Sendable {
    public var tuning: GestureTuning
    public var interests: GestureInterests
    private var devices: [DeviceState] = []

    public init(tuning: GestureTuning = GestureTuning(), interests: GestureInterests = .immediate) {
        self.tuning = tuning
        self.interests = interests
        devices.reserveCapacity(4)
    }

    /// Physical size of a device's surface, so thresholds are in millimetres on every trackpad.
    public mutating func setSurface(device: Int, width: Float, height: Float) {
        let index = slot(for: device)
        devices[index].width = max(width, 10)
        devices[index].height = max(height, 10)
    }

    /// Forgets every touch in progress (sleep, device change, pause).
    public mutating func reset() {
        for index in devices.indices {
            devices[index].endSession()
            devices[index].pending = nil
        }
    }

    public mutating func process(device: Int, timestamp: Double, contacts: [TouchContact]) -> RecognizerOutput {
        contacts.withUnsafeBufferPointer { process(device: device, timestamp: timestamp, contacts: $0) }
    }

    public mutating func process(device: Int, timestamp: Double, contacts: UnsafeBufferPointer<TouchContact>) -> RecognizerOutput {
        let index = slot(for: device)
        return devices[index].process(timestamp: timestamp, contacts: contacts, tuning: tuning, interests: interests)
    }

    /// Lets go of a held-back single tap whose double-tap window has passed. The touch source
    /// calls this at `pendingUntil`, because no frames arrive once the fingers are off the pad.
    public mutating func flush(now: Double) -> [Gesture] {
        var result: [Gesture] = []
        for index in devices.indices {
            if let gesture = devices[index].flush(now: now, tuning: tuning) { result.append(gesture) }
        }
        return result
    }

    private mutating func slot(for device: Int) -> Int {
        if let index = devices.firstIndex(where: { $0.device == device }) { return index }
        devices.append(DeviceState(device: device))
        return devices.count - 1
    }
}

/// A finger at the moment the current finger count settled (for pinch and rotate).
private struct BaseContact: Sendable {
    var id: Int32
    var x: Float
    var y: Float
    var angle: Float
}

private struct DeviceState: Sendable {
    let device: Int
    var width: Float = 156   // a 16-inch MacBook Pro's pad until the source says otherwise
    var height: Float = 96

    var active = false
    var sessionStart = 0.0
    var lastTimestamp = 0.0
    var peak = 0
    var peakReachedAt = 0.0
    var lastCount = 0
    var baseX: Float = 0
    var baseY: Float = 0
    var maxMovement: Float = 0
    var fired = false
    /// Where the touch started, as fractions of the pad (corner taps, edge swipes).
    var startFractionX: Float = 0
    var startFractionY: Float = 0
    var lastFractionX: Float = 0
    var lastFractionY: Float = 0
    /// Fingers when the count last settled, and their spread from the centroid.
    var base: [BaseContact] = []
    var baseSpread: Float = 0

    /// Tip-tap: a finger resting, and another one tapping next to it.
    var restID: Int32 = -1
    var restSince = 0.0
    var restX: Float = 0
    var restY: Float = 0
    var tapperID: Int32 = -1
    var tapperLanded = 0.0
    var tapperX: Float = 0
    var tapperY: Float = 0
    var tapperMoved: Float = 0
    var sessionHadTipTap = false

    /// A single tap held back in case a second one makes it a double tap.
    var pending: (fingers: Int, liftedAt: Double, deadline: Double)?
    var secondTapStarted = false

    init(device: Int) {
        self.device = device
        base.reserveCapacity(16)
    }

    mutating func endSession() {
        active = false
        peak = 0
        lastCount = 0
        fired = false
        maxMovement = 0
        base.removeAll(keepingCapacity: true)
        restID = -1
        tapperID = -1
        sessionHadTipTap = false
    }

    mutating func flush(now: Double, tuning: GestureTuning) -> Gesture? {
        guard let held = pending, !secondTapStarted, now >= held.deadline else { return nil }
        pending = nil
        return .tap(held.fingers)
    }

    /// Lets the held-back tap go now (as `earlier`).
    mutating func release(into output: inout RecognizerOutput) {
        if let held = pending {
            output.earlier = .tap(held.fingers)
            pending = nil
            secondTapStarted = false
        }
    }

    mutating func process(timestamp: Double, contacts: UnsafeBufferPointer<TouchContact>, tuning: GestureTuning,
                          interests: GestureInterests) -> RecognizerOutput {
        // Palm rejection: compare sizes within this frame only (units differ per device).
        var smallest = Float.greatestFiniteMagnitude
        for contact in contacts where contact.isTouching && contact.size > 0 {
            smallest = min(smallest, contact.size)
        }
        let palmLimit = smallest == .greatestFiniteMagnitude ? Float.greatestFiniteMagnitude : smallest * tuning.palmRatio
        var count = 0
        var sumX: Float = 0
        var sumY: Float = 0
        for contact in contacts where contact.isTouching && contact.size <= palmLimit {
            count += 1
            sumX += contact.x
            sumY += contact.y
        }
        let fractionX = count > 0 ? sumX / Float(count) : 0
        let fractionY = count > 0 ? sumY / Float(count) : 0
        let x = fractionX * width
        let y = fractionY * height

        var output = RecognizerOutput(fingers: count)

        // Frames stopped arriving mid-touch (device unplugged, sleep): start over.
        if active, timestamp - lastTimestamp > 0.5 || timestamp < lastTimestamp { endSession() }
        lastTimestamp = timestamp

        if !active {
            guard count > 0 else {
                if let gesture = flush(now: timestamp, tuning: tuning) { output.gesture = gesture }
                return finish(output)
            }
            active = true
            sessionStart = timestamp
            peak = count
            peakReachedAt = timestamp
            lastCount = count
            baseX = x
            baseY = y
            maxMovement = 0
            fired = false
            startFractionX = fractionX
            startFractionY = fractionY
            setBase(contacts, palmLimit: palmLimit, centroidX: x, centroidY: y)
            if let held = pending {
                if timestamp > held.deadline { release(into: &output) } else { secondTapStarted = true }
            }
            if count == 1, interests.tipTaps { startRest(contacts, palmLimit: palmLimit, at: timestamp) }
        } else if count == 0 {
            endTouch(at: timestamp, tuning: tuning, interests: interests, output: &output)
            endSession()
        } else {
            if count > peak {
                peak = count
                peakReachedAt = timestamp
                maxMovement = 0
            }
            if count != lastCount {
                // The centroid jumps when a finger lands or lifts: measure from here.
                if interests.tipTaps { trackTipTap(from: lastCount, to: count, contacts, palmLimit: palmLimit, at: timestamp,
                                                   tuning: tuning, output: &output) }
                baseX = x
                baseY = y
                lastCount = count
                setBase(contacts, palmLimit: palmLimit, centroidX: x, centroidY: y)
            } else if interests.tipTaps {
                moveTipTap(contacts, palmLimit: palmLimit, at: timestamp, tuning: tuning)
            }
            lastFractionX = fractionX
            lastFractionY = fractionY
            if pending != nil, timestamp - sessionStart > tuning.tapMaxDuration || count > (pending?.fingers ?? 0) {
                release(into: &output)
            }
            if count == peak {
                let dx = x - baseX
                let dy = y - baseY
                maxMovement = max(maxMovement, (dx * dx + dy * dy).squareRoot())
                if !fired, peakReachedAt - sessionStart <= tuning.landingWindow,
                   let gesture = moving(dx: dx, dy: dy, contacts, palmLimit: palmLimit, centroidX: x, centroidY: y,
                                        tuning: tuning, interests: interests) {
                    fired = true
                    release(into: &output)
                    output.gesture = gesture
                }
            }
        }
        if count > 0 {
            lastFractionX = fractionX
            lastFractionY = fractionY
        }
        return finish(output)
    }

    private func finish(_ output: RecognizerOutput) -> RecognizerOutput {
        var output = output
        if let held = pending, !secondTapStarted { output.pendingUntil = held.deadline }
        return output
    }

    // MARK: Taps

    private mutating func endTouch(at timestamp: Double, tuning: GestureTuning, interests: GestureInterests, output: inout RecognizerOutput) {
        let isTap = !fired && !sessionHadTipTap
            && peakReachedAt - sessionStart <= tuning.landingWindow
            && timestamp - sessionStart <= tuning.tapMaxDuration
            && maxMovement <= tuning.tapMaxMovement
        if secondTapStarted, let held = pending {
            pending = nil
            secondTapStarted = false
            if isTap, peak == held.fingers {
                output.gesture = .doubleTap(peak)
                return
            }
            output.earlier = .tap(held.fingers)
        }
        guard isTap else { return }
        if peak == 1 {
            if interests.corners, let corner = corner(startFractionX, startFractionY, tuning),
               self.corner(lastFractionX, lastFractionY, tuning) == corner {
                output.gesture = .cornerTap(corner)
            }
            return
        }
        guard GestureInterests.has(interests.taps, peak) else { return }
        if GestureInterests.has(interests.doubleTaps, peak) {
            pending = (peak, timestamp, timestamp + tuning.doubleTapWindow)
            secondTapStarted = false
        } else {
            output.gesture = .tap(peak)
        }
    }

    private func corner(_ x: Float, _ y: Float, _ tuning: GestureTuning) -> Gesture.Corner? {
        let size = tuning.cornerSize
        let left = x <= size
        let right = x >= 1 - size
        let top = y >= 1 - size     // the frame's y grows upwards
        let bottom = y <= size
        switch (left, right, top, bottom) {
        case (true, false, true, false): return .topLeft
        case (false, true, true, false): return .topRight
        case (true, false, false, true): return .bottomLeft
        case (false, true, false, true): return .bottomRight
        default: return nil
        }
    }

    // MARK: Moving gestures

    private mutating func setBase(_ contacts: UnsafeBufferPointer<TouchContact>, palmLimit: Float, centroidX: Float, centroidY: Float) {
        base.removeAll(keepingCapacity: true)
        var spread: Float = 0
        for contact in contacts where contact.isTouching && contact.size <= palmLimit && base.count < 16 {
            let px = contact.x * width - centroidX
            let py = contact.y * height - centroidY
            spread += (px * px + py * py).squareRoot()
            base.append(BaseContact(id: contact.id, x: px, y: py, angle: atan2(py, px)))
        }
        baseSpread = base.isEmpty ? 0 : spread / Float(base.count)
    }

    /// Swipe, edge swipe, pinch or rotate, whichever the movement so far amounts to.
    private func moving(dx: Float, dy: Float, _ contacts: UnsafeBufferPointer<TouchContact>, palmLimit: Float,
                        centroidX: Float, centroidY: Float, tuning: GestureTuning, interests: GestureInterests) -> Gesture? {
        let ax = abs(dx)
        let ay = abs(dy)
        let travelled = max(ax, ay)
        let direction: Gesture.Direction? = ax >= ay * tuning.swipeAxisRatio ? (dx < 0 ? .left : .right)
            : ay >= ax * tuning.swipeAxisRatio ? (dy > 0 ? .up : .down) : nil

        if peak == 2, interests.edges, travelled >= tuning.swipeDistance, let direction,
           let edge = edge(startFractionX, startFractionY, tuning), Self.inward(from: edge) == direction {
            return .edgeSwipe(edge)
        }
        if GestureInterests.has(interests.swipes, peak), travelled >= tuning.swipeDistance, let direction {
            return .swipe(peak, direction)
        }
        let wantsPinch = GestureInterests.has(interests.pinches, peak)
        let wantsRotate = GestureInterests.has(interests.rotates, peak)
        guard wantsPinch || wantsRotate, base.count == peak, baseSpread > 0, travelled < tuning.swipeDistance else { return nil }
        // Spread and turn of the same fingers since the count settled.
        var spread: Float = 0
        var turn: Float = 0
        var matched = 0
        for contact in contacts where contact.isTouching && contact.size <= palmLimit {
            guard let original = base.first(where: { $0.id == contact.id }) else { continue }
            let px = contact.x * width - centroidX
            let py = contact.y * height - centroidY
            spread += (px * px + py * py).squareRoot()
            var delta = atan2(py, px) - original.angle
            if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
            turn += delta
            matched += 1
        }
        guard matched == peak else { return nil }
        spread /= Float(matched)
        turn /= Float(matched)
        let change = spread - baseSpread
        let ratio = spread > baseSpread ? spread / max(baseSpread, 0.001) : baseSpread / max(spread, 0.001)
        let isPinch = abs(change) >= tuning.pinchDistance && ratio >= tuning.pinchRatio
        if wantsPinch, isPinch {
            return change < 0 ? .pinchIn(peak) : .pinchOut(peak)
        }
        if wantsRotate, !isPinch, ratio < tuning.pinchRatio, baseSpread >= 4, abs(turn) >= tuning.rotateAngle {
            // Positive turns are counterclockwise (y grows upwards).
            return .rotate(turn < 0)
        }
        return nil
    }

    private func edge(_ x: Float, _ y: Float, _ tuning: GestureTuning) -> Gesture.Edge? {
        let band = tuning.edgeBand
        if x <= band { return .left }
        if x >= 1 - band { return .right }
        if y >= 1 - band { return .top }
        if y <= band { return .bottom }
        return nil
    }

    private static func inward(from edge: Gesture.Edge) -> Gesture.Direction {
        switch edge {
        case .left: .right
        case .right: .left
        case .top: .down
        case .bottom: .up
        }
    }

    // MARK: Tip-taps

    private mutating func startRest(_ contacts: UnsafeBufferPointer<TouchContact>, palmLimit: Float, at timestamp: Double) {
        for contact in contacts where contact.isTouching && contact.size <= palmLimit {
            restID = contact.id
            restSince = timestamp
            restX = contact.x * width
            restY = contact.y * height
            return
        }
    }

    private mutating func moveTipTap(_ contacts: UnsafeBufferPointer<TouchContact>, palmLimit: Float, at timestamp: Double, tuning: GestureTuning) {
        for contact in contacts where contact.isTouching && contact.size <= palmLimit {
            let px = contact.x * width
            let py = contact.y * height
            if contact.id == restID, tapperID < 0 {
                // Still resting: a finger that's moving the pointer starts its rest again.
                let moved = ((px - restX) * (px - restX) + (py - restY) * (py - restY)).squareRoot()
                if moved > tuning.tapMaxMovement {
                    restSince = timestamp
                    restX = px
                    restY = py
                }
            } else if contact.id == tapperID {
                let moved = ((px - tapperX) * (px - tapperX) + (py - tapperY) * (py - tapperY)).squareRoot()
                tapperMoved = max(tapperMoved, moved)
            }
        }
    }

    private mutating func trackTipTap(from previous: Int, to count: Int, _ contacts: UnsafeBufferPointer<TouchContact>, palmLimit: Float,
                                      at timestamp: Double, tuning: GestureTuning, output: inout RecognizerOutput) {
        if previous == 1, count == 2, restID >= 0, timestamp - restSince >= tuning.restTime {
            for contact in contacts where contact.isTouching && contact.size <= palmLimit && contact.id != restID {
                tapperID = contact.id
                tapperLanded = timestamp
                tapperX = contact.x * width
                tapperY = contact.y * height
                tapperMoved = 0
                return
            }
        } else if previous == 2, count == 1, tapperID >= 0 {
            let restStillDown = contacts.contains { $0.id == restID && $0.isTouching }
            if restStillDown, timestamp - tapperLanded <= tuning.tapMaxDuration, tapperMoved <= tuning.tapMaxMovement {
                output.gesture = .tipTap(tapperX < restX ? .left : .right)
                sessionHadTipTap = true
            }
            tapperID = -1
            restSince = timestamp - tuning.restTime   // ready for the next tip-tap right away
        } else if count > 2 || count == 0 {
            tapperID = -1
            if count > 2 { restID = -1 }
        } else if count == 1, previous != 1 {
            // Back to one finger some other way: that finger may rest now.
            restID = -1
            startRest(contacts, palmLimit: palmLimit, at: timestamp)
        }
    }
}

/// Checks frames from the private framework look like touches. If its struct ever changes,
/// garbage arrives instead of a crash; this notices and gestures switch off.
public struct TouchFrameValidator: Sendable {
    public private(set) var badFrames = 0
    public private(set) var goodFrames = 0
    /// Bad frames in a row before giving up.
    public var limit = 8
    private var badInARow = 0

    public init() {}

    public static func isValid(_ contact: TouchContact) -> Bool {
        contact.x.isFinite && contact.y.isFinite && contact.size.isFinite
            && contact.x >= -0.05 && contact.x <= 1.05 && contact.y >= -0.05 && contact.y <= 1.05
            && (0...7).contains(contact.state)
    }

    /// Records a frame; returns false once frames have been garbage `limit` times in a row.
    public mutating func check(count: Int, allValid: Bool) -> Bool {
        if count >= 0 && count <= 20 && allValid {
            goodFrames += 1
            badInARow = 0
        } else {
            badFrames += 1
            badInARow += 1
        }
        return badInARow < limit
    }
}
