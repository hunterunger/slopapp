import Foundation
import Testing
@testable import DropperCore

@Suite struct ContrastPairTests {
    let red = ColorValue(red: 1, green: 0, blue: 0)
    let blue = ColorValue(red: 0.2, green: 0.4, blue: 0.8)
    let gray = ColorValue(red: 0.5, green: 0.5, blue: 0.5)
    let t = Date(timeIntervalSince1970: 0)

    @Test func firstOpenUsesLastTwoPicks() {
        var h = ColorHistory()
        #expect(ContrastPair.initial(from: h) == .blackOnWhite)
        h.add(red, at: t)
        #expect(ContrastPair.initial(from: h).text == red)
        h.add(blue, at: t)
        let pair = ContrastPair.initial(from: h)
        #expect(pair.text == red)
        #expect(pair.background == blue)
        #expect(pair.offer(from: h) == nil)
    }

    @Test func typedColorsSurviveUntilNewPicks() {
        var h = ColorHistory()
        h.add(red, at: t)
        h.add(blue, at: t)
        var pair = ContrastPair.initial(from: h)
        pair.text = gray // typed by the person
        #expect(pair.offer(from: h) == nil) // reopening keeps gray
        h.add(gray, at: t) // a new pick
        let offer = pair.offer(from: h)
        #expect(offer?.text == blue)
        #expect(offer?.background == gray)
        pair.useOffer(from: h)
        #expect(pair.text == blue)
        #expect(pair.background == gray)
        #expect(pair.offer(from: h) == nil)
    }

    @Test func picksMadeInTheCheckerAreNotOffered() {
        var h = ColorHistory()
        h.add(red, at: t)
        h.add(blue, at: t)
        var pair = ContrastPair.initial(from: h)
        h.add(gray, at: t) // picked with the checker's eyedropper
        pair.background = gray
        pair.markOffered(h)
        #expect(pair.offer(from: h) == nil)
    }

    @Test func noOfferWhenPicksAlreadyShown() {
        var h = ColorHistory()
        h.add(red, at: t)
        h.add(blue, at: t)
        let pair = ContrastPair(text: red, background: blue, offeredPickIDs: [])
        #expect(pair.offer(from: h) == nil)
    }

    @Test func codableRoundTrip() throws {
        let pair = ContrastPair(text: red, background: blue, offeredPickIDs: [UUID()])
        let data = try JSONEncoder().encode(pair)
        #expect(try JSONDecoder().decode(ContrastPair.self, from: data) == pair)
    }
}
