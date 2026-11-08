import Foundation
import Testing
@testable import GaugeCore

@Suite struct MenuBarTextTests {
    let battery = BatteryInfo(percent: 84, source: .battery, minutesToEmpty: 192)

    @Test func defaultIsCPUOnly() {
        let content = MenuBarText.content(for: Preferences(), values: ReadoutValues(cpu: 0.12), locale: us)
        #expect(content.segments.map(\.readout) == [.cpu])
        #expect(content.accessibilityLabel == "Gauge, CPU 12 percent")
    }

    @Test func cpuAndNetwork() {
        let content = MenuBarText.content(for: Preferences(readouts: [.cpu, .network]),
                                          values: ReadoutValues(cpu: 0.12, network: ByteRates(down: 1_200_000, up: 40_000)),
                                          locale: us)
        #expect(content.segments.map(\.readout) == [.cpu, .network])
        #expect(content.segments[0].symbol == "cpu")
        #expect(content.segments[0].fields.map(\.text) == ["12%"])
        #expect(content.segments[1].fields.map(\.text) == ["↓ 1.2 MB/s", "↑ 40 KB/s"])
        #expect(content.accessibilityLabel
                == "Gauge, CPU 12 percent, network down 1.2 megabytes per second, up 40 kilobytes per second")
    }

    @Test func unknownValuesShowADash() {
        let content = MenuBarText.content(for: Preferences(readouts: [.cpu, .memory, .disk]), values: ReadoutValues(), locale: us)
        #expect(content.segments.flatMap { $0.fields.map(\.text) } == ["–", "–", "–"])
        let network = MenuBarText.content(for: Preferences(readouts: [.network]), values: ReadoutValues(), locale: us)
        #expect(network.segments[0].fields.map(\.text) == ["↓ –", "↑ –"])
        #expect(content.accessibilityLabel.contains("CPU not known yet"))
    }

    @Test func everyFieldFitsItsCandidates() {
        let preferences = Preferences(readouts: [.memory, .disk, .battery])
        let content = MenuBarText.content(for: preferences,
                                          values: ReadoutValues(memoryPressure: 0.31, bootVolumeFree: 412_000_000_000, battery: battery),
                                          locale: us)
        for segment in content.segments {
            for field in segment.fields {
                let shape: (String) -> String = { String($0.map { $0.isNumber ? "8" : $0 }) }
                #expect(field.candidates.map(shape).contains(shape(field.text)), "\(field.text)")
            }
        }
        #expect(content.segments[2].symbol == "battery.75percent")
        #expect(content.accessibilityLabel.contains("battery 84 percent"))
    }

    @Test func batteryAndGPUHideWhenMissing() {
        let preferences = Preferences(readouts: [.gpu, .battery, .cpu])
        let content = MenuBarText.content(for: preferences, values: ReadoutValues(cpu: 0.5, gpu: 0.1, battery: battery),
                                          hasBattery: false, hasGPU: false, locale: us)
        #expect(content.segments.map(\.readout) == [.cpu])
    }

    @Test func layoutKeyIgnoresValues() {
        let both = Preferences(readouts: [.cpu, .network])
        let a = MenuBarText.content(for: both, values: ReadoutValues(cpu: 0.1), locale: us)
        let b = MenuBarText.content(for: both, values: ReadoutValues(cpu: 0.9, network: .zero), locale: us)
        #expect(a.layoutKey == b.layoutKey)
        #expect(a.drawnText != b.drawnText)
        let bits = MenuBarText.content(for: Preferences(rateUnit: .bits), values: ReadoutValues(), locale: us)
        #expect(bits.layoutKey != a.layoutKey)
    }

    @Test func batterySymbols() {
        #expect(MenuBarText.batterySymbol(nil) == "battery.100percent")
        #expect(MenuBarText.batterySymbol(BatteryInfo(percent: 5, source: .battery)) == "battery.0percent")
        #expect(MenuBarText.batterySymbol(BatteryInfo(percent: 30, source: .battery)) == "battery.25percent")
        #expect(MenuBarText.batterySymbol(BatteryInfo(percent: 50, source: .battery)) == "battery.50percent")
        #expect(MenuBarText.batterySymbol(BatteryInfo(percent: 95, source: .battery)) == "battery.100percent")
        #expect(MenuBarText.batterySymbol(BatteryInfo(percent: 40, source: .powerAdapter)) == "battery.100percent.bolt")
    }
}

@Suite struct RedrawPolicyTests {
    static let readouts: [Readout] = [.cpu, .network]

    func content(_ cpu: Double?, _ down: Double = 0) -> (MenuBarContent, ReadoutValues) {
        let values = ReadoutValues(cpu: cpu, network: ByteRates(down: down, up: 0))
        return (MenuBarText.content(for: Preferences(readouts: Self.readouts), values: values, locale: us), values)
    }

    final class Box { var policy = RedrawPolicy() }

    func redraw(_ box: Box, _ cpu: Double?, _ down: Double = 0, at now: Double, interval: Double = 2) -> Bool {
        let (content, values) = content(cpu, down)
        return box.policy.shouldRedraw(content, values: values, readouts: Self.readouts, interval: interval, now: now)
    }

