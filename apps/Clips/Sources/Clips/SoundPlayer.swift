import AudioToolbox
import ClipsCore
import Foundation
import os

/// Plays Clips' sounds the way UI sounds play: as system sounds, through the "Play sound
/// effects through" device at the alert volume.
///
/// Every sound is synthesized (`SoundPairs`, `SoundSynthesis`) and written once to Clips'
/// caches folder as AIFF, named with `SoundPairs.version` so a file from an older synthesis
/// is never played. `prepare(_:)` renders the chosen pair and creates its sound IDs off the
/// main thread (at launch and when the choice changes), so a copy only ever plays an ID
/// that's ready. If one isn't yet (a copy in the first few milliseconds after launch, or a
/// Settings preview of a pair just picked), `play` waits for it on the same serial queue (or
/// renders it there): under a millisecond, once. One queue means a file is never rendered twice.
final class SystemSoundPlayer: SoundPlaying, Sendable {
    private let ids = OSAllocatedUnfairLock<[SoundEffect: SystemSoundID]>(initialState: [:])
    private let queue = DispatchQueue(label: "app.slopapp.clips.sounds", qos: .utility)

    func play(_ effect: SoundEffect) {
        guard let id = ids.withLock({ $0[effect] }) ?? queue.sync(execute: { loaded(effect) }) else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Renders the pair's files if needed and creates their IDs, in the background. The first
    /// call also removes files left by older versions.
    func prepare(_ choice: SoundChoice) {
        let effects = SoundKind.allCases.map { SoundEffect(choice, $0) }
        queue.async { [self] in
            Self.removeStaleFiles()
            for effect in effects { _ = loaded(effect) }
        }
    }

    /// The sound's ID, rendering its file and creating the ID if needed. Only on `queue`.
    private func loaded(_ effect: SoundEffect) -> SystemSoundID? {
        dispatchPrecondition(condition: .onQueue(queue))
        if let id = ids.withLock({ $0[effect] }) { return id }
        guard let url = Self.rendered(effect) else { return nil }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return nil }
        ids.withLock { [id] in $0[effect] = id }
        return id
    }

    /// The rendered file, written if it's missing (deterministic and versioned, so an
    /// existing one is right).
    private static func rendered(_ effect: SoundEffect) -> URL? {
        let folder = soundsFolder
        let url = folder.appending(path: effect.fileName)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SoundSynthesis.aiff(effect.render()).write(to: url, options: .atomic)
            Diagnostics.record("sound written name=\(effect.fileName)")
            return url
        } catch {
            Diagnostics.record("sound write failed name=\(effect.fileName)")
            return nil
        }
    }

    private static let staleFilesRemoved = OSAllocatedUnfairLock(initialState: false)

    /// Deletes sound files from other versions (e.g. the first version's `snap-v1.aiff`).
    private static func removeStaleFiles() {
        guard !staleFilesRemoved.withLock({ done in defer { done = true }; return done }) else { return }
        let suffix = "-v\(SoundPairs.version).aiff"
        let files = (try? FileManager.default.contentsOfDirectory(at: soundsFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "aiff" && !file.lastPathComponent.hasSuffix(suffix) {
            try? FileManager.default.removeItem(at: file)
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
