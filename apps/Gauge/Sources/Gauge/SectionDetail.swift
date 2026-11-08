import GaugeCore
import SlopKit
import SwiftUI

/// The selected section's detail: a headline, a history graph, a few facts, and a list.
struct SectionDetail: View {
    let model: PanelModel
    @Bindable var store: PreferencesStore
    let actions: PanelActions
    let rowRadius: CGFloat

    private var data: PanelData? { model.update?.data }
    private var unit: RateUnit { store.preferences.rateUnit }
    private var now: Double { data?.snapshot.time ?? 0 }
    private var span: HistorySpan { store.preferences.historySpan }
    private var spanBinding: Binding<HistorySpan> { $store.preferences.historySpan }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            switch model.selection {
            case .cpu: cpu
            case .gpu: gpu
            case .memory: memory
            case .network: network
            case .disk: disk
            case .battery: battery
            }
        }
        .padding(.horizontal, PanelMetrics.rowInset * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: CPU

    @ViewBuilder private var cpu: some View {
        let usage = data?.snapshot.cpu
        Headline(value: usage.map { Format.percent($0.total) },
                 caption: usage.map { "User \(Format.percent($0.user))  ·  System \(Format.percent($0.system))" } ?? "Measuring…")
        graph(title: "CPU", metric: .cpu, ceiling: 1) { "Peak \(Format.percent($0))" }
        FactGrid(facts: cpuFacts)
        ProcessList(title: "Apps using the most CPU", unitTitle: "% CPU",
                    unitHelp: "100% is one core working flat out, as in Activity Monitor.",
                    rows: data?.topCPU ?? [], ready: data?.processesReady ?? false, sort: .cpu,
                    selectedRow: model.selectedRow, radius: rowRadius, actions: actions)
    }

    private var cpuFacts: [Fact] {
        var facts: [Fact] = []
        if let usage = data?.snapshot.cpu, let groups = data?.coreGroups, groups.count > 1 {
            for group in CPUMath.grouped(usage.perCore, by: groups).prefix(2) {
                let average = group.values.reduce(0, +) / Double(max(1, group.values.count))
                facts.append(Fact(label: "\(group.name) (\(group.values.count))", value: Format.percent(average)))
            }
        }
        if let load = data?.snapshot.load {
            facts.append(Fact(label: "Load", value: Format.load(load),
                              help: "Processes running or waiting for a core, averaged over 1, 5 and 15 minutes."))
            facts.append(Fact(label: "Uptime", value: Format.uptime(load.uptime)))
        }
        return facts
    }

    // MARK: GPU

    @ViewBuilder private var gpu: some View {
        Headline(value: data?.snapshot.gpu.map { Format.percent($0) }, caption: "How busy the graphics processor is")
        graph(title: "GPU", metric: .gpu, ceiling: 1, height: 150) { "Peak \(Format.percent($0))" }
        Text("macOS doesn't say which apps use the GPU, so there's no list here.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Memory

    @ViewBuilder private var memory: some View {
        let status = data?.snapshot.memory
        Headline(value: status.map { Format.percent($0.pressureFraction) },
                 caption: status.map { "Pressure: \($0.pressure.title)  ·  \(Format.memory($0.used)) of \(Format.memory($0.total)) used" }
                    ?? "Measuring…",
                 captionStyle: status?.pressure == .critical ? .textRed : status?.pressure == .warning ? .textOrange : .secondary,
                 help: "Memory pressure is how hard macOS is working to free memory. Normal means there's room; used memory is always high because macOS keeps files cached.")
        graph(title: "Memory pressure", metric: .memory, ceiling: 1, height: 40) { "Peak \(Format.percent($0))" }
        FactGrid(facts: memoryFacts)
        ProcessList(title: "Apps using the most memory", unitTitle: "Memory", unitHelp: nil,
                    rows: data?.topMemory ?? [], ready: true, sort: .memory,
                    selectedRow: model.selectedRow, radius: rowRadius, actions: actions)
    }

    private var memoryFacts: [Fact] {
        guard let status = data?.snapshot.memory else { return [] }
        var facts = [
            Fact(label: "App", value: Format.memory(status.app)),
            Fact(label: "Wired", value: Format.memory(status.wired)),
            Fact(label: "Compressed", value: Format.memory(status.compressed)),
            Fact(label: "Cached files", value: Format.memory(status.cached),
                 help: "Files macOS keeps in memory to open them faster. It's given up at once when apps need it."),
            Fact(label: "Swap used", value: Format.memory(status.swapUsed)),
        ]
        if let paging = data?.snapshot.paging {
            facts.append(Fact(label: "Swapping", value: "\(Int((paging.swapinsPerSecond + paging.swapoutsPerSecond).rounded()).formatted()) pages/s",
                              help: "Pages moved between memory and disk each second. Steady swapping slows a Mac down."))
        }
        return facts
    }

    // MARK: Network

    @ViewBuilder private var network: some View {
        let rates = data?.snapshot.network
        Headline(value: rates.map { "↓ \(Format.rate($0.down, unit: unit))   ↑ \(Format.rate($0.up, unit: unit))" },
                 caption: "Wi-Fi and Ethernet, all interfaces")
        let down = data?.history[.networkDown] ?? []
        let up = data?.history[.networkUp] ?? []
        HistoryGraph(title: "Network", series: [.init(points: down, color: .accentColor, filled: true),
                                                 .init(points: up, color: .secondary, filled: false)],
                     span: span, now: now, ceiling: Sparkline.rateCeiling([down, up]),
                     summary: "Peak ↓ \(Format.rate(data?.peak(.networkDown) ?? 0, unit: unit))  ↑ \(Format.rate(data?.peak(.networkUp) ?? 0, unit: unit))",
                     height: 96, spanSelection: spanBinding)
        FactGrid(facts: networkFacts, columns: 1)
    }

    private var networkFacts: [Fact] {
        guard let info = model.update?.network else {
            return [Fact(label: "Connection", value: "Not connected")]
        }
        var facts = [Fact(label: "Connection", value: "\(info.kind) (\(info.interface))")]
        facts.append(Fact(label: "IP address", value: info.ipv4 ?? "None", selectable: info.ipv4 != nil))
        if let ipv6 = info.ipv6 { facts.append(Fact(label: "IPv6 address", value: ipv6, selectable: true)) }
        return facts
    }

    // MARK: Disk

    @ViewBuilder private var disk: some View {
        let volumes = model.update?.volumes ?? []
        let boot = volumes.first(where: \.isBoot) ?? volumes.first
        Headline(value: boot.map { "\(Format.disk($0.available)) free" },
                 caption: boot.map { "of \(Format.disk($0.total)) on \($0.name)" } ?? "Reading volumes…")
        let read = data?.history[.diskRead] ?? []
        let write = data?.history[.diskWrite] ?? []
        HistoryGraph(title: "Disk activity", series: [.init(points: read, color: .accentColor, filled: true),
                                                       .init(points: write, color: .secondary, filled: false)],
                     span: span, now: now, ceiling: Sparkline.rateCeiling([read, write]),
                     summary: "Read \(Format.rate(data?.snapshot.disk?.down ?? 0))  ·  Write \(Format.rate(data?.snapshot.disk?.up ?? 0))",
                     height: 40, spanSelection: spanBinding)
        VolumeList(volumes: volumes)
    }

    // MARK: Battery

    @ViewBuilder private var battery: some View {
        let info = model.update?.battery
        Headline(value: info.map { Format.percent(Double($0.percent) / 100) }, caption: info.map(BatteryText.state) ?? "No battery")
        if let info {
            BatteryBar(percent: info.percent, charging: info.source == .powerAdapter)
            FactGrid(facts: BatteryText.facts(info), columns: 1)
        }
    }

    // MARK: Graph

    private func graph(title: String, metric: Metric, ceiling: Double, height: CGFloat = 56,
                       peak: (Double) -> String) -> some View {
        let points = data?.history[metric] ?? []
        let peakValue = data?.peak(metric)
        return HistoryGraph(title: title, series: [.init(points: points, color: .accentColor, filled: true)],
                            span: span, now: now, ceiling: ceiling,
                            summary: peakValue.map(peak) ?? "No history yet", height: height, spanSelection: spanBinding)
    }
}

/// The big number at the top of a detail, and a line under it.
struct Headline: View {
    let value: String?
    let caption: String
    var captionStyle: Color = .secondary
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? MenuBarText.placeholder)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(captionStyle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .help(help ?? "")
    }
}

struct Fact: Identifiable {
    let label: String
    let value: String
    var help: String?
    var selectable = false
    var id: String { label }
}

/// Label–value pairs in one or two columns.
struct FactGrid: View {
    let facts: [Fact]
    var columns = 2

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
            ForEach(Array(stride(from: 0, to: facts.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(facts[start..<min(facts.count, start + columns)]) { fact in
                        FactCell(fact: fact)
                    }
                }
            }
        }
        .font(.callout)
    }
}

