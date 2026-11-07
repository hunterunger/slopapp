import DictateCore
import SlopKit
import SwiftUI

/// Filler words, formatting, replacements, AI cleanup, and a place to try them.
struct CleanupTab: View {
    let model: AppModel
    @Bindable var settings: DictateSettings
    @State private var sample = ""
    @State private var result = ""
    @State private var running = false

    var body: some View {
        let aiReason = model.ai.unavailableReason
        ScrollingSettingsForm(height: 560) {
            Section {
                Toggle(isOn: $settings.removeFillers) {
                    Text("Remove filler words")
                    Text("“Um”, “uh”, “er” and the like, with the commas around them.")
                }
                Toggle(isOn: $settings.lowercaseStyle) {
                    Text("Lowercase start, no final period")
                    Text("For dropping words into the middle of a sentence.")
                }
            }

            Section {
                if settings.replacements.isEmpty {
                    Text("Fix names and words the model gets wrong, like “Katie” → “Kaity”. Whole words, any case.")
                        .foregroundStyle(.secondary)
                }
                ForEach($settings.replacements) { $rule in
                    HStack(spacing: Spacing.s) {
                        TextField("Heard", text: $rule.from)
                            .labelsHidden()
                            .accessibilityLabel("Heard")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Write", text: $rule.to)
                            .labelsHidden()
                            .accessibilityLabel("Write instead")
                        Button {
                            settings.replacements.removeAll { $0.id == rule.id }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this replacement")
                        .accessibilityLabel("Remove replacement")
                    }
                }
            } header: {
                Text("Word replacements")
            } footer: {
                HStack {
                    Spacer()
                    Button("Add Replacement") { settings.replacements.append(Replacement()) }
                }
            }

            Section {
                Toggle(isOn: $settings.aiCleanup) {
                    Text("Polish with Apple Intelligence")
                    Text(aiReason ?? "Fixes punctuation and self-corrections on this Mac. Adds a moment after you stop.")
                }
                .disabled(aiReason != nil)
                if settings.aiCleanup && aiReason == nil {
                    Toggle("Fix self-corrections (“3, I mean 4” → “4”)", isOn: $settings.aiFixCorrections)
                    Toggle("Format spoken lists as lists", isOn: $settings.aiFormatLists)
                    Toggle("Fix grammar and punctuation", isOn: $settings.aiGrammar)
                    Toggle("Spell vocabulary words exactly", isOn: $settings.aiUseVocabulary)
                    if settings.aiUseVocabulary {
                        LabeledContent {
                            TextField("Vocabulary", text: $settings.customVocabulary, prompt: Text("Kaity\nSlopapp"), axis: .vertical)
                                .labelsHidden()
                                .lineLimit(2...6)
                        } label: {
                            Text("Vocabulary")
                            Text("Names and terms, one per line. Replacement targets count too.")
                        }
                    }
                    LabeledContent {
                        TextField("Extra instruction", text: $settings.aiCustomPrompt, prompt: Text("Use British spelling."),
                                  axis: .vertical)
                            .labelsHidden()
                            .lineLimit(1...4)
                    } label: {
                        Text("Extra instruction")
                        Text("Optional.")
                    }
                }
            } header: {
                Text("AI cleanup")
            }

            Section {
                TextField("Sample", text: $sample, prompt: Text("Type or paste something you might say…"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...5)
                    .accessibilityLabel("Sample text")
                HStack {
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Clean Up") { run() }
                        .disabled(sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || running)
                }
                if !result.isEmpty {
                    Text(result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Result: \(result)")
                }
            } header: {
                Text("Try it")
            } footer: {
                Text("Runs your sample through the same steps as a dictation, without per-app changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        running = true
        let input = sample
        Task {
            result = await model.processor.process(input, config: settings.cleanupConfig(forBundleID: nil))
            running = false
        }
    }
}
