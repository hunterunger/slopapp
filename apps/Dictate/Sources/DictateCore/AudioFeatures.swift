import Foundation
import Accelerate
import os

/// Live descriptors of the voice, used only to animate the recording ring.
public struct AudioFeatures: Sendable, Equatable {
    /// Increments once per analysed window, so consumers can apply one-shot
    /// events (onsets) exactly once.
    public var index: Int = 0
    /// Loudness, 0...1 on a dB scale.
    public var level: Float = 0
    /// Pitch relative to the speaker's recent baseline, -1...1 (≈ ±6 semitones).
    /// Held (and slowly relaxed) through unvoiced sounds and pauses.
    public var pitch: Float = 0
    public var voiced = false
    /// Spectral centroid, 0 (dark vowels) ... 1 (sibilants).
    public var brightness: Float = 0
    /// Strength of a syllable attack in this window, 0 when there isn't one.
    public var onset: Float = 0
    /// Seven log-spaced band energies (low → high) in lanes 0...6, scaled by level.
    public var bands = SIMD8<Float>()

    public init() {}
}

/// Streaming analysis of 16 kHz mono audio: a 1024-sample window every 512
/// samples (32 ms). All buffers are allocated once; the per-window cost is one
/// real FFT plus, only while there is sound, a YIN pitch search.
public final class FeatureExtractor {
    private static let n = 1024
    private static let hop = 512
    private static let log2n: vDSP_Length = 10
    private static let sampleRate: Float = 16_000
    private static let binHz = sampleRate / Float(n)
    /// YIN searches 70–500 Hz over a 512-sample integration window.
    private static let yinWindow = 512
    private static let minLag = Int(sampleRate / 500)
    private static let maxLag = Int(sampleRate / 70)

    private static let signposter = OSSignposter(subsystem: "app.slopapp.dictate", category: "AudioFeatures")

    private let fftSetup: FFTSetup
    private let samples = UnsafeMutableBufferPointer<Float>.allocate(capacity: n)
    private let hann = UnsafeMutableBufferPointer<Float>.allocate(capacity: n)
    private let windowed = UnsafeMutableBufferPointer<Float>.allocate(capacity: n)
    private let real = UnsafeMutableBufferPointer<Float>.allocate(capacity: n / 2)
    private let imag = UnsafeMutableBufferPointer<Float>.allocate(capacity: n / 2)
    private let mags = UnsafeMutableBufferPointer<Float>.allocate(capacity: n / 2)
    private let prevMags = UnsafeMutableBufferPointer<Float>.allocate(capacity: n / 2)
    private let binRamp = UnsafeMutableBufferPointer<Float>.allocate(capacity: n / 2)
    private let yin = UnsafeMutableBufferPointer<Float>.allocate(capacity: maxLag + 2)
    private let bandEdges: [Int]

    private var filled = 0
    private var index = 0
    private var fluxMean: Float = 0
    private var lastOnset = -10
    private var baseline: Float?
    private var pitch: Float = 0

    public init() {
        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(hann.baseAddress!, vDSP_Length(Self.n), Int32(vDSP_HANN_NORM))
        for i in 0..<Self.n / 2 { binRamp[i] = Float(i) }
        prevMags.initialize(repeating: 0)
        samples.initialize(repeating: 0)

        // 8 edges → 7 bands, log-spaced from 90 Hz to 6 kHz.
        var edges: [Int] = []
        for k in 0...7 {
            let hz = 90 * pow(6000 / 90, Float(k) / 7)
            let bin = Int(hz / Self.binHz)
            edges.append(max(bin, (edges.last ?? 0) + 1))
        }
        bandEdges = edges
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        for buffer in [samples, hann, windowed, real, imag, mags, prevMags, binRamp, yin] {
            buffer.deallocate()
        }
    }

    /// Feed new samples; `emit` is called once per completed window.
    public func consume(_ input: UnsafePointer<Float>, count: Int, emit: (AudioFeatures) -> Void) {
        var i = 0
        while i < count {
            let take = min(Self.n - filled, count - i)
            (samples.baseAddress! + filled).update(from: input + i, count: take)
            filled += take
            i += take
            if filled == Self.n {
                emit(analyze())
                // Keep the newest half: windows overlap by 50%.
                memmove(samples.baseAddress!, samples.baseAddress! + Self.hop, (Self.n - Self.hop) * MemoryLayout<Float>.size)
                filled = Self.n - Self.hop
            }
        }
    }

