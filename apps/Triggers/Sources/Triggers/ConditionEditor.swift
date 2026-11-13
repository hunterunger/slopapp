import AppKit
import SlopKit
import SwiftUI
import TriggersCore

/// "Only when": a trigger's conditions. Empty is the common case and shows one row.
struct ConditionsSection: View {
    let model: AppModel
    @Binding var conditions: ConditionSet

    var body: some View {
        Section {
            if conditions.isEmpty {
                LabeledContent {
                    AddConditionMenu { conditions.conditions.append($0) }
                } label: {
                    Text("Only when")
                    Text("Runs every time. Add a condition to run it only on battery, at certain times, while an app is open…")
                }
            } else {
                if conditions.conditions.count > 1 {
                    Picker("Run when", selection: $conditions.match) {
                        Text("All of these are true").tag(ConditionSet.Match.all)
                        Text("Any of these is true").tag(ConditionSet.Match.any)
                    }
                }
                ForEach(Array(conditions.conditions.indices), id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        ConditionRow(model: model, condition: Binding(
                            get: { conditions.conditions.indices.contains(index) ? conditions.conditions[index] : .power(.charger) },
                            set: { if conditions.conditions.indices.contains(index) { conditions.conditions[index] = $0 } }
                        ))
                        RemoveButton(label: "Remove condition: \(conditions.conditions[index].title)") {
                            conditions.conditions.remove(at: index)
                        }
                    }
                }
                HStack {
                    Text(liveStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    AddConditionMenu { conditions.conditions.append($0) }
                }
            }
        } header: {
            Text("Conditions")
        }
    }

    private var liveStatus: String {
        guard conditions.isComplete else { return "Finish the conditions above." }
        return model.engine.conditionsHold(conditions) ? "True right now." : "Not true right now."
    }
}

struct AddConditionMenu: View {
    let add: (Condition) -> Void

    var body: some View {
        Menu("Add Condition") {
            ForEach(Condition.Kind.allCases, id: \.self) { kind in
                Button(kind.title) { add(kind.defaultCondition) }
            }
        }
        .fixedSize()
    }
}

/// A small "remove" button for list rows.
struct RemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// One condition's fields. Also used by "Wait until" steps.
struct ConditionRow: View {
    let model: AppModel
    @Binding var condition: Condition

