import Foundation
import Testing
@testable import ClipsCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private final class FakePlayer: SoundPlaying {
    var played: [SoundEffect] = []
    func play(_ effect: SoundEffect) { played.append(effect) }
}

// MARK: - When sounds play

@Suite struct CopyChimeTests {
    @Test func playsForARecordedCopy() {
        let player = FakePlayer()
        let chime = CopyChime(player: player, systemSoundsEnabled: { true }, clock: { now })
        #expect(chime.copyRecorded())
        #expect(player.played == [.copy(.paper)])
    }

    @Test func silentWhenTurnedOff() {
        let player = FakePlayer()
        let chime = CopyChime(player: player, isEnabled: false, playsPasteSound: false, systemSoundsEnabled: { true }, clock: { now })
        #expect(!chime.copyRecorded())
        #expect(!chime.clipUsed())
        #expect(player.played.isEmpty)
    }

    @Test func copyAndPasteSwitchesAreSeparate() {
        let player = FakePlayer()
        let chime = CopyChime(player: player, isEnabled: false, playsPasteSound: true, systemSoundsEnabled: { true }, clock: { now })
        #expect(!chime.copyRecorded())
        #expect(chime.clipUsed())
        chime.isEnabled = true
        chime.playsPasteSound = false
        #expect(chime.copyRecorded())
        #expect(!chime.clipUsed())
        #expect(player.played == [.paste(.paper), .copy(.paper)])
    }

    @Test func respectsTheSystemSoundEffectsSwitch() {
        let player = FakePlayer()
        var systemOn = false
        let chime = CopyChime(player: player, systemSoundsEnabled: { systemOn }, clock: { now })
        #expect(!chime.copyRecorded())
        #expect(!chime.clipUsed())
        systemOn = true
        #expect(chime.copyRecorded())
        #expect(chime.clipUsed())
        #expect(player.played.count == 2)
    }

    @Test func throttlesBurstsOfEachKind() {
        let player = FakePlayer()
        var time = now
        let chime = CopyChime(player: player, minimumInterval: 0.2, systemSoundsEnabled: { true }, clock: { time })
        #expect(chime.copyRecorded())
        // A paste right after a copy still sounds: separate throttles.
        #expect(chime.clipUsed())
        time += 0.05
        #expect(!chime.copyRecorded())
        #expect(!chime.clipUsed())
        time += 0.2
        #expect(chime.copyRecorded())
        #expect(player.played == [.copy(.paper), .paste(.paper), .copy(.paper)])
    }

    @Test func usesTheChosenPair() {
        let player = FakePlayer()
        let chime = CopyChime(player: player, sound: .glass, systemSoundsEnabled: { true }, clock: { now })
        chime.copyRecorded()
        chime.clipUsed()
        chime.sound = .pluck
        chime.preview()
        chime.previewPaste()
        #expect(player.played == [.copy(.glass), .paste(.glass), .copy(.pluck), .paste(.pluck)])
    }

    @Test func clipsOwnWriteIsNotACopy() {
        // Pasting a clip writes the pasteboard; that change must not count as a new copy, so
        // the paste sound plays alone (no copy sound on top).
        var tracker = ChangeTracker(startingAt: 10)
        tracker.noteOwnWrite(11)
        let ownWrite = tracker.isNewExternalChange(11)
        let realCopy = tracker.isNewExternalChange(12)
        #expect(!ownWrite)
        #expect(realCopy)
    }
}

// MARK: - Choices, settings and migration

@Suite struct SoundSettingsTests {
    private func load(_ saved: [String: Any]) -> SoundSettings {
        SoundSettings.load { saved[$0] }
    }

    @Test func defaultIsPaper() {
        #expect(SoundChoice.default == .paper)
        #expect(CopyChime(player: FakePlayer(), systemSoundsEnabled: { true }).sound == .paper)
        #expect(load([:]) == SoundSettings(playsCopySound: true, playsPasteSound: true, choice: .paper))
    }

