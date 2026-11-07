import FocusCore
import SlopKit
import SwiftUI

/// What the dial and its labels show at one moment.
@MainActor
struct TimerDisplay {
    var minutes: Double
    var time: String
    var caption: String
    var heading: String
    var tint: Color
    var range: String
    var isRunning: Bool
    var canDrag: Bool

    static func make(_ controller: FocusController, now: Date) -> TimerDisplay {
        let unit = controller.unit
        let settings = controller.settings
        let state = controller.state
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)
        if let run = state.run {
            let left = run.remaining(at: now)
            let caption: String
            if run.isPaused {
                caption = "Paused"
            } else {
                caption = run.phase.isBreak ? run.phase.title : "Focus"
            }
            let start = run.phase.isBreak ? run.startedAt : run.startedAt
            let end = run.projectedEnd(at: now)
            return TimerDisplay(
                minutes: left / unit,
                time: TimeText.menuBar(left, showSeconds: true, unit: unit),
                caption: caption,
                heading: run.phase.isBreak ? "Taking a break" : (run.label ?? "Focusing"),
                tint: phaseTint(run.phase, category: controller.category),
                range: "\(start.formatted(timeStyle)) → \(end.formatted(timeStyle))",
                isRunning: !run.isPaused,
                canDrag: false
            )
        }
        let next: Phase = state.pendingBreak ?? .focus
        let length = settings.minutes(for: next)
        let end = now.addingTimeInterval(TimeInterval(length) * unit)
        return TimerDisplay(
            minutes: Double(length),
            time: TimeText.menuBar(TimeInterval(length) * unit, showSeconds: true, unit: unit),
            caption: next.isBreak ? "Break next" : "Ready",
            heading: next.isBreak ? "Session done" : "What are you working on?",
            tint: phaseTint(next, category: controller.category),
            range: "\(now.formatted(timeStyle)) → \(end.formatted(timeStyle))",
            isRunning: false,
            canDrag: next == .focus
        )
    }
}

/// The intention text being typed, shared by the window and the menu bar panel.
@MainActor
@Observable
final class IntentionDraft {
    var text = ""
}

/// The text field for "what are you working on". Shows past intentions while typing (↑ ↓ to
/// choose, Return to pick); "@work" picks a category and "45m" the length, when started.
struct IntentionField: View {
    let controller: FocusController
    @Binding var text: String
    var placeholder = "Intention"
    var large = false
    /// Show suggestions without focus (offscreen renders).
    var alwaysSuggest = false
    let onSubmit: () -> Void

    @FocusState private var focused: Bool
    @State private var highlighted: Int?
    @State private var dismissedFor: String?

    private var suggestions: [IntentionSuggestion] {
        guard focused || alwaysSuggest, !text.trimmingCharacters(in: .whitespaces).isEmpty, dismissedFor != text else { return [] }
        return controller.suggestions(for: text)
    }

    var body: some View {
        let shown = suggestions
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(large ? .title3 : .body)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, large ? Spacing.m : Spacing.s)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .focused($focused)
            .accessibilityLabel("Intention")
            .onSubmit {
                if let index = highlighted, shown.indices.contains(index) {
                    pick(shown[index])
                } else {
                    onSubmit()
                }
            }
            .onKeyPress(.downArrow) {
                guard !shown.isEmpty else { return .ignored }
                highlighted = min((highlighted ?? -1) + 1, shown.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !shown.isEmpty, let current = highlighted else { return .ignored }
                highlighted = current == 0 ? nil : current - 1
                return .handled
            }
            .onKeyPress(.escape) {
                guard !shown.isEmpty else { return .ignored }
                dismissedFor = text
                return .handled
            }
            .onChange(of: text) { highlighted = nil }
            .overlay {
                if !shown.isEmpty {
                    // The list's top just under the field's bottom, at any text size.
                    GeometryReader { field in
                        SuggestionList(suggestions: shown, highlighted: highlighted, categories: controller.settings.categories, pick: pick)
                            .frame(width: field.size.width)
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(y: field.size.height + Spacing.xs)
                    }
                }
            }
            .zIndex(1)
    }

    private func pick(_ suggestion: IntentionSuggestion) {
        text = suggestion.text
        if let id = suggestion.categoryID, controller.settings.category(id: id) != nil {
            controller.setCategory(id)
        }
        highlighted = nil
        dismissedFor = suggestion.text
    }
}

private struct SuggestionList: View {
    /// Highlight inside the list's 8 pt corners, inset 4 pt: concentric.
    static let rowRadius = Radius.nested(in: Radius.m, padding: Spacing.xs)

    let suggestions: [IntentionSuggestion]
    let highlighted: Int?
    let categories: [FocusCore.Category]
    let pick: (IntentionSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    pick(suggestion)
                } label: {
                    HStack(spacing: Spacing.s) {
                        Text(suggestion.text)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.s)
                        if let category = categories.first(where: { $0.id == suggestion.categoryID }) {
                            CategoryTag(name: category.name, color: category.color.color)
                        }
                    }
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.s)
                    .contentShape(Rectangle())
                    .background(index == highlighted ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use “\(suggestion.text)”")
            }
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