    var body: some View {
        switch condition {
        case .appRunning(let id, let name, let running):
            LabeledContent("App") {
                HStack(spacing: Spacing.s) {
                    AppMenu(model: model, app: id.isEmpty ? nil : AppChoice(bundleID: id, name: name, url: nil)) { app in
                        condition = .appRunning(bundleID: app.bundleID, name: app.name, running: running)
                    }
                    Picker("State", selection: Binding(get: { running }, set: { condition = .appRunning(bundleID: id, name: name, running: $0) })) {
                        Text("is running").tag(true)
                        Text("isn't running").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        case .frontApp(let id, let name, let isFront):
            LabeledContent("App") {
                HStack(spacing: Spacing.s) {
                    AppMenu(model: model, app: id.isEmpty ? nil : AppChoice(bundleID: id, name: name, url: nil)) { app in
                        condition = .frontApp(bundleID: app.bundleID, name: app.name, isFront: isFront)
                    }
                    Picker("State", selection: Binding(get: { isFront }, set: { condition = .frontApp(bundleID: id, name: name, isFront: $0) })) {
                        Text("is in front").tag(true)
                        Text("isn't in front").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        case .network(let network):
            Picker("Network", selection: Binding(get: { network }, set: { condition = .network($0) })) {
                ForEach(Condition.NetworkCondition.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        case .display(let display):
            Picker("Display", selection: Binding(get: { display }, set: { condition = .display($0) })) {
                Text("An external display is connected").tag(Condition.DisplayCondition.externalConnected)
                Text("No external display is connected").tag(Condition.DisplayCondition.noExternal)
                let names = displayNames(including: display)
                if !names.isEmpty {
                    Divider()
                    ForEach(names, id: \.self) { name in
                        Text("“\(name)” is connected").tag(Condition.DisplayCondition.named(name))
                    }
                }
            }
        case .power(let power):
            Picker("Power", selection: Binding(get: { power }, set: { condition = .power($0) })) {
                ForEach(Condition.PowerCondition.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        case .time(let from, let to):
            LabeledContent("Between") {
                HStack(spacing: Spacing.s) {
                    TimeField(label: "From", minutes: Binding(get: { from }, set: { condition = .time(from: $0, to: to) }))
                    Text("and").foregroundStyle(.secondary)
                    TimeField(label: "To", minutes: Binding(get: { to }, set: { condition = .time(from: from, to: $0) }))
                }
            }
        case .days(let days):
            LabeledContent("On") {
                HStack(spacing: Spacing.xs) {
                    ForEach(dayOrder, id: \.self) { day in
                        Toggle(isOn: Binding(
                            get: { days.contains(day) },
                            set: { on in
                                var set = Set(days)
                                if on { set.insert(day) } else { set.remove(day) }
                                condition = .days(set.sorted())
                            }
                        )) {
                            Text(Calendar.current.veryShortWeekdaySymbols[day - 1]).frame(minWidth: 14)
                        }
                        .toggleStyle(.button)
                        .help(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    }
                }
            }
        case .modifiersHeld(let modifiers):
            LabeledContent("Holding") {
                ModifierToggles(modifiers: Binding(get: { modifiers }, set: { condition = .modifiersHeld($0) }))
            }
        case .appearance(let dark):
            Picker("Appearance", selection: Binding(get: { dark }, set: { condition = .appearance(dark: $0) })) {
                Text("Dark mode is on").tag(true)
                Text("Dark mode is off").tag(false)
            }
        }
    }

    /// Weekdays in the person's order (Monday first in most of Europe).
    private var dayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func displayNames(including current: Condition.DisplayCondition) -> [String] {
        var names = model.systemState.displays.map(\.name)
        if case .named(let name) = current, !names.contains(name) { names.append(name) }
        return names
    }
}

/// Hours and minutes, in the system's own format.
private struct TimeField: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(label, selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .accessibilityLabel(label)
    }
}

/// ⌃ ⌥ ⇧ ⌘ as four toggle buttons.
struct ModifierToggles: View {
    @Binding var modifiers: Modifiers

    var body: some View {
        HStack(spacing: Spacing.xs) {
            toggle(.control, "⌃", "Control")
            toggle(.option, "⌥", "Option")
            toggle(.shift, "⇧", "Shift")
            toggle(.command, "⌘", "Command")
        }
    }

    private func toggle(_ modifier: Modifiers, _ symbol: String, _ name: String) -> some View {
        Toggle(isOn: Binding(
            get: { modifiers.contains(modifier) },
            set: { on in if on { modifiers.insert(modifier) } else { modifiers.remove(modifier) } }
        )) {
            Text(symbol).frame(minWidth: 14)
        }
        .toggleStyle(.button)
        .help(name)
        .accessibilityLabel(name)
    }
}

/// Pick an app: the sidebar's apps and the open ones first, then any app.
struct AppMenu: View {
    let model: AppModel
    let app: AppChoice?
    let pick: (AppChoice) -> Void

    var body: some View {
        Menu {
            let running = AppCatalog.runningApps()
            let sidebar = model.config.apps.filter { entry in !running.contains { $0.bundleID == entry.bundleID } }
            if !sidebar.isEmpty {
                Section("Your Apps") {
                    ForEach(sidebar) { entry in Button(entry.name) { pick(AppChoice(bundleID: entry.bundleID, name: entry.name, url: nil)) } }
                }
            }
            if !running.isEmpty {
                Section("Open Apps") {
                    ForEach(running) { choice in Button(choice.name) { pick(choice) } }
                }
            }
            Divider()
            Button("Choose App…") {
                if let choice = AppCatalog.chooseApp(message: "Choose an app.") { pick(choice) }
            }
        } label: {
            Text(app?.name ?? "Choose…")
        }
        .fixedSize()
        .accessibilityLabel("App: \(app?.name ?? "none")")
    }
}
