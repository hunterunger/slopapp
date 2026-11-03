import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// One place: day/night symbol, name, "Tomorrow · +7 h", and the time.
///
/// Mouse handling (drag sideways to move the time, up or down to reorder, click the time
/// to type one) lives in `AppController.handleMouseDown`, which reads the frames reported
/// here.
struct ClockRowView: View {

    let row: ClockRow
    @Bindable var model: ZonesModel
    @Bindable var panel: PanelState
    let controller: AppController

    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelected: Bool { model.selection == row.id }
    private var isEditingTime: Bool { panel.mode == .editingTime(row.id) }
    private var isRenaming: Bool { panel.mode == .renaming(row.id) }
    private var isNight: Bool { row.phase == .night }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isNight ? .secondary : .primary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                nameLine
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let note = row.transitionNote {
                    Label(note, systemImage: "clock.arrow.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .labelStyle(CompactLabelStyle())
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: Spacing.xs)
            timeView
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundStyle)
                .padding(.horizontal, Spacing.xs)
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
        .contextMenu { contextMenu }
        .accessibilityElement(children: (isEditingTime || isRenaming) ? .contain : .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Press to type a time here. Other actions: copy, rename, move, remove.")
        .accessibilityAction { beginEditingTime() }
        .accessibilityAction(named: "Type a Time") { beginEditingTime() }
        .accessibilityAction(named: "Copy Time") { controller.copyTime(forRow: row.id) }
        .accessibilityAction(named: "Show in Menu Bar") { model.showInMenuBar(row.id) }
        .accessibilityActions {
            if !row.isLocal {
                Button("Rename") { panel.beginRenaming(row.id, current: row.label) }
                if model.canMove(row.id, by: -1) { Button("Move Up") { model.move(row.id, by: -1) } }
                if model.canMove(row.id, by: 1) { Button("Move Down") { model.move(row.id, by: 1) } }
                Button("Remove") { model.remove(row.id) }
            }
        }
        .task(id: model.recentlyAdded) {
            guard model.recentlyAdded == row.id else { return }
            try? await Task.sleep(for: .seconds(1.5))
            model.clearRecentlyAdded()
        }
    }

    private var symbol: String {
        switch row.phase {
        case .night: "moon.stars.fill"
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if model.recentlyAdded == row.id { return AnyShapeStyle(Color.accentColor.opacity(0.25)) }
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.14)) }
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
                if row.isLocal {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Your Mac's time zone")
                }
                if model.isInMenuBar(row.id) {
                    Image(systemName: "menubar.rectangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Shown in the menu bar")
                }
            }
        }
    }

    @ViewBuilder private var timeView: some View {
        if isEditingTime {
            TextField("Time", text: $panel.editText, prompt: Text("3pm"))
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .focused($fieldFocused)
                .onSubmit { controller.commitEdit() }
                .onAppear { focusSoon() }
                .help("Type a time in \(row.label), like 3pm or 15:30, then press Return")
                .accessibilityLabel("Time in \(row.label)")
        } else {
            Text(row.time)
                .font(.title2)
                .monospacedDigit()
                .foregroundStyle(isNight ? .secondary : .primary)
                .lineLimit(1)
                .fixedSize()
                .background {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                            panel.timeFrames[row.id] = frame
                        }
                    }
                }
                .help("Click to type a time in \(row.label)")
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button("Type a Time…") { beginEditingTime() }
        Button("Copy Time") { controller.copyTime(forRow: row.id) }
        Button(model.isInMenuBar(row.id) ? "Shown in Menu Bar" : "Show in Menu Bar") { model.showInMenuBar(row.id) }
            .disabled(model.isInMenuBar(row.id))
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

    private func beginEditingTime() {
        model.selection = row.id
        panel.beginEditingTime(row.id)
    }

    private func focusSoon() {
        DispatchQueue.main.async { fieldFocused = true }
    }
}

/// Icon and title close together, for small caption labels.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
