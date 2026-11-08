import AppKit
import Darwin
import GaugeCore
import SlopKit

/// Test and review hooks, all read from the environment so a normal launch never sees them:
///
/// - `GAUGE_DEMO=1`: made-up readings (DemoWorld) with an hour of seeded history, so
///   screenshots never show the owner's processes, volumes or network.
/// - `GAUGE_DEFAULTS_SUITE=<name>`: settings in that suite instead of the real ones.
///   `GAUGE_RESET=1` starts from the defaults.
/// - `GAUGE_READOUTS=cpu,memory,network`, `GAUGE_INTERVAL=1|2|5`, `GAUGE_UNITS=bits`,
///   `GAUGE_SPAN=hour`: start with these settings without saving them (perf scenarios B–D).
/// - `GAUGE_SHOW=panel[:memory]|settings|about`: opens that surface after launch.
/// - `GAUGE_PROBE=<file>`: measures one tick, a panel tick and a status item redraw, writes
///   JSON to the file and quits.
/// - `GAUGE_NO_OPEN=1`: "Open Activity Monitor" shows a HUD instead of opening it.
@MainActor
enum ReviewHooks {
    static func isDemo(_ environment: [String: String]) -> Bool { environment["GAUGE_DEMO"] != nil }

    static func applyPreferenceOverrides(to store: PreferencesStore, environment: [String: String]) {
        var preferences = store.preferences
        if let list = environment["GAUGE_READOUTS"] {
            preferences.readouts = list.split(separator: ",").compactMap { Readout(rawValue: String($0)) }
        }
        if let raw = environment["GAUGE_INTERVAL"].flatMap(Int.init), let interval = UpdateInterval(rawValue: raw) {
            preferences.interval = interval
        }
        if environment["GAUGE_UNITS"] == "bits" { preferences.rateUnit = .bits }
        if environment["GAUGE_SPAN"] == "hour" { preferences.historySpan = .hour }
        guard preferences != store.preferences else { return }
        store.isVolatile = true
        store.preferences = preferences
    }

    /// An hour of demo history, so graphs aren't empty in screenshots.
    static func seedHistory(session: GaugeSession, world: DemoWorld, now: Double) {
        session.volumes = DemoWorldVolumes.all
        for step in stride(from: now - 3600, to: now, by: 2) {
            world.setTime(step)
            _ = session.tick(at: step, interval: 2)
        }
        world.setTime(nil)
    }

    static func run(_ environment: [String: String], controller: AppController, sampler: Sampler) {
        if let path = environment["GAUGE_PROBE"] {
            Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                MainActor.assumeIsolated { probe(to: path, controller: controller, sampler: sampler) }
            }
            return
        }
        guard let value = environment["GAUGE_SHOW"] else { return }
        for (index, surface) in value.lowercased().split(separator: ",").enumerated() {
            let parts = surface.split(separator: ":").map(String.init)
            Timer.scheduledTimer(withTimeInterval: 1.2 + Double(index) * 0.8, repeats: false) { _ in
                MainActor.assumeIsolated {
                    switch parts.first {
                    case "panel":
                        if parts.count > 1, let section = PanelSection(rawValue: parts[1]) {
                            controller.panelModel.selection = section
                        }
                        controller.showPanel()
                    case "settings": controller.openSettings()
                    case "about": controller.showAbout()
                    default: break
                    }
                }
            }
        }
    }

    // MARK: Probe

    private static func cpuMilliseconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec) / 1000
        let system = Double(usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_stime.tv_usec) / 1000
        return user + system
    }

    private static func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func probe(to path: String, controller: AppController, sampler: Sampler) {
        let (ticks, _) = sampler.probe(count: 60)
        let sorted = ticks.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] * 1000 }
        let panelTick = sampler.probePanelTick() * 1000
        let perSource = sampler.probeSources()

        // Status item redraws: alternate two contents, compare with the same time idle.
        let item = controller.statusItemForProbe
        let a = MenuBarText.content(for: controller.store.preferences,
                                    values: ReadoutValues(cpu: 0.12, network: ByteRates(down: 1_200_000, up: 40_000)))
        let b = MenuBarText.content(for: controller.store.preferences,
                                    values: ReadoutValues(cpu: 0.37, network: ByteRates(down: 880_000, up: 9_000)))
        // The sampler stops first, so only the redraws are counted.
        sampler.pause()
        spin(1)
        let rounds = 15
        let gap = 1.0
        var start = cpuMilliseconds()
        for _ in 0..<rounds { spin(gap) }
        let idle = cpuMilliseconds() - start
        start = cpuMilliseconds()
        for index in 0..<rounds {
            item.render(index.isMultiple(of: 2) ? a : b)
            spin(gap)
        }
        let redraw = (cpuMilliseconds() - start - idle) / Double(rounds)

        let result: [String: Any] = [
            "tick_p50_ms": percentile(0.5), "tick_p95_ms": percentile(0.95), "tick_max_ms": (sorted.last ?? 0) * 1000,
            "panel_tick_ms": panelTick, "status_redraw_ms": redraw, "idle_spin_ms": idle,
            "readouts": controller.store.preferences.readouts.map(\.rawValue), "sources_ms": perSource,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}

/// The demo's volumes, also seeded before the first refresh.
enum DemoWorldVolumes {
    static let all = [
        VolumeInfo(id: "/", name: "Macintosh HD", available: 412_300_000_000, total: 994_660_000_000, isInternal: true, isBoot: true),
        VolumeInfo(id: "/Volumes/Archive", name: "Archive", available: 1_240_000_000_000, total: 2_000_000_000_000, isInternal: false),
    ]
}
