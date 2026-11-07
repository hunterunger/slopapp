import SlopKit
import SwiftUI
import ZonesCore

/// A time with the day period ("PM") set small and raised beside it.
struct TimeText: View {
    enum Size {
        case header, row, compact, card

        var font: Font {
            switch self {
            case .header: .largeTitle.weight(.light)
            case .row: .title.weight(.light)
            case .compact: .title3
            case .card: .title2.weight(.light)
            }
        }

        var periodFont: Font {
            switch self {
            case .header, .row, .card: .caption.weight(.medium)
            case .compact: .caption2.weight(.medium)
            }
        }

        /// How far the period sits above the baseline, roughly cap height minus its own.
        var raise: CGFloat {
            switch self {
            case .header: 13
            case .row: 10
            case .compact: 5
            case .card: 8
            }
        }
    }

    let parts: TimeParts
    let size: Size

    var body: some View {
        let main = Text(parts.main).font(size.font).monospacedDigit()
        if let period = parts.period {
            let small = Text(period).font(size.periodFont).baselineOffset(size.raise)
            parts.periodFirst ? small + Text(" ") + main : main + Text(" ").font(size.periodFont) + small
        } else {
            main
        }
    }
}

extension Activity {
    /// The time's colour: your accent while they're working, dimmed at night.
    var timeStyle: AnyShapeStyle {
        switch self {
        case .working: AnyShapeStyle(.tint)
        case .night: AnyShapeStyle(.secondary)
        case .afterHours, .dayOff: AnyShapeStyle(.primary)
        }
    }

    /// A symbol beside the offset, so the state never depends on colour alone.
    func symbol(phase: DayPhase) -> String {
        switch self {
        case .working: "briefcase.fill"
        case .night: "moon.fill"
        case .afterHours, .dayOff:
            switch phase {
            case .morning: "sunrise.fill"
            case .evening: "sunset.fill"
            default: "sun.max.fill"
            }
        }
    }

    /// Fill for a planner cell: lighter than a strip so the time on it reads well.
    var cellStyle: AnyShapeStyle {
        switch self {
        case .working: AnyShapeStyle(Color.accentColor.opacity(0.35))
        case .afterHours: AnyShapeStyle(Color.primary.opacity(0.10))
        case .dayOff: AnyShapeStyle(Color.primary.opacity(0.06))
        case .night: AnyShapeStyle(Color.primary.opacity(0.025))
        }
    }

    /// Fill for a day strip.
    var bandStyle: AnyShapeStyle {
        switch self {
        case .working: AnyShapeStyle(Color.accentColor.opacity(0.75))
        case .afterHours: AnyShapeStyle(Color.primary.opacity(0.16))
        case .dayOff: AnyShapeStyle(Color.primary.opacity(0.10))
        case .night: AnyShapeStyle(Color.primary.opacity(0.04))
        }
    }
}

/// A thin bar of one place's activity over time: working hours in your accent colour,
/// evenings lighter, nights almost empty; ticks where the place's date changes.
struct DayStripView: View {
    let strip: DayStrip

    var body: some View {
        Canvas { context, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.clip(to: shape)
            context.fill(shape, with: .color(Color.primary.opacity(0.04)))
            for segment in strip.segments {
                let rect = CGRect(x: segment.start * size.width, y: 0,
                                  width: (segment.end - segment.start) * size.width, height: size.height)
                context.fill(Path(rect), with: .style(segment.activity.bandStyle))
            }
            for midnight in strip.midnights {
                let rect = CGRect(x: midnight * size.width - 0.5, y: 0, width: 1, height: size.height)
                context.fill(Path(rect), with: .color(Color.primary.opacity(0.55)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Day toggles (S M T W T F S) for working hours, in the locale's week order.
struct WorkdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let symbols = calendar.veryShortWeekdaySymbols
        let names = calendar.weekdaySymbols
        let order = (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
        HStack(spacing: 2) {
            ForEach(order, id: \.self) { day in
                Toggle(symbols[day - 1], isOn: Binding(
                    get: { days.contains(day) },
                    set: { if $0 { days.insert(day) } else { days.remove(day) } }
                ))
                .toggleStyle(.button)
                .controlSize(.small)
                .accessibilityLabel(names[day - 1])
                .help(names[day - 1])
            }
        }
    }
}

/// Start, end and workdays.
struct WorkingHoursEditor: View {
    @Binding var hours: WorkingHours
    /// Shown under "Hours", when there's something to explain.
    var subtitle: String?

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.s) {
                DatePicker("Start", selection: minutes(\.start), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel("Start")
                Text("to").foregroundStyle(.secondary)
                DatePicker("End", selection: minutes(\.end), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel("End")
            }
        } label: {
            Text("Hours")
            if let subtitle { Text(subtitle) }
        }
        LabeledContent("Workdays") {
            WorkdayPicker(days: $hours.days)
        }
    }

    /// Minutes after midnight as a Date today in UTC, for the time pickers.
    private func minutes(_ keyPath: WritableKeyPath<WorkingHours, Int>) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: TimeInterval((hours[keyPath: keyPath] % 1440) * 60)) },
            set: { date in
                let seconds = Int(date.timeIntervalSince1970) % 86_400
                var minute = ((seconds + 86_400) % 86_400) / 60
                // An end at midnight means the end of the day.
                if keyPath == \WorkingHours.end, minute == 0 { minute = 1440 }
                hours[keyPath: keyPath] = minute
            }
        )
    }
}

extension View {
    /// The pickers above work in UTC so minutes after midnight round-trip exactly.
    func utcTimePickers() -> some View {
        environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
    }
}
