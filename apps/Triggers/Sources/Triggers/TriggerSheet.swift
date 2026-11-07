import AppKit
import SlopKit
import SwiftUI
import TriggersCore

/// New / Edit Trigger. The top is a recognize-only pad: perform the gesture, press the mouse
/// button or the key combination and it names it. While the sheet is open nothing runs any
/// action (Triggers is recording), so the pad doubles as a safe way to check recognition.
struct TriggerSheet: View {
    @Bindable var model: AppModel
    @State private var binding: TriggerBinding
    @State private var isListening: Bool
    /// A new trigger has no input until one is recorded or picked.
    @State private var hasInput: Bool
    @State private var hint: String?
    @State private var keyMonitor: Any?
    private let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undo

    init(model: AppModel, draft: Draft) {
        self.model = model
        _binding = State(initialValue: draft.binding)
        _isListening = State(initialValue: draft.isNew)
        _hasInput = State(initialValue: !draft.isNew)
        isNew = draft.isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    DoItNowArea(trigger: hasInput ? binding.trigger : nil, isListening: isListening, fingers: model.liveFingers, hint: hint) {
                        startListening()
                    }
                    InputPicker(trigger: $binding.trigger) {
                        hasInput = true
                        stopListening()
                    }
                    if hasInput, binding.trigger.family != .keyboard {
                        ModifierRow(trigger: $binding.trigger)
                    }
                    if hasInput {
                        ConflictNotes(model: model, binding: binding)
                    }
                }
                Section {
                    ScopePicker(model: model, scope: $binding.scope)
                }
                Section {
                    ActionEditor(model: model, action: $binding.action, scope: binding.scope)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Hairline()
            HStack {
                if !isNew {
                    Toggle("On", isOn: $binding.isEnabled)
                        .toggleStyle(.checkbox)
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Done") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(Spacing.l)
        }
        .frame(width: 520)
        .frame(minHeight: 600, idealHeight: 660)
        .onAppear {
            model.startRecording()
            installMonitor()
        }
        .onDisappear {
            removeMonitor()
            model.stopRecording()
        }
        .onChange(of: model.recordedTrigger) { _, trigger in
            guard isListening, let trigger else { return }
            accept(trigger)
        }
    }

    private var canSave: Bool {
        guard hasInput, binding.action.isComplete else { return false }
        if case .keyCombo(let combo) = binding.trigger, !combo.isUsableAsTrigger { return false }
        if binding.action == .passThrough, binding.scope == .allApps { return false }
        return true
    }

    private func startListening() {
        hint = nil
        model.recordedTrigger = nil
        isListening = true
    }

    private func stopListening() { isListening = false }

    private func accept(_ trigger: Trigger) {
        binding.trigger = trigger
        hasInput = true
        hint = nil
        isListening = false
    }

    private func save() {
        model.commit(Draft(binding: binding, isNew: isNew), undo: undo)
        dismiss()
    }

    private func close() {
        if isListening {
            // Esc while listening stops listening; it doesn't close the sheet.
            stopListening()
            return
        }
        model.draft = nil
        dismiss()
    }

    /// Mouse buttons and key combinations pressed while listening, in this window only.
    private func installMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { event in
            let isKey = event.type == .keyDown
            let keyCode = isKey ? Int(event.keyCode) : 0
            let button = isKey ? 0 : event.buttonNumber
            let modifiers = Modifiers(cgFlags: UInt64(event.cgEvent?.flags.rawValue ?? 0))
            let consumed = MainActor.assumeIsolated {
                handle(isKey: isKey, keyCode: keyCode, button: button, modifiers: modifiers)
            }
            return consumed ? nil : event
        }
    }

