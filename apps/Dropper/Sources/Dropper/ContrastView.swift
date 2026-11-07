import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// An AppKit-owned window so the global shortcut can open it from anywhere. Laid out like
/// the original's checker: the verdict on top, drawn in the two colors themselves, then a
/// column per color (value, eyedropper, Fix, hue/saturation/brightness sliders).
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
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func bringToFront() {
        guard let window, window.isVisible else { return }
        AppActivation.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = ContrastView(controller: controller, state: controller.contrast, model: controller.model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        // The verdict runs up under the see-through title bar. Without safe areas the window
        // is exactly as tall as the content; `ignoresSafeArea` instead left a title bar's
        // height (32 pt) of blank space under the footer.
        hosting.safeAreaRegions = []
        let window = ContrastPanelWindow(contentViewController: hosting)
        window.title = "Contrast Checker"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
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
        VStack(spacing: 0) {
            ContrastVerdict(report: report, valid: valid, text: state.text, background: state.background)
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let offer = state.offer {
                    offerBar(offer)
                }
                HStack(alignment: .top, spacing: Spacing.m) {
                    ContrastColorColumn(controller: controller, state: state, model: model, slot: .text, key: "1")
                    // Same caption + row as a column, so the arrows sit on the fields' centre line.
                    VStack(spacing: Spacing.s) {
                        Text(" ").font(.caption).accessibilityHidden(true)
                        Button {
                            state.swap()
                        } label: {
                            Label("Swap Colors", systemImage: "arrow.left.arrow.right")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .keyboardShortcut("e")
                        .help("Swap text and background (⌘E)")
                        .frame(height: ContrastColorColumn.rowHeight)
                    }
                    ContrastColorColumn(controller: controller, state: state, model: model, slot: .background, key: "2")
                }
                checks(report, valid: valid)
                Hairline()
                HStack {
                    Button {
                        let items = [state.text, state.background].map { PickedColor(color: $0, date: .now) }
                        let palette = controller.newPalette(colors: items)
                        controller.showLibrary(list: .palette(palette.id))
                    } label: {
                        Label("Save as Palette", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!valid)
                    .help("Make a palette of these two colors")
                    Spacer()
                    Text("WCAG 2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Large text is 24 px, or 19 px bold. The ratio is rounded down, so a pass is never overstated; pass and fail use the exact ratio.")
                    Button("Copy Result") {
                        model.copyText(report.summary(text: ColorFormatter.string(state.text, as: .hex, options: options),
                                                      background: ColorFormatter.string(state.background, as: .hex, options: options)))
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!valid)
                }
            }
            .padding(Spacing.windowMargin)
        }
        .frame(width: 480)
        .onChange(of: model.preferences.options) { _, new in state.refreshFields(options: new) }
        .onChange(of: model.history) { _, new in state.refreshOffer(history: new) }
    }

    private func offerBar(_ offer: (text: ColorValue, background: ColorValue)) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "eyedropper")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("New picks")
                .foregroundStyle(.secondary)
            SwatchView(color: offer.text, size: 16)
            SwatchView(color: offer.background, size: 16)
            Spacer()
            Button("Use Last Picks") {
                state.useOffer(history: model.history, options: options)
            }
            .help("Compare your last two picks: the older as text, the newer as background")
        }
        .font(.callout)
        .padding(Spacing.s)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }

    private func checks(_ report: ContrastReport, valid: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xs) {
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
                            Text("–").foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .font(.callout)
    }
}

/// The top of the checker: the verdict and ratio, drawn in the text color on the background.
private struct ContrastVerdict: View {
    /// The ratio pill sits this far from the window's top and trailing edges, so its corner
    /// follows the window's.
    static let ratioInset = Spacing.s
    /// Concentric with the window's corner. (`windowConcentric` would read the real radius,
    /// but in this self-sizing window it feeds back into the window's size and AppKit
    /// throws mid-layout, so the radius is the one macOS 26 gives a title-bar-only window.)
    static var ratioRadius: CGFloat {
        if #available(macOS 26, *) { return Radius.nested(in: Radius.xl, padding: ratioInset) }
        return Radius.nested(in: Radius.legacyWindow, padding: ratioInset, minimum: Radius.xs)
    }
    /// Room for the window buttons above the verdict (the title bar is see-through).
    static let titlebarClearance = Spacing.xxl * 2 + Spacing.xs

