import CoreGraphics
import Testing
@testable import SlopDrive

@Suite struct KeysTests {
    @Test func parsesCombos() throws {
        let (code, flags) = try Keys.parse("cmd+opt+ctrl+k")
        #expect(code == 40)
        #expect(flags == [.maskCommand, .maskAlternate, .maskControl])
        #expect(try Keys.parse("cmd+").0 == 24)   // a trailing + is the plus key
        #expect(throws: DriveError.self) { try Keys.parse("cmd") }
        #expect(throws: DriveError.self) { try Keys.parse("hyper+k") }
    }

    /// The bug: a --global cmd+opt+ctrl press left the modifiers registered as held.
    /// Every modifier must go down and come back up as its own event, and the stroke must
    /// end with no flag set.
    @Test func everyModifierIsPressedAndReleased() throws {
        let (code, flags) = try Keys.parse("cmd+opt+ctrl+shift+fn+k")
        let events = Keys.stroke(code, flags: flags)
        #expect(events.count == 2 + 2 * 5)
        #expect(events.last?.flags == [])
        for (flag, mod) in Keys.modifierKeys {
            let downs = events.filter { $0.code == mod && $0.down }
            let ups = events.filter { $0.code == mod && !$0.down }
            #expect(downs.count == 1 && ups.count == 1, "\(Keys.name(of: flag))")
            #expect(downs.allSatisfy(\.isModifier) && ups.allSatisfy(\.isModifier))
            #expect(downs.first?.flags.contains(flag) == true)
            #expect(ups.first?.flags.contains(flag) == false)
        }
        // The key itself goes down and up with every modifier held.
        let key = events.filter { !$0.isModifier }
        #expect(key.map(\.down) == [true, false])
        #expect(key.allSatisfy { $0.flags == flags })
    }

    @Test func modifiersComeUpInReverse() throws {
        let (code, flags) = try Keys.parse("ctrl+opt+cmd+space")
        let events = Keys.stroke(code, flags: flags)
        #expect(events.map(\.code) == [59, 58, 55, 49, 49, 55, 58, 59])
        #expect(events.map(\.down) == [true, true, true, true, false, false, false, false])
        #expect(events.map(\.flags) == [
            [.maskControl], [.maskControl, .maskAlternate], flags, flags, flags,
            [.maskControl, .maskAlternate], [.maskControl], [],
        ])
    }

    @Test func plainKeyHasNoModifierEvents() {
        let events = Keys.stroke(53, flags: [])
        #expect(events == [
            Keys.Event(code: 53, down: true, flags: [], isModifier: false),
            Keys.Event(code: 53, down: false, flags: [], isModifier: false),
        ])
    }
}
