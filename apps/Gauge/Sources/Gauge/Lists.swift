import GaugeCore
import SlopKit
import SwiftUI

/// The top five apps for a section. Its five rows are always laid out, empty while the first
/// sweeps run, so nothing moves when they fill in.
struct ProcessList: View {
    let title: String
    let unitTitle: String
    let unitHelp: String?
    let rows: [ProcessGroup]
    let ready: Bool
    let sort: ProcessSort
    let selectedRow: Int?
    let radius: CGFloat
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                Text(unitTitle).help(unitHelp ?? "")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, Spacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(0..<PanelMetrics.rowsShown, id: \.self) { index in
                    if index < rows.count, ready || sort == .memory {
                        ProcessRow(group: rows[index], sort: sort, selected: selectedRow == index, radius: radius, actions: actions)
                    } else {
                        Color.clear.frame(height: PanelMetrics.listRowHeight)
                            .accessibilityHidden(true)
                    }
                }
            }
            // Rows' highlights reach a little past the text column, like the overview's.
            .padding(.horizontal, -Spacing.s)
        }
    }
}

struct ProcessRow: View {
    let group: ProcessGroup
    let sort: ProcessSort
    let selected: Bool
    let radius: CGFloat
    let actions: PanelActions
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Button(action: actions.openActivityMonitor) {
            HStack(spacing: Spacing.s) {
                Image(nsImage: IconCache.icon(forApp: group.appPath))
                    .resizable()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.s)
                Text(value)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.s)
            .frame(height: PanelMetrics.listRowHeight)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? Color.selectionTint(activeState, opacity: 0.16) : hovering ? Color.primary.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy") { actions.copy(group, sort: sort) }
                .keyboardShortcut("c")
            Button("Open Activity Monitor") { actions.openActivityMonitor() }
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(spokenValue)
        .accessibilityHint("Opens Activity Monitor")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var name: String {
        group.appPath.map { IconCache.displayName(forApp: $0, fallback: group.name) } ?? group.name
    }

    private var value: String {
        sort == .cpu ? Format.processPercent(group.cpuPercent) : Format.memory(group.memory)
    }

    private var spokenValue: String {
        let count = group.count > 1 ? ", \(group.count) processes" : ""
        return sort == .cpu ? "\(Format.processPercent(group.cpuPercent)) CPU\(count)" : "\(Format.memory(group.memory)) memory\(count)"
    }

    private var help: String {
        var lines = [AppGrouping.copyText(group, sort: sort)]
        if group.isRestricted { lines.append("A system process: memory is its resident size.") }
        return lines.joined(separator: "\n")
    }
}

/// Free space per volume, startup disk first.
struct VolumeList: View {
    let volumes: [VolumeInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Volumes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if volumes.isEmpty {
                Text("No volumes to show.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(volumes.prefix(4)) { volume in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(volume.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Spacing.s)
                        Text("\(Format.disk(volume.available)) free")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    CapacityBar(fraction: volume.usedFraction)
                        .padding(.leading, 16 + Spacing.s)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(volume.name)
                .accessibilityValue("\(Format.disk(volume.available)) free of \(Format.disk(volume.total))")
            }
        }
    }
}

/// How full a volume is: accent until 90%, then orange, red past 95%.
struct CapacityBar: View {
    let fraction: Double

    var body: some View {
        let color: Color = fraction > 0.95 ? .red : fraction > 0.9 ? .orange : .accentColor
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
