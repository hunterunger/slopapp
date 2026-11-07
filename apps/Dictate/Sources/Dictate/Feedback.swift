import AppKit
import DictateCore
import SlopKit

/// The recording ring, the start/stop sounds and short messages.
final class Feedback: DictationFeedback {
    private let ring = RecordingRing()
    private weak var controller: DictationController?
    private var audio: AudioCapturing?

    func attach(audio: AudioCapturing, controller: DictationController) {
        self.audio = audio
        self.controller = controller
    }

    func dictationStarted(mode: DictationMode) {
        guard let audio, let controller else { return }
        ring.show(audio: audio, controller: controller)
    }

    func dictationEnded(_ outcome: DictationOutcome) {
        ring.hideSoon(outcome: outcome)
    }

    func play(_ cue: SoundCue) {
        // System sounds, quiet and familiar.
        NSSound(named: cue == .start ? "Tink" : "Pop")?.play()
    }

    func notify(_ message: String, fix: ProblemFix?) {
        let symbol = switch fix {
        case .downloadModel: "arrow.down.circle"
        case .microphoneSettings: "mic.slash"
        case .accessibilitySettings: "accessibility"
        case nil: message.hasPrefix("Copied") ? "doc.on.clipboard" : "exclamationmark.circle"
        }
        HUD.show(message, systemImage: symbol, duration: .seconds(fix == nil && message.hasPrefix("Copied") ? 1.6 : 3.5))
    }
}