    @Test func choicesInOrder() {
        #expect(SoundChoice.allCases.map(\.title) == ["Paper", "Glass", "Wood", "Bubble", "Snap", "Pluck", "Classic"])
    }

    @Test func aSavedChoiceIsKept() {
        for choice in SoundChoice.allCases {
            #expect(load([SoundSettings.Keys.soundChoice: choice.rawValue]).choice == choice)
        }
    }

    /// Before pairs, `copySound` was written only when someone picked a copy sound.
    @Test func migration() {
        // Never changed it (no keys at all): Paper.
        #expect(load([:]).choice == .paper)
        // Picked the first synthesized sound on purpose: that pair is Classic now.
        #expect(load(["copySound": "Snap"]).choice == .classic)
        // Picked a macOS sound, which is gone: the default.
        for old in ["Pop", "Tink", "Bottle", "Morse", "Purr", "Nonsense"] {
            #expect(load(["copySound": old]).choice == .paper)
        }
        // A new-style choice wins over the old key; an unknown one falls back.
        #expect(load(["copySound": "Snap", "soundChoice": "wood"]).choice == .wood)
        #expect(load(["copySound": "Snap", "soundChoice": "kazoo"]).choice == .classic)
        #expect(load(["soundChoice": "kazoo"]).choice == .paper)
    }

    @Test func soundOffStaysOff() {
        let off = load(["playsCopySound": false, "playsPasteSound": false])
        #expect(!off.playsCopySound && !off.playsPasteSound)
        #expect(off.choice == .paper)
        let copyOff = load(["playsCopySound": false, "copySound": "Pop"])
        #expect(!copyOff.playsCopySound && copyOff.playsPasteSound)
        #expect(load(["playsPasteSound": false]).playsPasteSound == false)
    }

    @Test func versionedFileNames() {
        let names = SoundChoice.allCases.flatMap { choice in SoundKind.allCases.map { SoundEffect(choice, $0).fileName } }
        #expect(Set(names).count == names.count)
        for name in names { #expect(name.hasSuffix("-v\(SoundPairs.version).aiff")) }
        #expect(SoundEffect.copy(.paper).fileName == "paper-copy-v\(SoundPairs.version).aiff")
        // The first version's files must never match.
        #expect(SoundPairs.version > 1)
        #expect(!names.contains("snap-v1.aiff") && !names.contains("tock-v1.aiff"))
    }
}

// MARK: - The pairs

@Suite("Sound pairs")
struct SoundPairsTests {
    static let pairs = SoundChoice.allCases.filter { $0 != .classic }
    static let effects = SoundChoice.allCases.flatMap { choice in SoundKind.allCases.map { SoundEffect(choice, $0) } }
    let rendered = Dictionary(uniqueKeysWithValues: Self.effects.map { ($0, $0.render()) })
    let rate = SoundPairs.sampleRate

    @Test(arguments: effects)
    func deterministic(_ effect: SoundEffect) {
        #expect(effect.render() == rendered[effect])
    }

    @Test(arguments: pairs)
    func loudnessTargets(_ choice: SoundChoice) {
        let copy = SoundPairs.activeRMS(rendered[.copy(choice)]!)
        let paste = SoundPairs.activeRMS(rendered[.paste(choice)]!)
        #expect(abs(SoundSynthesis.decibels(copy) - SoundPairs.copyLevel) <= 1)
        #expect(abs(SoundSynthesis.decibels(paste) - SoundPairs.pasteLevel) <= 1)
    }

    @Test(arguments: pairs)
    func peakGuard(_ choice: SoundChoice) {
        for kind in SoundKind.allCases {
            let peak = SoundSynthesis.peak(of: rendered[SoundEffect(choice, kind)]!)
            #expect(SoundSynthesis.decibels(peak) <= -6.02 + 0.001)
            #expect(peak > 0.05)  // and not silent
        }
    }

