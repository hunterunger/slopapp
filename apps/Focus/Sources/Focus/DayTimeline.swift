import FocusCore
import SlopKit
import SwiftUI

/// One block on the day timeline: a logged session or break, or the one running now.
struct TimelineBlock: Identifiable {
    var id: String
    var start: Date
    var end: Date
    var title: String
    var detail: String
    var tint: Color
    var isBreak: Bool
    var isLive: Bool
}

/// Today as a column of hours with each session drawn as a coloured block where it happened,
/// and a line at the current time. Scrolls to the current hour.
struct DayTimeline: View {
    let blocks: [TimelineBlock]
    let day: Date
    let now: Date
    let calendar: Calendar
    var hourHeight: CGFloat = 56

    private let gutter: CGFloat = 44
    /// Room above midnight's line so the "12 AM" label isn't clipped.
    private let topInset: CGFloat = Spacing.s

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hours
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                    if calendar.isDate(now, inSameDayAs: day) {
                        nowLine
                    }
                }
                .frame(height: hourHeight * 24 + topInset * 2)
                .padding(.trailing, Spacing.m)
            }
            .onAppear {
                // After the first layout pass: scrolling before the content has a size does
                // nothing, which left the timeline at midnight.
                let hour = max(0, calendar.component(.hour, from: now) - 3)
                DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }
            }
        }
    }

    private var startOfDay: Date { calendar.startOfDay(for: day) }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(startOfDay) / 3600) * hourHeight + topInset
    }

    private var hours: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Text(hourLabel(hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: gutter - Spacing.s, alignment: .trailing)
                        // Centre the label on its hour line.
                        .alignmentGuide(.top) { $0.height / 2 }
                    Hairline()
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .padding(.top, topInset)
        .accessibilityHidden(true)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func blockView(_ block: TimelineBlock) -> some View {
        let top = y(max(block.start, startOfDay))
        let height = max(Spacing.xs, y(block.end) - top)
        let shape = RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
        // A tinted block with a solid colour edge and primary text, like a calendar event:
        // readable in light and dark mode whatever the category colour (white text on a
        // yellow or green fill isn't).
        return shape
            .fill(block.tint.opacity(block.isBreak ? 0.12 : (block.isLive ? 0.16 : 0.24)))
            .overlay(alignment: .leading) {
                if !block.isBreak {
                    Rectangle().fill(block.tint).frame(width: 3)
                }
            }
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                if height >= 22 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(block.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(block.isBreak ? .secondary : .primary)
                            .lineLimit(1)
                        if height >= 38 {
                            Text(block.detail)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, Spacing.s + (block.isBreak ? 0 : 1))
                    .padding(.trailing, Spacing.s)
                    .padding(.vertical, Spacing.xs)
                }
            }
            .overlay {
                if block.isLive {
                    shape.strokeBorder(block.tint, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .frame(height: height)
            .padding(.leading, gutter)
            .offset(y: top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(block.title), \(block.detail)")
    }

    private static let nowDot: CGFloat = 7

    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle().fill(.red).frame(width: Self.nowDot, height: Self.nowDot)
            Rectangle().fill(.red).frame(height: 1)
        }
        .padding(.leading, gutter - Self.nowDot / 2)
        .offset(y: y(now) - Self.nowDot / 2)
        .accessibilityHidden(true)
    }
}

extension TimelineBlock {
    @MainActor
    static func blocks(for controller: FocusController, now: Date) -> [TimelineBlock] {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        var blocks = controller.todayRecords.map { record -> TimelineBlock in
            let category = controller.settings.category(id: record.categoryID)
            let length = CompactDuration.text(record.focused, unit: controller.unit)
            return TimelineBlock(
                id: record.id, start: record.startedAt, end: record.endedAt,
                title: record.isFocus ? (record.label ?? category?.name ?? "Focus") : "Break",
                detail: "\(record.startedAt.formatted(style)) – \(record.endedAt.formatted(style)) · \(length)",
                tint: record.isFocus ? category.dataTint : .green,
                isBreak: !record.isFocus, isLive: false
            )
        }
        if let run = controller.state.run {
            let end = run.projectedEnd(at: now)
            blocks.append(TimelineBlock(
                id: "live", start: run.startedAt, end: end,
                title: run.phase.isBreak ? "Break" : (run.label ?? "Focusing"),
                detail: "\(run.startedAt.formatted(style)) – \(end.formatted(style))",
                tint: run.phase.isBreak ? .green : controller.category.dataTint,
                isBreak: run.phase.isBreak, isLive: true
            ))
        }
        return blocks
    }
}

/// A row in a session list: colour bar, intention, times, category, length, mood, notes.
struct SessionRow: View {
    let record: SessionRecord
    let categories: [FocusCore.Category]
    let unit: TimeInterval

    var body: some View {
        let category = categories.first { $0.id == record.categoryID }
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        HStack(alignment: .top, spacing: Spacing.s) {
            Capsule()
                .fill(record.isFocus ? category.dataTint : Color.green.opacity(0.4))
                .frame(width: Spacing.xs)
                .frame(minHeight: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    if let mood = record.mood {
                        Image(systemName: mood.symbol)
                            .foregroundStyle(mood.tint)
                            .accessibilityLabel(mood.title)
                    }
                    Text(record.isFocus ? (record.label ?? "Untitled session") : record.kind.title)
                        .font(record.isFocus ? .body.weight(.medium) : .body)
                        .foregroundStyle(record.isFocus ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s)
                    if record.isFocus, let name = category?.name ?? record.categoryName {
                        CategoryTag(name: name, color: category.dataTint)
                    }
                }
                HStack(spacing: Spacing.s) {
                    Text("\(record.startedAt.formatted(style)) → \(record.endedAt.formatted(style))")
                    Spacer()
                    Text(CompactDuration.text(record.focused, unit: unit))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let notes = record.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        // Its own height: the colour bar would otherwise stretch to fill a tall pane.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
