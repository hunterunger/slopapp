import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// The menu bar panel: local time in a header card, a line down the list to drag through
/// time, the places, and a footer.
struct PanelView: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            if panel.mode == .search {
                SearchView(model: model, panel: panel, controller: controller)
            } else {
                LocalHeader(model: model, panel: panel, controller: controller)
                if panel.showsCalendar {
                    DateJumpCalendar(model: model, panel: panel)
                }
                ScrubBand(model: model, panel: panel)
                ClockList(model: model, panel: panel, controller: controller)
                PanelMessages(model: model, panel: panel, controller: controller)
                Hairline()
                PanelFooter(model: model, panel: panel, controller: controller)
            }
        }
        .frame(width: PanelMetrics.width)
    }
}

// MARK: - Header

/// Local time as a card: the place and the shown date on the left, a large time and what
/// that time means for you ("Working hours") on the right. Tinted while you're working.
/// When local time is hidden, only the date remains.
struct LocalHeader: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController
    @FocusState private var fieldFocused: Bool
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        if model.preferences.showLocalTime {
            card
        } else {
            HStack {
                DatePill(model: model, panel: panel)
                Spacer()
            }
            .padding(.horizontal, PanelMetrics.margin)
            .padding(.top, Spacing.m)
            .onAppear { forgetFrames() }
        }
    }

    /// The card is gone: its frames mustn't catch clicks meant for the rows.
    private func forgetFrames() {
        panel.rowFrames[ClockRow.localID] = nil
        panel.timeFrames[ClockRow.localID] = nil
    }

    private var row: ClockRow { model.localRow }
    private var isSelected: Bool { model.selection == ClockRow.localID }

    private var card: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.xs) {
                    Text(row.label)
                        .font(.title3)
                        .lineLimit(1)
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Your Mac's time zone")
                        .accessibilityHidden(true)
                    if model.isInMenuBar(ClockRow.localID) {
                        Image(systemName: "menubar.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Shown in the menu bar")
                    }
                }
                DatePill(model: model, panel: panel)
                if let note = row.transitionNote {
                    Label(note, systemImage: "clock.arrow.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                        .labelStyle(CompactLabelStyle())
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                if panel.mode == .editingTime(ClockRow.localID) {
                    TimeEntryField(row: row, panel: panel, controller: controller, focused: $fieldFocused)
                        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
                } else {
                    TimeText(parts: row.timeParts, size: .header)
                        .foregroundStyle(row.activity == .night ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .fixedSize()
                        .reportFrame { panel.timeFrames[ClockRow.localID] = $0 }
                        .help("Click to type a time")
                }
                Label(row.activity.title, systemImage: row.activity.symbol(phase: row.phase))
                    .labelStyle(CompactLabelStyle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Text on the panel's margin; the card itself inset like every filled shape, with
        // corners concentric with the panel's.
        .padding(.horizontal, PanelMetrics.shapeContentPadding)
        .padding(.vertical, Spacing.m)
        .background {
            let shape = RoundedRectangle(cornerRadius: PanelMetrics.shapeRadius, style: .continuous)
            shape.fill(fill)
            if isSelected {
                shape.strokeBorder(Color.selectionRing(activeState).opacity(0.6), lineWidth: 2)
            }
        }
        .padding(.horizontal, PanelMetrics.shapeInset)
        .padding(.top, PanelMetrics.shapeInset)
        .reportFrame { panel.rowFrames[ClockRow.localID] = $0 }
        .onDisappear { forgetFrames() }
        .contextMenu { RowContextMenu(row: row, model: model, panel: panel, controller: controller) }
        .rowAccessibility(row: row, model: model, panel: panel, controller: controller, isSelected: isSelected,
                          editing: true)
    }

    private var fill: AnyShapeStyle {
        switch row.activity {
        case .working: AnyShapeStyle(Color.accentColor.opacity(0.2))
        case .night: AnyShapeStyle(Color.primary.opacity(0.09))
        case .afterHours, .dayOff: AnyShapeStyle(Color.primary.opacity(0.05))
        }
    }
}

/// "Tue, Nov 3 ⌄": shows the shown day and opens a calendar to jump to another one.
struct DatePill: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState

    var body: some View {
        Button {
            panel.showsCalendar.toggle()
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(model.dateText)
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(panel.showsCalendar ? 180 : 0))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .reportFrame { panel.datePillFrame = $0 }
        .help("Go to another day (⌘D)")
        .accessibilityLabel("Shown Date")
        .accessibilityValue(model.formatter.longDate(model.instant, in: model.localTimeZone))
        .accessibilityHint("Opens a calendar to go to another day")
    }
}

/// A month calendar under the header. Picking a day keeps the time of day.
struct DateJumpCalendar: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState

    var body: some View {
        // Fixed to the calendar's width, so Today and Done line up with its edges.
        VStack(spacing: Spacing.s) {
            DatePicker("Go to date", selection: Binding(
                get: { model.instant },
                set: { model.goToDay($0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.timeZone, model.localTimeZone)
            .accessibilityLabel("Go to Date")
            HStack {
                Button("Today") { model.goToDay(model.now) }
                    .disabled(model.formatter.shortDate(model.instant, in: model.localTimeZone)
                              == model.formatter.shortDate(model.now, in: model.localTimeZone))
                Spacer()
                Button("Done") { panel.showsCalendar = false }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.m)
    }
}

// MARK: - Line and chip

/// The chip at the top of the drag line: a hint at rest, how far you've moved once you
/// have (click it to come back to now).
struct ScrubBand: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState

    var body: some View {
        // Only over a list to drag (or to say how far you've moved and get back).
        if model.isScrubbed || model.rows.contains(where: { !$0.isLocal }) { chip }
    }

    private var chip: some View {
        let offset = panel.lineOffset(instant: model.instant)
        return HStack(spacing: Spacing.xs) {
            Group {
                if model.isScrubbed {
                    Text(model.deltaText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Label("Drag sideways to change the time", systemImage: "arrow.left.and.right")
                        .labelStyle(CompactLabelStyle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // For VoiceOver an incrementor: up/down moves 15 minutes, and the value reads
            // "3 hours 15 minutes later, Wednesday, November 4, 3:00 PM".
            .accessibilityRepresentation {
                Stepper("Shown time", onIncrement: { model.step(.quarterHour, by: 1) },
                        onDecrement: { model.step(.quarterHour, by: -1) })
                    .accessibilityValue(model.timeAccessibilityValue)
            }
            if model.isScrubbed {
                Button { model.resetToNow() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .help("Back to now (Esc)")
                .accessibilityLabel("Back to Now")
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule().fill(model.isScrubbed ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.background.opacity(0.4)))
        }
        .hairlineBorder(Capsule())
        .fixedSize()
        .offset(x: offset)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.s)
        .animation(nil, value: offset)
    }
}

// MARK: - List

struct ClockList: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private var maxVisibleRows: Int {
        switch model.preferences.rowStyle {
        case .standard: 8
        case .compact: 14
        case .timeline: 6
        }
    }

    var body: some View {
        // Local time sits in the header.
        let rows = model.rows.filter { !$0.isLocal }
        Group {
            if rows.isEmpty {
                EmptyPlaces(localShown: model.preferences.showLocalTime)
            } else if rows.count > maxVisibleRows {
                ScrollViewReader { proxy in
                    ScrollView {
                        content(rows)
                    }
                    // Half a row more than fits, so the cut-off row says "scroll".
                    .frame(height: (CGFloat(maxVisibleRows) + 0.5) * rowHeight + Spacing.xs)
                    .onChange(of: model.selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            } else {
                content(rows)
            }
        }
        .overlay {
            if !rows.isEmpty { line }
        }
    }

    /// A row and the hairline under it (SlopKit's `Hairline` lays out 1 pt).
    private var rowHeight: CGFloat { PanelMetrics.rowHeight(model.preferences.rowStyle) + 1 }

    private func content(_ rows: [ClockRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ClockRowView(row: row, style: model.preferences.rowStyle, model: model, panel: panel,
                             controller: controller)
                    .id(row.id)
                if index < rows.count - 1 {
                    // Hidden beside a highlighted row (kept for its height), like a list's
                    // separators around a selection.
                    Hairline()
                        .padding(.horizontal, PanelMetrics.rowPadding)
                        .opacity(isHighlighted(rows[index].id) || isHighlighted(rows[index + 1].id) ? 0 : 1)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func isHighlighted(_ id: UUID) -> Bool {
        model.selection == id || model.recentlyAdded == id
    }

    /// The line you drag. It follows the pointer while dragging and springs back after.
    private var line: some View {
        let offset = panel.lineOffset(instant: model.instant)
        let pixel = 1 / max(displayScale, 1)
        let dragging = panel.stripAnchor != nil
        return ZStack {
            // At rest a one-pixel separator, nudged half a pixel so it sits on the pixel grid
            // (centred in an even width it would straddle two pixels and blur).
            Rectangle()
                .fill(dragging ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .separatorColor)))
                .frame(width: dragging ? 2 : pixel)
                .offset(x: dragging ? 0 : pixel / 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(2)
                .background(Circle().fill(.background))
                .opacity(dragging ? 0 : 1)
        }
        .offset(x: offset)
        .animation(panel.stripAnchor == nil && !reduceMotion ? .snappy(duration: 0.2) : nil, value: offset)
        .padding(.top, -2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EmptyPlaces: View {
    let localShown: Bool

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(localShown ? "No other places yet" : "No places to show")
                .font(.headline)
            Text(localShown
                 ? "Add the cities you work with (+ below, or ⌘N) to see their time here."
                 : "Add a place with + below, or show local time again in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }
}

/// Lines under the list: the first-run hint, a removed place with Undo, a note about a
/// typed time, or a typing error. At most a couple at once.
struct PanelMessages: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let error = panel.editError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            if let undo = model.pendingUndo {
                HStack {
                    Text(undo.message)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") { model.undo() }
                        .buttonStyle(.borderless)
                        .help("Undo (⌘Z)")
                }
            }
            if showsHint {
                Label("Add the cities you work with (+ below, or ⌘N) to see their time at a glance.",
                      systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .symbolRenderingMode(.hierarchical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, hasContent ? PanelMetrics.margin : 0)
        .padding(.vertical, hasContent ? Spacing.s : 0)
    }

    private var hasContent: Bool {
        panel.editError != nil || model.notice != nil || model.pendingUndo != nil || showsHint
    }

    /// The first-run hint, only under a list that has rows (an empty list explains itself).
    private var showsHint: Bool {
        model.showsAddHint && model.rows.contains { !$0.isLocal }
    }
}

// MARK: - Footer

/// Add on the left, Copy and the planner in the middle (centred on the panel, under the
/// line), Share and the settings menu on the right. The icons share one size and style and
/// their glyphs sit on the panel's margin.
struct PanelFooter: View {
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        ZStack {
            HStack(spacing: Spacing.xs) {
                FooterIconButton(symbol: "plus", label: "Add Place", help: "Add a city or time zone (⌘N)") {
                    panel.beginSearch()
                }
                Spacer(minLength: 0)
                FooterIconButton(symbol: "square.and.arrow.up", label: "Share",
                                 help: "Share the shown time in every place") {
                    controller.showSharePicker()
                }
                .reportFrame { panel.shareButtonFrame = $0 }
                .disabled(model.isEmpty)
                FooterIconButton(symbol: "gearshape", label: "More", help: "More actions and Settings") {
                    controller.showMoreMenu()
                }
                .reportFrame { panel.moreButtonFrame = $0 }
            }
            HStack(spacing: Spacing.s) {
                Button("Copy") { controller.copyTimes() }
                    .help("Copy the shown time in every place (⌘C)")
                    .accessibilityLabel("Copy Times")
                    .disabled(model.isEmpty)
                Button("Open Planner") { controller.openPlanner() }
                    .help("Plan across a whole day in a window (⌘0)")
            }
        }
        .controlSize(.small)
        // The icon buttons carry `Spacing.xs` of padding around their glyphs.
        .padding(.horizontal, PanelMetrics.margin - Spacing.xs)
        .padding(.vertical, Spacing.s)
    }
}

/// A borderless symbol button with a comfortable hit area around the glyph.
struct FooterIconButton: View {
    let symbol: String
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(minHeight: 16)
                .padding(Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
    }
}
