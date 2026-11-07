import Foundation

/// The user's timer preferences. Lengths are in minutes.
public struct TimerSettings: Codable, Equatable, Sendable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// A long break replaces the short one after this many sessions. 0 turns long breaks off.
    public var longBreakEvery: Int
    public var autoStartBreaks: Bool
    public var autoStartFocus: Bool
    public var showSeconds: Bool
    public var playSound: Bool
    public var soundName: String
    public var runShortcuts: Bool
    public var startShortcut: String?
    public var endShortcut: String?
    public var categories: [Category]
    /// Ask how the session went (mood and notes) when one ends.
    public var askReflection: Bool
    /// Cover the screen during breaks (easy to dismiss).
    public var breakScreen: Bool
    /// Hide the apps in `blockedApps` while a focus session runs.
    public var hideApps: Bool
    public var blockedApps: [BlockedApp]
    /// Sessions a day the goal dots count toward. 0 hides them.
    public var dailyGoal: Int

    public static let focusPresets = [15, 25, 45, 50]
    public static let focusRange = 1...180
    public static let breakRange = 1...60
    public static let longBreakEveryOptions = [0, 2, 3, 4, 5, 6, 7, 8]
    public static let minutesAdded = 5
    public static let dailyGoalRange = 0...16

    public init(
        focusMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        longBreakEvery: Int = 4,
        autoStartBreaks: Bool = true,
        autoStartFocus: Bool = false,
        showSeconds: Bool = false,
        playSound: Bool = true,
        soundName: String = "Glass",
        runShortcuts: Bool = false,
        startShortcut: String? = nil,
        endShortcut: String? = nil,
        categories: [Category] = Category.defaults,
        askReflection: Bool = true,
        breakScreen: Bool = false,
        hideApps: Bool = false,
        blockedApps: [BlockedApp] = [],
        dailyGoal: Int = 8
    ) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.longBreakEvery = longBreakEvery
        self.autoStartBreaks = autoStartBreaks
        self.autoStartFocus = autoStartFocus
        self.showSeconds = showSeconds
        self.playSound = playSound
        self.soundName = soundName
        self.runShortcuts = runShortcuts
        self.startShortcut = startShortcut
        self.endShortcut = endShortcut
        self.categories = categories
        self.askReflection = askReflection
        self.breakScreen = breakScreen
        self.hideApps = hideApps
        self.blockedApps = blockedApps
        self.dailyGoal = dailyGoal
    }

    /// Missing keys fall back to defaults, so older or hand-edited files still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TimerSettings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        longBreakEvery = try c.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? d.longBreakEvery
        autoStartBreaks = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? d.autoStartBreaks
        autoStartFocus = try c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? d.autoStartFocus
        showSeconds = try c.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? d.showSeconds
        playSound = try c.decodeIfPresent(Bool.self, forKey: .playSound) ?? d.playSound
        soundName = try c.decodeIfPresent(String.self, forKey: .soundName) ?? d.soundName
        runShortcuts = try c.decodeIfPresent(Bool.self, forKey: .runShortcuts) ?? d.runShortcuts
        startShortcut = try c.decodeIfPresent(String.self, forKey: .startShortcut)
        endShortcut = try c.decodeIfPresent(String.self, forKey: .endShortcut)
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? d.categories
        askReflection = try c.decodeIfPresent(Bool.self, forKey: .askReflection) ?? d.askReflection
        breakScreen = try c.decodeIfPresent(Bool.self, forKey: .breakScreen) ?? d.breakScreen
        hideApps = try c.decodeIfPresent(Bool.self, forKey: .hideApps) ?? d.hideApps
        blockedApps = try c.decodeIfPresent([BlockedApp].self, forKey: .blockedApps) ?? d.blockedApps
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? d.dailyGoal
        self = clamped()
    }

    /// Lengths pulled into their allowed ranges.
    public func clamped() -> TimerSettings {
        var s = self
        s.focusMinutes = Self.clamp(focusMinutes, to: Self.focusRange)
        s.shortBreakMinutes = Self.clamp(shortBreakMinutes, to: Self.breakRange)
        s.longBreakMinutes = Self.clamp(longBreakMinutes, to: Self.breakRange)
        s.longBreakEvery = longBreakEvery <= 0 ? 0 : Self.clamp(longBreakEvery, to: 2...8)
        s.dailyGoal = Self.clamp(dailyGoal, to: Self.dailyGoalRange)
        return s
    }

    public func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    /// Length in seconds. `unit` is the length of a minute: 60, except in accelerated tests.
    public func length(of phase: Phase, unit: TimeInterval = 60) -> TimeInterval {
        TimeInterval(minutes(for: phase)) * unit
    }

    public func category(id: String?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// An app hidden during focus sessions, by bundle id. The name is for display.
public struct BlockedApp: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}