    /// The guard itself: a sound that would peak above −6 dBFS at the loudness target is
    /// pulled down to exactly −6 dBFS.
    @Test func peakGuardClamps() {
        var spiky = [Double](repeating: 0, count: 4_410)
        spiky[100] = 1
        for i in 200..<4_000 { spiky[i] = 0.06 * sin(Double(i) * 0.3) }
        let out = SoundPairs.finish(spiky, targetRMSdB: -10)
        #expect(abs((out.map(abs).max() ?? 0) - SoundPairs.peakLimit) < 1e-12)
    }

    @Test(arguments: effects)
    func clean(_ effect: SoundEffect) {
        let sound = rendered[effect]!
        #expect(sound.allSatisfy { $0.isFinite && abs($0) < 1 })
        let mean = sound.reduce(0.0) { $0 + Double($1) } / Double(sound.count)
        #expect(abs(mean) < 1e-3)                                  // no DC
        #expect(abs(sound.first!) < 1e-3 && abs(sound.last!) < 1e-4)  // no click at either end
        #expect(Double(sound.count) / rate < 0.26)                  // short
    }

    /// Lengths match the designs: the sound plus a 30 ms room tail.
    @Test func lengths() {
        let expected: [SoundChoice: (Double, Double)] = [
            .paper: (0.16, 0.09), .glass: (0.22, 0.16), .wood: (0.14, 0.12),
            .bubble: (0.13, 0.12), .snap: (0.2, 0.1), .pluck: (0.2, 0.18),
        ]
        for (choice, (copy, paste)) in expected {
            #expect(rendered[.copy(choice)]!.count == Int(copy * rate) + Int(0.03 * rate))
            #expect(rendered[.paste(choice)]!.count == Int(paste * rate) + Int(0.03 * rate))
        }
    }

    /// Every sound is its own: no two are the same, or even close (normalized correlation at
    /// the best small offset stays well below 1).
    @Test func distinct() {
        let effects = Self.effects
        for i in effects.indices {
            for j in effects.indices where j > i {
                let a = rendered[effects[i]]!, b = rendered[effects[j]]!
                #expect(a != b, "\(effects[i]) vs \(effects[j])")
                #expect(similarity(a, b) < 0.9, "\(effects[i]) vs \(effects[j])")
            }
        }
    }

    /// The characters hold: Paper is noise (no frequency stands out), Glass, Wood and Pluck
    /// ring at their pitch, and Bubble rises for copy and falls for paste.
    @Test func characters() {
        #expect(tonality(rendered[.copy(.paper)]!).ratio < 20)
        for (choice, pitch) in [(SoundChoice.glass, 2093.0), (.wood, 1320), (.pluck, 784)] {
            let (peak, ratio) = tonality(rendered[.copy(choice)]!)
            #expect(abs(peak - pitch) <= 25, "\(choice)")
            #expect(ratio > 60, "\(choice) \(ratio)")
        }
        let bubbleCopy = rendered[.copy(.bubble)]!, bubblePaste = rendered[.paste(.bubble)]!
        #expect(crossings(bubbleCopy, 0.005..<0.015) < crossings(bubbleCopy, 0.04..<0.05))
        #expect(crossings(bubblePaste, 0.005..<0.015) > crossings(bubblePaste, 0.045..<0.055))
    }

    /// The strongest frequency on a 25 Hz grid (200 Hz–10 kHz) and how far its energy stands
    /// above the grid's mean.
    private func tonality(_ x: [Float]) -> (peak: Double, ratio: Double) {
        let grid = stride(from: 200.0, through: 10_000, by: 25).map { $0 }
        let energies = grid.map { goertzel(x, $0) }
        let best = energies.indices.max { energies[$0] < energies[$1] }!
        return (grid[best], energies[best] / (energies.reduce(0, +) / Double(energies.count)))
    }

    private func goertzel(_ x: [Float], _ frequency: Double) -> Double {
        let k = 2 * cos(2 * .pi * frequency / rate)
        var s1 = 0.0, s2 = 0.0
        for sample in x {
            let s0 = Double(sample) + k * s1 - s2
            s2 = s1; s1 = s0
        }
        return s1 * s1 + s2 * s2 - k * s1 * s2
    }

