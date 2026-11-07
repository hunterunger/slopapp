import Foundation

/// Clips' six sound pairs (every choice but Classic), synthesized in code from a few small
/// building blocks: damped sine partials, band-passed noise, a Karplus–Strong pluck, a
/// one-pole low-pass and a whisper of room. Mono, 44.1 kHz.
///
/// Loudness is matched, not peak-normalized: copy sounds sit at −30 dB RMS over their active
/// part (samples above 5 % of the peak), paste sounds at −27 dB (a touch more present), and
/// nothing ever peaks above −6 dBFS.
///
/// Deterministic: each sound's noise comes from its own fixed xorshift seed, so the same
/// samples come out every time and on every Mac.
public enum SoundPairs {
    /// Part of every cached file name. Bump when any sound's synthesis changes (Classic's too).
    public static let version = 2

    public static let sampleRate = 44_100.0
    /// RMS of the active part, dBFS.
    public static let copyLevel = -30.0
    public static let pasteLevel = -27.0
    /// Peak guard: never above −6 dBFS.
    public static let peakLimit = 0.5

    public static func render(_ choice: SoundChoice, _ kind: SoundKind) -> [Float] {
        var g = Generator(seed: seed(choice, kind))
        let level = kind == .copy ? copyLevel : pasteLevel
        let raw: [Double]
        switch (choice, kind) {
        // A page flick: a soft mid noise flick and an airy tail; nothing tonal.
        case (.paper, .copy):
            raw = room(mix([
                g.noise(0.16, centre: 2600, q: 1.6, amp: 1.0, attack: 0.003, decay: 0.012),
                g.noise(0.16, centre: 8000, q: 0.9, amp: 0.35, attack: 0.008, decay: 0.035, start: 0.012)]))
        case (.paper, .paste):
            raw = room(mix([
                g.noise(0.09, centre: 900, q: 1.2, amp: 1.0, attack: 0.002, decay: 0.010),
                g.partial(0.09, f0: 230, amp: 0.5, attack: 0.002, decay: 0.012)]))

        // A tiny glass tap: two inharmonic partials (1 : 2.76), a gentle ring.
        case (.glass, .copy):
            raw = room(mix([
                g.partial(0.22, f0: 2093, amp: 1.0, attack: 0.0015, decay: 0.045),
                g.partial(0.22, f0: 2093 * 2.76, amp: 0.25, attack: 0.001, decay: 0.018),
                g.noise(0.22, centre: 6000, q: 2, amp: 0.15, attack: 0.0005, decay: 0.002)]), amount: 0.18)
        case (.glass, .paste):
            raw = room(mix([
                g.partial(0.16, f0: 1568, amp: 1.0, attack: 0.0015, decay: 0.030),
                g.partial(0.16, f0: 1568 * 2.76, amp: 0.18, attack: 0.001, decay: 0.012)]), amount: 0.18)

        // A small marimba-like bar (1 : 3.93), warm and short.
        case (.wood, .copy):
            raw = room(mix([
                g.partial(0.14, f0: 1320, amp: 1.0, attack: 0.001, decay: 0.022),
                g.partial(0.14, f0: 1320 * 3.93, amp: 0.22, attack: 0.0007, decay: 0.006),
                g.noise(0.14, centre: 3000, q: 1.5, amp: 0.2, attack: 0.0005, decay: 0.002)]))
        case (.wood, .paste):
            raw = room(mix([
                g.partial(0.12, f0: 880, amp: 1.0, attack: 0.001, decay: 0.024),
                g.partial(0.12, f0: 880 * 3.93, amp: 0.15, attack: 0.0007, decay: 0.006)]))

        // A rising bloop for copy, a falling one for paste.
        case (.bubble, .copy):
            raw = room(lowpass(g.partial(0.13, f0: 520, f1: 1250, glide: 0.035, amp: 1.0, attack: 0.002, decay: 0.030), cutoff: 5000))
        case (.bubble, .paste):
            raw = room(lowpass(g.partial(0.12, f0: 1150, f1: 560, glide: 0.04, amp: 1.0, attack: 0.002, decay: 0.028), cutoff: 5000))

        // A soft, low tick with body and a short quiet swish; a gliding tock for paste.
        case (.snap, .copy):
            raw = room(mix([
                lowpass(g.partial(0.2, f0: 3600, amp: 0.6, attack: 0.0015, decay: 0.006), cutoff: 7000),
                g.partial(0.2, f0: 1150, amp: 0.7, attack: 0.0015, decay: 0.009),
                g.noise(0.2, centre: 8500, q: 1.0, amp: 0.22, attack: 0.012, decay: 0.03, start: 0.06)]))
        case (.snap, .paste):
            raw = room(mix([
                g.partial(0.1, f0: 640, f1: 520, glide: 0.02, amp: 1.0, attack: 0.0015, decay: 0.014),
                g.noise(0.1, centre: 1800, q: 1.2, amp: 0.25, attack: 0.0008, decay: 0.003)]))

        // A soft muted string, a fifth apart.
        case (.pluck, .copy):
            raw = room(lowpass(g.pluck(0.2, f: 784, amp: 1.0, damping: 0.985), cutoff: 4200))
        case (.pluck, .paste):
            raw = room(lowpass(g.pluck(0.18, f: 523, amp: 1.0, damping: 0.98), cutoff: 3500))

        case (.classic, .copy):
            return SoundSynthesis.snap()
        case (.classic, .paste):
            return SoundSynthesis.tock()
        }
        return finish(raw, targetRMSdB: level).map { Float($0) }
    }