    @Test func firstContentDrawsAndIdenticalTextNever() {
        let policy = Box()
        #expect(redraw(policy, 0.05, at: 0))
        #expect(!redraw(policy, 0.05, at: 2))
        #expect(!redraw(policy, 0.049, at: 100)) // rounds to the same "5%"
    }

    @Test func smallChangesWaitBigChangesDont() {
        let policy = Box()
        #expect(redraw(policy, 0.05, at: 0))
        #expect(!redraw(policy, 0.06, at: 2))   // 1 point: waits
        #expect(!redraw(policy, 0.12, at: 3))   // 7 points: waits
        #expect(!redraw(policy, 0.04, at: 4))
        #expect(redraw(policy, 0.40, at: 6))    // a spike shows at once
        #expect(!redraw(policy, 0.41, at: 8))
        #expect(!redraw(policy, 0.42, at: 35))
        #expect(redraw(policy, 0.42, at: 36))   // waited 30 s: shows
    }

    @Test func settleTimeFollowsTheInterval() {
        #expect(RedrawPolicy.settleSeconds(for: 1) == 15)
        #expect(RedrawPolicy.settleSeconds(for: 2) == 30)
        #expect(RedrawPolicy.settleSeconds(for: 5) == 60)
        let policy = Box()
        #expect(redraw(policy, 0.05, at: 0, interval: 1))
        #expect(!redraw(policy, 0.06, at: 14, interval: 1))
        #expect(redraw(policy, 0.06, at: 15, interval: 1))
    }

    @Test func networkChangesByFactorOrToAndFromIdle() {
        let policy = Box()
        #expect(redraw(policy, 0.05, 0, at: 0))
        #expect(!redraw(policy, 0.05, 3_000, at: 2))       // background chatter waits
        #expect(!redraw(policy, 0.05, 40_000, at: 4))
        #expect(redraw(policy, 0.05, 1_500_000, at: 6))    // a download starts
        #expect(!redraw(policy, 0.05, 2_700_000, at: 8))   // ×1.8: waits
        #expect(redraw(policy, 0.05, 4_600_000, at: 10))   // tripled: shows
        #expect(redraw(policy, 0.05, 200, at: 12))         // back to idle
        #expect(!redraw(policy, 0.05, 90_000, at: 14))     // chatter again
    }

    @Test func unknownToKnownIsSignificant() {
        let policy = Box()
        #expect(redraw(policy, nil, at: 0))
        #expect(redraw(policy, 0.05, at: 1))
    }

    @Test func layoutChangeAndResetRedraw() {
        let policy = Box()
        #expect(redraw(policy, 0.05, at: 0))
        let bits = MenuBarText.content(for: Preferences(readouts: Self.readouts, rateUnit: .bits),
                                       values: ReadoutValues(cpu: 0.05, network: .zero), locale: us)
        let switched = policy.policy.shouldRedraw(bits, values: ReadoutValues(cpu: 0.05, network: .zero),
                                                  readouts: Self.readouts, interval: 2, now: 1)
        #expect(switched)
        policy.policy.reset()
        #expect(redraw(policy, 0.05, at: 2))
    }

    @Test func gpuNeedsABiggerChange() {
        let policy = Box()
        let readouts: [Readout] = [.gpu]
        func draw(_ gpu: Double, at now: Double) -> Bool {
            let values = ReadoutValues(gpu: gpu)
            return policy.policy.shouldRedraw(MenuBarText.content(for: Preferences(readouts: readouts), values: values, locale: us),
                                              values: values, readouts: readouts, interval: 2, now: now)
        }
        #expect(draw(0.10, at: 0))
        #expect(!draw(0.24, at: 2))
        #expect(draw(0.25, at: 4))
    }

    @Test func diskAndBatteryChangesShowAtOnce() {
        let box = Box()
        let preferences = Preferences(readouts: [.disk, .battery])
        func draw(_ free: UInt64, _ percent: Int, at now: Double) -> Bool {
            let values = ReadoutValues(bootVolumeFree: free, battery: BatteryInfo(percent: percent, source: .battery))
            return box.policy.shouldRedraw(MenuBarText.content(for: preferences, values: values, locale: us), values: values,
                                       readouts: preferences.readouts, interval: 2, now: now)
        }
        #expect(draw(412_000_000_000, 80, at: 0))
        #expect(draw(412_000_000_000, 79, at: 1))
        #expect(draw(411_000_000_000, 79, at: 2))
    }
}

@Suite struct PreferencesTests {
    @Test func readoutsAreUniqueAndAtMostThree() {
        let preferences = Preferences(readouts: [.cpu, .cpu, .memory, .network, .disk])
        #expect(preferences.readouts == [.cpu, .memory, .network])
        var changed = preferences
        changed.readouts = [.disk, .disk, .battery]
        #expect(changed.readouts == [.disk, .battery])
    }

