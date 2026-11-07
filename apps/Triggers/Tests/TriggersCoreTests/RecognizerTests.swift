import Testing
@testable import TriggersCore

@Suite struct RecognizerTests {
    private func gestures(_ frames: [TouchFrame], device: Int = 1, tuning: GestureTuning = GestureTuning()) -> [Gesture] {
        var recognizer = GestureRecognizer(tuning: tuning)
        return frames.compactMap { recognizer.process(device: device, timestamp: $0.timestamp, contacts: $0.touches).gesture }
    }

    @Test(arguments: [3, 4])
    func tapFiresOnLift(fingers: Int) {
        let frames = SyntheticTouches.tap(fingers: fingers)
        var recognizer = GestureRecognizer()
        let outputs = frames.map { recognizer.process(device: 1, timestamp: $0.timestamp, contacts: $0.touches) }
        #expect(outputs.dropLast().allSatisfy { $0.gesture == nil }, "nothing before lift")
        #expect(outputs.last?.gesture == .tap(fingers))
    }

    @Test func twoAndFiveFingerTapsAreIgnored() {
        #expect(gestures(SyntheticTouches.tap(fingers: 2)).isEmpty)
        #expect(gestures(SyntheticTouches.tap(fingers: 5)).isEmpty)
    }

    @Test func slowTapIsNotATap() {
        #expect(gestures(SyntheticTouches.tap(fingers: 3, hold: 0.5)).isEmpty)
    }

    @Test func tapThatMovesIsNotATap() {
        // 10% of a 156 mm pad = 15.6 mm of drift.
        #expect(gestures(SyntheticTouches.tap(fingers: 3, drift: 0.1)).isEmpty)
    }

    @Test func fingersLandingSlowlyAreNotATap() {
        // 80 ms between fingers: the third lands 160 ms after the first.
        #expect(gestures(SyntheticTouches.tap(fingers: 3, stagger: 0.08, hold: 0.05)).isEmpty)
    }

    @Test(arguments: [3, 4], Gesture.Direction.allCases)
    func swipes(fingers: Int, direction: Gesture.Direction) {
        #expect(gestures(SyntheticTouches.swipe(fingers: fingers, direction: direction)) == [.swipe(fingers, direction)])
    }

    @Test func swipeFiresBeforeLiftAndOnlyOnce() {
        let frames = SyntheticTouches.swipe(fingers: 3, direction: .left, distance: 0.6, duration: 0.3)
        var recognizer = GestureRecognizer()
        var firedAt: Int?
        var count = 0
        for (index, frame) in frames.enumerated() where recognizer.process(device: 1, timestamp: frame.timestamp, contacts: frame.touches).gesture != nil {
            count += 1
            firedAt = firedAt ?? index
        }
        #expect(count == 1)
        #expect((firedAt ?? .max) < frames.count / 2, "fires as soon as it's far enough")
    }

    @Test func shortSwipeIsNothing() {
        // 5% of the pad width ≈ 8 mm, under the 18 mm threshold, and too far to be a tap.
        #expect(gestures(SyntheticTouches.swipe(fingers: 3, direction: .right, distance: 0.05, duration: 0.1)) .isEmpty)
    }

    @Test func swipeDistanceSetting() {
        let frames = SyntheticTouches.swipe(fingers: 3, direction: .right, distance: 0.12)
        #expect(gestures(frames, tuning: GestureTuning(tap: .standard, swipe: .short)) == [.swipe(3, .right)])
        #expect(gestures(frames, tuning: GestureTuning(tap: .standard, swipe: .long)).isEmpty)
    }

    @Test func diagonalSwipeIsIgnored() {
        var frames: [TouchFrame] = []
        for step in 0...20 {
            let p = Float(step) / 20 * 0.3
            frames.append(TouchFrame(timestamp: Double(step) / 120, contacts: (0..<3).map {
                TouchFrame.Contact(id: Int32($0), x: 0.3 + Float($0) * 0.08 + p, y: 0.3 + p * 1.6)
            }))
        }
        frames.append(TouchFrame(timestamp: 1, contacts: []))
        #expect(gestures(frames).isEmpty)
    }

    @Test func scrollThatGainsAThirdFingerIsNotASwipe() {
        var frames = SyntheticTouches.scroll(seconds: 0.4).dropLast().map { $0 }
        let last = frames.last!.timestamp
        // A third finger joins the scroll and everything keeps moving.
        for step in 1...40 {
            let y = 0.2 + Float(step) * 0.01
            frames.append(TouchFrame(timestamp: last + Double(step) / 120, contacts: [
                .init(id: 1, x: 0.4, y: y), .init(id: 2, x: 0.5, y: y), .init(id: 3, x: 0.6, y: y),
            ]))
        }
        frames.append(TouchFrame(timestamp: last + 1, contacts: []))
        #expect(gestures(frames).isEmpty)
    }

