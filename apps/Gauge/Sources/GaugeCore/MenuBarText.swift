import Foundation

/// The live values the menu bar can show. Nil means "not known yet" (shown as an en dash).
public struct ReadoutValues: Sendable, Equatable {
    public var cpu: Double?
    public var gpu: Double?
    public var memoryPressure: Double?
    public var network: ByteRates?
    public var bootVolumeFree: UInt64?
    public var battery: BatteryInfo?

    public init(cpu: Double? = nil, gpu: Double? = nil, memoryPressure: Double? = nil, network: ByteRates? = nil,
                bootVolumeFree: UInt64? = nil, battery: BatteryInfo? = nil) {
        self.cpu = cpu
        self.gpu = gpu
        self.memoryPressure = memoryPressure
        self.network = network
        self.bootVolumeFree = bootVolumeFree
        self.battery = battery
    }
}

/// What the status item draws: a row of segments, each an optional symbol and text fields.
/// Every field carries the widest strings it can ever show, so the UI sizes a fixed slot for
/// it once and the item never changes width (or pushes other menu bar items around).
public struct MenuBarContent: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public var text: String
        /// Every shape this field can take; the slot is as wide as the widest.
        public var candidates: [String]

        public init(_ text: String, candidates: [String]) {
            self.text = text
            self.candidates = candidates
        }
    }

    public struct Segment: Sendable, Equatable {
        public var readout: Readout
        public var symbol: String?
        public var fields: [Field]

        public init(readout: Readout, symbol: String?, fields: [Field]) {
            self.readout = readout
            self.symbol = symbol
            self.fields = fields
        }
    }

    public var segments: [Segment]
    /// What VoiceOver reads: "Gauge, CPU 12 percent, network down 1.2 megabytes per second…"
    public var accessibilityLabel: String

    /// Only what's drawn; two contents with the same text draw the same pixels.
    public var drawnText: String {
        segments.map { ($0.symbol ?? "") + "|" + $0.fields.map(\.text).joined(separator: " ") }.joined(separator: "  ")
    }

    /// A key for the slot widths: changes only when the layout (not the values) changes.
    public var layoutKey: String {
        segments.map { segment in
            segment.readout.rawValue + ":" + segment.fields.map { $0.candidates.joined(separator: ",") }.joined(separator: ";")
        }.joined(separator: "|")
    }
}

public enum MenuBarText {
    public static let placeholder = "–"

    public static func content(for preferences: Preferences, values: ReadoutValues, appName: String = "Gauge",
                               hasBattery: Bool = true, hasGPU: Bool = true,
                               locale: Locale = .autoupdatingCurrent) -> MenuBarContent {
        var segments: [MenuBarContent.Segment] = []
        var spoken: [String] = [appName]
        let percentCandidates = [Format.percent(1, locale: locale), Format.percent(0.88, locale: locale), placeholder]

        for readout in preferences.readouts {
            switch readout {
            case .cpu, .gpu, .memory:
                if readout == .gpu, !hasGPU { continue }
                let value = readout == .cpu ? values.cpu : readout == .gpu ? values.gpu : values.memoryPressure
                let text = value.map { Format.percent($0, locale: locale) } ?? placeholder
                segments.append(.init(readout: readout, symbol: readout.symbol,
                                      fields: [.init(text, candidates: percentCandidates)]))
                let name = readout == .cpu ? "CPU" : readout == .gpu ? "GPU" : "memory pressure"
                spoken.append(value.map { "\(name) \(Format.percentValue($0)) percent" } ?? "\(name) not known yet")

            case .network:
                let rates = values.network
                let candidates = Format.rateCandidates(unit: preferences.rateUnit, locale: locale)
                let down = rates.map { Format.rate($0.down, unit: preferences.rateUnit, locale: locale) } ?? placeholder
                let up = rates.map { Format.rate($0.up, unit: preferences.rateUnit, locale: locale) } ?? placeholder
                segments.append(.init(readout: .network, symbol: nil, fields: [
                    .init("↓ " + down, candidates: (candidates + [placeholder]).map { "↓ " + $0 }),
                    .init("↑ " + up, candidates: (candidates + [placeholder]).map { "↑ " + $0 }),
                ]))
                if let rates {
                    spoken.append("network down \(Format.spokenRate(rates.down, unit: preferences.rateUnit, locale: locale)), "
                        + "up \(Format.spokenRate(rates.up, unit: preferences.rateUnit, locale: locale))")
                } else {
                    spoken.append("network not known yet")
                }

            case .disk:
                let text = values.bootVolumeFree.map { Format.compactDisk($0, locale: locale) } ?? placeholder
                segments.append(.init(readout: .disk, symbol: readout.symbol, fields: [
                    .init(text, candidates: Format.compactDiskCandidates(locale: locale) + [placeholder]),
                ]))
                spoken.append(values.bootVolumeFree.map { "\(Format.disk($0, locale: locale)) free on the startup disk" }
                              ?? "disk not known yet")

            case .battery:
                guard hasBattery else { continue }
                let battery = values.battery
                let text = battery.map { Format.percent(Double($0.percent) / 100, locale: locale) } ?? placeholder
                segments.append(.init(readout: .battery, symbol: batterySymbol(battery),
                                      fields: [.init(text, candidates: percentCandidates)]))
                if let battery {
                    let state = battery.isCharging ? ", charging" : battery.source == .powerAdapter ? ", on power adapter" : ""
                    spoken.append("battery \(battery.percent) percent\(state)")
                } else {
                    spoken.append("battery not known yet")
                }
            }
        }
        return MenuBarContent(segments: segments, accessibilityLabel: spoken.joined(separator: ", "))
    }

