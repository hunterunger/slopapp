import Foundation

/// Window moves Triggers offers (layout math in `WindowLayout`).
public enum WindowMove: String, Codable, Sendable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case maximize, center, minimize, nextDisplay, fullScreen

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .topLeftQuarter: "Top-Left Quarter"
        case .topRightQuarter: "Top-Right Quarter"
        case .bottomLeftQuarter: "Bottom-Left Quarter"
        case .bottomRightQuarter: "Bottom-Right Quarter"
        case .maximize: "Maximize"
        case .center: "Center"
        case .minimize: "Minimize"
        case .nextDisplay: "Next Display"
        case .fullScreen: "Full Screen"
        }
    }

    /// The area of the usable screen this move fills, for the simple moves (fractions,
    /// origin top left). Nil for moves that aren't a fixed area.
    public var area: UnitRect? {
        let third = 1.0 / 3
        switch self {
        case .leftHalf: return UnitRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return UnitRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return UnitRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return UnitRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .leftThird: return UnitRect(x: 0, y: 0, width: third, height: 1)
        case .centerThird: return UnitRect(x: third, y: 0, width: third, height: 1)
        case .rightThird: return UnitRect(x: 2 * third, y: 0, width: third, height: 1)
        case .leftTwoThirds: return UnitRect(x: 0, y: 0, width: 2 * third, height: 1)
        case .rightTwoThirds: return UnitRect(x: third, y: 0, width: 2 * third, height: 1)
        case .topLeftQuarter: return UnitRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRightQuarter: return UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeftQuarter: return UnitRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRightQuarter: return UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .maximize: return UnitRect(x: 0, y: 0, width: 1, height: 1)
        case .center, .minimize, .nextDisplay, .fullScreen: return nil
        }
    }
}

extension WindowMove {
    /// "Move Window to Left Half", "Maximize Window".
    public var actionTitle: String {
        switch self {
        case .maximize, .center, .minimize: "\(title) Window"
        case .fullScreen: "Toggle Full Screen"
        default: "Move Window to \(title)"
        }
    }
}

/// A part of the usable screen as fractions (0…1), origin top left: "the right 40%, top two
/// thirds". For the custom window action.
public struct UnitRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0.01 && height > 0.01
            && x + width <= 1.0001 && y + height <= 1.0001
    }

    /// "Left 50%, top 0%, 50% × 100%".
    public var summary: String {
        func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
        return "\(percent(width)) × \(percent(height)) at \(percent(x)), \(percent(y))"
    }
}

/// Media and hardware keys, posted as the keyboard's own special keys (macOS shows its
/// volume and brightness overlays as usual).
public enum MediaKey: String, Codable, Sendable, CaseIterable {
    case playPause, next, previous, volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    public var title: String {
        switch self {
        case .playPause: "Play or Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        }
    }

    /// The special key's number (`NX_KEYTYPE_*` in IOKit's ev_keymap.h).
    public var keyType: Int {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    /// `NSEvent` system-defined `data1` for the key going down or up.
    public func data1(down: Bool) -> Int { (keyType << 16) | ((down ? 0xA : 0xB) << 8) }
}

/// Things the Mac does, with no app involved.
public enum SystemAction: String, Codable, Sendable, CaseIterable {
    case missionControl, appExpose, showDesktop, launchpad, sleepDisplay, lockScreen, screenSaver, toggleDarkMode

    public var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .launchpad: SystemAction.hasAppsApp ? "Show Apps" : "Launchpad"
        case .sleepDisplay: "Sleep Display"
        case .lockScreen: "Lock Screen"
        case .screenSaver: "Start Screen Saver"
        case .toggleDarkMode: "Toggle Dark Mode"
        }
    }

    /// macOS 26 replaced Launchpad with the Apps view.
    public static var hasAppsApp: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 }
}

/// The language of a script action.
public enum ScriptLanguage: String, Codable, Sendable, CaseIterable {
    case shell, appleScript

    public var title: String { self == .shell ? "Shell Script" : "AppleScript" }
}

/// A click posted at the pointer.
public enum ClickKind: String, Codable, Sendable, CaseIterable {
    case middle, right, commandClick

    public var title: String {
        switch self {
        case .middle: "Middle Click"
        case .right: "Right Click"
        case .commandClick: "Command-Click"
        }
    }
}

/// Something to open.
public enum OpenTarget: Hashable, Codable, Sendable {
    case app(bundleID: String, name: String)
    case url(String)
    case file(path: String)
}

/// One thing a binding does. A binding runs one or more of these in order (`ActionStep`).
public enum Action: Hashable, Codable, Sendable {
    /// Press a key combination in the front app.
    case pressKeys(KeyCombo)
    case click(ClickKind)
    /// Choose a menu item in the front app by its title path, e.g. ["File", "Export…"].
    case menuItem([String])
    case open(OpenTarget)
    /// Run a Shortcut by name.
    case runShortcut(String)
    case window(WindowMove)
    /// Move and resize the front window to part of its screen.
    case windowArea(UnitRect)
    case media(MediaKey)
    case system(SystemAction)
    /// Type text into the front app, as if typed (the clipboard isn't touched).
    case typeText(String)
    /// Run a shell script (`zsh`) or an AppleScript.
    case script(ScriptLanguage, String)
    /// Do nothing here and let the app have the input (overrides an all-apps binding).
    case passThrough

    /// Posting events and Accessibility calls need the Accessibility permission.
    public var needsAccessibility: Bool {
        switch self {
        case .pressKeys, .click, .menuItem, .window, .windowArea, .media, .typeText: true
        case .system(let action): action == .lockScreen
        case .open, .runShortcut, .script, .passThrough: false
        }
    }

