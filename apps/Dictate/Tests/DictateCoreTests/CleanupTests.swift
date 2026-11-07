import Foundation
import Testing
@testable import DictateCore

@Suite("Rule-based cleanup")
struct CleanupTests {
    @Test("Filler words go, with the commas around them", arguments: [
        ("Um, so we should ship it.", "So we should ship it."),
        ("I was, uh, thinking about it", "I was, thinking about it"),
        ("Well um I think so", "Well I think so"),
        ("Yes, um. Okay", "Yes. Okay"),
        ("Okay. Um, so it works", "Okay. So it works"),
        ("UH hello", "Hello"),
        ("hmm", ""),
    ])
    func fillers(input: String, expected: String) {
        #expect(TextCleanup.removeFillers(input) == expected)
    }

    @Test func fillersLeaveRealWordsAlone() {
        let text = "The umbrella and the hummingbird erupted. Errands, ahead, umami."
        #expect(TextCleanup.removeFillers(text) == text)
    }

    @Test func textWithoutFillersIsUnchanged() {
        // Not even re-capitalized: tidying only runs when something was removed.
        #expect(TextCleanup.removeFillers("lowercase start, no fillers") == "lowercase start, no fillers")
    }

    @Test func replacementsAreWholeWordAndCaseInsensitive() {
        let rules = [Replacement(from: "katie", to: "Kaity"), Replacement(from: "swift ui", to: "SwiftUI")]
        #expect(TextCleanup.applyReplacements("Katie loves swift UI. Katies too.", rules)
            == "Kaity loves SwiftUI. Katies too.")
    }

    @Test func replacementsHandleSymbolsAndTemplates() {
        let rules = [Replacement(from: "c sharp", to: "C#"), Replacement(from: "dollar", to: "$1 \\0")]
        #expect(TextCleanup.applyReplacements("I write c sharp for a dollar", rules) == "I write C# for a $1 \\0")
        let dotted = [Replacement(from: ".net", to: "dotnet")]
        #expect(TextCleanup.applyReplacements("I like .NET and asp.net", dotted) == "I like dotnet and asp.net")
    }

    @Test func emptyReplacementIsIgnored() {
        #expect(TextCleanup.applyReplacements("keep me", [Replacement(from: "  ", to: "x")]) == "keep me")
    }

    @Test("Lowercase style", arguments: [
        ("Hello there.", "hello there"),
        ("Done...", "done"),
        ("I think so.", "I think so"),
        ("NASA launched.", "NASA launched"),
        ("Okay.\n", "okay"),
        ("", ""),
    ])
    func lowercaseStyle(input: String, expected: String) {
        #expect(TextCleanup.applyLowercaseStyle(input) == expected)
    }

    @Test("Silence annotations count as nothing said", arguments: [
        "", "   ", "[BLANK_AUDIO]", "(silence)", "[MUSIC] [NOISE]", "<|nospeech|>", "*cough*", " . ",
    ])
    func silence(raw: String) {
        #expect(TextCleanup.meaningfulText(raw) == nil)
    }

    @Test func speechKeepsItsParentheticals() {
        #expect(TextCleanup.meaningfulText("  Buy milk (the oat kind).  ") == "Buy milk (the oat kind).")
        #expect(TextCleanup.meaningfulText("[MUSIC] Hello there") == "Hello there")
        #expect(TextCleanup.meaningfulText("42") == "42")
    }

    @Test func vocabularyTermsMergeAndDedupe() {
        let terms = Vocabulary.terms(vocabulary: "Kaity\nSlopapp, WhisperKit\n\n",
                                     replacements: [Replacement(from: "katie", to: "Kaity"), Replacement(from: "x", to: "Parakeet")])
        #expect(terms == ["Kaity", "Slopapp", "WhisperKit", "Parakeet"])
    }

    @Test func teachingAWordAppendsOnce() {
        #expect(Vocabulary.adding("Kaity", to: "") == "Kaity")
        #expect(Vocabulary.adding(" Slopapp ", to: "Kaity\n") == "Kaity\nSlopapp")
        #expect(Vocabulary.adding("kaity", to: "Kaity, Other") == nil)
        #expect(Vocabulary.adding("  ", to: "Kaity") == nil)
    }
}

