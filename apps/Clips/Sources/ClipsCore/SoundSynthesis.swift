import Foundation

/// Clips' own two sounds, synthesized in code (nothing recorded, bundled or borrowed). The
/// same samples come out every time: the noise is seeded.
///
/// - **Snap** (copy, 0.20 s, peak −18 dBFS): a crisp tick (damped 5.3 kHz sine with a softer
///   1.85 kHz partial and a 1 ms burst of high noise, ~3 ms time constant), near-silence, then
///   from 82 ms a soft airy swish (7–11.5 kHz band-passed noise, 12 ms attack, 40 ms decay).
///   Like a card snapping and sliding into a stack.
/// - **Tock** (paste, 0.08 s, peak −12 dBFS): a soft wooden tock (damped sine gliding from
///   970 down to 880 Hz, 6 ms time constant) with a tiny 2.9 kHz click on top.
///
/// Both are mono, 44.1 kHz, faded in and out, DC-free.
public enum SoundSynthesis {
    public static let sampleRate = 44_100.0

    public struct SnapParameters: Equatable, Sendable {
        public var duration = 0.200
        public var clickStart = 0.002
        public var clickFrequency = 5_300.0
        public var clickDecay = 0.0030
        public var partialFrequency = 1_850.0
        public var partialLevel = 0.45
        public var partialDecay = 0.0045
        public var burstLevel = 0.35
        public var burstDecay = 0.0012
        public var swishStart = 0.082
        public var swishLow = 7_000.0
        public var swishHigh = 11_500.0
        public var swishAttack = 0.012
        public var swishDecay = 0.040
        /// The swish's peak below the tick's.
        public var swishBelowClick = 12.0
        public var peak = -18.0
        public var fadeOut = 0.015
        public init() {}
    }

    public struct TockParameters: Equatable, Sendable {
        public var duration = 0.080
        public var start = 0.001
        public var startFrequency = 970.0
        public var endFrequency = 880.0
        public var glide = 0.012
        public var attack = 0.0012
        public var decay = 0.006
        public var clickFrequency = 2_900.0
        public var clickLevel = 0.18
        public var clickDecay = 0.0007
        public var peak = -12.0
        public var fadeOut = 0.010
        public init() {}
    }

