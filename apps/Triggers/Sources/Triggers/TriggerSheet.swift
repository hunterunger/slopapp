import AppKit
import SlopKit
import SwiftUI
import TriggersCore

/// New / Edit Trigger. The top is a recognize-only pad: perform the gesture, press the mouse
/// button, the key combination or the key sequence and it names it. While the sheet is open
/// nothing runs any action (Triggers is recording), so the pad doubles as a safe way to check
/// recognition. Below: where it works, when (conditions), and what it does (steps).
struct TriggerSheet: View {
    @Bindable var model: AppModel
    @State private var binding: TriggerBinding
    @State private var isListening: Bool
    /// A new trigger has no input until one is recorded or picked.
    @State private var hasInput: Bool
    @State private var hint: String?
    @State private var keyMonitor: Any?
    /// Keys pressed while listening, so a second press turns a combination into a sequence.
    @State private var keys = KeySequenceRecorder(timeout: TriggerSheet.recordingGap)
    /// After a key input is recorded, more presses within the gap still extend it.
    @State private var keysOpenUntil: Double = 0
    @State private var liveKeys: [KeyStep] = []
    private let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undo

    /// Longest pause between presses while recording a sequence.
    static let recordingGap = 1.0

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
                    DoItNowArea(trigger: hasInput ? binding.trigger : nil, isListening: isListening, fingers: model.liveFingers,
                                liveKeys: liveKeys, hint: hint) {
                        startListening()
                    }
                    InputPicker(trigger: $binding.trigger) {
                        hasInput = true
                        stopListening()
                    }
                    if hasInput, binding.trigger.takesModifiers {
                        ModifierRow(trigger: $binding.trigger)
                    }
                    if hasInput, case .keySequence(let sequence) = binding.trigger, sequence.steps.count > 1 {
                        Picker(selection: Binding(
                            get: { sequence.timeout },
                            set: { binding.trigger = .keySequence(KeySequence(sequence.steps, timeout: $0)) }
                        )) {
                            ForEach(KeySequence.timeouts, id: \.self) { Text(ActionStep.seconds($0)).tag($0) }
                        } label: {
                            Text("Time between presses")
                            Text("The keys still reach the app; Triggers only watches for them.")
                        }
                    }
                    if hasInput {
                        ConflictNotes(model: model, binding: binding)
                    }
                }
                Section {
                    ScopePicker(model: model, scope: $binding.scope)
                }
                ConditionsSection(model: model, conditions: $binding.conditions)
                StepsEditor(model: model, steps: $binding.steps, scope: binding.scope)
                if binding.steps.contains(where: { $0.action?.needsAccessibility == true }) || needsKeyboardTap, !model.isTrusted {
                    Section {
                        HStack {
                            Label("Needs Accessibility access.", systemImage: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.callout)
                            Spacer()
                            Button("Open System Settings") { model.openAccessibilitySettings() }
                                .controlSize(.small)
                        }
                    }
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
        .frame(width: 540)
        .frame(minHeight: 600, idealHeight: 680)
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
        .onChange(of: binding.scope) { _, scope in
            // "Do nothing" only exists outside All Apps.
            if scope == .allApps, binding.isPassThrough { binding.steps = [.action(.click(.middle))] }
        }
    }

    private var needsKeyboardTap: Bool {
        if case .keySequence = binding.trigger { return true }
        return false
    }

    private var canSave: Bool {
        guard hasInput, binding.isComplete else { return false }
        switch binding.trigger {
        case .keyCombo(let combo): if !combo.isUsableAsTrigger { return false }
        case .keySequence(let sequence): if !sequence.isUsable { return false }
        case .gesture(let gesture, _): if !gesture.isSupported { return false }
        case .mouseButton: break
        }
        if binding.isPassThrough, binding.scope == .allApps { return false }
        return true
    }

    private func startListening() {
        hint = nil
        model.recordedTrigger = nil
        keys.reset()
        liveKeys = []
        keysOpenUntil = 0
        isListening = true
    }

    private func stopListening() {
        isListening = false
        liveKeys = []
    }

    private func accept(_ trigger: Trigger) {
        binding.trigger = trigger
        hasInput = true
        hint = nil
        isListening = false
        if trigger.family != .keyboard {
            keysOpenUntil = 0
            liveKeys = []
        }
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

    /// Mouse buttons, keys and lone modifier taps, in this window only.
    private func installMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { event in
            let type = event.type
            let keyCode = type == .otherMouseDown ? 0 : Int(event.keyCode)
            let isRepeat = type == .keyDown && event.isARepeat
            let button = type == .otherMouseDown ? event.buttonNumber : 0
            let modifiers = Modifiers(cgFlags: UInt64(event.cgEvent?.flags.rawValue ?? 0))
            let time = event.timestamp
            let consumed = MainActor.assumeIsolated {
                handle(type, keyCode: keyCode, isRepeat: isRepeat, button: button, modifiers: modifiers, time: time)
            }
            return consumed ? nil : event
        }
    }

    /// True when the event was used for recording (and shouldn't reach the sheet's controls).
    private func handle(_ type: NSEvent.EventType, keyCode: Int, isRepeat: Bool, button: Int, modifiers: Modifiers, time: Double) -> Bool {
        guard !KeyRecorder.isActive else { return false }
        let extending = !isListening && time < keysOpenUntil && binding.trigger.family == .keyboard
        guard isListening || extending else { return false }
        switch type {
        case .otherMouseDown:
            guard isListening else { return false }
            accept(.mouseButton(button, modifiers: modifiers))
            return true
        case .keyDown:
            if keyCode == KeyNames.escape, modifiers.isEmpty, keys.steps.isEmpty || keys.isFinished(at: time) {
                if isListening { stopListening() }
                keysOpenUntil = 0
                return isListening || extending
            }
            record(keys.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, time: time), at: time)
            return true
        case .flagsChanged:
            record(keys.flagsChanged(modifiers, time: time), at: time)
            return false // modifiers also belong to whatever the person presses next
        default:
            return false
        }
    }

    private func record(_ result: KeySequenceRecorder.Result, at time: Double) {
        guard case .recording(let steps) = result, steps != liveKeys else { return }
        liveKeys = steps
        keysOpenUntil = time + TriggerSheet.recordingGap
        if let trigger = keys.trigger {
            accept(trigger)
        } else {
            // One plain key so far: that's typing, unless another press makes it a sequence.
            isListening = true
            hint = "Press another key to make a sequence (like G then H), or hold ⌘, ⌥ or ⌃ with the key."
        }
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
    let liveKeys: [KeyStep]
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
        .accessibilityHint(isListening ? "Perform a gesture, press a mouse button, a key combination or a key sequence." : "Record a new input by doing it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isListening { listen() } }
    }

    private var symbol: String {
        if isListening { return fingers > 0 ? "hand.raised.fingers.spread" : "dot.radiowaves.left.and.right" }
        return trigger?.systemImage ?? "hand.tap"
    }

    private var title: String {
        if isListening {
            if !liveKeys.isEmpty { return liveKeys.map { $0.title(keys: KeyDisplay.name) }.joined(separator: " ") + " …" }
            return fingers > 0 ? (fingers == 1 ? "1 finger" : "\(fingers) fingers") : "Listening…"
        }
        return trigger.map(KeyDisplay.title) ?? "No Input Yet"
    }

    private var subtitle: String {
        if let hint, isListening { return hint }
        if isListening { return "Tap, swipe, pinch or rotate on the trackpad, press a mouse button, a key combination, or keys one after another (⌘ twice). Esc stops listening." }
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
                    ForEach(Gesture.groups, id: \.title) { group in
                        Menu(group.title) {
                            ForEach(group.gestures, id: \.self) { gesture in
                                Button(gesture.title) { set(.gesture(gesture, modifiers: trigger.takesModifiers ? trigger.modifiers : [])) }
                            }
                        }
                    }
                }
                Section("Mouse") {
                    Menu("Buttons") {
                        ForEach(2..<8, id: \.self) { button in
                            Button(Trigger.buttonName(button)) { set(.mouseButton(button, modifiers: trigger.takesModifiers ? trigger.modifiers : [])) }
                        }
                    }
                }
                Section("Keyboard") {
                    Menu("Press a Modifier Twice") {
                        ForEach(Self.modifiers, id: \.0.rawValue) { modifier, name in
                            Button("\(name) Twice") { set(.keySequence(.doubleTap(modifier))) }
                        }
                    }
                    Menu("Tap a Modifier Alone") {
                        ForEach(Self.modifiers, id: \.0.rawValue) { modifier, name in
                            Button(name) { set(.keySequence(KeySequence([.modifierTap(modifier)]))) }
                        }
                    }
                }
            }
            .fixedSize()
            .accessibilityLabel("Choose an input")
        }
    }

    static let modifiers: [(Modifiers, String)] = [(.command, "Command (⌘)"), (.option, "Option (⌥)"), (.control, "Control (⌃)"), (.shift, "Shift (⇧)")]

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
            ModifierToggles(modifiers: Binding(get: { trigger.modifiers }, set: { trigger = trigger.with(modifiers: $0) }))
        }
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
