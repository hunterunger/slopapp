import AppKit
import SlopKit
import SwiftUI
import TriggersCore
import UniformTypeIdentifiers

/// What a trigger does: one action (the common case, which looks like a single Action field),
/// or several steps run in order, with pauses and "wait until" steps. Steps reorder by
/// dragging their header, or with Move Up / Move Down (keyboard and VoiceOver).
struct StepsEditor: View {
    let model: AppModel
    @Binding var steps: [ActionStep]
    let scope: Scope
    @State private var dropTarget: UUID?

    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
            Section {
                content(for: step, at: index)
                if index == steps.count - 1, !isPassThrough {
                    HStack {
                        Spacer()
                        AddStepMenu { steps.append($0) }
                    }
                }
            } header: {
                header(for: step, at: index)
            }
        }
    }

    private var isPassThrough: Bool { steps.count == 1 && steps[0].action == .passThrough }

    @ViewBuilder private func header(for step: ActionStep, at index: Int) -> some View {
        if steps.count == 1 {
            Text("Action")
        } else {
            HStack(spacing: Spacing.s) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Step \(index + 1)")
                if let kind = kindLabel(step) {
                    Text(kind).foregroundStyle(.secondary)
                }
                Spacer()
                RemoveButton(label: "Remove step \(index + 1)") { remove(step.id) }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
            .background {
                if dropTarget == step.id {
                    RoundedRectangle(cornerRadius: Radius.s).fill(.tint.opacity(0.15))
                }
            }
            .draggable(step.id.uuidString) {
                Text(KeyDisplay.title(step)).padding(Spacing.s)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let text = items.first, let id = UUID(uuidString: text) else { return false }
                move(id, before: step.id)
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? step.id : (dropTarget == step.id ? nil : dropTarget)
            }
            .contextMenu {
                Button("Move Up") { shift(step.id, by: -1) }.disabled(index == 0)
                Button("Move Down") { shift(step.id, by: 1) }.disabled(index == steps.count - 1)
                Divider()
                Button("Remove Step") { remove(step.id) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(index + 1) of \(steps.count): \(KeyDisplay.title(step))")
            .accessibilityAction(named: "Move Up") { shift(step.id, by: -1) }
            .accessibilityAction(named: "Move Down") { shift(step.id, by: 1) }
            .accessibilityAction(named: "Remove Step") { remove(step.id) }
        }
    }

    @ViewBuilder private func content(for step: ActionStep, at index: Int) -> some View {
        switch step.kind {
        case .action(let action):
            ActionEditor(model: model, action: Binding(
                get: { action },
                set: { new in replace(step.id, with: .action(new)) }
            ), scope: scope, offersPassThrough: steps.count == 1)
        case .delay(let seconds):
            LabeledContent("Wait") {
                SecondsField(label: "Seconds to wait", seconds: Binding(get: { seconds }, set: { replace(step.id, with: .delay(seconds: $0)) }),
                             range: ActionStep.delayRange)
            }
        case .waitUntil(let condition, let timeout):
            ConditionRow(model: model, condition: Binding(get: { condition }, set: { replace(step.id, with: .waitUntil($0, timeout: timeout)) }))
            LabeledContent {
                SecondsField(label: "Longest wait in seconds", seconds: Binding(get: { timeout }, set: { replace(step.id, with: .waitUntil(condition, timeout: $0)) }),
                             range: ActionStep.waitRange)
            } label: {
                Text("Wait until true, for up to")
                Text("If it isn't true by then, the rest of the steps don't run.")
            }
        }
    }

    /// "Wait", "Wait Until" (actions say what they are in their own Action field).
    private func kindLabel(_ step: ActionStep) -> String? {
        switch step.kind {
        case .action: nil
        case .delay: "Wait"
        case .waitUntil: "Wait Until"
        }
    }

    private func replace(_ id: UUID, with kind: ActionStep.Kind) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].kind = kind
        // "Do nothing" stands alone.
        if case .action(.passThrough) = kind { steps = [steps[index]] }
    }

    private func remove(_ id: UUID) {
        guard steps.count > 1 else { return }
        steps.removeAll { $0.id == id }
    }

    private func shift(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }

    private func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = steps.firstIndex(where: { $0.id == id }) else { return }
        let step = steps.remove(at: from)
        let to = steps.firstIndex(where: { $0.id == target }) ?? steps.count
        // Dropped on a later step: land after it (dragging down), else before it.
        steps.insert(step, at: from <= to ? min(to + 1, steps.count) : to)
        dropTarget = nil
    }
}

/// Then… another action, a pause, or a wait.
struct AddStepMenu: View {
    let add: (ActionStep) -> Void

    var body: some View {
        Menu("Add Step") {
            Button("Action") { add(.action(.pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)))) }
            Button("Wait") { add(.delay(ActionStep.defaultDelay)) }
            Menu("Wait Until") {
                ForEach(Condition.Kind.allCases, id: \.self) { kind in
                    Button(kind.title) { add(.waitUntil(kind.defaultCondition)) }
                }
            }
        }
        .fixedSize()
        .help("Do more after this: another action, a pause, or wait for something")
    }
}

/// Seconds, typed or stepped.
struct SecondsField: View {
    let label: String
    @Binding var seconds: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: Spacing.xs) {
            TextField(label, value: Binding(get: { seconds }, set: { seconds = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .accessibilityLabel(label)
            Stepper(label, value: $seconds, in: range, step: seconds < 1 ? 0.1 : 0.5)
                .labelsHidden()
            Text("s").foregroundStyle(.secondary)
        }
    }
}
