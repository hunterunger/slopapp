import AppKit
import FocusCore
import SlopKit
import SwiftUI

/// Diagnostics: `FOCUS_SNAPSHOT_DIR=/tmp/x` renders the main window (idle, focusing, break,
/// reflection), Stats (day, week, month), the menu bar panel, the break screen and the new
/// Settings tabs offscreen to PNGs, light and dark, then quits. For reviewing the design when
/// the screen can't be driven (locked, or on CI). Uses made-up sessions in memory and a fixed
/// clock; never reads or writes real data (pair it with `FOCUS_DATA_DIR=/tmp/...` anyway).
@MainActor
enum Snapshots {
    static func runIfAsked() -> Bool {
        guard let directory = TestHooks.snapshotDirectory else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 14, minute: 20, second: 0, of: Date()) ?? Date()
        let info = AppInfo.current(fallbackName: "Focus")
        let savedTab = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        defer {
            if let savedTab { UserDefaults.standard.set(savedTab, forKey: SettingsTab.storageKey) } else { UserDefaults.standard.removeObject(forKey: SettingsTab.storageKey) }
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let mainSize = NSSize(width: 780, height: 580)

            // Idle, typing an intention: suggestions open.
            let idle = Scenario(now: now)
            idle.controller.setCategory("work")
            let typing = IntentionDraft()
            typing.text = "wri"
            render(MainWindowView(controller: idle.controller, state: MainWindowState(), intention: typing,
                                  reflection: ReflectionDraft(), snapshotNow: now),
                   size: mainSize, to: directory, "main-idle-\(name)")

            // Focusing, notes open.
            let focusing = Scenario(now: now)
            focusing.at(-11) { $0.startFocus(intention: "Draft chapter 3 @work") }
            focusing.controller.setNotes("Opening scene done.\nNeed a better hook for the second half; try starting with the letter.")
            let notesState = MainWindowState()
            notesState.side = .notes
            render(MainWindowView(controller: focusing.controller, state: notesState, intention: IntentionDraft(),
                                  reflection: ReflectionDraft(), snapshotNow: now),
                   size: mainSize, to: directory, "main-focus-\(name)")
            let timelineState = MainWindowState()
            render(MainWindowView(controller: focusing.controller, state: timelineState, intention: IntentionDraft(),
                                  reflection: ReflectionDraft(), snapshotNow: now),
                   size: mainSize, to: directory, "main-focus-timeline-\(name)")

            // A session just ended: break running, reflection waiting.
            let resting = Scenario(now: now, settings: TimerSettings(breakScreen: true))
            resting.at(-27) { $0.startFocus(intention: "Outline the talk @study") }
            resting.at(-1) { $0.setNotes("Three sections, intro still rough.") }
            resting.controller.refresh()
            let draft = ReflectionDraft()
            draft.sync(with: resting.controller.pendingReflection)
            draft.mood = .focused
            render(MainWindowView(controller: resting.controller, state: MainWindowState(), intention: IntentionDraft(),
                                  reflection: draft, snapshotNow: now),
                   size: mainSize, to: directory, "main-reflection-\(name)")
            render(BreakScreenView(controller: resting.controller, reflection: draft, snapshotNow: now),
                   size: NSSize(width: 1100, height: 760), to: directory, "break-screen-\(name)")
            resting.controller.skipReflection()
            render(MainWindowView(controller: resting.controller, state: MainWindowState(), intention: IntentionDraft(),
                                  reflection: ReflectionDraft(), snapshotNow: now),
                   size: mainSize, to: directory, "main-break-\(name)")

            // Stats.
            let statsSize = NSSize(width: 1040, height: 700)
            for period in StatsPeriod.allCases {
                let stats = MainWindowState()
                stats.section = .stats
                stats.stats.period = period
                stats.stats.anchor = now
                render(MainWindowView(controller: idle.controller, state: stats, intention: IntentionDraft(),
                                      reflection: ReflectionDraft(), snapshotNow: now),
                       size: statsSize, to: directory, "stats-\(period.rawValue)-\(name)")
            }

            // Menu bar panel.
            render(MenuPanel(controller: idle.controller, intention: IntentionDraft(), reflection: ReflectionDraft(), info: info, snapshotNow: now),
                   to: directory, "panel-idle-\(name)")
            render(MenuPanel(controller: focusing.controller, intention: IntentionDraft(), reflection: ReflectionDraft(), info: info, snapshotNow: now),
                   to: directory, "panel-focus-\(name)")
            let offered = Scenario(now: now, settings: TimerSettings(autoStartBreaks: false))
            offered.at(-26) { $0.startFocus(intention: "Inbox zero @work 25m") }
            offered.controller.refresh()
            render(MenuPanel(controller: offered.controller, intention: IntentionDraft(), reflection: ReflectionDraft(), info: info, snapshotNow: now),
                   to: directory, "panel-reflection-\(name)")

            // Settings tabs.
            let apps = [BlockedApp(bundleID: "com.apple.MobileSMS", name: "Messages"),
                        BlockedApp(bundleID: "com.apple.news", name: "News"),
                        BlockedApp(bundleID: "com.apple.Music", name: "Music")]
            let configured = Scenario(now: now, settings: TimerSettings(hideApps: true, blockedApps: apps))
            for tab in [SettingsTab.general, .timer, .categories, .blocking, .shortcuts] {
                SettingsTab.select(tab)
                render(FocusSettingsView(controller: configured.controller, info: info),
                       to: directory, "settings-\(tab.rawValue)-\(name)")
            }
        }
        return true
    }

    /// A controller over made-up history, with a clock the scenario moves.
    @MainActor
    final class Scenario {
        let clock: Clock
        let controller: FocusController
        let now: Date

        final class Clock { var now: Date; init(_ now: Date) { self.now = now } }

        init(now: Date, settings: TimerSettings = TimerSettings()) {
            self.now = now
            let clock = Clock(now)
            self.clock = clock
            let storage = MemoryStorage(settings: settings, history: SampleHistory.make(endingBefore: now.addingTimeInterval(-40 * 60)))
            controller = FocusController(
                storage: storage, notifier: LogNotifier(), sound: LogSound(), shortcuts: LogShortcutRunner(names: []),
                scheduler: IdleScheduler(), activity: NoActivity(), clock: { clock.now }
            )
        }

        /// Runs `action` `minutes` from now (negative: in the past), then returns to now.
        func at(_ minutes: Double, _ action: (FocusController) -> Void) {
            clock.now = now.addingTimeInterval(minutes * 60)
            action(controller)
            clock.now = now
        }
    }

    private final class IdleScheduler: Scheduler {
        struct Never: Cancellable { func cancel() {} }
        func schedule(after interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable { Never() }
    }

    private final class NoActivity: ActivityToken {
        func begin() {}
        func end() {}
    }

    private static func render<V: View>(_ view: V, size: NSSize? = nil, to directory: URL, _ name: String) {
        let hosting = NSHostingView(rootView: view)
        let fitting = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fitting), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: fitting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        // Paint the window background first: materials don't render offscreen.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        hosting.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        hosting.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        window.close()
    }
}