    @Test func setAndMove() {
        var preferences = Preferences()
        #expect(preferences.readouts == [.cpu])
        preferences.set(.network, shown: true)
        preferences.set(.memory, shown: true)
        #expect(preferences.readouts == [.cpu, .network, .memory])
        #expect(!preferences.canAdd(.disk))
        #expect(preferences.canAdd(.cpu))
        preferences.set(.disk, shown: true)
        #expect(preferences.readouts.count == 3)
        preferences.move(.memory, by: -1)
        #expect(preferences.readouts == [.cpu, .memory, .network])
        preferences.move(.cpu, by: -1)
        #expect(preferences.readouts == [.cpu, .memory, .network])
        preferences.set(.cpu, shown: false)
        preferences.set(.memory, shown: false)
        preferences.set(.network, shown: false)
        #expect(preferences.readouts.isEmpty)
    }

    @Test func roundTripsThroughStorage() {
        let storage = MemoryStorage()
        #expect(PreferencesCodec.load(from: storage) == Preferences())
        let preferences = Preferences(readouts: [.battery, .gpu], interval: .fiveSeconds, slowDownInLowPowerMode: false,
                                      rateUnit: .bits, groupProcessesByApp: false, historySpan: .hour)
        PreferencesCodec.save(preferences, to: storage)
        #expect(PreferencesCodec.load(from: storage) == preferences)
    }

    @Test func toleratesUnknownAndMissingKeys() throws {
        let storage = MemoryStorage()
        storage.values[PreferencesCodec.key] = Data(#"{"readouts":["cpu","temperature","disk"],"interval":7,"future":true}"#.utf8)
        let preferences = PreferencesCodec.load(from: storage)
        #expect(preferences.readouts == [.cpu, .disk])
        #expect(preferences.interval == .twoSeconds)
        #expect(preferences.groupProcessesByApp)
        storage.values[PreferencesCodec.key] = Data("not json".utf8)
        #expect(PreferencesCodec.load(from: storage) == Preferences())
    }

    @Test func cadence() {
        let preferences = Preferences(interval: .twoSeconds)
        #expect(Cadence.interval(for: preferences, panelOpen: false, lowPowerMode: false) == 2)
        #expect(Cadence.interval(for: preferences, panelOpen: true, lowPowerMode: true) == 1)
        #expect(Cadence.interval(for: preferences, panelOpen: false, lowPowerMode: true) == 5)
        var fast = Preferences(interval: .oneSecond)
        fast.slowDownInLowPowerMode = false
        #expect(Cadence.interval(for: fast, panelOpen: false, lowPowerMode: true) == 1)
        #expect(Cadence.leeway(for: 2) == 0.4)
        #expect(Cadence.leeway(for: 10) == 1)
    }
}

@Suite struct SmootherTests {
    @Test func firstValuePassesThroughThenAverages() throws {
        var smoother = ReadoutSmoother()
        let first = smoother.smooth(ReadoutValues(cpu: 0.1, network: ByteRates(down: 0, up: 700_000)), at: 0)
        #expect(first.cpu == 0.1)
        let second = smoother.smooth(ReadoutValues(cpu: 0.2, network: ByteRates(down: 0, up: 0)), at: 2)
        let weight = 1 - exp(-2.0 / 4)
        #expect(abs(try #require(second.cpu) - (0.1 + 0.1 * weight)) < 1e-9)
        #expect(abs(try #require(second.network).up - 700_000 * (1 - weight)) < 1e-6)
    }

    @Test func bigRisesJumpFallsEase() throws {
        var smoother = ReadoutSmoother()
        _ = smoother.smooth(ReadoutValues(cpu: 0.17, network: ByteRates(down: 5_000, up: 0)), at: 0)
        let spike = smoother.smooth(ReadoutValues(cpu: 0.70, network: ByteRates(down: 2_800_000, up: 0)), at: 2)
        #expect(spike.cpu == 0.70)                      // one step, one redraw
        #expect(spike.network?.down == 2_800_000)
        let after = smoother.smooth(ReadoutValues(cpu: 0.10, network: ByteRates(down: 0, up: 0)), at: 4)
        #expect(after.cpu == 0.10)                       // a big fall jumps too
        #expect(try #require(after.network).down > 1_000_000) // rates ease down
        let wobble = smoother.smooth(ReadoutValues(cpu: 0.16), at: 6)
        #expect(try #require(wobble.cpu) < 0.14)         // small changes average
    }

    @Test func flickeringUploadReadsSteady() {
        var smoother = ReadoutSmoother()
        var shown: [Double] = []
        for step in 0..<20 {
            let up = step.isMultiple(of: 2) ? 700_000.0 : 0
            shown.append(smoother.smooth(ReadoutValues(network: ByteRates(down: 0, up: up)), at: Double(step) * 2).network!.up)
        }
        let settled = shown.suffix(10)
        #expect(settled.max()! / settled.min()! < 2.5)
    }

    @Test func missingValuesKeepTheLastAndResetForgets() {
        var smoother = ReadoutSmoother()
        _ = smoother.smooth(ReadoutValues(cpu: 0.5), at: 0)
        #expect(smoother.smooth(ReadoutValues(), at: 2).cpu == 0.5)
        smoother.reset()
        #expect(smoother.smooth(ReadoutValues(cpu: 0.2), at: 3).cpu == 0.2)
    }
}
