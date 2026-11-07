import Foundation

/// The macOS trackpad gestures that matter for conflicts, read (never written) from the
/// trackpad preference domains and the Dock's. `read` returns an integer preference or nil.
public struct SystemGestureSettings: Equatable, Sendable {
    public enum HorizontalUse: Equatable, Sendable { case off, pages, fullScreenApps }

    public var threeFingerDrag = false
    public var threeFingerTapLookUp = false
    public var threeFingerHorizontal: HorizontalUse = .off
    public var fourFingerHorizontal = false
    public var threeFingerVertical = false
    public var fourFingerVertical = false
    public var missionControlGesture = true
    public var appExposeGesture = false

    public init() {}

    public static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
    public static let dockDomain = "com.apple.dock"

    /// Reads both trackpad domains (built-in and Bluetooth); a gesture counts as used if either
    /// uses it. Missing keys fall back to macOS's defaults.
    public init(read: (_ key: String, _ domain: String) -> Int?) {
        func any(_ key: String, default value: Int, where test: (Int) -> Bool) -> Bool {
            let values = Self.domains.map { read(key, $0) }
            if values.allSatisfy({ $0 == nil }) { return test(value) }
            return values.compactMap { $0 }.contains(where: test)
        }
        threeFingerDrag = any("TrackpadThreeFingerDrag", default: 0) { $0 != 0 }
        threeFingerTapLookUp = any("TrackpadThreeFingerTapGesture", default: 0) { $0 == 2 }
        if any("TrackpadThreeFingerHorizSwipeGesture", default: 2, where: { $0 == 2 }) {
            threeFingerHorizontal = .fullScreenApps
        } else if any("TrackpadThreeFingerHorizSwipeGesture", default: 2, where: { $0 == 1 }) {
            threeFingerHorizontal = .pages
        }
        fourFingerHorizontal = any("TrackpadFourFingerHorizSwipeGesture", default: 2) { $0 == 2 }
        threeFingerVertical = any("TrackpadThreeFingerVertSwipeGesture", default: 2) { $0 == 2 }
        fourFingerVertical = any("TrackpadFourFingerVertSwipeGesture", default: 2) { $0 == 2 }
        missionControlGesture = (read("showMissionControlGestureEnabled", Self.dockDomain) ?? 1) != 0
        appExposeGesture = (read("showAppExposeGestureEnabled", Self.dockDomain) ?? 0) != 0
    }

    /// What macOS does with this gesture, if anything.
    public func systemUse(of gesture: Gesture) -> SystemGestureUse? {
        if gesture.fingers == 3, threeFingerDrag { return .threeFingerDrag }
        switch (gesture.kind, gesture.fingers, gesture.direction) {
        case (.tap, 3, _):
            return threeFingerTapLookUp ? .lookUp : nil
        case (.swipe, 3, .left?), (.swipe, 3, .right?):
            switch threeFingerHorizontal {
            case .off: return nil
            case .pages: return .pages
            case .fullScreenApps: return .fullScreenApps
            }
        case (.swipe, 4, .left?), (.swipe, 4, .right?):
            return fourFingerHorizontal ? .fullScreenApps : nil
        case (.swipe, 3, .up?):
            return threeFingerVertical && missionControlGesture ? .missionControl : nil
        case (.swipe, 4, .up?):
            return fourFingerVertical && missionControlGesture ? .missionControl : nil
        case (.swipe, 3, .down?):
            return threeFingerVertical && appExposeGesture ? .appExpose : nil
        case (.swipe, 4, .down?):
            return fourFingerVertical && appExposeGesture ? .appExpose : nil
        default:
            return nil
        }
    }
}

/// A macOS gesture that overlaps one of ours.
public enum SystemGestureUse: Equatable, Sendable {
    case lookUp, pages, fullScreenApps, missionControl, appExpose, threeFingerDrag

