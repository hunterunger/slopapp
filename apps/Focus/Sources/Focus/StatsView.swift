import AppKit
import Charts
import FocusCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class StatsState {
    var period: StatsPeriod = .week
    /// Any date inside the period shown.
    var anchor = Date()
    /// Nil: every category. `StatsReport.noCategory`: sessions without one.
    var categoryFilter: String?
    var notesOnly = false
}

/// Totals, a chart and the session log for a day, week or month.
struct StatsView: View {
    let controller: FocusController
    @Bindable var state: StatsState
    var snapshotNow: Date?
    @State private var pendingDelete: SessionRecord?

    private var calendar: Calendar { controller.calendarInUse }

    var body: some View {
        let now = snapshotNow ?? Date()
        let range = StatsRange.containing(state.anchor, period: state.period, calendar: calendar)
        // Reading historyVersion makes the view reload when the log changes.
        let _ = controller.historyVersion
        let report = StatsReport.make(range: range, records: controller.history(), categories: controller.settings.categories,
                                      now: now, calendar: calendar, categoryFilter: state.categoryFilter)
        VStack(spacing: 0) {
            header(range: range, now: now)
            Hairline()
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.m) {
                        SummaryTiles(report: report, unit: controller.unit, calendar: calendar)
                        MoodRow(report: report)
                        DistributionChart(report: report, controller: controller)
                        CategoryTable(report: report, unit: controller.unit)
                    }
                    .padding(Spacing.l)
                }
                .frame(width: 420)
                Hairline(axis: .vertical)
                log(report)
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 760)
        .confirmationDialog("Delete this session?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { record in
            Button("Delete", role: .destructive) { controller.delete(record) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from your stats and exports.")
        }
    }

    private func header(range: StatsRange, now: Date) -> some View {
        HStack(spacing: Spacing.m) {
            Picker("Period", selection: $state.period) {
                ForEach(StatsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            HStack(spacing: Spacing.xs) {
                Button { state.anchor = range.shifted(by: -1, calendar: calendar).start } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous")
                .help("Previous")
                Text(range.title(now: now, calendar: calendar))
                    .font(.headline)
                    .frame(minWidth: 150)
                Button { state.anchor = range.shifted(by: 1, calendar: calendar).start } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next")
                .help("Next")
                .disabled(range.end > now)
            }
            .buttonStyle(.borderless)
            Button("Today") { state.anchor = now }
                .disabled(range.contains(now))
            Spacer()
            Menu {
                Button("All Categories") { state.categoryFilter = nil }
                Divider()
                ForEach(controller.settings.categories) { category in
                    Button { state.categoryFilter = category.id } label: {
                        Label { Text(category.name) } icon: { ColorDot(color: category.color) }
                    }
                }
                Button { state.categoryFilter = StatsReport.noCategory } label: {
                    Label { Text("No Category") } icon: { Image(nsImage: DotImage.make(.systemGray)) }
                }
            } label: {
                Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
            .accessibilityLabel("Filter: \(filterTitle)")
            Toggle("Notes Only", isOn: $state.notesOnly)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    private var filterTitle: String {
        guard let filter = state.categoryFilter else { return "All Categories" }
        if filter == StatsReport.noCategory { return "No Category" }
        return controller.settings.category(id: filter)?.name ?? "All Categories"
    }

    @ViewBuilder
    private func log(_ report: StatsReport) -> some View {
        let records = report.records.filter { !state.notesOnly || !($0.notes ?? "").isEmpty }
        if records.isEmpty {
            ContentUnavailableView("No Sessions", systemImage: "timer",
                                   description: Text(state.notesOnly ? "No sessions with notes in this period." : "Sessions you finish show up here."))
        } else {
            let days = Dictionary(grouping: records) { calendar.startOfDay(for: $0.endedAt) }
            List {
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                        ForEach(days[day] ?? []) { record in
                            SessionRow(record: record, categories: controller.settings.categories, unit: controller.unit)
                                .contextMenu { menu(for: record) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private func menu(for record: SessionRecord) -> some View {
        if record.isFocus {
            Menu("Mood") {
                ForEach(Mood.allCases, id: \.self) { mood in
                    Toggle(mood.title, isOn: Binding(get: { record.mood == mood }, set: { on in
                        var changed = record
                        changed.mood = on ? mood : nil
                        controller.update(changed)
                    }))
                }
            }
            Menu("Category") {
                ForEach(controller.settings.categories) { category in
                    Toggle(category.name, isOn: Binding(get: { record.categoryID == category.id }, set: { _ in
                        var changed = record
                        changed.categoryID = category.id
                        controller.update(changed)
                    }))
                }
            }
            Divider()
        }
        Button("Delete…", role: .destructive) { pendingDelete = record }
    }
}

private struct Tile: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

private struct SummaryTiles: View {
    let report: StatsReport
    let unit: TimeInterval
    let calendar: Calendar

    var body: some View {
        Card {
            Grid(horizontalSpacing: Spacing.m, verticalSpacing: Spacing.l) {
                GridRow {
                    Tile(value: CompactDuration.text(report.totalFocus, unit: unit), title: "Total Focus")
                    Tile(value: "\(report.sessions)", title: report.sessions == 1 ? "Session" : "Sessions")
                    Tile(value: report.mostFocusedHour.map { CompactDuration.hour($0, calendar: calendar) } ?? "–", title: "Most Focused")
                }
                GridRow {
                    Tile(value: CompactDuration.text(report.averagePerDay, unit: unit), title: "Average a Day")
                    Tile(value: CompactDuration.text(report.totalBreak, unit: unit), title: "Total Break")
                    Tile(value: ratio, title: "Focus to Break")
                }
            }
        }
    }

    private var ratio: String {
        guard report.totalBreak > 0 else { return "–" }
        return String(format: "%.1f : 1", report.totalFocus / report.totalBreak)
    }
}

private struct MoodRow: View {
    let report: StatsReport

    var body: some View {
        Card {
            HStack {
                ForEach(Mood.allCases, id: \.self) { mood in
                    VStack(spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: mood.symbol).foregroundStyle(mood.tint)
                            Text("\(report.moods[mood] ?? 0)").font(.title3.monospacedDigit())
                        }
                        Text(mood.title).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Minutes per hour (day) or per day (week, month), stacked by category, with the average.
private struct DistributionChart: View {
    let report: StatsReport
    let controller: FocusController
    @Environment(\.displayScale) private var displayScale

    private struct Bar: Identifiable {
        var start: Date
        var category: String
        var order: Int
        var minutes: Double
        var id: String { "\(start.timeIntervalSince1970)-\(category)" }
    }

    var body: some View {
        let unit = controller.unit
        let shares = report.categories
        let names = shares.map(\.name)
        let colors = shares.map { share -> Color in
            share.id == StatsReport.noCategory ? .gray : (share.color?.color ?? .gray)
        }
        // Stacked in the legend's order on every day (a dictionary's order changed per bar
        // and per launch).
        let bars = report.buckets.flatMap { bucket in
            bucket.seconds.compactMap { key, seconds -> Bar? in
                guard let order = shares.firstIndex(where: { $0.id == key }) else { return nil }
                return Bar(start: bucket.start, category: shares[order].name, order: order, minutes: seconds / unit)
            }
            .sorted { $0.order < $1.order }
        }
        let byDay = report.range.period != .day
        let activeBuckets = report.buckets.filter { $0.start <= Date() }.count
        let average = byDay && activeBuckets > 0 ? report.totalFocus / unit / Double(min(activeBuckets, report.buckets.count)) : nil
        let tallest = report.buckets.map { $0.total / unit }.max() ?? 0
        let axis = ChartAxis.scale(maxMinutes: tallest)
        let isEmpty = report.totalFocus <= 0
        let hairline = 1 / max(displayScale, 1)
        let gridStroke = StrokeStyle(lineWidth: hairline)
        let grid = Color(nsColor: .separatorColor)

        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(byDay ? "Daily Focus" : "Focus by Hour").font(.headline)
                Spacer(minLength: Spacing.s)
                if let average, average > 0 {
                    // The average in the header, not over the bars where it collided with them.
                    HStack(spacing: Spacing.xs) {
                        AverageSwatch()
                        Text("Average \(CompactDuration.text(average * unit, unit: unit))")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value(byDay ? "Day" : "Hour", bar.start, unit: byDay ? .day : .hour),
                            y: .value("Minutes", bar.minutes))
                        .foregroundStyle(by: .value("Category", bar.category))
                        .cornerRadius(Radius.xs)
                        .accessibilityLabel(bar.start.formatted(byDay ? .dateTime.weekday(.wide).month().day() : .dateTime.hour()))
                        .accessibilityValue("\(bar.category), \(CompactDuration.text(bar.minutes * unit, unit: unit))")
                }
                if let average, average > 0 {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .chartForegroundStyleScale(domain: names, range: colors)
            .chartLegend(names.count > 1 ? .visible : .hidden)
            .chartXScale(domain: report.range.start...report.range.end)
            .chartYScale(domain: 0...axis.top)
            .chartYAxis {
                AxisMarks(values: Array(stride(from: 0, through: axis.top, by: axis.step))) { value in
                    AxisGridLine(stroke: gridStroke).foregroundStyle(grid)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text(CompactDuration.text(minutes * unit, unit: unit)).monospacedDigit() }
                    }
                }
            }
            .chartXAxis {
                switch report.range.period {
                case .day:
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine(stroke: gridStroke).foregroundStyle(grid)
                        AxisValueLabel(format: .dateTime.hour())
                    }
                case .week:
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true) }
                case .month:
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(stroke: gridStroke).foregroundStyle(grid)
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.overlay {
                    if isEmpty {
                        Text("No focus time in this period.")
                            .font(.callout)
                            // Explicit: inside a chart `.secondary` resolves against the accent.
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Focus time chart")
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// A short dashed line, the key for the average rule.
private struct AverageSwatch: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0.5))
            path.addLine(to: CGPoint(x: 14, y: 0.5))
        }
        .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .frame(width: 14, height: 1)
        .accessibilityHidden(true)
    }
}

private struct CategoryTable: View {
    let report: StatsReport
    let unit: TimeInterval

    var body: some View {
        Card(title: "Categories") {
            if report.categories.isEmpty {
                Text("No focus time in this period.")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
                    ForEach(report.categories) { share in
                        GridRow {
                            HStack(spacing: Spacing.s) {
                                Circle().fill(share.id == StatsReport.noCategory ? Color.gray : (share.color?.color ?? .gray))
                                    .frame(width: 8, height: 8)
                                Text(share.name).lineLimit(1)
                            }
                            Capsule()
                                .fill(.quaternary)
                                .frame(width: 90, height: 6)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(share.id == StatsReport.noCategory ? Color.gray : (share.color?.color ?? .gray))
                                        .frame(width: max(6, 90 * share.share), height: 6)
                                }
                                .accessibilityHidden(true)
                            Text("\(Int((share.share * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(CompactDuration.text(share.seconds, unit: unit))
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }
}

/// Export… : every session and break as CSV, through a save panel.
@MainActor
enum Exporter {
    static func exportCSV(controller: FocusController) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = CSVExport.fileName(now: Date(), calendar: controller.calendarInUse)
        panel.canCreateDirectories = true
        AppActivation.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(controller: controller, to: url)
    }

    /// Writes the CSV; returns false (after telling the user) if it couldn't.
    @discardableResult
    static func write(controller: FocusController, to url: URL) -> Bool {
        let csv = CSVExport.make(controller.history(), categories: controller.settings.categories)
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            TestHooks.log("exported \(url.path)")
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't export your sessions"
            alert.informativeText = "Check that you can write to that folder and try again."
            alert.runModal()
            return false
        }
    }
}
