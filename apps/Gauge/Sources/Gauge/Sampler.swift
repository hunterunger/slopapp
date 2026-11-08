import Foundation
import GaugeCore
import os

/// What the panel gets each tick: the session's data plus what the system pushed.
struct PanelUpdate: Sendable {
    var data: PanelData
    var volumes: [VolumeInfo]
    var battery: BatteryInfo?
    var network: NetworkInfo?
}

/// Owns the sampling queue, its one timer, and the session. Everything in `session` is touched
/// only on `queue`; results hop to the main actor only when something on screen changes (the
/// menu bar text, or the open panel).
final class Sampler: @unchecked Sendable {
    let queue = DispatchQueue(label: "app.slopapp.gauge.sampling", qos: .utility)
    private let volumeQueue = DispatchQueue(label: "app.slopapp.gauge.volumes", qos: .utility)
    private let psQueue = DispatchQueue(label: "app.slopapp.gauge.ps", qos: .utility)
    private let session: GaugeSession
    private let clock: any MonotonicClock
    private let volumeSource: any VolumeSource
    private let batterySource: any BatterySource
    private let psRunner: (any PSRunner)?
    private let signposter = OSSignposter(subsystem: "app.slopapp.gauge", category: .pointsOfInterest)

    private var timer: DispatchSourceTimer?
    private var scheduledInterval: TimeInterval = 0
    private var lowPowerMode = false
    private var paused = false
    private var lastVolumes: Double = -.infinity
    private var volumesInFlight = false
    private var lastNetworkInfo: Double = -.infinity
    private var networkInfo: NetworkInfo?

    /// Main-actor callbacks.
    private let onMenuBar: @MainActor @Sendable (MenuBarContent) -> Void
    private let onPanel: @MainActor @Sendable (PanelUpdate) -> Void

    /// Tick cost, for `GAUGE_PROBE` and the research doc.
    private(set) var tickDurations: [Double] = []
    var recordsTickDurations = false

    init(session: GaugeSession, clock: any MonotonicClock, volumes: any VolumeSource, battery: any BatterySource,
         ps: (any PSRunner)?, onMenuBar: @escaping @MainActor @Sendable (MenuBarContent) -> Void,
         onPanel: @escaping @MainActor @Sendable (PanelUpdate) -> Void) {
        self.session = session
        self.clock = clock
        volumeSource = volumes
        batterySource = battery
        psRunner = ps
        self.onMenuBar = onMenuBar
        self.onPanel = onPanel
    }

    // MARK: Lifecycle

    func start(lowPowerMode: Bool) {
        queue.async { [self] in
            self.lowPowerMode = lowPowerMode
            session.battery = batterySource.read(details: false)
            session.hasBattery = session.battery != nil
            tick()
            reschedule()
        }
    }

    var hasBattery: Bool { queue.sync { session.hasBattery } }

    private var interval: TimeInterval {
        Cadence.interval(for: session.preferences, panelOpen: session.panelOpen, lowPowerMode: lowPowerMode)
    }