    public var message: String {
        switch self {
        case .lookUp: "macOS also uses a three-finger tap for Look Up, so both will happen."
        case .pages: "macOS also uses this swipe to go back and forward between pages, so both will happen."
        case .fullScreenApps: "macOS also uses this swipe to move between full-screen apps and desktops, so both will happen."
        case .missionControl: "macOS also uses this swipe for Mission Control, so both will happen."
        case .appExpose: "macOS also uses this swipe for App Exposé, so both will happen."
        case .threeFingerDrag: "Three-finger drag is on, so macOS treats three fingers as dragging. Use four fingers, or turn three-finger drag off."
        }
    }

    /// Which System Settings pane changes it.
    public var settingsPane: SettingsPane { self == .threeFingerDrag ? .pointerControl : .trackpad }
}

public enum SettingsPane: Sendable, Equatable {
    case trackpad, pointerControl, keyboardShortcuts

    public var url: URL {
        switch self {
        case .trackpad: URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!
        case .pointerControl: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Pointer")!
        case .keyboardShortcuts: URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        }
    }

    public var buttonTitle: String {
        switch self {
        case .trackpad: "Open Trackpad Settings"
        case .pointerControl: "Open Pointer Control Settings"
        case .keyboardShortcuts: "Open Keyboard Settings"
        }
    }
}

/// Something worth telling the person about a binding before it surprises them.
public enum Conflict: Equatable, Sendable {
    /// macOS does something with the same gesture.
    case system(SystemGestureUse)
    /// Another enabled binding in the same place uses the same input; only one runs.
    case duplicate(TriggerBinding)
    /// macOS (or an app's menu) already uses this key combination.
    case systemShortcut
    /// Another app registered this key combination first, so it can't be used.
    case shortcutTaken
    /// The action presses the same keys as the trigger.
    case pressesItself
    /// Informational: in this app it replaces the All Apps (or Browsers) binding.
    case overrides(TriggerBinding)

    /// Warnings get an orange badge; informational notes don't.
    public var isWarning: Bool {
        if case .overrides = self { return false }
        return true
    }
}

/// Works out the conflicts for one binding (draft or saved) against the config and macOS.
public struct ConflictChecker: Sendable {
    public var system: SystemGestureSettings
    /// Key combos macOS uses (its symbolic hotkeys).
    public var systemShortcuts: Set<KeyCombo>
    /// Key combos Triggers couldn't register because another app holds them.
    public var unavailableShortcuts: Set<KeyCombo>

    public init(system: SystemGestureSettings = SystemGestureSettings(), systemShortcuts: Set<KeyCombo> = [], unavailableShortcuts: Set<KeyCombo> = []) {
        self.system = system
        self.systemShortcuts = systemShortcuts
        self.unavailableShortcuts = unavailableShortcuts
    }

    public func conflicts(for binding: TriggerBinding, in config: Config) -> [Conflict] {
        var result: [Conflict] = []
        switch binding.trigger {
        case .gesture(let gesture, _):
            if let use = system.systemUse(of: gesture) { result.append(.system(use)) }
        case .keyCombo(let combo):
            if unavailableShortcuts.contains(combo) {
                result.append(.shortcutTaken)
            } else if systemShortcuts.contains(combo) {
                result.append(.systemShortcut)
            }
            if case .pressKeys(let pressed) = binding.action, pressed == combo { result.append(.pressesItself) }
        case .mouseButton:
            break
        }
        let others = config.bindings.filter { $0.id != binding.id && $0.isEnabled && $0.trigger == binding.trigger }
        if let duplicate = others.first(where: { $0.scope == binding.scope }) {
            result.append(.duplicate(duplicate))
        }
        if binding.scope != .allApps {
            // The broader binding this one replaces in its app or group.
            let broader: [Scope] = binding.scope == .browsers ? [.allApps]
                : BrowserGroup.contains(binding.scope.bundleID) ? [.browsers, .allApps] : [.allApps]
            if let replaced = broader.lazy.compactMap({ scope in others.first { $0.scope == scope } }).first {
                result.append(.overrides(replaced))
            }
        }
        return result
    }
}
