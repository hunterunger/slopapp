import Testing
@testable import TriggersCore

/// The gestures added after 0.1: double taps, five-finger swipes, pinch and spread, rotate,
/// corner taps, edge swipes and tip-taps, and how they stay out of each other's way.
@Suite struct MoreGestureTests {
    /// Runs frames through a recognizer, then lets any held-back tap go a second later.
    private func gestures(_ frames: [TouchFrame], interests: GestureInterests = .immediate) -> [Gesture] {
        var recognizer = GestureRecognizer(interests: interests)
        var result = frames.flatMap { recognizer.process(device: 1, timestamp: $0.timestamp, contacts: $0.touches).gestures }
        result += recognizer.flush(now: (frames.last?.timestamp ?? 0) + 1)
        return result
    }

    private func only(_ gesture: Gesture) -> GestureInterests { GestureInterests([gesture]) }

    @Test(arguments: [2, 3, 4, 5])
    func doubleTap(fingers: Int) {
        let frames = SyntheticTouches.frames(for: .doubleTap(fingers))
        #expect(gestures(frames, interests: GestureInterests([.doubleTap(fingers), .tap(fingers)])) == [.doubleTap(fingers)])
    }

    @Test func singleTapWaitsOnlyWhenADoubleTapIsBound() {
        let frames = SyntheticTouches.tap(fingers: 3)
        var waiting = GestureRecognizer(interests: GestureInterests([.doubleTap(3), .tap(3)]))
        let outputs = frames.map { waiting.process(device: 1, timestamp: $0.timestamp, contacts: $0.touches) }
        #expect(outputs.allSatisfy { $0.gesture == nil }, "held back in case a second tap comes")
        let deadline = outputs.last?.pendingUntil
        #expect(deadline != nil)
        #expect(waiting.flush(now: (deadline ?? 0) - 0.01).isEmpty, "not before the window ends")
        #expect(waiting.flush(now: deadline ?? 0) == [.tap(3)])
        // With no double tap bound, the same tap fires on lift.
        var instant = GestureRecognizer(interests: GestureInterests([.tap(3)]))
        #expect(frames.map { instant.process(device: 1, timestamp: $0.timestamp, contacts: $0.touches) }.last?.gesture == .tap(3))
    }

    @Test func twoTapsTooFarApartAreTwoSingleTaps() {
        let first = SyntheticTouches.tap(fingers: 3)
        let second = SyntheticTouches.tap(fingers: 3, at: (first.last?.timestamp ?? 0) + 0.6)
        #expect(gestures(first + second, interests: GestureInterests([.doubleTap(3), .tap(3)])) == [.tap(3), .tap(3)])
    }

    @Test func aDifferentSecondTapLetsTheFirstGo() {
        let first = SyntheticTouches.tap(fingers: 3)
        let second = SyntheticTouches.tap(fingers: 4, at: (first.last?.timestamp ?? 0) + 0.08)
        let interests = GestureInterests([.doubleTap(3), .tap(3), .tap(4)])
        #expect(gestures(first + second, interests: interests) == [.tap(3), .tap(4)])
    }

    @Test func aSwipeAfterATapLetsTheTapGoFirst() {
        let first = SyntheticTouches.tap(fingers: 3)
        let swipe = SyntheticTouches.swipe(fingers: 3, direction: .up, at: (first.last?.timestamp ?? 0) + 0.08)
        let interests = GestureInterests([.doubleTap(3), .tap(3), .swipe(3, .up)])
        #expect(gestures(first + swipe, interests: interests) == [.tap(3), .swipe(3, .up)])
    }

    @Test(arguments: Gesture.Direction.allCases)
    func fiveFingerSwipes(direction: Gesture.Direction) {
        #expect(gestures(SyntheticTouches.swipe(fingers: 5, direction: direction)) == [.swipe(5, direction)])
    }

    @Test(arguments: [2, 3, 4, 5])
    func pinchAndSpread(fingers: Int) {
        #expect(gestures(SyntheticTouches.pinch(fingers: fingers, spreading: false)) == [.pinchIn(fingers)])
        #expect(gestures(SyntheticTouches.pinch(fingers: fingers, spreading: true)) == [.pinchOut(fingers)])
    }