    @Test func tapToClickWithTwoRestingFingersIsNotAThreeFingerTap() {
        var frames: [TouchFrame] = []
        // Two fingers rest for half a second, then a third taps.
        for step in 0..<60 {
            frames.append(TouchFrame(timestamp: Double(step) / 120, contacts: [.init(id: 1, x: 0.2, y: 0.2), .init(id: 2, x: 0.3, y: 0.2)]))
        }
        for step in 60..<70 {
            frames.append(TouchFrame(timestamp: Double(step) / 120, contacts: [
                .init(id: 1, x: 0.2, y: 0.2), .init(id: 2, x: 0.3, y: 0.2), .init(id: 3, x: 0.6, y: 0.6),
            ]))
        }
        frames.append(TouchFrame(timestamp: 0.6, contacts: []))
        #expect(gestures(frames).isEmpty)
    }

    @Test func palmIsNotCountedAsAFinger() {
        // A resting palm (huge contact) plus two fingers tapping is a two-finger tap: nothing.
        let frames = SyntheticTouches.tap(fingers: 2).map { frame in
            var copy = frame
            if !copy.contacts.isEmpty { copy.contacts.append(.init(id: 9, x: 0.9, y: 0.1, size: 12)) }
            return copy
        }
        #expect(gestures(frames).isEmpty)
        // And a palm next to a three-finger tap doesn't make it four.
        let three = SyntheticTouches.tap(fingers: 3).map { frame in
            var copy = frame
            if !copy.contacts.isEmpty { copy.contacts.append(.init(id: 9, x: 0.9, y: 0.1, size: 12)) }
            return copy
        }
        #expect(gestures(three) == [.tap(3)])
    }

    @Test func hoveringAndLiftingContactsDontCount() {
        let frames = SyntheticTouches.tap(fingers: 3).map { frame in
            var copy = frame
            copy.contacts = copy.contacts.map { var c = $0; c.state = c.id == 3 ? 2 : 4; return c }
            return copy
        }
        #expect(gestures(frames).isEmpty, "only two of the three were touching")
    }

    @Test func devicesAreKeptApart() {
        // Three fingers on one pad while three rest on another must not look like six.
        var recognizer = GestureRecognizer()
        let a = SyntheticTouches.tap(fingers: 3)
        let b = SyntheticTouches.tap(fingers: 3, at: 0.001)
        var found: [Gesture] = []
        for (fa, fb) in zip(a, b) {
            if let g = recognizer.process(device: 1, timestamp: fa.timestamp, contacts: fa.touches).gesture { found.append(g) }
            if let g = recognizer.process(device: 2, timestamp: fb.timestamp, contacts: fb.touches).gesture { found.append(g) }
        }
        #expect(found == [.tap(3), .tap(3)])
    }

    @Test func staleSessionIsDropped() {
        // Fingers down, then frames stop for a second (unplugged): the next touch starts fresh.
        var recognizer = GestureRecognizer()
        _ = recognizer.process(device: 1, timestamp: 0, contacts: [.init(id: 1, x: 0.5, y: 0.5)])
        let later = SyntheticTouches.tap(fingers: 3, at: 2)
        let result = later.compactMap { recognizer.process(device: 1, timestamp: $0.timestamp, contacts: $0.touches).gesture }
        #expect(result == [.tap(3)])
    }

    @Test func liveFingerCount() {
        var recognizer = GestureRecognizer()
        let output = recognizer.process(device: 1, timestamp: 0, contacts: [.init(id: 1, x: 0.5, y: 0.5), .init(id: 2, x: 0.6, y: 0.5)])
        #expect(output.fingers == 2)
    }

    @Test func surfaceSizeScalesThresholds() {
        // A small pad (100 mm wide): a 15% swipe is 15 mm, short of 18 mm.
        var recognizer = GestureRecognizer()
        recognizer.setSurface(device: 1, width: 100, height: 70)
        let frames = SyntheticTouches.swipe(fingers: 3, direction: .right, distance: 0.15)
        #expect(frames.compactMap { recognizer.process(device: 1, timestamp: $0.timestamp, contacts: $0.touches).gesture }.isEmpty)
    }

    @Test func validatorSwitchesOffOnGarbage() {
        var validator = TouchFrameValidator()
        #expect(TouchFrameValidator.isValid(TouchContact(id: 1, x: 0.5, y: 0.5)))
        #expect(!TouchFrameValidator.isValid(TouchContact(id: 1, x: 37, y: 0.5)))
        #expect(!TouchFrameValidator.isValid(TouchContact(id: 1, x: .nan, y: 0.5)))
        #expect(!TouchFrameValidator.isValid(TouchContact(id: 1, x: 0.5, y: 0.5, state: 99)))
        for _ in 0..<7 {
            let keepGoing = validator.check(count: 3, allValid: false)
            #expect(keepGoing)
        }
        let afterGood = validator.check(count: 3, allValid: true)
        #expect(afterGood, "a good frame resets the run")
        for _ in 0..<7 { _ = validator.check(count: 99, allValid: true) }
        let gaveUp = !validator.check(count: 3, allValid: false)
        #expect(gaveUp)
    }
}
