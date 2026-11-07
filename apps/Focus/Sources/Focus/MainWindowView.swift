import AppKit
import FocusCore
import SlopKit
import SwiftUI

/// Which view the main window shows (⌘1, ⌘2).
enum MainSection: String, CaseIterable, Identifiable {
    case timer, stats
    var id: String { rawValue }
    var title: String { self == .timer ? "Timer" : "Stats" }
    var symbol: String { self == .timer ? "timer" : "chart.bar.xaxis" }
}

@MainActor
@Observable
final class MainWindowState {
    var section: MainSection = .timer
    var side: SidePane.Tab = .today
    var stats = StatsState()
}

/// The main window: the timer on the left (category, intention, dial, controls), notes or
/// today's timeline on the right. Stats replaces both.
struct MainWindowView: View {
    @Bindable var controller: FocusController
    @Bindable var state: MainWindowState
    let intention: IntentionDraft
    let reflection: ReflectionDraft
    var snapshotNow: Date?

    var body: some View {
        Group {
            switch state.section {
            case .timer:
                HStack(spacing: 0) {
                    TimerPane(controller: controller, intention: intention, reflection: reflection, snapshotNow: snapshotNow)
                        .frame(width: 360)
                    Hairline(axis: .vertical)
                    SidePane(controller: controller, tab: $state.side, snapshotNow: snapshotNow)
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
            case .stats:
                StatsView(controller: controller, state: state.stats, snapshotNow: snapshotNow)
            }
        }
        .frame(minWidth: 700, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $state.section) {
                    ForEach(MainSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)
                .fixedSize()
                .help("Timer ⌘1 · Stats ⌘2")
            }
            if state.section == .stats {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Exporter.exportCSV(controller: controller)
                    } label: {
                        Label("Export CSV…", systemImage: "square.and.arrow.up")
                    }
                    .help("Export sessions as CSV")
                }
            }
        }
        .onChange(of: controller.runningPhase) { _, phase in
            // Notes while focusing, the timeline otherwise.
            state.side = phase == .focus ? .notes : .today
        }
        .onAppear {
            // Also when the window opens on a session that's already running.
            if snapshotNow == nil { state.side = controller.runningPhase == .focus ? .notes : .today }
        }
    }
}

/// Left half of the timer view.
struct TimerPane: View {
    /// Tall enough for the idle header (title, category pill, large field) and the running one.
    static let headerHeight: CGFloat = 116

    let controller: FocusController
    let intention: IntentionDraft
    let reflection: ReflectionDraft
    var snapshotNow: Date?

