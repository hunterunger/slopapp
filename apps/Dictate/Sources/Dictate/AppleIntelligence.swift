import DictateCore
import Foundation
import FoundationModels

/// AI cleanup and Command Mode through Apple Intelligence's on-device model. Nothing leaves
/// the Mac. When the model isn't available, everything degrades to "no AI" with a reason.
final class AppleIntelligence: AITextService {
    /// A session loaded ahead of time for the next request with the same instructions.
    private var warmSession: (instructions: String, session: LanguageModelSession)?

    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn on Apple Intelligence in System Settings to use it."
        case .unavailable(.modelNotReady):
            "Apple Intelligence is still getting ready. Try again soon."
        case .unavailable:
            "Apple Intelligence isn't available right now."
        }
    }

    func prewarm(instructions: String) {
        guard isAvailable, warmSession?.instructions != instructions else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        warmSession = (instructions, session)
    }

    func respond(instructions: String, prompt: String) async -> String? {
        guard isAvailable else { return nil }
        // A session keeps a transcript; use each one once so requests don't leak into each other.
        let session: LanguageModelSession
        if let warm = warmSession, warm.instructions == instructions {
            session = warm.session
            warmSession = nil
        } else {
            session = LanguageModelSession(instructions: instructions)
        }
        let start = Diagnostics.now()
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2))
            Diagnostics.record("ai ms=\(Diagnostics.milliseconds(since: start))")
            return response.content
        } catch {
            Diagnostics.record("ai failed \(error.localizedDescription)")
            return nil
        }
    }
}