    /// Each sound's noise seed: the generator state each sound started from when the pairs
    /// were designed, so these renders match those exactly. (Bubble and Classic use no
    /// xorshift noise.)
    static func seed(_ choice: SoundChoice, _ kind: SoundKind) -> UInt64 {
        switch (choice, kind) {
        case (.paper, .copy): 0x9E37_79B9_7F4A_7C15
        case (.paper, .paste): 0x78A4_76BD_0865_C9F5
        case (.glass, .copy): 0xC52D_DB76_D9A6_6A8B
        case (.glass, .paste), (.wood, .copy), (.wood, .paste): 0x13CE_6085_48EF_CE2E
        case (.bubble, _), (.classic, _), (.snap, .copy): 0xBB80_CD31_007D_750E
        case (.snap, .paste): 0x12DF_58F7_C40C_8EAC
        case (.pluck, .copy): 0x9A66_88C1_D99D_E9C1
        case (.pluck, .paste): 0x1EE5_7AA5_B0C4_D643
        }
    }

    // MARK: - Building blocks

    static func samples(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

    /// Raised-cosine attack, exponential decay.
    static func envelope(_ t: Double, attack: Double, decay: Double) -> Double {
        if t < 0 { return 0 }
        let a = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1
        return a * exp(-max(0, t - attack) / decay)
    }

    /// The parts that use noise. A xorshift64 generator, uniform in −1…1.
    struct Generator {
        var seed: UInt64

        mutating func random() -> Double {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 2_000_001) / 1_000_000 - 1
        }

        /// A damped partial with an optional pitch glide (f0 → f1 over `glide` seconds).
        func partial(_ length: Double, f0: Double, f1: Double? = nil, glide: Double = 0.03, amp: Double,
                     attack: Double, decay: Double, start: Double = 0) -> [Double] {
            var out = [Double](repeating: 0, count: samples(length))
            var phase = 0.0
            for i in 0..<out.count {
                let t = Double(i) / sampleRate - start
                if t < 0 { continue }
                let f = f1.map { f0 + ($0 - f0) * min(1, t / glide) } ?? f0
                phase += 2 * .pi * f / sampleRate
                out[i] = amp * sin(phase) * envelope(t, attack: attack, decay: decay)
            }
            return out
        }

        /// Band-passed noise (a two-pole resonator) shaped by an envelope.
        mutating func noise(_ length: Double, centre: Double, q: Double, amp: Double,
                            attack: Double, decay: Double, start: Double = 0) -> [Double] {
            var out = [Double](repeating: 0, count: samples(length))
            let w = 2 * .pi * centre / sampleRate, alpha = sin(w) / (2 * q)
            let b0 = alpha, b2 = -alpha, a0 = 1 + alpha, a1 = -2 * cos(w), a2 = 1 - alpha
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in 0..<out.count {
                let x = random()
                let y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
                x2 = x1; x1 = x; y2 = y1; y1 = y
                let t = Double(i) / sampleRate - start
                out[i] = t < 0 ? 0 : amp * y * envelope(t, attack: attack, decay: decay)
            }
            return out
        }

        /// A Karplus–Strong pluck, its first 1.5 ms softened.
        mutating func pluck(_ length: Double, f: Double, amp: Double, damping: Double) -> [Double] {
            let period = Int(sampleRate / f)
            var buffer = [Double]()
            buffer.reserveCapacity(period)
            for _ in 0..<period { buffer.append(random()) }
            var out = [Double](repeating: 0, count: samples(length))
            var index = 0
            for i in 0..<out.count {
                let next = (index + 1) % period
                let v = damping * 0.5 * (buffer[index] + buffer[next])
                out[i] = amp * buffer[index]
                buffer[index] = v
                index = next
            }
            let soften = samples(0.0015)
            for i in 0..<min(out.count, soften) { out[i] *= Double(i) / Double(soften) }
            return out
        }
    }

