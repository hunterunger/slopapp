import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// Sizes shared by the panel's pieces. The drag line runs down the middle of the list, so
/// names keep to the left half and times to the right.
///
/// One leading/trailing edge for everything: the header's text, row names and times, the
/// search field and results, messages and the footer's icons all sit `margin` from the
/// panel's sides. Filled shapes (the header card, a selected row, the search highlight) sit
/// `shapeInset` from the sides, with corners concentric with the panel's.
enum PanelMetrics {
    /// Wider than SlopKit's 320 pt menu bar window: two columns either side of the line.
    static let width: CGFloat = 360
    /// Where text and icons start and end, from the panel's sides.
    static let margin: CGFloat = Spacing.xl
    /// Where filled shapes start, from the panel's sides (and the card from its top).
    static let shapeInset: CGFloat = Spacing.s
    /// Padding inside a filled shape, so its text lands on `margin`.
    static let shapeContentPadding: CGFloat = margin - shapeInset
    /// The popover's own corner radius. NSPopover doesn't publish it and SwiftUI's
    /// container shape doesn't reach into a popover, so it's measured: 19 pt on macOS 26
    /// (screenshots, `scripts/measure line` along the curve), the window radius before.
    static var panelRadius: CGFloat {
        if #available(macOS 26, *) { return 19 } // lint:allow measured system radius, not a design value
        return Radius.legacyWindow
    }
    /// Shapes `shapeInset` inside the panel: concentric with its corners.
    static var shapeRadius: CGFloat { Radius.nested(in: panelRadius, padding: shapeInset, minimum: Radius.xs) }
    static let rowPadding: CGFloat = margin
    /// Space kept clear either side of the line.
    static let lineGap: CGFloat = Spacing.s
    static var columnWidth: CGFloat { width / 2 - rowPadding - lineGap }
    /// Half the width a day strip covers (it spans the row inside its padding).
    static var stripHalfWidth: CGFloat { width / 2 - rowPadding }
    /// Row heights per style (without the hairline between rows), for sizing the scroll area.
    static func rowHeight(_ style: RowStyle) -> CGFloat {
        switch style {
        case .standard: 48
        case .compact: 28
        case .timeline: 62
        }
    }
}

/// One place: name and "Tomorrow · +7 h" on the left, a large time on the right, coloured
/// by what people there are probably doing. The timeline style adds a strip of their day.
///
/// Mouse handling (drag sideways to move the time, up or down to reorder, click the time
/// to type one) lives in `AppController.handleMouseDown`, which reads the frames reported
/// here.
struct ClockRowView: View {

    let row: ClockRow
    let style: RowStyle
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var isSelected: Bool { model.selection == row.id }
    private var isEditingTime: Bool { panel.mode == .editingTime(row.id) }
    private var isRenaming: Bool { panel.mode == .renaming(row.id) }

    var body: some View {
        VStack(spacing: style == .timeline ? Spacing.s : 0) {
            if style == .compact { compactLine } else { standardLine }
            if style == .timeline {
                DayStripView(strip: panel.strip(for: row, model: model))
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, PanelMetrics.rowPadding)
        .padding(.vertical, style == .compact ? Spacing.xs : Spacing.s)
        .frame(minHeight: PanelMetrics.rowHeight(style))
        .contentShape(Rectangle())
        .background {
            // Same inset and corners as the header card, so a selected row lines up with it.
            RoundedRectangle(cornerRadius: PanelMetrics.shapeRadius, style: .continuous)
                .fill(backgroundStyle)
                .padding(.horizontal, PanelMetrics.shapeInset)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.recentlyAdded)
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                    panel.rowFrames[row.id] = frame
                }
            }
        }
        .onDisappear { panel.rowFrames[row.id] = nil; panel.timeFrames[row.id] = nil }
        .contextMenu { RowContextMenu(row: row, model: model, panel: panel, controller: controller) }
        .rowAccessibility(row: row, model: model, panel: panel, controller: controller,
                          isSelected: isSelected, editing: isEditingTime || isRenaming)
        .task(id: model.recentlyAdded) {
            guard model.recentlyAdded == row.id else { return }
            try? await Task.sleep(for: .seconds(1.5))
            model.clearRecentlyAdded()
        }
    }

    private var standardLine: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                nameLine
                subline
                if let note = row.transitionNote {
                    Label(note, systemImage: "clock.arrow.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.textOrange)
                        .labelStyle(CompactLabelStyle())
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: PanelMetrics.columnWidth, alignment: .leading)
            Spacer(minLength: 0)
            timeView(size: .row)
        }
    }

    private var compactLine: some View {
        // Name, offset and time share a baseline.
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                nameLine
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            .frame(width: PanelMetrics.columnWidth, alignment: .leading)
            Spacer(minLength: 0)
            if row.transitionNote != nil {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.textOrange)
                    .help(row.transitionNote ?? "")
            }
            timeView(size: .compact)
        }
    }

    private var subline: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: row.activity.symbol(phase: row.phase))
                .font(.caption2)
                .foregroundStyle(row.activity == .working ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .help(row.activity.title)
            Text(row.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if model.recentlyAdded == row.id { return AnyShapeStyle(Color.selectionTint(activeState, opacity: 0.25)) }
        if isSelected { return AnyShapeStyle(Color.selectionTint(activeState, opacity: 0.14)) }
        return AnyShapeStyle(Color.clear)
    }

    @ViewBuilder private var nameLine: some View {
        if isRenaming {
            TextField("Name", text: $panel.editText, prompt: Text(row.label))
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { controller.commitEdit() }
                .onAppear { focusSoon() }
                .accessibilityLabel("Name for \(row.label)")
        } else {
            HStack(spacing: Spacing.xs) {
                Text(row.label)
                    .font(.body)
                    .lineLimit(1)
                if model.isInMenuBar(row.id) {
                    Image(systemName: "menubar.rectangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Shown in the menu bar")
                }
            }
        }
    }

    @ViewBuilder private func timeView(size: TimeText.Size) -> some View {
        if isEditingTime {
            TimeEntryField(row: row, panel: panel, controller: controller, focused: $fieldFocused)
                .onAppear { focusSoon() }
        } else {
            TimeText(parts: row.timeParts, size: size)
                .foregroundStyle(row.activity.timeStyle)
                .lineLimit(1)
                .fixedSize()
                .reportFrame { panel.timeFrames[row.id] = $0 }
                .help("Click to type a time in \(row.label)")
        }
    }

    private func focusSoon() {
        DispatchQueue.main.async { fieldFocused = true }
    }
}

