import Foundation

/// Which of Clips' sound pairs plays. Each choice is a copy sound and a paste sound, all
/// synthesized in code (see `SoundSynthesis` and `SoundPairs`); nothing is recorded or bundled.
public enum SoundChoice: String, Sendable, CaseIterable, Identifiable {
    case paper
    case glass
    case wood
    case bubble
    case snap
    case pluck
    /// Clips' first pair (the "snap" and "tock" from before there was a choice).
    case classic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paper: "Paper"
        case .glass: "Glass"
        case .wood: "Wood"
        case .bubble: "Bubble"
        case .snap: "Snap"
        case .pluck: "Pluck"
        case .classic: "Classic"
        }
    }

    public static let `default` = SoundChoice.paper

    /// The choice to use, given what's saved.
    ///
    /// - `saved`: the `soundChoice` key (written only when someone picks a sound).
    /// - `legacyCopySound`: the old `copySound` key, written only when someone picked a copy
    ///   sound in an earlier version. Its "Snap" was the first synthesized pair, so it maps to
    ///   Classic. The old macOS system sounds (Pop, Tink …) are gone; they get the default.
    ///
    /// Nobody who never picked a sound has either key, so they get Paper.
    public static func resolve(saved: String?, legacyCopySound: String?) -> SoundChoice {
        if let saved, let choice = SoundChoice(rawValue: saved) { return choice }
        if legacyCopySound == "Snap" { return .classic }
        return .default
    }
}

/// The sound settings, as saved in Clips' defaults.
public struct SoundSettings: Equatable, Sendable {
    public var playsCopySound: Bool
    public var playsPasteSound: Bool
    public var choice: SoundChoice

    public enum Keys {
        public static let playsCopySound = "playsCopySound"
        public static let playsPasteSound = "playsPasteSound"
        public static let soundChoice = "soundChoice"
        /// Before sound pairs: the copy sound someone picked ("Snap", "Pop" …). Read, never written.
        public static let legacyCopySound = "copySound"
    }

    /// Reads the settings (`value` looks a key up). Both sounds are on unless turned off; an
    /// "off" saved by any version stays off. Reading never writes anything back.
    public static func load(_ value: (String) -> Any?) -> SoundSettings {
        SoundSettings(
            playsCopySound: value(Keys.playsCopySound) as? Bool ?? true,
            playsPasteSound: value(Keys.playsPasteSound) as? Bool ?? true,
            choice: SoundChoice.resolve(saved: value(Keys.soundChoice) as? String,
                                        legacyCopySound: value(Keys.legacyCopySound) as? String)
        )
    }
}

/// Copy or paste.
public enum SoundKind: String, Sendable, CaseIterable {
    case copy
    case paste
}

/// What Clips can play. The app's implementation uses AudioToolbox system sounds; tests fake it.
public struct SoundEffect: Hashable, Sendable {
    public var choice: SoundChoice
    public var kind: SoundKind

    public init(_ choice: SoundChoice, _ kind: SoundKind) {
        self.choice = choice
        self.kind = kind
    }

    /// A copy was recorded.
    public static func copy(_ choice: SoundChoice) -> SoundEffect { SoundEffect(choice, .copy) }
    /// Clips pasted or copied a clip for you.
    public static func paste(_ choice: SoundChoice) -> SoundEffect { SoundEffect(choice, .paste) }

    /// The samples (mono, 44.1 kHz). Deterministic: the same every time.
    public func render() -> [Float] { SoundPairs.render(choice, kind) }

    /// The cached file's name. Bump `SoundPairs.version` when any synthesis changes, so
    /// files rendered by an older version are never played.
    public var fileName: String { "\(choice.rawValue)-\(kind.rawValue)-v\(SoundPairs.version).aiff" }
}

public protocol SoundPlaying: AnyObject {
    func play(_ effect: SoundEffect)
}

/// Decides when Clips makes a sound.
///
/// - **Copy**: only for a copy Clips actually recorded (never for skipped, ignored or
///   concealed content, and never for Clips' own writes: those don't count as copies, see
///   `ChangeTracker`).
/// - **Paste**: when Clips pastes or copies a clip for you (Return, ⌘1–⌘9, double-click,
///   the menus, History, a card dragged out). Never for ⌘V in other apps: Clips doesn't see those.
///
/// Both only when the user wants them and System Settings' "Play user interface sound
/// effects" is on, and never more than once per `minimumInterval` each, so bursts don't
/// machine-gun.
public final class CopyChime {
    public var isEnabled: Bool
    public var playsPasteSound: Bool
    public var sound: SoundChoice
    /// Seconds between two sounds of the same kind at most.
    public let minimumInterval: TimeInterval

    private let player: SoundPlaying
    /// "Play user interface sound effects" in System Settings › Sound.
    private let systemSoundsEnabled: () -> Bool
    private let clock: () -> Date
    private var lastCopy: Date?
    private var lastPaste: Date?

    public init(player: SoundPlaying, isEnabled: Bool = true, playsPasteSound: Bool = true, sound: SoundChoice = .default,
                minimumInterval: TimeInterval = 0.2,
                systemSoundsEnabled: @escaping () -> Bool, clock: @escaping () -> Date = Date.init) {
        self.player = player
        self.isEnabled = isEnabled
        self.playsPasteSound = playsPasteSound
        self.sound = sound
        self.minimumInterval = minimumInterval
        self.systemSoundsEnabled = systemSoundsEnabled
        self.clock = clock
    }

    /// Call when a new copy was recorded. Returns true if a sound played.
    @discardableResult
    public func copyRecorded() -> Bool {
        guard isEnabled, systemSoundsEnabled(), allowed(since: &lastCopy) else { return false }
        player.play(.copy(sound))
        return true
    }

    /// Call when Clips pasted or copied a clip for the user. Returns true if a sound played.
    @discardableResult
    public func clipUsed() -> Bool {
        guard playsPasteSound, systemSoundsEnabled(), allowed(since: &lastPaste) else { return false }
        player.play(.paste(sound))
        return true
    }

    /// Plays the copy sound once regardless of throttling (Settings preview).
    public func preview() {
        player.play(.copy(sound))
    }

    public func previewPaste() {
        player.play(.paste(sound))
    }

    private func allowed(since last: inout Date?) -> Bool {
        let now = clock()
        if let last, now.timeIntervalSince(last) < minimumInterval { return false }
        last = now
        return true
    }
}