    /// The battery symbol for a level: full, three quarters, half, a quarter, empty; with a
    /// bolt while on the power adapter.
    public static func batterySymbol(_ battery: BatteryInfo?) -> String {
        guard let battery else { return "battery.100percent" }
        if battery.source == .powerAdapter { return "battery.100percent.bolt" }
        switch battery.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

/// Decides when the menu bar redraws.
///
/// Reading the counters costs about 0.2 ms; redrawing the status item costs 6–12 ms of CPU on
/// macOS 27 (AppKit re-renders the item into a bitmap for the menu bar every time it changes;
/// measured in docs/research/gauge.md). So the menu bar only redraws when what it shows
/// changes enough to matter, or when a small change has waited long enough. Big changes
/// (a CPU spike, a download starting) appear on the next tick; idle jitter (CPU wobbling
/// between 4% and 6%) is shown at most every `settleSeconds`.
public struct RedrawPolicy: Sendable {
    /// Percent readouts: a change of at least this many points shows at once. Smaller ones
    /// are the jitter of a Mac at rest (4%, 7%, 5%…) and wait.
    public var percentStep: Int = 5
    /// GPU utilisation jumps around with every animation on screen, so it needs a bigger
    /// change to redraw at once.
    public var gpuStep: Int = 10
    /// Rates: a change by at least this factor shows at once…
    public var rateFactor: Double = 2
    /// …unless both values are under this (background chatter of a few KB/s, which
    /// wobbles by large factors every second), or it's a change to or from 0.
    public var rateFloor: Double = 100_000

    private var shown: ReadoutValues?
    private var shownText: String?
    private var shownLayout: String?
    private var shownAt: Double = -.infinity

    public init() {}

    /// How long a small change may wait: 20 s, 30 s at the 5 s interval (Low Power Mode),
    /// 10 s for people who chose 1 s updates. Each redraw costs 10–17 ms of CPU on macOS 27, so
    /// at rest this is what sets Gauge's cost.
    public static func settleSeconds(for interval: TimeInterval) -> TimeInterval {
        interval <= 1 ? 10 : interval >= 5 ? 30 : 20
    }

    /// True if `content` should be drawn now; records it as shown when it is.
    public mutating func shouldRedraw(_ content: MenuBarContent, values: ReadoutValues, readouts: [Readout],
                                      interval: TimeInterval, now: Double) -> Bool {
        let text = content.drawnText
        if text == shownText { return false }
        let redraw = shownText == nil || content.layoutKey != shownLayout
            || isSignificant(from: shown, to: values, readouts: readouts)
            || now - shownAt >= Self.settleSeconds(for: interval)
        if redraw {
            shown = values
            shownText = text
            shownLayout = content.layoutKey
            shownAt = now
        }
        return redraw
    }

    /// Forget what's shown, so the next content draws (after sleep, or a settings change).
    public mutating func reset() {
        shown = nil
        shownText = nil
        shownLayout = nil
        shownAt = -.infinity
    }

    func isSignificant(from old: ReadoutValues?, to new: ReadoutValues, readouts: [Readout]) -> Bool {
        guard let old else { return true }
        for readout in readouts {
            switch readout {
            case .cpu: if percentChanged(old.cpu, new.cpu) { return true }
            case .gpu: if percentChanged(old.gpu, new.gpu, step: gpuStep) { return true }
            case .memory: if percentChanged(old.memoryPressure, new.memoryPressure) { return true }
            case .network:
                switch (old.network, new.network) {
                case (nil, nil): break
                case let (before?, after?):
                    if rateChanged(before.down, after.down) || rateChanged(before.up, after.up) { return true }
                default: return true
                }
            // Rare, slow-moving values: any visible change shows.
            case .disk: if old.bootVolumeFree != new.bootVolumeFree { return true }
            case .battery: if old.battery?.percent != new.battery?.percent || old.battery?.source != new.battery?.source { return true }
            }
        }
        return false
    }

    private func percentChanged(_ old: Double?, _ new: Double?, step: Int? = nil) -> Bool {
        switch (old, new) {
        case (nil, nil): return false
        case let (old?, new?): return abs(Format.percentValue(old) - Format.percentValue(new)) >= (step ?? percentStep)
        default: return true
        }
    }

    private func rateChanged(_ old: Double, _ new: Double) -> Bool {
        let idle = 1000.0 // below 1 KB/s reads as 0
        if (old < idle) != (new < idle) { return max(old, new) >= rateFloor }
        if max(old, new) < rateFloor { return false }
        let ratio = max(old, new) / max(min(old, new), idle)
        return ratio >= rateFactor
    }
}

/// Averages what the menu bar shows over the last few seconds (an exponential moving
/// average, 4 s time constant), so it reads calmly: a busy upload that flips between 0 and
/// 700 KB/s every second reads as a steady rate, and CPU wobble doesn't flicker. A big change
/// jumps straight there instead of ramping (CPU or GPU by 15 points either way, a rate
/// tripling past 100 KB/s), so it shows at once and in one redraw; rates always ease down,
/// so a finished download fades instead of flickering. The panel shows the instant values.
public struct ReadoutSmoother: Sendable {
    public var timeConstant: Double = 4

    private var cpu: Double?
    private var gpu: Double?
    private var down: Double?
    private var up: Double?
    private var lastTime: Double?

    public init() {}

    public mutating func smooth(_ values: ReadoutValues, at now: Double) -> ReadoutValues {
        let weight = lastTime.map { 1 - exp(-max(0, now - $0) / timeConstant) } ?? 1
        lastTime = now
        func blend(_ old: inout Double?, _ new: Double?, jumps: (Double, Double) -> Bool) -> Double? {
            guard let new else { return old }
            if let previous = old, !jumps(previous, new) {
                old = previous + (new - previous) * weight
            } else {
                old = new
            }
            return old
        }
        let percentJump: (Double, Double) -> Bool = { old, new in abs(new - old) >= 0.15 }
        let rateJump: (Double, Double) -> Bool = { old, new in new >= 100_000 && new >= max(old, 1000) * 3 }
        var result = values
        result.cpu = blend(&cpu, values.cpu, jumps: percentJump)
        result.gpu = blend(&gpu, values.gpu, jumps: percentJump)
        if let rates = values.network {
            result.network = ByteRates(down: blend(&down, rates.down, jumps: rateJump) ?? rates.down,
                                       up: blend(&up, rates.up, jumps: rateJump) ?? rates.up)
        }
        return result
    }

    /// After sleep: start over from the next reading.
    public mutating func reset() {
        self = ReadoutSmoother()
    }
}