    /// The copy sound.
    public static func snap(_ p: SnapParameters = SnapParameters(), seed: UInt64 = 0x5EED_C11F) -> [Float] {
        let count = Int(p.duration * sampleRate)
        var rng = SplitMix(seed: seed)
        var click = [Double](repeating: 0, count: count)
        var swish = [Double](repeating: 0, count: count)
        var burstFilter = Biquad.highPass(frequency: 4_000, q: 0.7)
        var swishHigh = Biquad.highPass(frequency: p.swishLow, q: 0.7)
        var swishLow = Biquad.lowPass(frequency: p.swishHigh, q: 0.7)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let noise = rng.unit()
            let burstNoise = burstFilter.process(noise)
            let airy = swishLow.process(swishHigh.process(noise))
            let u = t - p.clickStart
            if u >= 0 {
                let attack = raisedCosine(u, over: 0.0006)
                let tone = sin(2 * .pi * p.clickFrequency * u) * exp(-u / p.clickDecay)
                    + p.partialLevel * sin(2 * .pi * p.partialFrequency * u) * exp(-u / p.partialDecay)
                click[i] = attack * (tone + p.burstLevel * burstNoise * exp(-u / p.burstDecay))
            }
            let s = t - p.swishStart
            if s >= 0 {
                let envelope = raisedCosine(s, over: p.swishAttack) * (s < p.swishAttack ? 1 : exp(-(s - p.swishAttack) / p.swishDecay))
                swish[i] = airy * envelope
            }
        }
        let target = pow(10, p.peak / 20)
        let clickPeak = click.map(abs).max() ?? 1
        let swishPeak = swish.map(abs).max() ?? 1
        let swishTarget = target * pow(10, -p.swishBelowClick / 20)
        let mixed = (0..<count).map { click[$0] * target / clickPeak + swish[$0] * swishTarget / swishPeak }
        return finish(mixed, fadeOut: p.fadeOut, peak: target)
    }

    /// The paste sound.
    public static func tock(_ p: TockParameters = TockParameters()) -> [Float] {
        let count = Int(p.duration * sampleRate)
        var samples = [Double](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let u = t - p.start
            guard u >= 0 else { continue }
            let frequency = p.endFrequency + (p.startFrequency - p.endFrequency) * exp(-u / p.glide)
            phase += 2 * .pi * frequency / sampleRate
            let body = sin(phase) * exp(-u / p.decay)
            let click = p.clickLevel * sin(2 * .pi * p.clickFrequency * u) * exp(-u / p.clickDecay)
            samples[i] = raisedCosine(u, over: p.attack) * (body + click)
        }
        let target = pow(10, p.peak / 20)
        let peak = samples.map(abs).max() ?? 1
        return finish(samples.map { $0 * target / peak }, fadeOut: p.fadeOut, peak: target)
    }

    /// Removes DC, fades the tail out, and sets the exact peak.
    private static func finish(_ input: [Double], fadeOut: Double, peak target: Double) -> [Float] {
        var dcBlock = Biquad.highPass(frequency: 30, q: 0.707)
        var samples = input.map { dcBlock.process($0) }
        let fade = Int(fadeOut * sampleRate)
        for k in 0..<min(fade, samples.count) {
            samples[samples.count - 1 - k] *= raisedCosine(Double(k) / sampleRate, over: fadeOut)
        }
        let peak = samples.map(abs).max() ?? 1
        return samples.map { Float($0 * target / max(peak, 1e-12)) }
    }

    /// 0 → 1 along half a cosine over `duration`, then 1.
    static func raisedCosine(_ t: Double, over duration: Double) -> Double {
        guard t < duration else { return 1 }
        guard t > 0 else { return 0 }
        return 0.5 - 0.5 * cos(.pi * t / duration)
    }

    // MARK: - Measuring (tests and the build notes)

    public static func peak(of samples: [Float]) -> Double {
        Double(samples.map(abs).max() ?? 0)
    }

    public static func decibels(_ value: Double) -> Double { 20 * log10(max(value, 1e-9)) }

    /// RMS level in dBFS per `window` seconds.
    public static func envelope(of samples: [Float], window: Double = 0.005) -> [Double] {
        let size = max(1, Int(window * sampleRate))
        return stride(from: 0, to: samples.count, by: size).map { start in
            let slice = samples[start..<min(start + size, samples.count)]
            let power = slice.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(slice.count)
            return decibels(sqrt(power))
        }
    }

    // MARK: - AIFF

    /// 16-bit mono AIFF (what macOS system sounds use).
    public static func aiff(_ samples: [Float], sampleRate: Double = sampleRate) -> Data {
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) } }
        let soundBytes = samples.count * 2
        data.append(contentsOf: Array("FORM".utf8))
        append32(UInt32(4 + 26 + 16 + soundBytes))
        data.append(contentsOf: Array("AIFF".utf8))
        data.append(contentsOf: Array("COMM".utf8))
        append32(18)
        append16(1)
        append32(UInt32(samples.count))
        append16(16)
        data.append(contentsOf: extended80(sampleRate))
        data.append(contentsOf: Array("SSND".utf8))
        append32(UInt32(8 + soundBytes))
        append32(0)
        append32(0)
        for sample in samples {
            let value = Int16(max(-32_767, min(32_767, (Double(sample) * 32_767).rounded())))
            append16(UInt16(bitPattern: value))
        }
        return data
    }

    /// An 80-bit IEEE extended float, as AIFF stores its sample rate.
    static func extended80(_ value: Double) -> [UInt8] {
        guard value > 0 else { return [UInt8](repeating: 0, count: 10) }
        let exponent = Int(floor(log2(value)))
        let mantissa = UInt64(value * pow(2, Double(63 - exponent)))
        let biased = UInt16(16_383 + exponent)
        var bytes: [UInt8] = [UInt8(biased >> 8), UInt8(biased & 0xFF)]
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((mantissa >> UInt64(shift)) & 0xFF)) }
        return bytes
    }
}

/// A second-order filter (RBJ cookbook), direct form I.
struct Biquad {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }

    static func lowPass(frequency: Double, q: Double, sampleRate: Double = SoundSynthesis.sampleRate) -> Biquad {
        let w = 2 * .pi * frequency / sampleRate, alpha = sin(w) / (2 * q), cosw = cos(w), a0 = 1 + alpha
        return Biquad(b0: (1 - cosw) / 2 / a0, b1: (1 - cosw) / a0, b2: (1 - cosw) / 2 / a0, a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }

    static func highPass(frequency: Double, q: Double, sampleRate: Double = SoundSynthesis.sampleRate) -> Biquad {
        let w = 2 * .pi * frequency / sampleRate, alpha = sin(w) / (2 * q), cosw = cos(w), a0 = 1 + alpha
        return Biquad(b0: (1 + cosw) / 2 / a0, b1: -(1 + cosw) / a0, b2: (1 + cosw) / 2 / a0, a1: -2 * cosw / a0, a2: (1 - alpha) / a0)
    }
}

extension SplitMix {
    /// Uniform in −1…1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53) * 2 - 1
    }
}
