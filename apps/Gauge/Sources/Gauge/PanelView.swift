import GaugeCore
import SlopKit
import SwiftUI

enum PanelMetrics {
    static let overviewRowHeight: CGFloat = 26
    static let menuRowHeight: CGFloat = 22
    static let listRowHeight: CGFloat = 22
    /// Every detail is this tall, so switching sections never resizes the panel.
    static let detailHeight: CGFloat = 328
    static let rowsShown = 5
    /// Rows are inset this far from the panel's edge; their text another `Spacing.s`.
    static let rowInset: CGFloat = Spacing.s
    static let sparklineWidth: CGFloat = 44
}

/// The panel: an overview row per section (pick one with a click, 1–6, ← →), the selected
/// section's detail, the thermal state, and the standard menu rows.
struct PanelView: View {
    @Bindable var model: PanelModel
    @Bindable var store: PreferencesStore
    let actions: PanelActions
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(model.sections.enumerated()), id: \.element) { index, section in
                    OverviewRow(section: section, number: index + 1, model: model, unit: store.preferences.rateUnit,
                                radius: rowRadius)
                }
            }
            .padding(PanelMetrics.rowInset)

            Hairline()

            SectionDetail(model: model, store: store, actions: actions, rowRadius: rowRadius)
                .frame(height: PanelMetrics.detailHeight, alignment: .top)
                .padding(.vertical, Spacing.s)

            Hairline()

            ThermalLine(level: model.thermal)
                .padding(.horizontal, PanelMetrics.rowInset * 2)
                .frame(height: PanelMetrics.menuRowHeight + Spacing.s)

            Hairline()

            VStack(spacing: 0) {
                PanelMenuRow(title: "Open Activity Monitor", shortcut: "↩", radius: rowRadius, action: actions.openActivityMonitor)
                PanelMenuRow(title: "Settings…", shortcut: "⌘,", radius: rowRadius, action: actions.openSettings)
                PanelMenuRow(title: "About \(AppController.shared.info.name)", radius: rowRadius, action: actions.showAbout)
                PanelMenuRow(title: IssueReport.Kind.problem.title, radius: rowRadius, action: actions.reportProblem)
                PanelMenuRow(title: "Quit \(AppController.shared.info.name)", shortcut: "⌘Q", radius: rowRadius, action: actions.quit)
            }
            .padding(PanelMetrics.rowInset)
        }
        .frame(width: PanelController.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Rows inset from the panel's edge stay concentric with it.
    private var rowRadius: CGFloat { Radius.nested(in: panelRadius, padding: PanelMetrics.rowInset) }
}

/// One section in the overview: symbol, name, a small graph and the live value.
struct OverviewRow: View {
    let section: PanelSection
    let number: Int
    let model: PanelModel
    let unit: RateUnit
    let radius: CGFloat
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let selected = model.selection == section
        Button {
            model.selection = section
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? Color.windowAccent(active: true) : Color.secondary)
                    .frame(width: 18)
                Text(section.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: Spacing.s)
                if let points = miniSeries, !points.isEmpty {
                    Sparkline(series: [.init(points: points, color: .accentColor, filled: true)], span: .tenMinutes,
                              now: model.update?.data.snapshot.time ?? 0, ceiling: miniCeiling(points), lineWidth: 1)
                        .frame(width: PanelMetrics.sparklineWidth, height: 14)
                }
                Text(value.text)
                    .monospacedDigit()
                    .foregroundStyle(value.style)
                    .lineLimit(1)
                    .frame(minWidth: valueWidth, alignment: .trailing)
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: PanelMetrics.overviewRowHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(selected ? Color.selectionTint(activeState, opacity: 0.16) : hovering ? Color.primary.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(section.title)
        .accessibilityValue(value.spoken)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Shows details. Press \(number).")
        .help("\(section.title) (\(number))")
    }

    private var data: PanelData? { model.update?.data }

    private var symbol: String {
        section == .battery ? MenuBarText.batterySymbol(model.update?.battery) : section.symbol
    }

    private var valueWidth: CGFloat { section == .network ? 150 : 64 }

    private var miniSeries: [TimeSeries.Point]? {
        switch section {
        case .cpu: data?.history[.cpu]
        case .gpu: data?.history[.gpu]
        case .memory: data?.history[.memory]
        case .network: nil
        case .disk, .battery: nil
        }
    }

    private func miniCeiling(_ points: [TimeSeries.Point]) -> Double { 1 }

    private var value: (text: String, spoken: String, style: Color) {
        let dash = (MenuBarText.placeholder, "not known yet", Color.secondary)
        switch section {
        case .cpu:
            guard let cpu = data?.snapshot.cpu else { return dash }
            return (Format.percent(cpu.total), "\(Format.percentValue(cpu.total)) percent", .primary)
        case .gpu:
            guard let gpu = data?.snapshot.gpu else { return dash }
            return (Format.percent(gpu), "\(Format.percentValue(gpu)) percent", .primary)
        case .memory:
            guard let memory = data?.snapshot.memory else { return dash }
            let style: Color = memory.pressure == .critical ? .textRed : memory.pressure == .warning ? .textOrange : .primary
            let text = memory.pressure == .normal
                ? Format.percent(memory.pressureFraction)
                : "\(memory.pressure.title) \(Format.percent(memory.pressureFraction))"
            return (text, "pressure \(Format.percentValue(memory.pressureFraction)) percent, \(memory.pressure.title)", style)
        case .network:
            guard let rates = data?.snapshot.network else { return dash }
            return ("↓ \(Format.rate(rates.down, unit: unit))  ↑ \(Format.rate(rates.up, unit: unit))",
                    "down \(Format.spokenRate(rates.down, unit: unit)), up \(Format.spokenRate(rates.up, unit: unit))", .primary)
        case .disk:
            guard let boot = model.update?.volumes.first(where: \.isBoot) ?? model.update?.volumes.first else { return dash }
            return ("\(Format.compactDisk(boot.available)) free", "\(Format.disk(boot.available)) free", .primary)
        case .battery:
            guard let battery = model.update?.battery else { return dash }
            let percent = Format.percent(Double(battery.percent) / 100)
            return (percent, "\(battery.percent) percent, \(BatteryText.state(battery))", .primary)
        }
    }
}

/// "Thermal state: Normal", with what it means on hover.
struct ThermalLine: View {
    let level: ThermalLevel

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text("Thermal state")
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.s)
            Text(level.title)
                .foregroundStyle(level == .critical ? .textRed : level == .serious ? .textOrange : .primary)
        }
        .font(.callout)
        .help(level.explanation)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thermal state")
        .accessibilityValue("\(level.title). \(level.explanation)")
    }
}

/// A menu-style row at the bottom of the panel: text only, with its shortcut.
struct PanelMenuRow: View {
    let title: String
    var shortcut: String?
    let radius: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: PanelMetrics.menuRowHeight)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}