struct FactCell: View {
    let fact: Fact

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(fact.label)
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.xs)
            Group {
                if fact.selectable {
                    Text(fact.value).textSelection(.enabled)
                } else {
                    Text(fact.value)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .help(fact.help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fact.label)
        .accessibilityValue(fact.value)
    }
}

/// Battery wording shared by the overview, detail and VoiceOver.
enum BatteryText {
    static func state(_ battery: BatteryInfo) -> String {
        if battery.source == .powerAdapter {
            if battery.isCharged || battery.percent >= 100 { return "Charged" }
            if battery.isCharging {
                return battery.minutesToFull.map { "Charging, \(Format.hoursMinutes($0)) until full" } ?? "Charging"
            }
            return "On power adapter, not charging"
        }
        return battery.minutesToEmpty.map { "On battery, \(Format.hoursMinutes($0)) left" } ?? "On battery, estimating time left"
    }

    static func facts(_ battery: BatteryInfo) -> [Fact] {
        var facts = [Fact(label: "Power source", value: battery.source == .powerAdapter ? "Power adapter" : "Battery")]
        if let watts = battery.adapterWatts { facts.append(Fact(label: "Adapter", value: "\(watts) W")) }
        if let cycles = battery.cycleCount { facts.append(Fact(label: "Cycle count", value: cycles.formatted())) }
        if let health = battery.healthPercent {
            facts.append(Fact(label: "Maximum capacity", value: Format.percent(Double(health) / 100),
                              help: "How much charge the battery holds now compared with when it was new."))
        }
        return facts
    }
}

/// A level bar, green when charging, orange and red as it runs low.
struct BatteryBar: View {
    let percent: Int
    let charging: Bool

    var body: some View {
        let color: Color = charging ? .green : percent <= 10 ? .red : percent <= 20 ? .orange : .accentColor
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(6, proxy.size.width * CGFloat(min(100, max(0, percent))) / 100))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
