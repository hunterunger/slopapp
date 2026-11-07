import AppKit
import AwakeCore
import SlopKit
import SwiftUI

/// The small "Keep Awake" window behind "Custom Duration…" and "Until…": pick a length or a
/// clock time, press Return.
@MainActor
final class CustomSessionWindow {
    private let controller: AwakeController
    private let state = CustomSessionState()
    private var window: NSWindow?

    init(controller: AwakeController) {
        self.controller = controller
    }

    func show(mode: CustomSessionState.Mode) {
        state.reset(mode: mode, now: Date())
        let isFirstShow = self.window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        // Centred the first time; after that it opens wherever the person last left it.
        if isFirstShow { window.center() }
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = CustomSessionView(state: state) { [weak self] kind in
            if let kind { self?.controller.start(kind) }
            self?.window?.orderOut(nil)
        }
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Keep Awake"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.setContentSize(hosting.view.fittingSize)
        return window
    }
}

@MainActor
@Observable
final class CustomSessionState {
    enum Mode: String, CaseIterable {
        case duration = "For"
        case until = "Until"
    }

    var mode: Mode = .until
    var hours = 1
    var minutes = 30
    var time = Date()
    /// Refreshed when the window opens so "tomorrow" and "from now" stay right.
    var now = Date()

    func reset(mode: Mode, now: Date) {
        self.mode = mode
        self.now = now
        // Suggest the next half hour at least an hour away: 9:10 → 10:30.
        let calendar = Calendar.current
        let later = now.addingTimeInterval(3600)
        let minute = calendar.component(.minute, from: later)
        time = calendar.date(byAdding: .minute, value: minute <= 30 ? 30 - minute : 60 - minute, to: later) ?? later
    }

    var durationSeconds: TimeInterval { TimeInterval(hours * 3600 + minutes * 60) }

    /// The next time the picked clock time comes round.
    var untilDate: Date? { untilDate(after: now) }

    func untilDate(after now: Date) -> Date? {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return NextOccurrence.of(hour: parts.hour ?? 0, minute: parts.minute ?? 0, after: now)
    }

    var kind: SessionKind? {
        switch mode {
        case .duration: durationSeconds > 0 ? .duration(AwakeDuration(seconds: durationSeconds)) : nil
        case .until: untilDate.map { .until($0) }
        }
    }

    /// "Today, in 1 hr 20 min" / "Tomorrow, in 13 hr".
    func untilDescription(now: Date) -> String {
        guard let date = untilDate(after: now) else { return "" }
        let day = Calendar.current.isDate(date, inSameDayAs: now) ? "Today" : "Tomorrow"
        let left = RemainingTime.string(date.timeIntervalSince(now)).replacingOccurrences(of: " left", with: "")
        return "\(day), in \(left)"
    }
}

struct CustomSessionView: View {
    @Bindable var state: CustomSessionState
    let finish: (SessionKind?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Picker("Keep awake", selection: $state.mode) {
                ForEach(CustomSessionState.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Keep awake for a length of time or until a time")

            VStack(alignment: .leading, spacing: Spacing.s) {
                // Both modes' controls share one slot, as tall as the taller row, so switching
                // modes neither resizes the window nor moves the caption. The hidden row is
                // disabled so Tab can't reach it.
                ZStack(alignment: .leading) {
                    durationRow.shown(state.mode == .duration)
                    untilRow.shown(state.mode == .until)
                }
                // Re-read every minute so the times stay right while the window is open.
                TimelineView(.everyMinute) { context in
                    Text(caption(now: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Start") {
                    state.now = Date()
                    finish(state.kind)
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.kind == nil)
            }
        }
        .padding(Spacing.windowMargin)
        .frame(width: 300)
    }

    private var durationRow: some View {
        HStack(spacing: Spacing.s) {
            NumberField(value: $state.hours, range: 0...99, step: 1, label: "Hours")
            Text("hr").foregroundStyle(.secondary)
            NumberField(value: $state.minutes, range: 0...59, step: 5, label: "Minutes")
            Text("min").foregroundStyle(.secondary)
        }
    }

    private var untilRow: some View {
        DatePicker("Time", selection: $state.time, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .labelsHidden()
            .accessibilityLabel("Time")
    }

    private func caption(now: Date) -> String {
        switch state.mode {
        case .duration:
            guard state.durationSeconds > 0 else { return "Choose a length of time." }
            return "Ends at \(now.addingTimeInterval(state.durationSeconds).formatted(date: .omitted, time: .shortened))"
        case .until:
            return state.untilDescription(now: now)
        }
    }
}

private extension View {
    /// In the layout either way; only the visible one can be seen, focused or read aloud.
    func shown(_ isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .disabled(!isShown)
            .accessibilityHidden(!isShown)
    }
}

/// A small number field with a stepper.
struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            TextField(label, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number)
                .frame(width: 44)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .labelsHidden()
                .accessibilityLabel(label)
            Stepper(label, value: $value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }
}
