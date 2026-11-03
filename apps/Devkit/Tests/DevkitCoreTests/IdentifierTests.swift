import Foundation
import Testing
@testable import DevkitCore

/// Deterministic randomness for tests (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct IdentifierTests {
    let fixed = Date(timeIntervalSince1970: 1_645_557_742) // the RFC 9562 example time

    @Test func v4HasVersionAndVariant() {
        var generator = IdentifierGenerator(random: SeededRandom(state: 1), now: { fixed })
        for id in generator.generate(.uuidV4, count: 50) {
            let bytes = Identifiers.parseUUID(id)!
            #expect(bytes[6] >> 4 == 4)
            #expect(bytes[8] >> 6 == 0b10)
            #expect(id == id.lowercased())
        }
    }

    @Test func v7EmbedsTimeAndIsMonotonic() {
        var generator = IdentifierGenerator(random: SeededRandom(state: 2), now: { fixed })
        let ids = generator.generate(.uuidV7, count: 500)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == 500)
        #expect(ids[0].hasPrefix("017f22e2-79b0-7"))
    }

    @Test func formatOptions() {
        var generator = IdentifierGenerator(random: SeededRandom(state: 3), now: { fixed })
        let id = generator.generate(.uuidV4, count: 1, format: .init(uppercase: true, hyphens: false))[0]
        #expect(id.count == 32 && id == id.uppercased())
    }

    @Test func ulidSpecTimestamp() {
        // ULID spec: time 1469918176385 encodes as 01ARYZ6S41.
        var generator = IdentifierGenerator(random: SeededRandom(state: 4), now: { Date(timeIntervalSince1970: 1_469_918_176.385) })
        let ids = generator.generate(.ulid, count: 100)
        #expect(ids.allSatisfy { $0.hasPrefix("01ARYZ6S41") && $0.count == 26 })
        #expect(ids == ids.sorted())
        #expect(Identifiers.decodeULID(ids[0]).map(Identifiers.encodeULID) == ids[0])
    }

    @Test func ulidDecodingIsLenient() {
        #expect(Identifiers.decodeULID("01aryz6s41tsv4rrffq69g5fav") != nil)
        #expect(Identifiers.decodeULID("8ZZZZZZZZZZZZZZZZZZZZZZZZZ") == nil) // overflows 128 bits
        #expect(Identifiers.decodeULID("01ARYZ6S41TSV4RRFFQ69G5FAU") == nil) // U isn't Crockford
    }

    // RFC 9562 Appendix A examples.
    @Test func inspectsRFC9562Examples() throws {
        let utc = TimeZone(identifier: "UTC")!
        let v1 = try Identifiers.inspect("C232AB00-9414-11EC-B3C8-9F6BDECED846", timeZone: utc)
        #expect(v1.first { $0.label == "Version" }?.value == "1 (time and node)")
        #expect(v1.first { $0.label == "Time" }?.value == "2022-02-22T19:22:22.000Z")
        let v6 = try Identifiers.inspect("1EC9414C-232A-6B00-B3C8-9F6BDECED846", timeZone: utc)
        #expect(v6.first { $0.label == "Time" }?.value == "2022-02-22T19:22:22.000Z")
        let v7 = try Identifiers.inspect("017F22E2-79B0-7CC3-98C4-DC0C0C07398F", timeZone: utc)
        #expect(v7.first { $0.label == "Version" }?.value == "7 (Unix time, sortable)")
        #expect(v7.first { $0.label == "Variant" }?.value == "RFC 9562 (standard)")
        #expect(v7.first { $0.label == "Unix milliseconds" }?.value == "1645557742000")
        let v4 = try Identifiers.inspect("{919108f7-52d1-4320-9bac-f847db4148a8}")
        #expect(v4.first { $0.label == "Version" }?.value == "4 (random)")
        #expect(v4.contains { $0.label == "Time" } == false)
    }

    @Test func inspectsULIDAndSpecialUUIDs() throws {
        let rows = try Identifiers.inspect("01ARYZ6S41TSV4RRFFQ69G5FAV", timeZone: TimeZone(identifier: "UTC")!)
        #expect(rows.first { $0.label == "Unix milliseconds" }?.value == "1469918176385")
        #expect(try Identifiers.inspect("00000000-0000-0000-0000-000000000000").first { $0.label == "Version" }?.value == "Nil UUID (all zeros)")
        #expect(try Identifiers.inspect("urn:uuid:ffffffff-ffff-ffff-ffff-ffffffffffff").first { $0.label == "Version" }?.value == "Max UUID (all ones)")
        #expect(throws: Identifiers.InspectError.unrecognized) { try Identifiers.inspect("not-a-uuid") }
    }

    @Test func uuidULIDRoundTrip() throws {
        let bytes = Identifiers.parseUUID("017F22E2-79B0-7CC3-98C4-DC0C0C07398F")!
        #expect(Identifiers.decodeULID(Identifiers.encodeULID(bytes)) == bytes)
        let rows = try Identifiers.inspect("017F22E2-79B0-7CC3-98C4-DC0C0C07398F")
        #expect(rows.first { $0.label == "Integer" }?.value == "1989357241971137676463954034883508623")
    }
}