    /// The kind, for pickers.
    public var kind: ActionKind {
        switch self {
        case .pressKeys: .pressKeys
        case .click(let click):
            switch click {
            case .middle: .middleClick
            case .right: .rightClick
            case .commandClick: .commandClick
            }
        case .menuItem: .menuItem
        case .open(let target):
            switch target {
            case .app: .openApp
            case .url: .openURL
            case .file: .openFile
            }
        case .runShortcut: .runShortcut
        case .window(let move): .window(move)
        case .windowArea: .windowArea
        case .media(let key): .media(key)
        case .system(let action): .system(action)
        case .typeText: .typeText
        case .script(let language, _): language == .shell ? .shellScript : .appleScript
        case .passThrough: .passThrough
        }
    }

    /// "Press ⌘[" (US key names; the app shows the current layout's).
    public var fallbackTitle: String { title(keys: { $0.fallbackDisplay }) }

    /// A short summary, with key combos named by `keys`.
    public func title(keys: (KeyCombo) -> String) -> String {
        switch self {
        case .pressKeys(let combo): return "Press \(keys(combo))"
        case .click(let click): return click.title
        case .menuItem(let path): return path.isEmpty ? "Choose a menu item" : path.joined(separator: " › ")
        case .open(.app(_, let name)): return "Open \(name)"
        case .open(.url(let url)): return "Open \(url)"
        case .open(.file(let path)): return "Open \((path as NSString).lastPathComponent)"
        case .runShortcut(let name): return "Run “\(name)”"
        case .window(let move): return move.actionTitle
        case .windowArea(let area): return "Move Window to \(area.summary)"
        case .media(let key): return key.title
        case .system(let action): return action.title
        case .typeText(let text): return "Type “\(Action.excerpt(text))”"
        case .script(let language, let source):
            let line = Action.excerpt(source)
            return line.isEmpty ? "Run \(language.title)" : "Run \(language.title): \(line)"
        case .passThrough: return "Do nothing (let the app have it)"
        }
    }

    /// The first line, shortened.
    static func excerpt(_ text: String, limit: Int = 32) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }

    /// Whether the action is filled in enough to run.
    public var isComplete: Bool {
        switch self {
        case .menuItem(let path): return !path.isEmpty && path.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .open(.url(let url)): return OpenURLCheck.isOpenable(url)
        case .open(.file(let path)): return !path.isEmpty
        case .open(.app(let bundleID, _)): return !bundleID.isEmpty
        case .runShortcut(let name): return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .typeText(let text): return !text.isEmpty
        case .script(_, let source): return !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .windowArea(let area): return area.isValid
        default: return true
        }
    }
}

/// Action kinds, for the picker in the editor.
public enum ActionKind: Hashable, Sendable {
    case pressKeys, typeText, middleClick, rightClick, commandClick, menuItem, openApp, openURL, openFile,
         runShortcut, shellScript, appleScript, window(WindowMove), windowArea, media(MediaKey), system(SystemAction), passThrough

    public var title: String {
        switch self {
        case .pressKeys: "Press Keys"
        case .typeText: "Type Text"
        case .middleClick: "Middle Click"
        case .rightClick: "Right Click"
        case .commandClick: "Command-Click"
        case .menuItem: "Choose Menu Item"
        case .openApp: "Open App"
        case .openURL: "Open Link"
        case .openFile: "Open File"
        case .runShortcut: "Run Shortcut"
        case .shellScript: "Run Shell Script"
        case .appleScript: "Run AppleScript"
        case .window(let move): move.actionTitle
        case .windowArea: "Move Window to Custom Area"
        case .media(let key): key.title
        case .system(let action): action.title
        case .passThrough: "Do Nothing"
        }
    }

    /// Picker groups, in order.
    public static let groups: [(title: String, kinds: [ActionKind])] = [
        ("Keyboard", [.pressKeys, .typeText]),
        ("Click", [.middleClick, .rightClick, .commandClick]),
        ("App", [.menuItem, .openApp, .openURL, .openFile, .runShortcut]),
        ("Script", [.shellScript, .appleScript]),
        ("Media", MediaKey.allCases.map { .media($0) }),
        ("System", SystemAction.allCases.map { .system($0) }),
        ("Window", WindowMove.allCases.map { .window($0) } + [.windowArea]),
    ]

    /// A starting action of this kind, keeping what can be kept from `current`.
    public func defaultAction(from current: Action?) -> Action {
        if let current, current.kind == self { return current }
        switch self {
        case .pressKeys: return .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command))
        case .typeText: return .typeText("")
        case .middleClick: return .click(.middle)
        case .rightClick: return .click(.right)
        case .commandClick: return .click(.commandClick)
        case .menuItem: return .menuItem([])
        case .openApp: return .open(.app(bundleID: "", name: ""))
        case .openURL: return .open(.url(""))
        case .openFile: return .open(.file(path: ""))
        case .runShortcut: return .runShortcut("")
        case .shellScript:
            if case .script(.appleScript, let source)? = current { return .script(.shell, source) }
            return .script(.shell, "")
        case .appleScript:
            if case .script(.shell, let source)? = current { return .script(.appleScript, source) }
            return .script(.appleScript, "")
        case .window(let move): return .window(move)
        case .windowArea: return .windowArea(UnitRect(x: 0.25, y: 0, width: 0.5, height: 1))
        case .media(let key): return .media(key)
        case .system(let action): return .system(action)
        case .passThrough: return .passThrough
        }
    }
}

/// Which links "Open Link" accepts: web links and app URL schemes, never file or script URLs.
public enum OpenURLCheck {
    public static func isOpenable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        let blocked: Set<String> = ["file", "javascript", "data"]
        if blocked.contains(scheme) { return false }
        if scheme == "http" || scheme == "https" { return url.host?.isEmpty == false }
        return trimmed.count > scheme.count + 1
    }
}
