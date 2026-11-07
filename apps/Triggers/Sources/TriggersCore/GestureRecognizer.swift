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

    public init() {}

    public enum TapSensitivity: String, CaseIterable, Sendable, Codable { case relaxed, standard, strict }
    public enum SwipeDistance: String, CaseIterable, Sendable, Codable { case short, standard, long }

    public init(tap: TapSensitivity, swipe: SwipeDistance) {
        self.init()
        switch tap {
        case .relaxed: landingWindow = 0.16; tapMaxDuration = 0.40; tapMaxMovement = 8
        case .standard: break
        case .strict: landingWindow = 0.08; tapMaxDuration = 0.22; tapMaxMovement = 3
        }
        switch swipe {
        case .short: swipeDistance = 12
        case .standard: break
        case .long: swipeDistance = 28
        }
    }
}

/// What a frame produced.
public struct RecognizerOutput: Sendable, Equatable {
    /// A gesture that completed on this frame.
    public var gesture: Gesture?
    /// Fingers touching right now (for the recognize-only pad).
    public var fingers: Int
}

/// Frames → gestures. A pure state machine, one state per device (mixing a built-in and a
/// Magic Trackpad would see six fingers where there are three). No allocation per frame
/// once a device has been seen. Not thread-safe: the touch source serializes calls.
///
/// Taps fire on lift (no double-tap variants, so single taps never wait). Swipes fire once
/// per touch session, as soon as the fingers have travelled far enough together.
public struct GestureRecognizer: Sendable {
    public var tuning: GestureTuning
    private var devices: [DeviceState] = []

    public init(tuning: GestureTuning = GestureTuning()) {
        self.tuning = tuning
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
        for index in devices.indices { devices[index].endSession() }
    }

    public mutating func process(device: Int, timestamp: Double, contacts: [TouchContact]) -> RecognizerOutput {
        contacts.withUnsafeBufferPointer { process(device: device, timestamp: timestamp, contacts: $0) }
    }

    public mutating func process(device: Int, timestamp: Double, contacts: UnsafeBufferPointer<TouchContact>) -> RecognizerOutput {
        let index = slot(for: device)
        return devices[index].process(timestamp: timestamp, contacts: contacts, tuning: tuning)
    }

    private mutating func slot(for device: Int) -> Int {
        if let index = devices.firstIndex(where: { $0.device == device }) { return index }
        devices.append(DeviceState(device: device))
        return devices.count - 1
    }
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

    init(device: Int) { self.device = device }

    mutating func endSession() {
        active = false
        peak = 0
        lastCount = 0
        fired = false
        maxMovement = 0
    }

    mutating func process(timestamp: Double, contacts: UnsafeBufferPointer<TouchContact>, tuning: GestureTuning) -> RecognizerOutput {
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
        let x = count > 0 ? sumX / Float(count) * width : 0
        let y = count > 0 ? sumY / Float(count) * height : 0

        // Frames stopped arriving mid-touch (device unplugged, sleep): start over.
        if active, timestamp - lastTimestamp > 0.5 || timestamp < lastTimestamp { endSession() }
        lastTimestamp = timestamp

        var gesture: Gesture?
        if !active {
            if count > 0 {
                active = true
                sessionStart = timestamp
                peak = count
                peakReachedAt = timestamp
                lastCount = count
                baseX = x
                baseY = y
                maxMovement = 0
                fired = false
            }
        } else if count == 0 {
            if !fired, (3...4).contains(peak),
               peakReachedAt - sessionStart <= tuning.landingWindow,
               timestamp - sessionStart <= tuning.tapMaxDuration,
               maxMovement <= tuning.tapMaxMovement {
                gesture = .tap(peak)
            }
            endSession()
        } else {
            if count > peak {
                peak = count
                peakReachedAt = timestamp
                maxMovement = 0
            }
            if count != lastCount {
                // The centroid jumps when a finger lands or lifts: measure from here.
                baseX = x
                baseY = y
                lastCount = count
            }
            if count == peak {
                let dx = x - baseX
                let dy = y - baseY
                maxMovement = max(maxMovement, (dx * dx + dy * dy).squareRoot())
                if !fired, (3...4).contains(peak), peakReachedAt - sessionStart <= tuning.landingWindow {
                    let ax = abs(dx)
                    let ay = abs(dy)
                    if max(ax, ay) >= tuning.swipeDistance {
                        if ax >= ay * tuning.swipeAxisRatio {
                            gesture = .swipe(peak, dx < 0 ? .left : .right)
                            fired = true
                        } else if ay >= ax * tuning.swipeAxisRatio {
                            gesture = .swipe(peak, dy > 0 ? .up : .down)
                            fired = true
                        }
                    }
                }
            }
        }
        return RecognizerOutput(gesture: gesture, fingers: count)
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
