import AudioToolbox
import ClipsCore
import Foundation

/// Plays Clips' sounds the way UI sounds play: as system sounds, through the "Play sound
/// effects through" device at the alert volume.
///
/// Clips' own sounds (Snap, Tock) are synthesized (`SoundSynthesis`) and written once to
/// Clips' caches folder as AIFF; their sound IDs are created at launch so the first copy
/// plays at once. The other copy sounds are macOS system sounds, loaded on first use.
final class SystemSoundPlayer: SoundPlaying {
    private var ids: [SoundEffect: SystemSoundID] = [:]

    /// Bump when the synthesis changes, so old files are replaced.
    static let version = 1

    func play(_ effect: SoundEffect) {
        guard let id = ids[effect] ?? load(effect) else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Writes Clips' own sounds if needed and creates their IDs (call at launch).
    func prepare() {
        for effect in [SoundEffect.copy(.snap), .paste] where ids[effect] == nil { _ = load(effect) }
    }

    private func load(_ effect: SoundEffect) -> SystemSoundID? {
        guard let url = Self.url(for: effect) else { return nil }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return nil }
        ids[effect] = id
        return id
    }

    private static func url(for effect: SoundEffect) -> URL? {
        switch effect {
        case .copy(let sound) where sound.isSystemSound:
            return URL(fileURLWithPath: "/System/Library/Sounds/\(sound.rawValue).aiff")
        case .copy:
            return rendered("snap") { SoundSynthesis.snap() }
        case .paste:
            return rendered("tock") { SoundSynthesis.tock() }
        }
    }

    /// The rendered file, written if it's missing (deterministic, so an existing one is right).
    private static func rendered(_ name: String, _ synthesize: () -> [Float]) -> URL? {
        let folder = soundsFolder
        let url = folder.appending(path: "\(name)-v\(version).aiff")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SoundSynthesis.aiff(synthesize()).write(to: url, options: .atomic)
            Diagnostics.record("sound written name=\(name)")
            return url
        } catch {
            Diagnostics.record("sound write failed name=\(name)")
            return nil
        }
    }

    /// Caches (or the test data folder under `CLIPS_DATA_DIR`).
    static var soundsFolder: URL {
        if let test = Diagnostics.dataDirectory { return test.appending(path: "Sounds", directoryHint: .isDirectory) }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: Bundle.main.bundleIdentifier ?? "app.slopapp.clips", directoryHint: .isDirectory)
            .appending(path: "Sounds", directoryHint: .isDirectory)
    }

    /// System Settings › Sound › "Play user interface sound effects" (on unless turned off).
    static var userInterfaceSoundsEnabled: Bool {
        (UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? NSNumber)?.boolValue ?? true
    }
}