/// The field for typing a time on a row ("3pm").
struct TimeEntryField: View {
    let row: ClockRow
    @Bindable var panel: PanelState
    let controller: AppController
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField("Time", text: $panel.editText, prompt: Text("3pm"))
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 104)
            .focused(focused)
            .onSubmit { controller.commitEdit() }
            .help("Type a time in \(row.label), like 3pm or 15:30, then press Return")
            .accessibilityLabel("Time in \(row.label)")
    }
}

/// Right-click menu of a row (and of the local time header).
struct RowContextMenu: View {
    let row: ClockRow
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    var body: some View {
        Button("Type a Time…") { controller.beginEditingTime(row.id) }
        Button("Copy Time") { controller.copyTime(forRow: row.id) }
        if model.isInMenuBar(row.id) {
            Button("Remove from Menu Bar") { model.removeFromMenuBar(row.id) }
        } else {
            Button("Show in Menu Bar") { model.showInMenuBar(row.id) }
        }
        Button("Working Hours…") { controller.editWorkingHours(row.id) }
        if !row.isLocal {
            Divider()
            Button("Rename…") { panel.beginRenaming(row.id, current: row.label) }
            Button("Move Up") { model.move(row.id, by: -1) }
                .disabled(!model.canMove(row.id, by: -1))
            Button("Move Down") { model.move(row.id, by: 1) }
                .disabled(!model.canMove(row.id, by: 1))
            Divider()
            Button("Remove") { model.remove(row.id) }
        } else {
            Divider()
            Button("Hide Local Time") { model.preferences.showLocalTime = false }
        }
    }
}

extension View {
    /// A row reads as one VoiceOver sentence and offers every row action by name.
    func rowAccessibility(row: ClockRow, model: ZonesModel, panel: PanelState, controller: AppController,
                          isSelected: Bool, editing: Bool) -> some View {
        accessibilityElement(children: editing ? .contain : .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Press to type a time here. Other actions: copy, menu bar, working hours, rename, move, remove.")
            .accessibilityAction { controller.beginEditingTime(row.id) }
            .accessibilityAction(named: "Type a Time") { controller.beginEditingTime(row.id) }
            .accessibilityAction(named: "Copy Time") { controller.copyTime(forRow: row.id) }
            .accessibilityAction(named: model.isInMenuBar(row.id) ? "Remove from Menu Bar" : "Show in Menu Bar") {
                if model.isInMenuBar(row.id) { model.removeFromMenuBar(row.id) } else { model.showInMenuBar(row.id) }
            }
            .accessibilityAction(named: "Working Hours") { controller.editWorkingHours(row.id) }
            .accessibilityActions {
                if !row.isLocal {
                    Button("Rename") { panel.beginRenaming(row.id, current: row.label) }
                    if model.canMove(row.id, by: -1) { Button("Move Up") { model.move(row.id, by: -1) } }
                    if model.canMove(row.id, by: 1) { Button("Move Down") { model.move(row.id, by: 1) } }
                    Button("Remove") { model.remove(row.id) }
                }
            }
    }

    /// Reports the view's frame in window coordinates (for AppKit mouse handling).
    func reportFrame(_ report: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                    report(frame)
                }
            }
        }
    }
}

/// Icon and title close together, for small caption labels.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}
