import AppKit
import Observation
import ShorthandCore
import SlopKit
import SwiftUI

/// The fill-in form's state: the fields, what's been filled in (memory only, never stored),
/// and which control has the keyboard. Shared by the floating form and the editor's Try It.
@MainActor
@Observable
final class FillInState {
    let title: String
    let fields: [FillField]
    var values: FillValues
    /// The key of the control with the keyboard.
    var focus: String?
    /// Plain-text preview of the result with the current values.
    @ObservationIgnored var preview: (FillValues) -> String
    @ObservationIgnored var onInsert: (FillValues) -> Void = { _ in }
    @ObservationIgnored var onCancel: () -> Void = {}

    init(title: String, fields: [FillField], preview: @escaping (FillValues) -> String) {
        self.title = title
        self.fields = fields
        values = FillValues.defaults(fields)
        self.preview = preview
        focus = fields.first?.key
    }

    func isEnabled(_ field: FillField) -> Bool {
        guard let section = field.onlyInSection else { return true }
        if case .flag(false)? = values.values[section] { return false }
        // Its section may itself sit in a section that's off.
        if let parent = fields.first(where: { $0.key == section }) { return isEnabled(parent) }
        return true
    }

    /// Tab / Shift-Tab: the next control that's on.
    func moveFocus(by step: Int) {
        let enabled = fields.filter(isEnabled)
        guard !enabled.isEmpty else { return }
        let current = enabled.firstIndex { $0.key == focus } ?? (step > 0 ? -1 : 0)
        focus = enabled[(current + step + enabled.count) % enabled.count].key
    }

    func text(_ field: FillField) -> Binding<String> {
        Binding(get: { self.values.text(field.name) ?? "" }, set: { self.values[field.name] = .text($0) })
    }

    func flag(_ field: FillField) -> Binding<Bool> {
        Binding(get: { self.values.flag(field.name) ?? false }, set: { self.values[field.name] = .flag($0) })
    }

    /// ↑↓ (or ←→) on a choice: the previous or next option.
    func step(_ field: FillField, by step: Int) {
        guard case .choice(let options) = field.kind, !options.isEmpty else { return }
        let index = options.firstIndex(of: values.text(field.name) ?? "") ?? 0
        values[field.name] = .text(options[min(max(index + step, 0), options.count - 1)])
    }

    /// Typing a letter on a choice picks the next option starting with it.
    func pick(_ field: FillField, startingWith character: Character) -> Bool {
        guard case .choice(let options) = field.kind else { return false }
        let prefix = SnippetSearch.fold(String(character))
        let current = options.firstIndex(of: values.text(field.name) ?? "") ?? -1
        let order = Array(options.indices.dropFirst(current + 1)) + Array(options.indices.prefix(current + 1))
        guard let match = order.first(where: { SnippetSearch.fold(options[$0]).hasPrefix(prefix) }) else { return false }
        values[field.name] = .text(options[match])
        return true
    }

    func insert() { onInsert(values) }

    var focusedField: FillField? { fields.first { $0.key == focus } }

    /// Keys for a focused choice or section (text fields handle their own). True if used.
    func handleControlKey(_ event: NSEvent) -> Bool {
        guard let field = focusedField, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch field.kind {
        case .text:
            return false
        case .choice:
            switch event.keyCode {
            case 125, 124: step(field, by: 1); return true    // ↓ →
            case 126, 123: step(field, by: -1); return true   // ↑ ←
            default:
                guard let character = event.charactersIgnoringModifiers?.first, character.isLetter || character.isNumber else { return false }
                _ = pick(field, startingWith: character)
                return true
            }
        case .section:
            guard event.keyCode == 49 else { return false }   // Space
            values[field.name] = .flag(!(values.flag(field.name) ?? false))
            return true
        }
    }
}

