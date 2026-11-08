import Foundation

/// What the panel shows, copied out of the sampling queue once per tick while it's open.
public struct PanelData: Sendable {
    public var snapshot: Snapshot
    public var history: [Metric: [TimeSeries.Point]]
    public var span: HistorySpan
    public var topCPU: [ProcessGroup]
    public var topMemory: [ProcessGroup]
    /// True once two sweeps have run, so CPU percentages exist.
    public var processesReady: Bool
    public var coreGroups: [CoreGroup]
    public var hasGPU: Bool

    public init(snapshot: Snapshot, history: [Metric: [TimeSeries.Point]] = [:], span: HistorySpan = .tenMinutes,
                topCPU: [ProcessGroup] = [], topMemory: [ProcessGroup] = [], processesReady: Bool = false,
                coreGroups: [CoreGroup] = [], hasGPU: Bool = true) {
        self.snapshot = snapshot
        self.history = history
        self.span = span
        self.topCPU = topCPU
        self.topMemory = topMemory
        self.processesReady = processesReady
        self.coreGroups = coreGroups
        self.hasGPU = hasGPU
    }

    /// The peak of a metric's history in the shown span.
    public func peak(_ metric: Metric) -> Double? {
        history[metric]?.lazy.filter { !$0.isGap }.map { Double($0.value) }.max()
    }
}

/// One tick's results: what to draw, if anything.
public struct TickOutput: Sendable {
    /// Non-nil when the menu bar should redraw.
    public var menuBar: MenuBarContent?
    /// Non-nil while the panel is open.
    public var panel: PanelData?
    /// The panel wants a fresh `ps` run for root processes.
    public var wantsPS: Bool
}

/// Ties the engine, the redraw policy and the process tracker together. Not thread-safe:
/// lives on the sampling queue. Everything the system pushes (battery changes, volumes) is
/// handed in with the setters, on the same queue.
public final class GaugeSession {
    public let engine: GaugeEngine
    public let processes: any ProcessSource
    public var preferences: Preferences {
        didSet { if preferences != oldValue { policy.reset() } }
    }
    public var battery: BatteryInfo?
    public var hasBattery: Bool
    public var volumes: [VolumeInfo] = []
    public private(set) var panelOpen = false

    private var policy = RedrawPolicy()
    private var smoother = ReadoutSmoother()
    /// The smoothed values the menu bar shows.
    private var shownValues = ReadoutValues()
    private let tracker = ProcessTracker()
    private var sweeps = 0
    private var lastSweep: Double?
    private var topCPU: [ProcessGroup] = []
    private var topMemory: [ProcessGroup] = []
    /// Seconds between process sweeps while the panel is open.
    public static let sweepInterval: Double = 2
    private var lastPS: Double?
    private var psRuns = 0
    private let appName: String
    private let locale: Locale

    public init(sources: TickSources, processes: any ProcessSource, preferences: Preferences,
                hasBattery: Bool, appName: String = "Gauge", locale: Locale = .autoupdatingCurrent) {
        engine = GaugeEngine(sources: sources)
        self.processes = processes
        self.preferences = preferences
        self.hasBattery = hasBattery
        self.appName = appName
        self.locale = locale
    }

    public var bootVolumeFree: UInt64? {
        (volumes.first(where: \.isBoot) ?? volumes.first)?.available
    }

    /// The menu bar's values: the latest tick, smoothed, with the latest battery and disk.
    private var values: ReadoutValues {
        var values = shownValues
        values.bootVolumeFree = bootVolumeFree
        values.battery = battery
        return values
    }

    public func menuBarContent() -> MenuBarContent {
        MenuBarText.content(for: preferences, values: values, appName: appName, hasBattery: hasBattery,
                            hasGPU: engine.hasGPU, locale: locale)
    }

    /// Reads everything and decides what to redraw.
    public func tick(at now: Double, interval: TimeInterval) -> TickOutput {
        engine.tick(at: now)
        shownValues = smoother.smooth(engine.readoutValues(bootVolumeFree: nil, battery: nil), at: now)
        let content = menuBarContent()
        let values = self.values
        let redraw = policy.shouldRedraw(content, values: values, readouts: preferences.readouts, interval: interval, now: now)

        var panel: PanelData?
        var wantsPS = false
        if panelOpen {
            // Processes: at open, 0.3 s later (so CPU percentages appear at once), then every
            // 2 s. A sweep over a thousand processes is most of the open panel's cost, and a
            // two-second average reads more calmly in a list anyway.
            if sweeps < 2 || lastSweep.map({ now - $0 >= Self.sweepInterval - 0.1 }) ?? true {
                let usages = tracker.update(sweep: processes.sweep(), at: now)
                sweeps += 1
                lastSweep = now
                let groups = AppGrouping.group(usages, byApp: preferences.groupProcessesByApp)
                topCPU = AppGrouping.top(groups, by: .cpu)
                topMemory = AppGrouping.top(groups, by: .memory)
            }
            panel = panelData(now: now)
            // ps fills in root processes: at open, again a second later (so they get CPU
            // percentages), then every 5 s.
            wantsPS = lastPS == nil || (psRuns < 2 && now - lastPS! >= 0.9) || now - lastPS! >= 5
            if wantsPS { lastPS = now }
        }
        return TickOutput(menuBar: redraw ? content : nil, panel: panel, wantsPS: wantsPS)
    }

    /// The menu bar content right now, drawn whatever the policy says (settings changed,
    /// battery changed). Records it as shown.
    public func forceMenuBar(at now: Double, interval: TimeInterval) -> MenuBarContent {
        policy.reset()
        let content = menuBarContent()
        _ = policy.shouldRedraw(content, values: values, readouts: preferences.readouts, interval: interval, now: now)
        return content
    }

    /// Battery or volumes changed: redraw if a shown readout changed.
    public func externalChange(at now: Double, interval: TimeInterval) -> MenuBarContent? {
        let content = menuBarContent()
        return policy.shouldRedraw(content, values: values, readouts: preferences.readouts, interval: interval, now: now)
            ? content : nil
    }

    public func applyPS(_ rows: [PSRow], at now: Double) {
        guard panelOpen else { return }
        tracker.update(ps: rows, at: now)
        psRuns += 1
    }

    public func setPanelOpen(_ open: Bool) {
        guard open != panelOpen else { return }
        panelOpen = open
        tracker.reset()
        sweeps = 0
        lastSweep = nil
        topCPU = []
        topMemory = []
        lastPS = nil
        psRuns = 0
    }

    public func pause(at now: Double) {
        engine.pause(at: now)
        smoother.reset()
        shownValues = ReadoutValues()
        tracker.reset()
        sweeps = 0
        lastSweep = nil
        policy.reset()
    }

    func panelData(now: Double) -> PanelData {
        let span = preferences.historySpan
        var history: [Metric: [TimeSeries.Point]] = [:]
        for metric in Metric.allCases {
            // The widest graph is 288 pt: more points than that only cost diffing and drawing.
            history[metric] = TimeSeries.decimate(engine.histories[metric]?.points(span: span, now: now) ?? [], to: 300)
        }
        return PanelData(snapshot: engine.latest ?? Snapshot(time: now), history: history, span: span,
                         topCPU: topCPU, topMemory: topMemory,
                         processesReady: sweeps >= 2, coreGroups: engine.coreGroups, hasGPU: engine.hasGPU)
    }
}