    @Test func rotate() {
        #expect(gestures(SyntheticTouches.rotate(clockwise: true)) == [.rotate(true)])
        #expect(gestures(SyntheticTouches.rotate(clockwise: false)) == [.rotate(false)])
    }

    @Test func twoFingerScrollingIsNeitherPinchNorRotate() {
        #expect(gestures(SyntheticTouches.scroll(seconds: 2)).isEmpty)
    }

    @Test func aSwipeIsNotAPinch() {
        for fingers in 3...5 {
            #expect(gestures(SyntheticTouches.swipe(fingers: fingers, direction: .left), interests: .all) == [.swipe(fingers, .left)])
        }
    }

    @Test(arguments: Gesture.Corner.allCases)
    func cornerTaps(corner: Gesture.Corner) {
        #expect(gestures(SyntheticTouches.cornerTap(corner)) == [.cornerTap(corner)])
    }

    @Test func aOneFingerTapInTheMiddleIsJustAClick() {
        let frames = (0..<10).map { TouchFrame(timestamp: Double($0) / 120, contacts: [TouchFrame.Contact(id: 1, x: 0.5, y: 0.5)]) }
            + [TouchFrame(timestamp: 0.1, contacts: [])]
        #expect(gestures(frames, interests: .all).isEmpty)
    }

    @Test(arguments: Gesture.Edge.allCases)
    func edgeSwipes(edge: Gesture.Edge) {
        #expect(gestures(SyntheticTouches.edgeSwipe(edge)) == [.edgeSwipe(edge)])
    }

    @Test func aTwoFingerSwipeAwayFromTheEdgeIsScrolling() {
        // Same movement as a left-edge swipe, but starting mid-pad.
        let frames = SyntheticTouches.edgeSwipe(.left).map { frame in
            TouchFrame(timestamp: frame.timestamp, contacts: frame.contacts.map { TouchFrame.Contact(id: $0.id, x: $0.x + 0.3, y: $0.y) })
        }
        #expect(gestures(frames, interests: .all).isEmpty)
    }

    @Test func tipTaps() {
        #expect(gestures(SyntheticTouches.tipTap(side: .left)) == [.tipTap(.left)])
        #expect(gestures(SyntheticTouches.tipTap(side: .right)) == [.tipTap(.right)])
    }

    @Test func tipTapIsNotATwoFingerTap() {
        #expect(gestures(SyntheticTouches.tipTap(side: .right), interests: GestureInterests([.tap(2)])).isEmpty)
    }

    @Test func tipTapsRepeatWhileTheFingerRests() {
        let resting = TouchFrame.Contact(id: 1, x: 0.5, y: 0.45)
        var frames: [TouchFrame] = []
        var time = 0.0
        func add(_ contacts: [TouchFrame.Contact], _ count: Int) {
            for _ in 0..<count { frames.append(TouchFrame(timestamp: time, contacts: contacts)); time += 1.0 / 120 }
        }
        add([resting], 30)
        add([resting, TouchFrame.Contact(id: 2, x: 0.62, y: 0.5)], 8)
        add([resting], 12)
        add([resting, TouchFrame.Contact(id: 3, x: 0.62, y: 0.5)], 8)
        add([resting], 12)
        frames.append(TouchFrame(timestamp: time, contacts: []))
        #expect(gestures(frames) == [.tipTap(.right), .tipTap(.right)])
    }

    @Test func everySupportedGestureIsRecognizedFromItsSyntheticTouches() {
        // While recording, everything is looked for at once: each gesture still comes out as itself.
        for gesture in Gesture.supported {
            #expect(gestures(SyntheticTouches.frames(for: gesture), interests: .all) == [gesture], "\(gesture.title)")
        }
    }

    @Test func supportedGesturesAreValidAndTitled() {
        #expect(Gesture.supported.count == 4 + 4 + 12 + 8 + 2 + 4 + 4 + 2)
        #expect(Gesture.supported.allSatisfy { $0.isSupported })
        #expect(Set(Gesture.supported.map(\.title)).count == Gesture.supported.count, "titles are unique")
        #expect(!Gesture.swipe(2, .left).isSupported, "two-finger swipes are scrolling")
        #expect(!Gesture.tap(1).isSupported, "one-finger taps are clicks")
    }
}