    private func reschedule(firstIn delay: TimeInterval? = nil) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !paused else { return }
        let interval = self.interval
        let leeway = Cadence.leeway(for: interval)
        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.activate()
            self.timer = timer
        }
        timer?.schedule(deadline: .now() + (delay ?? interval), repeating: interval,
                        leeway: .milliseconds(Int(leeway * 1000)))
        scheduledInterval = interval
    }

    private func tick() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !paused else { return }
        let state = signposter.beginInterval("tick")
        let start = recordsTickDurations ? clock.now() : 0
        let now = clock.now()
        let output = session.tick(at: now, interval: interval)
        refreshVolumesIfNeeded(now: now)
        if let content = output.menuBar {
            DispatchQueue.main.async { [onMenuBar] in MainActor.assumeIsolated { onMenuBar(content) } }
        }
        if var panel = output.panel {
            if now - lastNetworkInfo >= 5 {
                networkInfo = session.engine.sources.network.primary()
                lastNetworkInfo = now
            }
            // An empty first sweep (the panel just opened) keeps the rows' space reserved.
            panel.span = session.preferences.historySpan
            let update = PanelUpdate(data: panel, volumes: session.volumes, battery: session.battery, network: networkInfo)
            DispatchQueue.main.async { [onPanel] in MainActor.assumeIsolated { onPanel(update) } }
        }
        if output.wantsPS { runPS() }
        if recordsTickDurations { tickDurations.append(clock.now() - start) }
        signposter.endInterval("tick", state)
    }

    // MARK: Inputs

    func setPreferences(_ preferences: Preferences) {
        queue.async { [self] in
            let rescheduleNeeded = preferences.interval != session.preferences.interval
                || preferences.slowDownInLowPowerMode != session.preferences.slowDownInLowPowerMode
            let needsVolumes = preferences.shows(.disk) && !session.preferences.shows(.disk)
            session.preferences = preferences
            if needsVolumes { lastVolumes = -.infinity; refreshVolumesIfNeeded(now: clock.now()) }
            let content = session.forceMenuBar(at: clock.now(), interval: interval)
            DispatchQueue.main.async { [onMenuBar] in MainActor.assumeIsolated { onMenuBar(content) } }
            if rescheduleNeeded { reschedule() }
        }
    }

    func setLowPowerMode(_ on: Bool) {
        queue.async { [self] in
            guard on != lowPowerMode else { return }
            lowPowerMode = on
            reschedule()
        }
    }

    /// The panel opened or closed. Opening samples at once, again 0.3 s later (so process
    /// CPU appears quickly), then every second; closing drops back to the menu bar cadence.
    func setPanelOpen(_ open: Bool) {
        queue.async { [self] in
            guard open != session.panelOpen else { return }
            session.setPanelOpen(open)
            if open {
                session.battery = batterySource.read(details: true) ?? session.battery
                lastNetworkInfo = -.infinity
                lastVolumes = -.infinity
                tick()
                reschedule(firstIn: 0.3)
            } else {
                reschedule()
            }
        }
    }

    /// The panel's data right now, without waiting for a tick (for the first frame).
    func currentPanelUpdate() -> PanelUpdate {
        queue.sync {
            let data = PanelData(snapshot: session.engine.latest ?? Snapshot(time: clock.now()),
                                 history: Dictionary(uniqueKeysWithValues: Metric.allCases.map { metric in
                                     (metric, session.engine.histories[metric]?.points(span: session.preferences.historySpan,
                                                                                         now: clock.now()) ?? [])
                                 }),
                                 span: session.preferences.historySpan, coreGroups: session.engine.coreGroups,
                                 hasGPU: session.engine.hasGPU)
            return PanelUpdate(data: data, volumes: session.volumes, battery: session.battery, network: networkInfo)
        }
    }

    /// Sleep or display sleep: stop the timer and leave a gap in the history.
    func pause() {
        queue.async { [self] in
            guard !paused else { return }
            paused = true
            timer?.suspend()
            session.pause(at: clock.now())
        }
    }

    /// Awake again: take a baseline now, show real values a second later.
    func resume() {
        queue.async { [self] in
            guard paused else { return }
            paused = false
            session.engine.prime(at: clock.now())
            timer?.resume()
            reschedule(firstIn: 1)
        }
    }

    /// IOPowerSources said something changed.
    func batteryChanged() {
        queue.async { [self] in
            let battery = batterySource.read(details: session.panelOpen)
            guard battery != session.battery else { return }
            session.battery = battery
            if let content = session.externalChange(at: clock.now(), interval: interval) {
                DispatchQueue.main.async { [onMenuBar] in MainActor.assumeIsolated { onMenuBar(content) } }
            }
        }
    }

    /// A volume mounted or unmounted.
    func volumesChanged() {
        queue.async { [self] in
            lastVolumes = -.infinity
            refreshVolumesIfNeeded(now: clock.now())
        }
    }

    // MARK: Volumes and ps, off the sampling queue

    /// Every 30 s while the disk readout or the panel needs it. Reading can block on a network
    /// volume, so it runs on its own queue and never holds up a tick.
    private func refreshVolumesIfNeeded(now: Double) {
        guard session.preferences.shows(.disk) || session.panelOpen, !volumesInFlight, now - lastVolumes >= 30 else { return }
        volumesInFlight = true
        lastVolumes = now
        volumeQueue.async { [self] in
            let volumes = volumeSource.volumes()
            queue.async { [self] in
                volumesInFlight = false
                guard volumes != session.volumes else { return }
                session.volumes = volumes
                if let content = session.externalChange(at: clock.now(), interval: interval) {
                    DispatchQueue.main.async { [onMenuBar] in MainActor.assumeIsolated { onMenuBar(content) } }
                }
            }
        }
    }

    private func runPS() {
        guard psRunner != nil else { return }
        psQueue.async { [self] in
            let rows = psRunner?.run().map(PSParser.parse) ?? []
            queue.async { [self] in session.applyPS(rows, at: clock.now()) }
        }
    }

    // MARK: Probe

    /// Runs `count` ticks back to back with the real sources and returns their durations.
    func probe(count: Int) -> (ticks: [Double], sample: TickOutput?) {
        queue.sync {
            var durations: [Double] = []
            var last: TickOutput?
            for _ in 0..<count {
                let start = clock.now()
                last = session.tick(at: start, interval: 2)
                durations.append(clock.now() - start)
                Thread.sleep(forTimeInterval: 0.05)
            }
            return (durations, last)
        }
    }

    /// Median cost of each source, in milliseconds.
    func probeSources() -> [String: Double] {
        queue.sync {
            let sources = session.engine.sources
            func median(_ body: () -> Void) -> Double {
                var times: [Double] = []
                for _ in 0..<40 {
                    let start = clock.now()
                    body()
                    times.append(clock.now() - start)
                }
                return times.sorted()[times.count / 2] * 1000
            }
            return [
                "cpu": median { _ = sources.cpu.ticks() },
                "memory": median { _ = sources.memory.read() },
                "network": median { _ = sources.network.counters() },
                "gpu": median { _ = sources.gpu.utilization() },
                "disk_io": median { _ = sources.diskIO.counters() },
                "load": median { _ = sources.load.load() },
                "process_sweep": median { _ = session.processes.sweep() },
                "menu_text": median { _ = session.menuBarContent() },
            ]
        }
    }

    func probePanelTick() -> Double {
        queue.sync {
            session.setPanelOpen(true)
            _ = session.tick(at: clock.now(), interval: 1)
            Thread.sleep(forTimeInterval: 0.3)
            let start = clock.now()
            _ = session.tick(at: start, interval: 1)
            let cost = clock.now() - start
            session.setPanelOpen(false)
            return cost
        }
    }
}
