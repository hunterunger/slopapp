import AppKit
import DropperCore
import Observation
import SlopKit
import SwiftUI

/// The two colors being compared, their text fields, and any newer picks on offer.
/// The pair is saved, so it survives closing the window and relaunching.
@MainActor
@Observable
final class ContrastState {
    enum Slot: String { case text, background }

    private(set) var pair: ContrastPair
    var textField = ""
    var backgroundField = ""
    private(set) var textInvalid = false
    private(set) var backgroundInvalid = false
    /// Newer picks the person can switch to with one click.
    private(set) var offer: (text: ColorValue, background: ColorValue)?

    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "contrastPair"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        pair = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(ContrastPair.self, from: $0) }
            ?? .blackOnWhite
        hasStoredPair = defaults.data(forKey: Self.storageKey) != nil
    }

    @ObservationIgnored private var hasStoredPair: Bool

    var text: ColorValue { pair.text }
    var background: ColorValue { pair.background }
    var isValid: Bool { !textInvalid && !backgroundInvalid }
    var report: ContrastReport { ContrastReport(text: pair.text, background: pair.background) }

    /// Called when the window opens: first time ever, start from the last picks; after that
    /// keep the pair and offer newer picks.
    func prepare(history: ColorHistory, options: FormatOptions) {
        if !hasStoredPair {
            pair = .initial(from: history)
            hasStoredPair = true
            save()
        }
        refreshOffer(history: history)
        refreshFields(options: options)
    }

    func refreshOffer(history: ColorHistory) {
        offer = pair.offer(from: history).map { (text: $0.text, background: $0.background) }
    }

    func useOffer(history: ColorHistory, options: FormatOptions) {
        pair.useOffer(from: history)
        offer = nil
        save()
        refreshFields(options: options)
    }

    /// A color picked from the screen with the checker's own eyedropper buttons.
    func set(_ color: ColorValue, for slot: Slot, history: ColorHistory, options: FormatOptions) {
        switch slot {
        case .text: pair.text = color
        case .background: pair.background = color
        }
        pair.markOffered(history)
        offer = nil
        save()
        refreshFields(options: options)
    }

    /// Applies typed or pasted text (hex, rgb(), hsl(), color(display-p3 …)). Invalid text
    /// keeps the old color and marks the field.
    func apply(_ string: String, to slot: Slot, options: FormatOptions) {
        let color = ColorParser.color(string, in: options.space)
        let invalid = color == nil
        switch slot {
        case .text:
            textInvalid = invalid
            if let color { pair.text = color }
        case .background:
            backgroundInvalid = invalid
            if let color { pair.background = color }
        }
        if color != nil { save() }
    }

    func swap() {
        (pair.text, pair.background) = (pair.background, pair.text)
        (textField, backgroundField) = (backgroundField, textField)
        (textInvalid, backgroundInvalid) = (backgroundInvalid, textInvalid)
        save()
    }

    /// Rewrites both fields as hex in the current options (after a pick, on submit, or when
    /// the color space changes).
    func refreshFields(options: FormatOptions) {
        textField = ColorFormatter.string(pair.text, as: .hex, options: options)
        backgroundField = ColorFormatter.string(pair.background, as: .hex, options: options)
        textInvalid = false
        backgroundInvalid = false
    }

    /// After Return in a field: show a valid value as hex (pasted rgb() becomes #RRGGBB).
    func normalizeField(_ slot: Slot, options: FormatOptions) {
        switch slot {
        case .text where !textInvalid:
            textField = ColorFormatter.string(pair.text, as: .hex, options: options)
        case .background where !backgroundInvalid:
            backgroundField = ColorFormatter.string(pair.background, as: .hex, options: options)
        default:
            break
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pair) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// An AppKit-owned window so the global shortcut can open it from anywhere.
@MainActor
final class ContrastWindowController {
    private let controller: AppController
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func bringToFront() {
        guard let window, window.isVisible else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = ContrastView(controller: controller, state: controller.contrast, model: controller.model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = ContrastPanelWindow(contentViewController: hosting)
        window.title = "Contrast Checker"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ContrastChecker")
        if !window.setFrameUsingName("ContrastChecker") {
            window.center()
        }
        return window
    }
}

/// Esc and ⌘W close it (menu bar apps have no Close menu item to lean on).
final class ContrastPanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct ContrastView: View {
    let controller: AppController
    @Bindable var state: ContrastState
    @Bindable var model: DropperModel

    private var options: FormatOptions { model.preferences.options }

    var body: some View {
        let report = state.report
        let valid = state.isValid
        VStack(alignment: .leading, spacing: Spacing.l) {
            if let offer = state.offer {
                offerBar(offer)
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
                colorRow("Text", slot: .text, color: state.text, field: $state.textField,
                         invalid: state.textInvalid, key: "1")
                colorRow("Background", slot: .background, color: state.background, field: $state.backgroundField,
                         invalid: state.backgroundInvalid, key: "2")
            }

            preview
                .opacity(valid ? 1 : 0.35)

            HStack(alignment: .firstTextBaseline) {
                Text(valid ? report.formattedRatio : "–:1")
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                    .foregroundStyle(valid ? .primary : .tertiary)
                    .textSelection(.enabled)
                    // Decision (round 1, F6): the shown ratio is truncated to 2 decimals;
                    // pass/fail always uses the exact ratio.
                    .help("Rounded down, so a pass is never overstated. Pass and fail use the exact ratio.")
                    .accessibilityLabel(valid ? "Contrast ratio \(report.formattedRatio)" : "No contrast ratio: fix the color value")
                Spacer()
                Button {
                    state.swap()
                } label: {
                    Label("Swap Colors", systemImage: "arrow.up.arrow.down")
                }
                .keyboardShortcut("e")
                .help("Swap text and background (⌘E)")
            }

            checks(report, valid: valid)

            HStack {
                Text("WCAG 2. Large text is 24 px, or 19 px bold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Result") {
                    model.copyText(report.summary(text: ColorFormatter.string(state.text, as: .hex, options: options),
                                                  background: ColorFormatter.string(state.background, as: .hex, options: options)))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!valid)
            }
        }
        .padding(Spacing.windowMargin)
        .frame(width: 440)
        .onChange(of: model.preferences.options) { _, new in state.refreshFields(options: new) }
        .onChange(of: model.history) { _, new in state.refreshOffer(history: new) }
    }

    private func colorRow(_ title: String, slot: ContrastState.Slot, color: ColorValue, field: Binding<String>,
                          invalid: Bool, key: Character) -> some View {
        GridRow {
            Text(title)
                .gridColumnAlignment(.trailing)
            SwatchView(color: color, size: 22, cornerRadius: 5)
                .opacity(invalid ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                TextField(title, text: field, prompt: Text("#RRGGBB or rgb()"))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .frame(width: 110)
                    .overlay {
                        if invalid {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(.red, lineWidth: 1)
                        }
                    }
                    .accessibilityLabel("\(title) color")
                    .onChange(of: field.wrappedValue) { _, new in state.apply(new, to: slot, options: options) }
                    .onSubmit { state.normalizeField(slot, options: options) }
            }
            Button {
                controller.pickForContrast(slot)
            } label: {
                Label("Pick \(title) Color", systemImage: "eyedropper")
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
            .help("Pick the \(title.lowercased()) color from the screen (⌘\(String(key)))")
            Group {
                if invalid {
                    Label("Not a color", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help("Type or paste a color like #3366CC, rgb(51, 102, 204) or hsl(220, 60%, 50%)")
                } else if color.isOutside(options.space) {
                    Text("Outside \(options.space.title)")
                        .foregroundStyle(.secondary)
                        .help("This color is more vivid than \(options.space.title) can show; the hex is the closest value")
                }
            }
            .font(.caption)
            .lineLimit(1)
            .frame(width: 104, alignment: .leading)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // WCAG sizes: large text is 18 pt print = 24 px. Fixed on purpose.
            Text("Large text sample")
                .font(.system(size: 24))
            Text("Normal text: the quick brown fox jumps over the lazy dog.")
                .font(.body)
        }
        .foregroundStyle(state.text.swiftUIColor)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.background.swiftUIColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the text color on the background color")
    }

    private func offerBar(_ offer: (text: ColorValue, background: ColorValue)) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "eyedropper")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("New picks")
                .foregroundStyle(.secondary)
            SwatchView(color: offer.text, size: 16, cornerRadius: 4)
            SwatchView(color: offer.background, size: 16, cornerRadius: 4)
            Spacer()
            Button("Use Last Picks") {
                state.useOffer(history: model.history, options: options)
            }
            .help("Compare your last two picks: the older as text, the newer as background")
        }
        .font(.callout)
        .padding(Spacing.s)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func checks(_ report: ContrastReport, valid: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
            GridRow {
                Text("")
                Text("AA").font(.caption).foregroundStyle(.secondary)
                Text("AAA").font(.caption).foregroundStyle(.secondary)
            }
            ForEach([ContrastCheck.Kind.normalText, .largeText, .uiComponents], id: \.self) { kind in
                let row = report.checks.filter { $0.kind == kind }
                GridRow {
                    Text(row.first?.title ?? "")
                    ForEach([ContrastCheck.Level.aa, .aaa], id: \.self) { level in
                        if let check = row.first(where: { $0.level == level }) {
                            CheckBadge(check: check, valid: valid)
                        } else {
                            Text("–").foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

private struct CheckBadge: View {
    let check: ContrastCheck
    let valid: Bool

    var body: some View {
        if valid {
            result
        } else {
            Text("–")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("\(check.title) \(check.level.rawValue): no result")
        }
    }

    private var result: some View {
        Label {
            Text(check.passes ? "Pass" : "Fail")
        } icon: {
            Image(systemName: check.passes ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(check.passes ? .green : .red)
        }
        .help("Needs \(Contrast.formatted(check.minimum))")
        .accessibilityLabel("\(check.title) \(check.level.rawValue): \(check.passes ? "pass" : "fail"), needs \(Contrast.formatted(check.minimum))")
    }
}
