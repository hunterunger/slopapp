import Foundation

/// Window moves Triggers offers (layout math in `WindowLayout`).
public enum WindowMove: String, Codable, Sendable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, minimize, nextDisplay

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .maximize: "Maximize"
        case .center: "Center"
        case .minimize: "Minimize"
        case .nextDisplay: "Next Display"
        }
    }
}

extension WindowMove {
    /// "Move Window to Left Half", "Maximize Window".
    public var actionTitle: String {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf, .nextDisplay: "Move Window to \(title)"
        case .maximize, .center, .minimize: "\(title) Window"
        }
    }
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

/// What a binding does. One action per binding in v1.
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
    /// Do nothing here and let the app have the input (overrides an all-apps binding).
    case passThrough

    /// Posting events and Accessibility calls need the Accessibility permission.
    public var needsAccessibility: Bool {
        switch self {
        case .pressKeys, .click, .menuItem, .window: true
        case .open, .runShortcut, .passThrough: false
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
        case .passThrough: return "Do nothing (let the app have it)"
        }
    }

    /// Whether the action is filled in enough to run.
    public var isComplete: Bool {
        switch self {
        case .menuItem(let path): return !path.isEmpty && path.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .open(.url(let url)): return OpenURLCheck.isOpenable(url)
        case .open(.file(let path)): return !path.isEmpty
        case .open(.app(let bundleID, _)): return !bundleID.isEmpty
        case .runShortcut(let name): return !name.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
}

/// Action kinds, for the picker in the editor.
public enum ActionKind: Hashable, Sendable {
    case pressKeys, middleClick, rightClick, commandClick, menuItem, openApp, openURL, openFile,
         runShortcut, window(WindowMove), passThrough

    public var title: String {
        switch self {
        case .pressKeys: "Press Keys"
        case .middleClick: "Middle Click"
        case .rightClick: "Right Click"
        case .commandClick: "Command-Click"
        case .menuItem: "Choose Menu Item"
        case .openApp: "Open App"
        case .openURL: "Open Link"
        case .openFile: "Open File"
        case .runShortcut: "Run Shortcut"
        case .window(let move): move.actionTitle
        case .passThrough: "Do Nothing"
        }
    }

    /// Picker groups, in order.
    public static let groups: [(title: String, kinds: [ActionKind])] = [
        ("Keyboard", [.pressKeys]),
        ("Click", [.middleClick, .rightClick, .commandClick]),
        ("App", [.menuItem, .openApp, .openURL, .openFile, .runShortcut]),
        ("Window", WindowMove.allCases.map { .window($0) }),
    ]

    /// A starting action of this kind, keeping what can be kept from `current`.
    public func defaultAction(from current: Action?) -> Action {
        if let current, current.kind == self { return current }
        switch self {
        case .pressKeys: return .pressKeys(KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command))
        case .middleClick: return .click(.middle)
        case .rightClick: return .click(.right)
        case .commandClick: return .click(.commandClick)
        case .menuItem: return .menuItem([])
        case .openApp: return .open(.app(bundleID: "", name: ""))
        case .openURL: return .open(.url(""))
        case .openFile: return .open(.file(path: ""))
        case .runShortcut: return .runShortcut("")
        case .window(let move): return .window(move)
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