    static func mix(_ parts: [[Double]]) -> [Double] {
        var out = [Double](repeating: 0, count: parts.map(\.count).max() ?? 0)
        for part in parts { for i in 0..<part.count { out[i] += part[i] } }
        return out
    }

    /// One-pole low-pass, to tame harshness.
    static func lowpass(_ x: [Double], cutoff: Double) -> [Double] {
        let a = exp(-2 * .pi * cutoff / sampleRate)
        var y = 0.0
        return x.map { y = (1 - a) * $0 + a * y; return y }
    }

    /// A whisper of room: a few quiet early reflections and a 30 ms tail, so it isn't bone-dry.
    static func room(_ x: [Double], amount: Double = 0.12) -> [Double] {
        let taps: [(delay: Double, gain: Double)] = [(0.0071, 1), (0.0113, 0.7), (0.0173, 0.5), (0.0241, 0.35)]
        var out = x + [Double](repeating: 0, count: samples(0.03))
        for tap in taps {
            let k = samples(tap.delay)
            for i in 0..<x.count { out[i + k] += x[i] * tap.gain * amount }
        }
        return out
    }

    /// DC removal, a 12 ms linear fade at the end, loudness matched to `targetRMSdB` over the
    /// active part, then the peak guard.
    static func finish(_ x: [Double], targetRMSdB: Double) -> [Double] {
        var y = x
        var previousX = 0.0, previousY = 0.0
        for i in 0..<y.count {
            let v = y[i] - previousX + 0.995 * previousY
            previousX = y[i]; previousY = v; y[i] = v
        }
        let fade = samples(0.012)
        for i in 0..<min(fade, y.count) { y[y.count - 1 - i] *= Double(i) / Double(fade) }
        let rms = activeRMS(y)
        guard rms > 0 else { return y }
        let gain = pow(10, targetRMSdB / 20) / rms
        y = y.map { $0 * gain }
        let peak = y.map(abs).max() ?? 0
        if peak > peakLimit { y = y.map { $0 * peakLimit / peak } }
        return y
    }

    /// RMS over the samples above 5 % of the peak (the part you hear, not the silent tail).
    public static func activeRMS(_ x: [Float]) -> Double { activeRMS(x.map(Double.init)) }

    public static func activeRMS(_ x: [Double]) -> Double {
        let peak = x.map(abs).max() ?? 0
        let active = x.filter { abs($0) > peak * 0.05 }
        return sqrt(active.map { $0 * $0 }.reduce(0, +) / Double(max(active.count, 1)))
    }
}