@Suite("AI prompts")
struct PromptTests {
    @Test func instructionsFollowTheToggles() {
        let all = AIPrompts.cleanupInstructions(AICleanupOptions(vocabularyTerms: ["Kaity"], customPrompt: "Use British spelling."))
        #expect(all.contains("self-corrections"))
        #expect(all.contains("list"))
        #expect(all.contains("punctuation"))
        #expect(all.contains("Kaity"))
        #expect(all.hasSuffix("Use British spelling."))

        let none = AIPrompts.cleanupInstructions(AICleanupOptions(fixCorrections: false, formatLists: false, grammar: false,
                                                                   customVocabulary: false, vocabularyTerms: ["Kaity"]))
        #expect(!none.contains("self-corrections"))
        #expect(!none.contains("Kaity"))
        #expect(none.contains("Never add information"))
    }

    @Test("Replies lose stray wrapping", arguments: [
        ("\"Hello there.\"", "Hello there."),
        ("“Hello.”", "Hello."),
        ("Here is the cleaned transcript:\nHello there.", "Hello there."),
        ("```\nHello\n```", "Hello"),
        ("She said \"hi\" and \"bye\"", "She said \"hi\" and \"bye\""),
        ("  Plain.  ", "Plain."),
    ])
    func cleanReply(reply: String, expected: String) {
        #expect(AIPrompts.cleanReply(reply) == expected)
    }

    @Test func commandPromptHoldsBoth() {
        let prompt = AIPrompts.commandPrompt(instruction: "make it formal", text: "hey there")
        #expect(prompt.contains("Instruction: make it formal"))
        #expect(prompt.hasSuffix("hey there"))
    }
}

@Suite("Cleanup pipeline")
@MainActor
struct PipelineTests {
    func settings() -> DictateSettings { DictateSettings(store: MemoryStore()) }

    @Test func ordersFillersReplacementsAIThenLowercase() async {
        let s = settings()
        s.replacements = [Replacement(from: "katie", to: "Kaity")]
        let ai = FakeAI()
        ai.reply = "Kaity said hello."
        let processor = TranscriptProcessor(settings: s, ai: ai)
        let config = CleanupConfig(removeFillers: true, lowercaseStyle: true, aiCleanup: true)
        let result = await processor.process("Um, katie said hello", config: config)
        #expect(ai.prompts.first?.prompt == "Kaity said hello")
        #expect(result == "kaity said hello")
    }

    @Test func aiSkippedWhenUnavailableOrOff() async {
        let s = settings()
        let ai = FakeAI(available: false)
        let processor = TranscriptProcessor(settings: s, ai: ai)
        let config = CleanupConfig(removeFillers: false, lowercaseStyle: false, aiCleanup: true)
        #expect(!processor.willRunAI(config))
        #expect(await processor.process("two words", config: config) == "two words")
        #expect(ai.prompts.isEmpty)

        let off = TranscriptProcessor(settings: s, ai: FakeAI())
        #expect(!off.willRunAI(CleanupConfig(removeFillers: false, lowercaseStyle: false, aiCleanup: false)))
    }

    @Test func aiSkipsSingleWordsAndKeepsTextOnFailure() async {
        let s = settings()
        let ai = FakeAI()
        let processor = TranscriptProcessor(settings: s, ai: ai)
        let config = CleanupConfig(removeFillers: false, lowercaseStyle: false, aiCleanup: true)
        #expect(await processor.process("Hello", config: config) == "Hello")
        #expect(ai.prompts.isEmpty)
        ai.reply = nil
        #expect(await processor.process("Hello there", config: config) == "Hello there")
        ai.reply = "   "
        #expect(await processor.process("Hello there", config: config) == "Hello there")
    }

    @Test func commandMode() async {
        let s = settings()
        let ai = FakeAI()
        ai.reply = "\"Good afternoon.\""
        let processor = TranscriptProcessor(settings: s, ai: ai)
        #expect(await processor.runCommand(instruction: "make it formal", on: "hey") == "Good afternoon.")
        #expect(ai.prompts.last?.instructions == AIPrompts.commandInstructions)
        #expect(await processor.runCommand(instruction: " ", on: "hey") == nil)
        #expect(await processor.runCommand(instruction: "x", on: "") == nil)
        #expect(TranscriptProcessor(settings: s, ai: FakeAI(available: false)).commandUnavailableReason != nil)
        #expect(processor.commandUnavailableReason == nil)
    }

    @Test func prewarmOnlyWhenAIWillRun() {
        let s = settings()
        let ai = FakeAI()
        let processor = TranscriptProcessor(settings: s, ai: ai)
        processor.prepare(for: CleanupConfig(removeFillers: false, lowercaseStyle: false, aiCleanup: false))
        #expect(ai.prewarmed == 0)
        processor.prepare(for: CleanupConfig(removeFillers: false, lowercaseStyle: false, aiCleanup: true))
        #expect(ai.prewarmed == 1)
    }
}