    let report: ContrastReport
    let valid: Bool
    let text: ColorValue
    let background: ColorValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(valid ? level : "–")
                    .font(.system(size: 52, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(valid ? sentence : "Fix the color value below to see the result.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(text.swiftUIColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Self.titlebarClearance)
            .padding(.bottom, Spacing.xxl)
            Text(valid ? String(report.formattedRatio.dropLast(2)) : "–")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(background.swiftUIColor)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(text.swiftUIColor, in: RoundedRectangle(cornerRadius: Self.ratioRadius, style: .continuous))
                .padding(.top, Self.ratioInset)
                .padding(.trailing, Self.ratioInset)
                .help("Contrast ratio \(report.formattedRatio), rounded down")
                .accessibilityLabel(valid ? "Contrast ratio \(report.formattedRatio)" : "No contrast ratio")
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(background.swiftUIColor)
        .opacity(valid ? 1 : 0.5)
        .accessibilityElement(children: .combine)
    }

    private var level: String {
        switch report.ratio {
        case 7...: "AAA"
        case 4.5...: "AA"
        case 3...: "AA Large"
        default: "Fail"
        }
    }

    private var sentence: String {
        switch report.ratio {
        case 7...: "Enhanced contrast: text of any size reads easily."
        case 4.5...: "Enough contrast for body text. 7:1 reaches AAA."
        case 3...: "Only large text (24 px, or 19 px bold) and interface shapes pass."
        default: "Not enough contrast for text. Try Fix."
        }
    }
}

/// One color of the pair: swatch, value field with an eyedropper, Fix, and HSB sliders.
private struct ContrastColorColumn: View {
    /// Height of the swatch / field / Fix row: a regular bordered button's height on
    /// macOS 26, so the field, the swatch and Fix line up top and bottom (the swap button
    /// matches it too).
    static let rowHeight: CGFloat = 24

    let controller: AppController
    @Bindable var state: ContrastState
    @Bindable var model: DropperModel
    let slot: ContrastState.Slot
    let key: Character
    @State private var hue: Double = 0
    @State private var fixMessage: String?

    private var options: FormatOptions { model.preferences.options }
    private var title: String { slot == .text ? "Text" : "Background" }
    private var color: ColorValue { state.color(for: slot) }
    private var other: ColorValue { state.color(for: slot == .text ? .background : .text) }
    private var invalid: Bool { slot == .text ? state.textInvalid : state.backgroundInvalid }
    private var field: Binding<String> { slot == .text ? $state.textField : $state.backgroundField }

    var body: some View {
        let target = ContrastFixer.target(for: state.report.ratio)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Spacing.s) {
                RoundSwatch(color: color, size: Self.rowHeight)
                    .opacity(invalid ? 0.35 : 1)
                HStack(spacing: 2) {
                    TextField(title, text: field, prompt: Text("#RRGGBB"))
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                        .accessibilityLabel("\(title) color")
                        .onChange(of: field.wrappedValue) { _, new in state.apply(new, to: slot, options: options) }
                        .onSubmit { state.normalizeField(slot, options: options) }
                    Button {
                        controller.pickForContrast(slot)
                    } label: {
                        Label("Pick \(title) Color", systemImage: "eyedropper")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
                    .help("Pick the \(title.lowercased()) color from the screen (⌘\(String(key)))")
                }
                .padding(.leading, Spacing.s)
                .padding(.trailing, Spacing.xs)
                .frame(height: Self.rowHeight)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .overlay {
                    if invalid { RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(.red, lineWidth: 1) }
                }
                Button("Fix") { fix(target) }
                    .frame(height: Self.rowHeight)
                    .disabled(target == nil || !state.isValid)
                    .help(target.map { "Change only this color’s lightness to reach \(Contrast.formatted($0))" } ?? "Already AAA")
                    .accessibilityLabel("Fix \(title.lowercased()) color")
            }
            GradientSlider(label: "\(title) hue", value: hueBinding, colors: hueStops,
                           knob: Color(hue: hue, saturation: 1, brightness: 1),
                           valueDescription: { "\(Int(($0 * 360).rounded())) degrees" })
            GradientSlider(label: "\(title) saturation", value: channel(.saturation),
                           colors: [hsb(saturation: 0), hsb(saturation: 1)], knob: color.swiftUIColor)
            GradientSlider(label: "\(title) brightness", value: channel(.brightness),
                           colors: [hsb(brightness: 0), hsb(brightness: 1)], knob: color.swiftUIColor)
            Group {
                if invalid {
                    Label("Not a color", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textRed)
                        .help("Type or paste a color like #3366CC, rgb(51, 102, 204) or hsl(220, 60%, 50%)")
                } else if let fixMessage {
                    Text(fixMessage).foregroundStyle(.secondary)
                } else if color.isOutside(options.space) {
                    Text("Outside \(options.space.title)").foregroundStyle(.secondary)
                } else {
                    Text(" ").accessibilityHidden(true)
                }
            }
            .font(.caption)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: syncHue)
        .onChange(of: color) { _, _ in syncHue() }
    }

    private var units: (hue: Double, saturation: Double, brightness: Double) { color.sRGB.hsbUnits }

    /// Keeps the hue while a color passes through gray or black.
    private func syncHue() {
        let u = units
        if u.saturation > 0.001, u.brightness > 0.001 { hue = u.hue }
    }

    private var hueBinding: Binding<Double> {
        Binding(get: { hue }, set: { new in
            hue = new
            let u = units
            set(RGB.fromHSB(hue: new, saturation: u.saturation, brightness: u.brightness))
        })
    }

    private enum Channel { case saturation, brightness }

    private func channel(_ which: Channel) -> Binding<Double> {
        Binding(get: { which == .saturation ? units.saturation : units.brightness }, set: { new in
            let u = units
            let s = which == .saturation ? new : u.saturation
            let b = which == .brightness ? new : u.brightness
            set(RGB.fromHSB(hue: hue, saturation: s, brightness: b))
        })
    }

    private func set(_ rgb: RGB) {
        fixMessage = nil
        state.adjust(ColorValue(sRGB: rgb.quantized), for: slot, options: options)
    }

    private func hsb(saturation: Double? = nil, brightness: Double? = nil) -> Color {
        let u = units
        return Color(hue: hue, saturation: saturation ?? u.saturation, brightness: brightness ?? u.brightness)
    }

    private func fix(_ target: Double?) {
        guard let target else { return }
        if let fixed = ContrastFixer.fix(color, against: other, target: target) {
            fixMessage = nil
            state.adjust(fixed, for: slot, options: options)
        } else {
            fixMessage = "Can’t reach \(Contrast.formatted(target)) by changing only the \(title.lowercased()) color."
            NSSound.beep()
        }
    }
}

private struct CheckBadge: View {
    let check: ContrastCheck
    let valid: Bool

    var body: some View {
        if valid {
            Label {
                Text(check.passes ? "Pass" : "Fail")
            } icon: {
                Image(systemName: check.passes ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(check.passes ? .green : .red)
            }
            .help("Needs \(Contrast.formatted(check.minimum))")
            .accessibilityLabel("\(check.title) \(check.level.rawValue): \(check.passes ? "pass" : "fail"), needs \(Contrast.formatted(check.minimum))")
        } else {
            Text("–")
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(check.title) \(check.level.rawValue): no result")
        }
    }
}