    private func analyze() -> AudioFeatures {
        let interval = Self.signposter.beginInterval("analyze")
        defer { Self.signposter.endInterval("analyze", interval) }

        index += 1
        let x = samples.baseAddress!
        let half = vDSP_Length(Self.n / 2)
        var features = AudioFeatures()
        features.index = index

        // Loudness from the newest hop, for responsiveness.
        var rms: Float = 0
        vDSP_rmsqv(x + (Self.n - Self.hop), 1, &rms, vDSP_Length(Self.hop))
        let level = min(1, max(0, (20 * log10(max(rms, 1e-6)) + 55) / 40))
        features.level = level

        // Magnitude spectrum.
        vDSP_vmul(x, 1, hann.baseAddress!, 1, windowed.baseAddress!, 1, vDSP_Length(Self.n))
        var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
        windowed.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.n / 2) {
            vDSP_ctoz($0, 2, &split, 1, half)
        }
        vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
        imag[0] = 0 // packed Nyquist term; not needed
        vDSP_zvabs(&split, 1, mags.baseAddress!, 1, half)
        mags[0] = 0

        var total: Float = 0
        vDSP_sve(mags.baseAddress!, 1, &total, half)

        // Brightness: spectral centroid mapped 300 Hz → 0, 4 kHz → 1 (log).
        if total > 1e-4 {
            var weighted: Float = 0
            vDSP_dotpr(mags.baseAddress!, 1, binRamp.baseAddress!, 1, &weighted, half)
            let centroid = max(1, weighted / total * Self.binHz)
            features.brightness = min(1, max(0, log2(centroid / 300) / log2(4000 / 300)))
        }

        // Onsets: rectified spectral flux against its running mean.
        var flux: Float = 0
        for k in 1..<Self.n / 2 {
            let d = mags[k] - prevMags[k]
            if d > 0 { flux += d }
        }
        prevMags.baseAddress!.update(from: mags.baseAddress!, count: Self.n / 2)
        flux /= total + 1e-3
        if level > 0.2, flux > fluxMean * 1.6 + 0.04, index - lastOnset >= 3 {
            features.onset = min(1, (flux - fluxMean) * 3)
            lastOnset = index
        }
        fluxMean = fluxMean * 0.9 + flux * 0.1

        // Bands: shape relative to the loudest band, scaled by loudness.
        var peak: Float = 1e-6
        var bands = SIMD8<Float>()
        for b in 0..<7 {
            let lo = bandEdges[b], hi = bandEdges[b + 1]
            var mean: Float = 0
            vDSP_meanv(mags.baseAddress! + lo, 1, &mean, vDSP_Length(hi - lo))
            bands[b] = mean
            peak = max(peak, mean)
        }
        for b in 0..<7 { bands[b] = (bands[b] / peak).squareRoot() * level }
        features.bands = bands

        // Pitch: skipped entirely in silence, which is most of the time.
        if level > 0.15, let f0 = detectPitch() {
            let semitones = 12 * log2(f0 / 440)
            let base = baseline ?? semitones
            baseline = base + (semitones - base) * 0.02
            pitch = min(1, max(-1, (semitones - base) / 6))
            features.voiced = true
        } else {
            pitch *= 0.97
        }
        features.pitch = pitch
        return features
    }

    /// YIN fundamental-frequency estimate, or nil when the frame isn't
    /// clearly periodic.
    private func detectPitch() -> Float? {
        let x = samples.baseAddress!
        let w = vDSP_Length(Self.yinWindow)
        let maxLag = Self.maxLag

        // Difference function d(τ), then its cumulative-mean normalisation.
        yin[0] = 1
        var running: Float = 0
        for tau in 1...maxLag {
            var d: Float = 0
            vDSP_distancesq(x, 1, x + tau, 1, &d, w)
            running += d
            yin[tau] = running > 0 ? d * Float(tau) / running : 1
        }

        var tau = -1
        var t = Self.minLag
        while t < maxLag {
            if yin[t] < 0.15 {
                while t + 1 < maxLag, yin[t + 1] < yin[t] { t += 1 }
                tau = t
                break
            }
            t += 1
        }
        guard tau > Self.minLag, tau < maxLag else { return nil }

        // Parabolic interpolation around the minimum.
        let a = yin[tau - 1], b = yin[tau], c = yin[tau + 1]
        let denom = a - 2 * b + c
        let refined = Float(tau) + (abs(denom) > 1e-6 ? (a - c) / (2 * denom) : 0)
        return Self.sampleRate / refined
    }
}