    var body: some View {
        let running = controller.state.run.map { !$0.isPaused } ?? false
        TimelineView(.periodic(from: .now, by: running ? min(1, max(0.05, controller.unit / 60)) : 30)) { context in
            content(now: snapshotNow ?? context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let display = TimerDisplay.make(controller, now: now)
        VStack(spacing: Spacing.m) {
            GoalDots(done: controller.today.sessions, goal: controller.settings.dailyGoal, tint: controller.category.tint)
                .padding(.top, Spacing.l)
            if let record = controller.pendingReflection, controller.runningPhase != .focus {
                ReflectionCard(controller: controller, record: record, draft: reflection)
                    .padding(Spacing.l)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    .padding(.horizontal, Spacing.l)
                Spacer(minLength: 0)
                smallDial(display)
                Spacer(minLength: 0)
            } else {
                header(display)
                    // A fixed slot: idle (heading, category, field) and running (category,
                    // a one- or two-line heading, Edit Intention) differ in height, and the
                    // dial must not move when a session starts.
                    .frame(height: Self.headerHeight, alignment: .top)
                Spacer(minLength: Spacing.s)
                FocusDial(minutes: display.minutes, tint: display.tint, time: display.time, caption: display.caption,
                          size: 230,
                          onSetMinutes: display.canDrag ? { minutes in controller.updateSettings { $0.focusMinutes = minutes } } : nil)
                adjustRow(display)
                Spacer(minLength: Spacing.s)
            }
            TimerControls(controller: controller, draft: intention)
                .padding(.bottom, Spacing.xl)
            notices
        }
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func header(_ display: TimerDisplay) -> some View {
        VStack(spacing: Spacing.s) {
            if controller.isIdle {
                Text(display.heading)
                    .font(.title2.weight(.semibold))
                CategoryPicker(controller: controller)
                IntentionField(controller: controller, text: Bindable(intention).text, placeholder: "Intention, e.g. Draft intro @work 45m",
                               large: true, alwaysSuggest: snapshotNow != nil) {
                    controller.startFocus(intention: intention.text)
                }
                .padding(.horizontal, Spacing.s)
                .onAppear { if intention.text.isEmpty { intention.text = controller.label ?? "" } }
            } else {
                CategoryPicker(controller: controller)
                    .disabled(controller.runningPhase?.isBreak ?? false)
                Text(display.heading)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button("Edit Intention…") { IntentionEditor.ask(controller: controller) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .opacity(controller.runningPhase == .focus ? 1 : 0)
                    .disabled(controller.runningPhase != .focus)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func adjustRow(_ display: TimerDisplay) -> some View {
        HStack(spacing: Spacing.m) {
            StepButton(title: "−5", label: "Remove 5 minutes") { adjust(by: -5) }
                .disabled(controller.isIdle ? controller.settings.focusMinutes <= 5 : !controller.canRemoveTime)
                .help("Remove 5 minutes (⇧⌘,)")
            Text(display.range)
                .font(.callout.monospacedDigit())
                .padding(.horizontal, Spacing.m)
                .frame(height: StepButton.side - Spacing.s)
                .hairlineBorder(Capsule())
                .accessibilityLabel("From \(display.range.replacingOccurrences(of: "→", with: "to"))")
            StepButton(title: "+5", label: "Add 5 minutes") { adjust(by: 5) }
                .help("Add 5 minutes (⇧⌘.)")
        }
    }

    private func adjust(by minutes: Int) {
        if controller.isIdle {
            controller.updateSettings { $0.focusMinutes += minutes }
        } else if minutes > 0 {
            controller.addTime()
        } else {
            controller.removeTime()
        }
    }

    private func smallDial(_ display: TimerDisplay) -> some View {
        FocusDial(minutes: display.minutes, tint: display.tint, time: display.time, caption: display.caption, size: 150)
    }

    @ViewBuilder private var notices: some View {
        if let error = controller.automationError ?? controller.saveError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Spacing.m)
        }
    }
}

/// Right half of the timer view: notes for the running session, or today's timeline.
struct SidePane: View {
    enum Tab: String, CaseIterable { case notes, today }

    let controller: FocusController
    @Binding var tab: Tab
    var snapshotNow: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(tab == .notes ? "Notes" : "Today")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("Show", selection: $tab) {
                    Image(systemName: "square.and.pencil").help("Notes").tag(Tab.notes).accessibilityLabel("Notes")
                    Image(systemName: "calendar.day.timeline.left").help("Today").tag(Tab.today).accessibilityLabel("Today")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            switch tab {
            case .notes: notes
            case .today: today
            }
        }
        .padding(Spacing.l)
    }

    @ViewBuilder private var notes: some View {
        let focusing = controller.runningPhase == .focus
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { controller.notes }, set: { controller.setNotes($0) }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(Spacing.s)
                .disabled(!focusing)
                .accessibilityLabel("Session notes")
            if controller.notes.isEmpty {
                Text(focusing ? "Thoughts, progress, what's blocking you. Saved with this session."
                              : "Notes are saved with the session you're focusing on. Start one to write here.")
                    .foregroundStyle(focusing ? AnyShapeStyle(Color(nsColor: .placeholderTextColor)) : AnyShapeStyle(.secondary))
                    // TextEditor's text starts 5 pt in from its own edge.
                    .padding(.leading, Spacing.s + 5) // lint:allow matches NSTextView's line fragment padding
                    .padding(.top, Spacing.s)
                    .allowsHitTesting(false)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .frame(maxHeight: .infinity)
        let recent = controller.todayRecords.filter { $0.isFocus && !($0.notes ?? "").isEmpty }.prefix(3)
        if !recent.isEmpty {
            Text("Earlier Today")
                .font(.headline)
            ForEach(Array(recent)) { record in
                SessionRow(record: record, categories: controller.settings.categories, unit: controller.unit)
            }
        }
    }

    @ViewBuilder private var today: some View {
        Text(controller.todayText.replacingOccurrences(of: "Today: ", with: "").capitalizedFirst)
            .font(.callout)
            .foregroundStyle(.secondary)
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = snapshotNow ?? context.date
            DayTimeline(blocks: TimelineBlock.blocks(for: controller, now: now), day: now, now: now,
                        calendar: controller.calendarInUse)
        }
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// "−5" / "+5" in a small circle.
struct StepButton: View {
    static let side: CGFloat = 34

    let title: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium).monospacedDigit())
                .frame(width: Self.side, height: Self.side)
                .background(.quaternary, in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Editing the intention while a session runs: a small alert with a text field.
@MainActor
enum IntentionEditor {
    static func ask(controller: FocusController) {
        let alert = NSAlert()
        alert.messageText = "What are you working on?"
        alert.informativeText = "Changes the intention of the running session and the next ones."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = controller.label ?? ""
        field.placeholderString = "Intention"
        field.setAccessibilityLabel("Intention")
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        AppActivation.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller.setLabel(field.stringValue)
    }
}
