import AppKit
import FocusCore
import SlopKit
import SwiftUI

/// The menu bar panel: category and goal, a small dial with the time, the intention, the
/// controls, today's total, then Open Focus / Stats and the Settings, About and Quit footer.
struct MenuPanel: View {
    let controller: FocusController
    let intention: IntentionDraft
    let reflection: ReflectionDraft
    let info: AppInfo
    var snapshotNow: Date?

    var body: some View {
        let running = controller.state.run.map { !$0.isPaused } ?? false
        TimelineView(.periodic(from: .now, by: running ? min(1, max(0.05, controller.unit / 60)) : 30)) { context in
            content(now: snapshotNow ?? context.date)
        }
        .frame(width: Metrics.menuBarWindowWidth)
        .onAppear { if intention.text.isEmpty { intention.text = controller.label ?? "" } }
    }

    private func content(now: Date) -> some View {
        let display = TimerDisplay.make(controller, now: now)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                CategoryPicker(controller: controller, compact: true)
                    .disabled(controller.runningPhase?.isBreak ?? false)
                Spacer()
                GoalDots(done: controller.today.sessions, goal: min(controller.settings.dailyGoal, 10),
                         tint: controller.category.tint, size: 6)
            }

            if let record = controller.pendingReflection, controller.runningPhase != .focus {
                ReflectionCard(controller: controller, record: record, draft: reflection, compact: true)
                Hairline()
            }

            HStack(spacing: Spacing.l) {
                FocusDial(minutes: display.minutes, tint: display.tint, time: display.time, caption: display.caption, size: 104)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(panelHeading(display))
                        .font(.headline)
                        .lineLimit(2)
                    Text(display.range)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(controller.todayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if controller.isIdle {
                IntentionField(controller: controller, text: Bindable(intention).text, placeholder: "Intention, e.g. Email @work 15m",
                               alwaysSuggest: false) {
                    controller.startFocus(intention: intention.text)
                }
            }

            HStack(spacing: Spacing.s) {
                TimerControls(controller: controller, draft: intention, compact: true)
                if controller.runningPhase != nil {
                    Spacer()
                    StepButton(title: "−5", label: "Remove 5 minutes") { controller.removeTime() }
                        .disabled(!controller.canRemoveTime)
                    StepButton(title: "+5", label: "Add 5 minutes") { controller.addTime() }
                }
            }
            .frame(maxWidth: .infinity)

            notices
            Hairline()
            PanelFooter(info: info) {
                PanelRow(title: "Open Focus Window", shortcut: "0") { FocusWindow.show(.timer) }
                PanelRow(title: "Stats", shortcut: "2") { FocusWindow.show(.stats) }
            }
        }
        .padding(Spacing.m)
        .padding(.top, Spacing.xs)
    }

    private func panelHeading(_ display: TimerDisplay) -> String {
        guard controller.isIdle else { return display.heading }
        if controller.state.pendingBreak != nil { return "Session done" }
        return controller.label ?? "Ready to focus"
    }

    @ViewBuilder private var notices: some View {
        if controller.permission == .denied {
            NotificationsOffNotice(appName: info.name)
        }
        if let error = controller.automationError {
            HStack {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") { controller.dismissAutomationError() }
                    .controlSize(.small)
            }
        }
        if let error = controller.saveError {
            Text(error).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// "Notifications are off for Focus." with a link to System Settings: the panel and
/// Settings ▸ General show it when notifications were turned off, so the alert sound and the
/// bell in the menu bar are explained.
struct NotificationsOffNotice: View {
    let appName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: "bell.slash")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off for \(appName).")
                Text("When time is up, a bell flashes in the menu bar instead (and the sound plays, if it's on).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Notification Settings…") { NSWorkspace.shared.open(SystemNotifier.settingsURL) }
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A menu-like row for a `.window`-style menu bar panel (candidate for SlopKit).
struct PanelRow: View {
    /// The menu bar window's corner, measured on macOS 27 (`scripts/measure corners`: 17 pt);
    /// SwiftUI can't read it. Rows sit 8 pt in from its sides, so the hover highlight is
    /// concentric at 17 − 8.
    static let systemPanelRadius: CGFloat = 17
    static let highlightRadius = Radius.nested(in: systemPanelRadius, padding: Spacing.s)

    let title: String
    let symbol: String?
    var shortcut: KeyEquivalent?
    let action: () -> Void
    @State private var hovering = false

    init(title: String, symbol: String? = nil, shortcut: KeyEquivalent? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .frame(width: 16)
                        .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
                Text(title)
                Spacer()
                if let shortcut {
                    Text("⌘\(String(shortcut.character).uppercased())")
                        .foregroundStyle(hovering ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
            }
            .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: Self.highlightRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(OptionalShortcut(key: shortcut))
        .accessibilityLabel(title)
    }

    private struct OptionalShortcut: ViewModifier {
        let key: KeyEquivalent?
        func body(content: Content) -> some View {
            if let key { content.keyboardShortcut(key, modifiers: .command) } else { content }
        }
    }
}

/// The end of a `.window`-style menu bar panel: the app's own rows, then Settings…, About,
/// Report a Problem… and Quit, like SlopKit's `MenuFooter` for `.menu` menus (candidate for SlopKit).
struct PanelFooter<Rows: View>: View {
    let info: AppInfo
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            rows
            // Text only, like Golden Gate's menus (no decorative icons beside commands).
            PanelRow(title: "Settings…", shortcut: ",") { FocusSettingsOpener.open(nil) }
            PanelRow(title: "About \(info.name)") { AboutWindow.show(info: info) }
            PanelRow(title: IssueReport.Kind.problem.title) { IssueReport.open(.problem, info: info) }
            PanelRow(title: "Quit \(info.name)", shortcut: "q") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, -Spacing.xs)
    }
}

