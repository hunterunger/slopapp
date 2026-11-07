import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// The planner window: every place as a clock card along the top, and below a grid of one
/// day, hour by hour, coloured by working hours, with the hours everyone shares marked.
/// Click an hour (or use ← →) to read it everywhere; ⌘C copies it.
@MainActor
@Observable
final class PlannerState {
    enum Face: String, CaseIterable, Identifiable {
        case analog, digital
        var id: String { rawValue }
        var title: String { self == .analog ? "Analog" : "Digital" }
    }

    /// Any instant on the local day shown in the grid.
    var day: Date
    /// The chosen hour's start, or nil for "now".
    var selection: Date?
    var face: Face {
        didSet { defaults.set(face.rawValue, forKey: "plannerFace") }
    }
    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults`: the app's settings store (the test suite under `ZONES_DEFAULTS_SUITE`).
    init(day: Date, defaults: UserDefaults) {
        self.day = day
        self.defaults = defaults
        face = Face(rawValue: defaults.string(forKey: "plannerFace") ?? "") ?? .analog
    }
}

@MainActor
enum PlannerWindow {
    private static var window: NSWindow?
    private static var state: PlannerState?
    private static var keyMonitor: Any?
    static let identifier = NSUserInterfaceItemIdentifier("planner")

    /// Opens (or brings forward) the planner, on the day of `instant` with its hour chosen.
    static func show(model: ZonesModel, controller: AppController, at instant: Date?) {
        model.refresh()
        if window == nil {
            let state = PlannerState(day: instant ?? model.now, defaults: controller.defaults)
            let hosting = NSHostingController(rootView: PlannerView(model: model, state: state, controller: controller))
            hosting.sizingOptions = []
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.identifier = identifier
            newWindow.title = "Planner"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.contentMinSize = NSSize(width: 640, height: 420)
            newWindow.setContentSize(NSSize(width: 980, height: 600))
            if !newWindow.setFrameUsingName("ZonesPlanner") { newWindow.center() }
            newWindow.setFrameAutosaveName("ZonesPlanner")
            window = newWindow
            self.state = state
            installKeys(model: model, controller: controller)
        }
        if let state {
            // Opened from a moved panel: that day with its hour chosen (the hour it falls
            // in). Otherwise today, now.
            state.day = instant ?? model.now
            let hours = DayPlan.hours(ofDayContaining: state.day, in: model.localTimeZone)
            state.selection = instant.flatMap { DayPlan.index(of: $0, in: hours) }.map { hours[$0] }
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// ← → move the chosen hour, ⌥← ⌥→ the day, Esc goes back to now, ⌘C copies, ⌘T today.
    private static func installKeys(model: ZonesModel, controller: AppController) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let window, event.window === window, let state,
                      !(window.firstResponder is NSText) else { return false }
                let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                let planner = PlannerActions(model: model, state: state, controller: controller)
                switch (event.keyCode, flags) {
                case (KeyCode.left, []): planner.moveSelection(by: -1)
                case (KeyCode.right, []): planner.moveSelection(by: 1)
                case (KeyCode.left, .option): planner.moveDay(by: -1)
                case (KeyCode.right, .option): planner.moveDay(by: 1)
                case (KeyCode.escape, []):
                    if state.selection != nil { state.selection = nil } else { window.performClose(nil) }
                default:
                    guard flags == .command else { return false }
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "c": planner.copy()
                    case "t": planner.goToToday()
                    default: return false
                    }
                }
                return true
            }
            return handled ? nil : event
        }
    }
}

/// What the planner's buttons and keys do.
@MainActor
struct PlannerActions {
    let model: ZonesModel
    let state: PlannerState
    let controller: AppController

    var hours: [Date] { DayPlan.hours(ofDayContaining: state.day, in: model.localTimeZone) }
    var shownInstant: Date { state.selection ?? model.now }
    /// Today, with no hour chosen: "Today" has nothing to do.
    var isShowingNow: Bool { state.selection == nil && DayPlan.index(of: model.now, in: hours) != nil }

    func moveSelection(by delta: Int) {
        let hours = hours
        guard !hours.isEmpty else { return }
        let current = state.selection.flatMap { DayPlan.index(of: $0, in: hours) }
            ?? DayPlan.index(of: model.now, in: hours) ?? (delta > 0 ? -1 : hours.count)
        let next = current + delta
        if next < 0 {
            moveDay(by: -1)
            state.selection = self.hours.last
        } else if next >= hours.count {
            moveDay(by: 1)
            state.selection = self.hours.first
        } else {
            state.selection = hours[next]
        }
    }

    func moveDay(by days: Int) {
        state.day = Scrubbing.step(from: state.day, days: days, local: model.localTimeZone)
        if let selection = state.selection {
            let moved = Scrubbing.step(from: selection, days: days, local: model.localTimeZone)
            let hours = hours
            state.selection = DayPlan.index(of: moved, in: hours).map { hours[$0] } ?? hours.first
        }
    }

    func goToToday() {
        state.day = model.now
        state.selection = nil
    }

    func copy() {
        controller.pasteboard.write(model.timesText(at: shownInstant))
        HUD.show("Copied", systemImage: "doc.on.doc")
    }
}

struct PlannerView: View {
    @Bindable var model: ZonesModel
    @Bindable var state: PlannerState
    let controller: AppController

    private var actions: PlannerActions { PlannerActions(model: model, state: state, controller: controller) }

    var body: some View {
        let shown = actions.shownInstant
        let rows = ClockRows.make(places: model.places, local: model.localTimeZone, showLocal: true, at: shown,
                                  formatter: model.formatter, defaultHours: model.preferences.defaultWorkingHours)
        VStack(spacing: 0) {
            ClockCardStrip(rows: rows, places: model.places, face: state.face, formatter: model.formatter, instant: shown)
            Hairline()
            PlannerGrid(model: model, state: state, rows: rows, actions: actions)
            Hairline()
            PlannerBar(model: model, state: state, rows: rows, actions: actions)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { actions.moveDay(by: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous day (⌥←)")
                    .accessibilityLabel("Previous Day")
                DatePicker("Day", selection: Binding(
                    get: { state.day },
                    set: { state.day = $0; state.selection = nil }
                ), displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, model.localTimeZone)
                .accessibilityLabel("Day")
                Button { actions.moveDay(by: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Next day (⌥→)")
                    .accessibilityLabel("Next Day")
                Button("Today") { actions.goToToday() }
                    .help("Today, now (⌘T)")
                    .disabled(actions.isShowingNow)
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Clock face", selection: $state.face) {
                    ForEach(PlannerState.Face.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Clock style for the cards")
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

// MARK: - Cards

/// Every place as a card: a clock face (or digital time), the name and where it is,
/// coloured by what people there are doing.
struct ClockCardStrip: View {
    let rows: [ClockRow]
    let places: [Place]
    let face: PlannerState.Face
    let formatter: TimeFormatter
    let instant: Date

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) {
                ForEach(rows) { row in
                    ClockCard(row: row, detail: detail(for: row), face: face, instant: instant)
                }
            }
            .padding(Spacing.s)
        }
        // As tall as the cards plus their padding (a fixed height clipped the analog cards).
        .fixedSize(horizontal: false, vertical: true)
        .background(.background.secondary)
    }

    private func detail(for row: ClockRow) -> String {
        if row.isLocal { return "Local time" }
        guard let place = places.first(where: { $0.id == row.id }) else { return "" }
        switch place.kind {
        case .city: return place.detail
        case .utc: return "Coordinated Universal Time"
        case .fixedOffset: return "Fixed offset"
        case .zone: return "Time zone"
        }
    }
}

struct ClockCard: View {
    let row: ClockRow
    let detail: String
    let face: PlannerState.Face
    let instant: Date

    var body: some View {
        VStack(spacing: Spacing.xs) {
            if face == .analog {
                AnalogClock(instant: instant, zone: row.timeZone, activity: row.activity,
                            period: row.timeParts.period)
                    .frame(width: 104, height: 104)
                    .padding(.bottom, Spacing.xs)
            } else {
                TimeText(parts: row.timeParts, size: .card)
                    .foregroundStyle(row.activity.timeStyle)
                    .padding(.vertical, Spacing.xs)
            }
            HStack(spacing: Spacing.xs) {
                Text(row.label)
                    .font(.headline)
                    .lineLimit(1)
                if row.isLocal {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail.isEmpty ? row.subtitle : detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(row.isLocal ? row.activity.title : "\(row.subtitle) · \(row.activity.title)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.m)
        .frame(width: 168)
        .background {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(fill)
        }
        // Local time's card is plain; a hairline keeps it a card in dark mode too.
        .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m, style: .continuous),
                        color: row.isLocal ? Color(nsColor: .separatorColor) : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var fill: AnyShapeStyle {
        if row.isLocal { return AnyShapeStyle(.background) }
        switch row.activity {
        case .working: return AnyShapeStyle(Color.accentColor.opacity(0.22))
        case .night: return AnyShapeStyle(Color.primary.opacity(0.10))
        case .afterHours, .dayOff: return AnyShapeStyle(Color.primary.opacity(0.04))
        }
    }
}

/// A plain clock face: minute ticks, hour and minute hands, and a hub in the accent colour
/// during working hours.
struct AnalogClock: View {
    @Environment(\.controlActiveState) private var activeState
    let instant: Date
    let zone: TimeZone
    let activity: Activity
    let period: String?

    var body: some View {
        let (hour, minute) = TimeMath.wallTime(of: instant, in: zone)
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let face = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(face, with: .color(activity == .night ? Color.primary.opacity(0.06) : Color.primary.opacity(0.02)))
            context.stroke(face, with: .color(Color.primary.opacity(0.25)), lineWidth: 1)
            for tick in 0..<60 {
                let angle = Double(tick) / 60 * 2 * .pi
                let major = tick % 5 == 0
                let outer = radius - 3
                let inner = outer - (major ? 7 : 3)
                var path = Path()
                path.move(to: point(center, inner, angle))
                path.addLine(to: point(center, outer, angle))
                context.stroke(path, with: .color(Color.primary.opacity(major ? 0.7 : 0.3)), lineWidth: major ? 1.5 : 0.75)
            }
            let minuteAngle = Self.minuteAngle(minute)
            let hourAngle = Self.hourAngle(hour, minute)
            // The day period sits under the hands, where they aren't.
            if let period {
                let spot = point(center, radius * 0.42, Self.periodAngle(hour: hourAngle, minute: minuteAngle))
                context.draw(Text(period).font(.caption2).foregroundStyle(.secondary), at: spot)
            }
            hand(context, center, length: radius * 0.5, angle: hourAngle, width: 3.5)
            hand(context, center, length: radius * 0.78, angle: minuteAngle, width: 2)
            let hub = Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
            context.fill(hub, with: activity == .working ? .color(Color.windowAccent(activeState)) : .color(.primary))
        }
        .accessibilityHidden(true)
    }

    static func minuteAngle(_ minute: Int) -> Double { Double(minute) / 60 * 2 * .pi }
    static func hourAngle(_ hour: Int, _ minute: Int) -> Double { (Double(hour % 12) + Double(minute) / 60) / 12 * 2 * .pi }

    /// Where on the dial the "AM"/"PM" goes: below the hub (6 o'clock) like most faces,
    /// unless a hand is there; then above it, or to the side, whichever is furthest from
    /// both hands.
    static func periodAngle(hour: Double, minute: Double) -> Double {
        func distance(_ a: Double, _ b: Double) -> Double {
            let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
            return min(d, 2 * .pi - d)
        }
        let clear = 0.7 // about 40°: the label's half-width at that radius, plus the hand
        let candidates: [Double] = [.pi, 0, .pi * 1.5, .pi * 0.5]
        if let free = candidates.first(where: { distance($0, hour) > clear && distance($0, minute) > clear }) {
            return free
        }
        return candidates.max { min(distance($0, hour), distance($0, minute)) < min(distance($1, hour), distance($1, minute)) } ?? .pi
    }

    private func point(_ center: CGPoint, _ length: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + length * sin(angle), y: center.y - length * cos(angle))
    }

    private func hand(_ context: GraphicsContext, _ center: CGPoint, length: CGFloat, angle: Double, width: CGFloat) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center, length, angle))
        context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

// MARK: - Grid

/// One row per place, one column per hour of the local day. Each cell is that place's
/// time, shaded by working hours; the hours everyone works are marked by a bar on top, the
/// chosen hour by an outline around its whole column, now by a red line.
struct PlannerGrid: View {
    @Environment(\.controlActiveState) private var activeState
    @Bindable var model: ZonesModel
    @Bindable var state: PlannerState
    let rows: [ClockRow]
    let actions: PlannerActions

    /// Column and row pitch. Cells are `gap` smaller, so the space between them is the
    /// same across and down.
    static let cellWidth: CGFloat = 44
    static let rowHeight: CGFloat = 44
    static let gap: CGFloat = Spacing.xs
    static let headerHeight: CGFloat = Spacing.xl
    static let nameWidth: CGFloat = 180
    /// Cells' corners; the chosen column's outline fills the gap around them, so its corners
    /// are the cells' plus half the gap (concentric).
    static let cellRadius: CGFloat = Radius.xs
    static var outlineRadius: CGFloat { cellRadius + gap / 2 }

    var body: some View {
        let hours = actions.hours
        let flags = DayPlan.overlap(hours: hours, places: rows.map { ($0.timeZone, $0.workingHours) })
        let selected = state.selection.flatMap { DayPlan.index(of: $0, in: hours) }
        let nowIndex = DayPlan.index(of: model.now, in: hours)
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Names
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(width: Self.nameWidth - Spacing.l, height: Self.headerHeight)
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(.body).lineLimit(1)
                            Text(row.isLocal ? "Local time" : OffsetText.relative(row.offset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: Self.nameWidth - Spacing.l - Spacing.s, height: Self.rowHeight, alignment: .leading)
                        .padding(.trailing, Spacing.s)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.leading, Spacing.l)
                Hairline(axis: .vertical)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            header(hours: hours, flags: flags)
                            ForEach(rows) { row in
                                HStack(spacing: 0) {
                                    ForEach(hours.indices, id: \.self) { index in
                                        PlannerCell(hour: hours[index], row: row, formatter: model.formatter,
                                                    selected: index == selected)
                                            .onTapGesture { state.selection = hours[index] }
                                            .accessibilityAction { state.selection = hours[index] }
                                    }
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let selected {
                                RoundedRectangle(cornerRadius: Self.outlineRadius, style: .continuous)
                                    .strokeBorder(Color.selectionRing(activeState), lineWidth: Self.gap / 2)
                                    .frame(width: Self.cellWidth, height: CGFloat(rows.count) * Self.rowHeight)
                                    .offset(x: CGFloat(selected) * Self.cellWidth, y: Self.headerHeight)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if let nowIndex {
                                let fraction = model.now.timeIntervalSince(hours[nowIndex]) / 3600
                                NowLine(height: Self.headerHeight + CGFloat(rows.count) * Self.rowHeight,
                                        dotCenter: Self.headerHeight / 2)
                                    .offset(x: (CGFloat(nowIndex) + CGFloat(fraction)) * Self.cellWidth - NowLine.width / 2)
                            }
                        }
                        .padding(.trailing, Spacing.l)
                    }
                    .onAppear { scroll(proxy, to: selected ?? nowIndex ?? 8, animated: false) }
                    .onChange(of: selected) { _, index in if let index { scroll(proxy, to: index, animated: true) } }
                }
            }
            .padding(.vertical, Spacing.s)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Day planner")
    }

    /// The row above the cells: one bar over each run of hours when everyone is working,
    /// ending where its cells end.
    private func header(hours: [Date], flags: [Bool]) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(hours.indices, id: \.self) { index in
                    Color.clear.frame(width: Self.cellWidth, height: Self.headerHeight).id(index)
                }
            }
            ForEach(DayPlan.runs(flags), id: \.lowerBound) { run in
                Capsule()
                    .fill(Color.windowAccent(activeState))
                    .frame(width: CGFloat(run.count) * Self.cellWidth - Self.gap, height: Spacing.xs)
                    .offset(x: CGFloat(run.lowerBound) * Self.cellWidth + Self.gap / 2)
                    .help("Everyone is working")
                    .accessibilityHidden(true)
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to index: Int, animated: Bool) {
        let target = max(0, index - 3)
        if animated {
            withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(target, anchor: .leading) }
        } else {
            proxy.scrollTo(target, anchor: .leading)
        }
    }
}

/// Now in the grid: a red line down every row with a dot in the header, like a calendar's.
struct NowLine: View {
    static let width: CGFloat = 2
    let height: CGFloat
    let dotCenter: CGFloat

    var body: some View {
        let dot = Spacing.s
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.red)
                .frame(width: Self.width, height: height - dotCenter)
                .padding(.top, dotCenter)
            Circle()
                .fill(Color.red)
                .frame(width: dot, height: dot)
                .padding(.top, dotCenter - dot / 2)
        }
        .frame(width: Self.width, height: height, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct PlannerCell: View {
    let hour: Date
    let row: ClockRow
    let formatter: TimeFormatter
    let selected: Bool

    var body: some View {
        let activity = Activity.at(hour, in: row.timeZone, hours: row.workingHours)
        let label = formatter.hourLabel(hour, in: row.timeZone)
        VStack(spacing: 0) {
            Text(label.main)
                .font(.callout.weight(label.main.first?.isLetter == true ? .semibold : .regular))
                .monospacedDigit()
            if let period = label.period {
                Text(period)
                    .font(.caption2.weight(period.first?.isUppercase == true && period.count > 2 ? .semibold : .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(activity == .night ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .frame(width: PlannerGrid.cellWidth - PlannerGrid.gap, height: PlannerGrid.rowHeight - PlannerGrid.gap)
        .background(RoundedRectangle(cornerRadius: PlannerGrid.cellRadius, style: .continuous).fill(activity.cellStyle))
        .frame(width: PlannerGrid.cellWidth, height: PlannerGrid.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label), \(formatter.time(hour, in: row.timeZone)), \(activity.spokenName)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Bottom bar

struct PlannerBar: View {
    @Environment(\.controlActiveState) private var activeState
    @Bindable var model: ZonesModel
    @Bindable var state: PlannerState
    let rows: [ClockRow]
    let actions: PlannerActions

    var body: some View {
        let hours = actions.hours
        let flags = DayPlan.overlap(hours: hours, places: rows.map { ($0.timeZone, $0.workingHours) })
        let overlap = DayPlan.overlapText(hours: hours, flags: flags, local: model.localTimeZone, formatter: model.formatter)
        HStack(spacing: Spacing.m) {
            Label {
                if let overlap {
                    Text("Everyone is working \(overlap)")
                } else {
                    Text("No hour when everyone is working on this day")
                }
            } icon: {
                Image(systemName: overlap == nil ? "person.2.slash" : "person.2.fill")
                    .foregroundStyle(overlap == nil ? Color.secondary : Color.windowAccent(activeState))
            }
            .font(.callout)
            .lineLimit(1)
            Spacer()
            Text(state.selection == nil ? "Now" : model.formatter.shortDate(actions.shownInstant, in: model.localTimeZone)
                 + ", " + model.formatter.time(actions.shownInstant, in: model.localTimeZone))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            // Always there (disabled at now), so the buttons beside it never move.
            Button("Back to Now") { state.selection = nil }
                .help("Back to now (Esc)")
                .disabled(state.selection == nil)
            Button("Copy Times") { actions.copy() }
                .help("Copy the chosen time in every place (⌘C)")
            Button("Add to Calendar…") { actions.controller.addToCalendar(at: actions.shownInstant) }
                .help("Make an hour-long event at the chosen time in your calendar app")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }
}