/// The form: one row per field, a live preview, Cancel and Insert. Keyboard first: Tab moves,
/// ↑↓ change a choice, Space ticks a section, Return inserts, Esc cancels.
struct FillInForm: View {
    @Bindable var state: FillInState
    var showsKeyHints = true
    @FocusState private var focus: String?
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(state.title)
                .font(.headline)
                .lineLimit(1)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.s) {
                ForEach(state.fields) { field in
                    GridRow {
                        label(field)
                            .gridColumnAlignment(.trailing)
                        control(field)
                            .disabled(!state.isEnabled(field))
                    }
                }
            }
            preview
            HStack(spacing: Spacing.s) {
                if showsKeyHints {
                    Text("Tab moves, Return inserts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.m)
                Button("Cancel") { state.onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { state.insert() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 420)
        .defaultFocus($focus, state.focus)
        .onAppear {
            // After the panel is key, or AppKit picks its own first control.
            DispatchQueue.main.async { focus = state.focus }
        }
        .onChange(of: state.focus) { _, new in
            let isText = state.focusedField.map { if case .text = $0.kind { true } else { false } } ?? false
            focus = isText ? new : nil
        }
        .onChange(of: focus) { _, new in if let new, state.focus != new { state.focus = new } }
    }

    @ViewBuilder private func label(_ field: FillField) -> some View {
        switch field.kind {
        case .section: Text("")
        default:
            Text(field.name)
                .lineLimit(1)
                .foregroundStyle(state.isEnabled(field) ? .primary : .secondary)
        }
    }

    @ViewBuilder private func control(_ field: FillField) -> some View {
        switch field.kind {
        case .text(let defaultValue):
            TextField(field.name, text: state.text(field), prompt: Text(defaultValue.isEmpty ? field.name : defaultValue))
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: field.key)
                .onSubmit { state.insert() }
                .accessibilityLabel(field.name)
        case .choice(let options):
            Picker(field.name, selection: state.text(field)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .modifier(KeyFocusRing(shown: state.focus == field.key))
        case .section:
            Toggle(field.name, isOn: state.flag(field))
                .toggleStyle(.checkbox)
                .modifier(KeyFocusRing(shown: state.focus == field.key))
        }
    }

    private var preview: some View {
        let text = state.preview(state.values)
        return Text(text.isEmpty ? " " : text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(4, reservesSpace: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.nested(in: panelRadius, padding: Spacing.l)))
            .accessibilityLabel("Preview")
            .accessibilityValue(text)
    }
}

/// The system's keyboard-focus ring around a choice or section that has the keyboard (AppKit
/// only gives popups and checkboxes real focus with Full Keyboard Access on; the form's key
/// handling drives them either way).
struct KeyFocusRing: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .padding(Spacing.xs / 2)
            .overlay {
                if shown {
                    RoundedRectangle(cornerRadius: Radius.s)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .accessibilityHidden(true)
                }
            }
            .padding(-Spacing.xs / 2)
            .accessibilityAddTraits(shown ? .isSelected : [])
    }
}

/// Shows the form in a floating panel next to the caret of the app being typed in. The app
/// keeps focus (the panel doesn't activate Shorthand); when the form is done, the panel goes
/// away and the text goes into that app.
@MainActor
final class FillInController {
    private var panel: FloatingPanel?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    /// The open form (test hooks fill it in).
    private(set) var state: FillInState?
    private var completing = false
    private(set) var isShowing = false
    /// The panel has the keyboard: the tap must ignore what's typed in it.
    var onShowingChange: (Bool) -> Void = { _ in }

    func present(_ state: FillInState, targetPID: pid_t?, onInsert: @escaping (FillValues) -> Void, onCancel: @escaping () -> Void) {
        close()
        completing = false
        self.state = state
        let panel = FloatingPanel(cornerRadius: Radius.xl) { FillInForm(state: state) }
        panel.setAccessibilityLabel("Fill in “\(state.title)”")
        state.onInsert = { [weak self] values in
            guard let self else { return }
            self.completing = true
            self.panel?.dismiss()
            onInsert(values)
        }
        state.onCancel = { [weak self] in self?.panel?.dismiss() }
        panel.keyHandler = { [weak state] event in
            guard let state else { return false }
            switch event.keyCode {
            case 48: // Tab
                state.moveFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1)
                return true
            case 36, 76: // Return, Enter
                state.insert()
                return true
            default:
                return state.handleControlKey(event)
            }
        }
        // The form's own popup menus take the keyboard for a moment: don't close for those.
        // A click in another app, or another app coming forward, cancels it.
        panel.dismissesOnResignKey = false
        // (Test mode types into a pad in the background, so clicks and app switches elsewhere
        // on the Mac don't mean anything there.)
        if Diagnostics.insertOnlyInto == nil {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    Diagnostics.record("fill-in: click in another app")
                    self?.panel?.dismiss()
                }
            }) { monitors.append(monitor) }
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard pid != ProcessInfo.processInfo.processIdentifier, pid != targetPID else { return }
                    Diagnostics.record("fill-in: another app came forward")
                    self?.panel?.dismiss()
                }
            }
        }
        panel.onDismiss = { [weak self] in
            guard let self else { return }
            for monitor in self.monitors { NSEvent.removeMonitor(monitor) }
            self.monitors = []
            if let observer = self.activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            self.activationObserver = nil
            self.isShowing = false
            self.onShowingChange(false)
            if !self.completing { onCancel() }
            self.panel = nil
            self.state = nil
        }
        self.panel = panel
        isShowing = true
        onShowingChange(true)
        panel.show(near: CaretLocator.anchor(pid: targetPID))
        Diagnostics.record("fill-in form shown fields=\(state.fields.count)")
    }

    func close() {
        panel?.dismiss()
    }
}