    /// True when the event was used for recording (and shouldn't reach the sheet's controls).
    private func handle(isKey: Bool, keyCode: Int, button: Int, modifiers: Modifiers) -> Bool {
        guard isListening, !KeyRecorder.isActive else { return false }
        if !isKey {
            accept(.mouseButton(button, modifiers: modifiers))
            return true
        }
        if keyCode == KeyNames.escape, modifiers.isEmpty {
            stopListening()
            return true
        }
        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        if combo.isUsableAsTrigger {
            accept(.keyCombo(combo))
        } else {
            hint = "Hold ⌘, ⌥ or ⌃ with the key, so typing isn't affected."
        }
        return true
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// The big "do it now" target.
private struct DoItNowArea: View {
    let trigger: Trigger?
    let isListening: Bool
    let fingers: Int
    let hint: String?
    let listen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isListening ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isListening && fingers == 0 && !reduceMotion)
                .frame(height: 36)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(.horizontal, Spacing.l)
        .contentShape(Rectangle())
        .onTapGesture { if !isListening { listen() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isListening ? "Listening for an input" : "Input: \(trigger.map(KeyDisplay.title) ?? "none")")
        .accessibilityHint(isListening ? "Perform a gesture, press a mouse button or a key combination." : "Record a new input by doing it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isListening { listen() } }
    }

    private var symbol: String {
        if isListening { return fingers > 0 ? "hand.raised.fingers.spread" : "dot.radiowaves.left.and.right" }
        return trigger?.systemImage ?? "hand.tap"
    }

    private var title: String {
        if isListening {
            return fingers > 0 ? (fingers == 1 ? "1 finger" : "\(fingers) fingers") : "Listening…"
        }
        return trigger.map(KeyDisplay.title) ?? "No Input Yet"
    }

    private var subtitle: String {
        if let hint, isListening { return hint }
        if isListening { return "Tap or swipe with three or four fingers, press a mouse button, or press a key combination. Esc stops listening." }
        return trigger == nil ? "Click here, then do the gesture, button or keys." : "Click here to record a different input by doing it."
    }
}

/// Every supported input, for people who'd rather pick (and for VoiceOver).
private struct InputPicker: View {
    @Binding var trigger: Trigger
    let picked: () -> Void

    var body: some View {
        LabeledContent("Or pick from a list") {
            Menu("Choose…") {
                Section("Trackpad") {
                    ForEach(Gesture.supported, id: \.self) { gesture in
                        Button(gesture.title) { set(.gesture(gesture, modifiers: trigger.modifiers)) }
                    }
                }
                Section("Mouse") {
                    ForEach(2..<8, id: \.self) { button in
                        Button(Trigger.buttonName(button)) { set(.mouseButton(button, modifiers: trigger.modifiers)) }
                    }
                }
            }
            .fixedSize()
            .accessibilityLabel("Choose an input")
        }
    }


    private func set(_ new: Trigger) {
        trigger = new
        picked()
    }
}

/// Modifier keys to hold during a gesture or mouse button.
private struct ModifierRow: View {
    @Binding var trigger: Trigger

    var body: some View {
        LabeledContent("While holding") {
            HStack(spacing: Spacing.xs) {
                toggle(.control, "⌃", "Control")
                toggle(.option, "⌥", "Option")
                toggle(.shift, "⇧", "Shift")
                toggle(.command, "⌘", "Command")
            }
        }
    }

    private func toggle(_ modifier: Modifiers, _ symbol: String, _ name: String) -> some View {
        Toggle(isOn: Binding(
            get: { trigger.modifiers.contains(modifier) },
            set: { on in
                var modifiers = trigger.modifiers
                if on { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
                trigger = trigger.with(modifiers: modifiers)
            }
        )) {
            Text(symbol).frame(minWidth: 14)
        }
        .toggleStyle(.button)
        .help(name)
        .accessibilityLabel(name)
    }
}

/// What else uses this input, before it surprises anyone.
private struct ConflictNotes: View {
    let model: AppModel
    let binding: TriggerBinding

    var body: some View {
        let conflicts = model.conflicts(for: binding)
        if model.needsGestures(binding), let problem = model.gestureProblem {
            note(problem, warning: true)
        }
        ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
            HStack(alignment: .firstTextBaseline) {
                note(ConflictText.message(conflict), warning: conflict.isWarning)
                Spacer(minLength: Spacing.s)
                if case .system(let use) = conflict {
                    Button(use.settingsPane.buttonTitle) { NSWorkspace.shared.open(use.settingsPane.url) }
                        .controlSize(.small)
                } else if case .systemShortcut = conflict {
                    Button(SettingsPane.keyboardShortcuts.buttonTitle) { NSWorkspace.shared.open(SettingsPane.keyboardShortcuts.url) }
                        .controlSize(.small)
                } else if case .duplicate(let other) = conflict {
                    Button("Edit That One") { model.draft = Draft(binding: other, isNew: false) }
                        .controlSize(.small)
                }
            }
        }
    }

    private func note(_ text: String, warning: Bool) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "info.circle")
                .symbolRenderingMode(warning ? .multicolor : .hierarchical)
        }
        .font(.callout)
        .foregroundStyle(warning ? .primary : .secondary)
    }
}

/// Where the trigger works.
private struct ScopePicker: View {
    let model: AppModel
    @Binding var scope: Scope

    var body: some View {
        Picker("Works in", selection: $scope) {
            Text("All Apps").tag(Scope.allApps)
            Text("Browsers").tag(Scope.browsers)
            let apps = model.config.apps
            if !apps.isEmpty || extraApp != nil {
                Divider()
                ForEach(apps) { app in Text(app.name).tag(Scope.app(bundleID: app.bundleID)) }
                if let extraApp { Text(model.appName(extraApp)).tag(Scope.app(bundleID: extraApp)) }
            }
        }
    }

    /// An app scope that isn't in the sidebar yet (it's added on save).
    private var extraApp: String? {
        guard case .app(let id) = scope, model.config.app(id) == nil else { return nil }
        return id
    }
}
