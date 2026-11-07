import Foundation

/// What a menu item does. The app maps each to an action.
public enum MenuCommand: Hashable, Sendable {
    case turnOn
    case turnOff
    case start(AwakeDuration)
    case until
    case customDuration
    case whileRunning(AppRef)
    case extend
    case toggleDisplaySleep
    case toggleTriggers
    case setUpTriggers
    case settings
    case about
    case quit
}

/// One row of the status item menu, independent of AppKit so it can be tested and dumped.
public indirect enum MenuEntry: Equatable, Sendable {
    /// What Awake is doing ("25 min left"): non-clickable, and kept current while the menu is open.
    case status(String)
    /// Why Awake couldn't do what was asked, shown like the status line.
    case error(String)
    /// A grey, non-clickable line (an empty list).
    case text(String)
    /// A section header.
    case header(String)
    /// `key` is a ⌘ key equivalent. `showsToggleShortcut` displays the global shortcut.
    case item(String, MenuCommand, checked: Bool = false, key: String? = nil, showsToggleShortcut: Bool = false)
    case submenu(String, [MenuEntry])
    case separator
}

/// Builds the status item menu: status → on/off → durations → options → footer.
@MainActor
public enum MenuContent {
    public static func entries(for controller: AwakeController, appName: String) -> [MenuEntry] {
        let preferences = controller.preferences
        let session = controller.session
        var entries: [MenuEntry] = []

        if let status = controller.statusText { entries.append(.status(status)) }
        if let error = controller.lastError { entries.append(.error(error)) }
        if controller.isActive {
            entries.append(.item("Turn Off", .turnOff, showsToggleShortcut: true))
            if session?.endsAt != nil { entries.append(.item("Add 30 Minutes", .extend)) }
        } else {
            let duration = preferences.defaultDuration
            let title = duration == .indefinitely ? "Turn On" : "Turn On for \(duration.title)"
            entries.append(.item(title, .turnOn, showsToggleShortcut: true))
        }
        entries.append(.separator)

        entries.append(.header("Keep Awake"))
        for duration in AwakeDuration.presets {
            entries.append(.item(duration.title, .start(duration), checked: session?.duration == duration))
        }
        let isCustomDuration = session?.duration.map { !AwakeDuration.presets.contains($0) } ?? false
        var isUntil = false
        if case .until = session?.kind { isUntil = true }
        entries.append(.item("Custom Duration…", .customDuration, checked: isCustomDuration))
        entries.append(.item("Until…", .until, checked: isUntil))

        var runningID: String?
        if case .whileRunning(let app) = session?.kind { runningID = app.bundleID }
        let apps = controller.runningApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let appItems: [MenuEntry] = apps.isEmpty
            ? [.text("No Apps Running")]
            : apps.map { .item($0.name, .whileRunning($0), checked: $0.bundleID == runningID) }
        entries.append(.submenu("While App Is Running", appItems))
        entries.append(.separator)

        entries.append(.item("Allow Display Sleep", .toggleDisplaySleep, checked: !preferences.keepDisplayOn))
        if preferences.hasTriggers {
            entries.append(.item("Use Triggers", .toggleTriggers, checked: preferences.triggersEnabled))
        } else {
            entries.append(.item("Set Up Triggers…", .setUpTriggers))
        }

        entries.append(.separator)
        entries.append(.item("Settings…", .settings, key: ","))
        entries.append(.item("About \(appName)", .about))
        entries.append(.separator)
        entries.append(.item("Quit \(appName)", .quit, key: "q"))
        return entries
    }

    /// A plain-text rendering ("✓ 1 Hour", indented submenus) for tests and diagnostics.
    public static func dump(_ entries: [MenuEntry], indent: String = "") -> String {
        entries.map { entry in
            switch entry {
            case .status(let text), .error(let text), .text(let text): return "\(indent)[\(text)]"
            case .header(let title): return "\(indent)== \(title) =="
            case .item(let title, _, let checked, let key, let shortcut):
                return indent + (checked ? "✓ " : "  ") + title + (key.map { "  ⌘\($0.uppercased())" } ?? "")
                    + (shortcut ? "  (global shortcut)" : "")
            case .submenu(let title, let children):
                return "\(indent)  \(title) ▸\n" + dump(children, indent: indent + "    ")
            case .separator: return "\(indent)----"
            }
        }.joined(separator: "\n")
    }
}
