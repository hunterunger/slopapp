import Foundation

/// What Clips can play. The app's implementation uses AudioToolbox system sounds; tests fake it.
public enum SoundEffect: Hashable, Sendable {
    /// A copy was recorded.
    case copy(CopySound)
    /// Clips pasted or copied a clip for you (the soft "tock").
    case paste
}

public protocol SoundPlaying: AnyObject {
    func play(_ effect: SoundEffect)
}

/// The sound for a recorded copy. Snap is Clips' own (see `SoundSynthesis`) and the default;
/// the others are macOS system sounds (in /System/Library/Sounds), kept for anyone who chose one.
public enum CopySound: String, Sendable, CaseIterable, Identifiable {
    case snap = "Snap"
    case pop = "Pop"
    case tink = "Tink"
    case bottle = "Bottle"
    case morse = "Morse"
    case purr = "Purr"

    public var id: String { rawValue }
    public var title: String { rawValue }
    public var isSystemSound: Bool { self != .snap }
    /// New installs, and settings with no choice saved, get Snap. A saved "Pop" stays Pop.
    public static let `default` = CopySound.snap

    public static func saved(_ rawValue: String?) -> CopySound {
        rawValue.flatMap(CopySound.init) ?? .default
    }
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
    public var sound: CopySound
    /// Seconds between two sounds of the same kind at most.
    public let minimumInterval: TimeInterval

    private let player: SoundPlaying
    /// "Play user interface sound effects" in System Settings › Sound.
    private let systemSoundsEnabled: () -> Bool
    private let clock: () -> Date
    private var lastCopy: Date?
    private var lastPaste: Date?

    public init(player: SoundPlaying, isEnabled: Bool = true, playsPasteSound: Bool = true, sound: CopySound = .default,
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
        player.play(.paste)
        return true
    }

    /// Plays the copy sound once regardless of throttling (Settings preview).
    public func preview() {
        player.play(.copy(sound))
    }

    public func previewPaste() {
        player.play(.paste)
    }

    private func allowed(since last: inout Date?) -> Bool {
        let now = clock()
        if let last, now.timeIntervalSince(last) < minimumInterval { return false }
        last = now
        return true
    }
}