/// Plausible made-up sessions for the last five weeks (deterministic).
enum SampleHistory {
    static func make(endingBefore end: Date, calendar: Calendar = .current) -> [SessionRecord] {
        var seed: UInt64 = 42
        func next(_ n: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(n))
        }
        let plans: [(String, String?)] = [
            ("Draft chapter 3", "work"), ("Review pull requests", "work"), ("Write tests", "work"),
            ("Spanish flashcards", "study"), ("Read papers", "study"), ("Outline the talk", "study"),
            ("Budget", "personal"), ("Plan the trip", "personal"), ("Inbox zero", nil),
        ]
        let notes = ["Got further than expected.", "Kept checking chat, need to hide it.", "Finished the outline.", nil, nil, nil]
        var records: [SessionRecord] = []
        let today = calendar.startOfDay(for: end)
        for back in (0...34).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let count = (weekday == 1 || weekday == 7) ? next(3) : 3 + next(5)
            var cursor = day.addingTimeInterval(TimeInterval(8 * 3600 + next(4) * 1800))
            for _ in 0..<count {
                let (label, category) = plans[next(plans.count)]
                let length = [25, 25, 25, 45, 50][next(5)]
                let start = cursor
                let stop = start.addingTimeInterval(TimeInterval(length * 60))
                guard stop < end else { break }
                let mood: Mood? = [Mood.focused, .focused, .neutral, .distracted, nil][next(5)]
                records.append(SessionRecord(startedAt: start, endedAt: stop, planned: TimeInterval(length * 60),
                                             focused: TimeInterval(length * 60), completed: true, label: label,
                                             categoryID: category, mood: mood, notes: notes[next(notes.count)]))
                let rest = length >= 45 ? 10 : 5
                let restEnd = stop.addingTimeInterval(TimeInterval(rest * 60))
                if restEnd < end {
                    records.append(SessionRecord(startedAt: stop, endedAt: restEnd, planned: TimeInterval(rest * 60),
                                                 focused: TimeInterval(rest * 60), completed: true, label: nil, kind: .shortBreak))
                }
                cursor = restEnd.addingTimeInterval(TimeInterval(next(6) * 600))
            }
        }
        return records
    }
}