    private func crossings(_ x: [Float], _ window: Range<Double>) -> Int {
        let range = Int(window.lowerBound * rate)..<Int(window.upperBound * rate)
        return range.dropFirst().filter { (x[$0 - 1] < 0) != (x[$0] < 0) }.count
    }

    private func similarity(_ a: [Float], _ b: [Float]) -> Double {
        let energyA = a.reduce(0.0) { $0 + Double($1) * Double($1) }
        let energyB = b.reduce(0.0) { $0 + Double($1) * Double($1) }
        var best = 0.0
        for lag in stride(from: -88, through: 88, by: 4) {
            var dot = 0.0
            for i in a.indices where i + lag >= 0 && i + lag < b.count { dot += Double(a[i]) * Double(b[i + lag]) }
            best = max(best, abs(dot) / sqrt(energyA * energyB))
        }
        return best
    }
}

// MARK: - Classic

@Suite("Classic synthesis")
struct SoundSynthesisTests {
    let snap = SoundSynthesis.snap()
    let tock = SoundSynthesis.tock()
    let rate = SoundSynthesis.sampleRate

    @Test func classicIsTheFirstPair() {
        #expect(SoundEffect.copy(.classic).render() == snap)
        #expect(SoundEffect.paste(.classic).render() == tock)
    }

    @Test func deterministic() {
        #expect(SoundSynthesis.snap() == snap)
        #expect(SoundSynthesis.tock() == tock)
    }

    @Test func lengthsAndLevels() {
        #expect(abs(Double(snap.count) / rate - 0.200) < 0.001)
        #expect(abs(Double(tock.count) / rate - 0.080) < 0.001)
        #expect(abs(SoundSynthesis.decibels(SoundSynthesis.peak(of: snap)) + 18) < 0.05)
        #expect(abs(SoundSynthesis.decibels(SoundSynthesis.peak(of: tock)) + 12) < 0.05)
        for sound in [snap, tock] {
            #expect(sound.allSatisfy { $0.isFinite && abs($0) < 1 })
            let mean = sound.reduce(0.0) { $0 + Double($1) } / Double(sound.count)
            #expect(abs(mean) < 1e-4)  // no DC
            #expect(abs(sound.first!) < 1e-3 && abs(sound.last!) < 1e-4)  // no click at either end
        }
    }

    /// Copy: a tick in the first 25 ms, near-silence, a softer swish from ~80 ms, silence at the end.
    @Test func snapHasTwoEvents() {
        let env = SoundSynthesis.envelope(of: snap)  // 5 ms windows
        let peakIndex = env.indices.max { env[$0] < env[$1] }!
        #expect(peakIndex < 5)
        let peak = env[peakIndex]
        let gap = env[8..<15].max()!            // 40–75 ms
        let swish = env[16..<26].max()!         // 80–130 ms
        #expect(gap < peak - 25)
        #expect(swish > gap + 10)
        #expect(swish < peak - 8)
        #expect(env.last! < -60)
    }

    /// Paste: one event that decays fast.
    @Test func tockIsOneFastEvent() {
        let env = SoundSynthesis.envelope(of: tock)
        let peakIndex = env.indices.max { env[$0] < env[$1] }!
        #expect(peakIndex < 2)
        #expect(env[5] < env[peakIndex] - 25)   // 25–30 ms
        for i in (peakIndex + 1)..<env.count { #expect(env[i] <= env[i - 1] + 0.5) }  // only decays
        #expect(env.last! < -60)
    }

    @Test func aiffHeader() {
        let data = SoundSynthesis.aiff(tock)
        #expect(Array(data.prefix(4)) == Array("FORM".utf8))
        #expect(Array(data[8..<12]) == Array("AIFF".utf8))
        #expect(data.count == 54 + tock.count * 2)
        #expect(SoundSynthesis.extended80(44_100) == [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])
    }
}