/// "● Work" in a capsule, for rows and suggestions.
struct CategoryTag: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension Mood {
    var symbol: String {
        switch self {
        case .focused: "arrow.up.circle.fill"
        case .neutral: "arrow.right.circle.fill"
        case .distracted: "arrow.down.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .focused: .green
        case .neutral: .secondary
        case .distracted: .orange
        }
    }
}

/// The reflection being written, shared so the window, panel and break screen agree.
@MainActor
@Observable
final class ReflectionDraft {
    var mood: Mood?
    var notes = ""
    /// The record the draft belongs to; a new session resets it.
    var recordID: String?

    func sync(with record: SessionRecord?) {
        guard record?.id != recordID else { return }
        recordID = record?.id
        mood = nil
        notes = record?.notes ?? ""
    }

    func save(_ controller: FocusController) {
        controller.reflect(mood: mood, notes: notes)
        sync(with: nil)
    }
}

/// "How did it go?": a mood and a note for the session that just ended.
struct ReflectionCard: View {
    let controller: FocusController
    let record: SessionRecord
    @Bindable var draft: ReflectionDraft
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Spacing.s : Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How did it go?")
                    .font(compact ? .headline : .title3.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: Spacing.s) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    MoodButton(mood: mood, selected: draft.mood == mood, compact: compact) {
                        draft.mood = draft.mood == mood ? nil : mood
                    }
                }
            }
            TextField("What did you get done?", text: $draft.notes, axis: .vertical)
                .lineLimit(compact ? 2...3 : 3...6)
                .textFieldStyle(.plain)
                .padding(Spacing.s)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .accessibilityLabel("Reflection notes")
            HStack {
                Spacer()
                Button("Skip") { controller.skipReflection() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { draft.save(controller) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { draft.sync(with: record) }
        .onChange(of: record.id) { draft.sync(with: record) }
    }

    private var summary: String {
        let minutes = TimeText.duration(seconds: record.focused, unit: controller.unit)
        return [record.label, record.categoryName, minutes].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct MoodButton: View {
    let mood: Mood
    let selected: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        let tint = mood == .neutral ? Color.gray : mood.tint
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: mood.symbol)
                    .font(compact ? .title3 : .title2)
                    .foregroundStyle(mood.tint)
                Text(mood.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? Spacing.s - 2 : Spacing.s)
            // Selected: a tint wash and a 2 pt ring in the mood's colour, with primary text
            // (white on the green fill measured about 2:1).
            .background(selected ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: shape)
            .overlay { if selected { shape.strokeBorder(tint, lineWidth: 2) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A round icon button (pause, finish, stop).
struct RoundButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var size: CGFloat = 44
    let action: () -> Void
    /// Like a prominent push button, the accent fill goes grey when the window isn't key.
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let accented = prominent && appearsActive
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(accented ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(accented ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

/// The buttons under the dial for each state.
struct TimerControls: View {
    let controller: FocusController
    let draft: IntentionDraft
    var compact = false

    var body: some View {
        let size: CGFloat = compact ? 34 : 46
        // One fixed-height slot for every state, so nothing above or below moves when the
        // controls change (Start Focus → round buttons → break choices).
        buttons(size: size)
            .frame(height: size)
    }

    @ViewBuilder
    private func buttons(size: CGFloat) -> some View {
        let settings = controller.settings
        if let phase = controller.runningPhase {
            HStack(spacing: compact ? Spacing.m : Spacing.l) {
                if controller.isPaused {
                    RoundButton(title: "Resume", symbol: "play.fill", prominent: true, size: size) { controller.resume() }
                } else {
                    RoundButton(title: "Pause", symbol: "pause.fill", prominent: true, size: size) { controller.pause() }
                }
                if phase.isBreak {
                    RoundButton(title: "Skip Break", symbol: "forward.end.fill", size: size) { controller.skipBreak() }
                } else {
                    RoundButton(title: "Finish Session", symbol: "checkmark", size: size) { controller.finish() }
                }
                RoundButton(title: "Stop", symbol: "stop.fill", size: size) { controller.stop() }
            }
        } else if let pending = controller.state.pendingBreak {
            HStack(spacing: Spacing.s) {
                Button("Start Focus") { controller.startFocus(intention: draft.text) }
                    .controlSize(compact ? .regular : .large)
                Button("Start \(pending == .longBreak ? "Long Break" : "Break") (\(TimeText.duration(minutes: settings.minutes(for: pending))))") {
                    controller.startBreak()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .regular : .large)
            }
        } else {
            Button {
                controller.startFocus(intention: draft.text)
            } label: {
                Text("Start Focus")
                    .frame(maxWidth: compact ? .infinity : 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
