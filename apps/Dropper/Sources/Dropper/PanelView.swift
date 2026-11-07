import AppKit
import DropperCore
import SlopKit
import SwiftUI

/// The panel under the menu bar icon, laid out like the original's: a toolbar (pick,
/// contrast, new palette, color editor), the copy-format selector, the list (Color History
/// on top, then palettes as color strips; click one to open it), and a bottom bar
/// (Settings, color vision, Library window, Quit).
struct PanelView: View {
    static let width: CGFloat = 320
    /// The panel's own corner radius.
    static let cornerRadius = Radius.xl
    /// The list card: inset `cardInset` from the panel's sides, so far from the panel's
    /// corners that it takes its own token rather than a nested radius.
    static let cardRadius = Radius.xl
    static let cardInset = Spacing.s
    /// Padding inside the card around the rows; rows' hover shapes nest in the card.
    static let cardPadding = Spacing.xs
    static let rowRadius = Radius.nested(in: cardRadius, padding: cardPadding)
    /// Padding inside a row; strips nest in the row.
    static let rowPadding = Spacing.xs
    static let stripRadius = Radius.nested(in: rowRadius, padding: rowPadding)
    /// Leading edge of row content from the panel's edge: the bottom bar lines up with it.
    static let contentInset = cardInset + cardPadding + rowPadding

    let controller: AppController
    @Bindable var model: DropperModel
    @Bindable var settings: AppSettings

    private var state: PanelState { controller.panelState }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, Self.contentInset)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.s)
            // Same width as the card under it.
            FormatSelector(model: model)
                .padding(.horizontal, Self.cardInset)
                .padding(.bottom, Spacing.s)
            ScrollView {
                Group {
                    if let list = state.list {
                        PanelListDetail(controller: controller, list: list)
                    } else {
                        PanelPaletteList(controller: controller)
                    }
                }
                .padding(Self.cardPadding)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured[state.list] = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // A solid surface with plain (non-vibrant) label colours: on the glass, vibrant
            // secondary text came out at 3.2:1 (light) and 3.1:1 (dark) on a 75 % card.
            .modifier(PlainLabelColors())
            .frame(height: contentHeight)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .padding(.horizontal, Self.cardInset)
            bottomBar
                .padding(.horizontal, Self.contentInset)
                .padding(.vertical, Spacing.s)
        }
        .frame(width: Self.width)
        .onChange(of: contentHeight) { _, _ in controller.statusItem.panelSizeChanged() }
    }

    /// The list's measured height per page, so the card hugs its content.
    @State private var measured: [ColorListID?: CGFloat] = [:]

    /// Grows with what's in it, up to a comfortable height. Until a page has been measured,
    /// an estimate keeps the first open close to its final size.
    private var contentHeight: CGFloat {
        let height: CGFloat
        if let known = measured[state.list], known > 0 {
            height = known
        } else if let list = state.list {
            height = 48 + CGFloat(max(model.items(in: list).count, 2)) * 44
        } else {
            height = 72 + CGFloat(model.palettes.count) * 72 + (model.historyLoadError == nil ? 0 : 40)
        }
        return min(max(height, 140), 470)
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.l) {
            if state.list != nil {
                Button {
                    state.list = nil
                } label: {
                    Label("Back to Palettes", systemImage: "chevron.left")
                }
                .help("Back to all palettes")
            } else {
                // Keeps the icons centered the same way as with the back button.
                Image(systemName: "chevron.left").hidden().accessibilityHidden(true)
            }
            Spacer()
            Menu {
                Button("Pick Color") { controller.pickAndCopy() }
                Button("Pick Multiple Colors") { controller.pickMultiple() }
                Button("Pick Contrast Pair") { controller.pickContrastPair() }
            } label: {
                Label("Pick Color", systemImage: "eyedropper")
            } primaryAction: {
                controller.pickAndCopy()
            }
            .menuStyle(.borderlessButton)
            // No arrow: it pushed the four icons off centre. Holding opens the menu (as the
            // tooltip says); the same commands are in the Color menu.
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pick a color from the screen. Click and hold for more ways to pick.")
            Button {
                controller.showContrastChecker()
            } label: {
                Label("Contrast Checker", systemImage: "circle.lefthalf.filled")
            }
            .help("Contrast Checker")
            Button {
                let palette = controller.newPalette()
                state.renaming = palette.id
                state.list = nil
            } label: {
                Label("New Palette", systemImage: "plus")
            }
            .help("New palette")
            Button {
                controller.showLibrary(list: .history, color: model.history.latest?.id)
            } label: {
                Label("Color Editor", systemImage: "paintpalette")
            }
            .help("Edit colors in the Library window")
            Spacer()
            Image(systemName: "chevron.left").hidden().accessibilityHidden(true)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
        .imageScale(.large)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                controller.showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")
            Spacer()
            Menu {
                Picker("Color Vision", selection: $settings.colorVision) {
                    ForEach(ColorVision.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Color Vision: \(settings.colorVision.title)",
                      systemImage: settings.colorVision == .normal ? "eye" : "eye.trianglebadge.exclamationmark")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Show swatches as people with color blindness see them")
            Spacer()
            Button {
                controller.showLibrary()
            } label: {
                Label("Open Library Window", systemImage: "macwindow")
            }
            .help("Open the Library window")
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Dropper", systemImage: "power")
            }
            .help("Quit Dropper (⌘Q)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// The copy-format control under the toolbar: a full-width menu, grouped like Settings.
struct FormatSelector: View {
    @Bindable var model: DropperModel

    var body: some View {
        Picker(selection: $model.preferences.format) {
            ForEach(ColorFormat.groups) { group in
                let formats = model.preferences.visible(in: group)
                if !formats.isEmpty {
                    Section(group.title) {
                        ForEach(formats) { Text($0.title).tag($0) }
                    }
                }
            }
        } label: {
            Text("Copy Format")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.large)
        .modifier(FlexibleWidth())
        .help("The format colors are copied in")
    }
}

/// Stretches a menu or button to its container's width (macOS 26 sizes them to fit).
struct FlexibleWidth: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.buttonSizing(.flexible).frame(maxWidth: .infinity)
        } else {
            content.frame(maxWidth: .infinity)
        }
        #else
        content.frame(maxWidth: .infinity)
        #endif
    }
}

/// Color History on top, then every palette, as strips.
struct PanelPaletteList: View {
    let controller: AppController
    private var model: DropperModel { controller.model }
    private var state: PanelState { controller.panelState }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xs) {
            if let error = model.historyLoadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(PanelView.rowPadding)
            }
            PanelHistoryRow(controller: controller)
            ForEach(model.palettes) { palette in
                PanelPaletteRow(controller: controller, palette: palette)
            }
        }
    }

}

/// The Color History row: its name and a strip of every pick; click opens it.
struct PanelHistoryRow: View {
    let controller: AppController
    @State private var hovering = false
    private var model: DropperModel { controller.model }
    private var state: PanelState { controller.panelState }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Button {
                    state.list = .history
                } label: {
                    Text("Color History")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color History, \(model.history.items.count) colors")
                .accessibilityHint("Opens the history")
                Menu {
                    ListActions(controller: controller, list: .history, rename: {})
                } label: {
                    Label("History Actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : PanelRowStyle.restingActionOpacity)
            }
            if model.history.items.isEmpty {
                Text(emptyLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ColorStrip(colors: model.history.items.map(\.color), vision: controller.settings.colorVision,
                           cornerRadius: PanelView.stripRadius)
                    .contentShape(Rectangle())
                    .onTapGesture { state.list = .history }
                    .accessibilityHidden(true)
            }
        }
        .modifier(PanelRowStyle(hovering: $hovering))
    }

    private var emptyLine: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .pickColor) {
            return "No colors yet. Press \(shortcut) or click the eyedropper to pick one."
        }
        return "No colors yet. Click the eyedropper to pick one."
    }
}

/// Padding and hover shape shared by the panel's list rows, nested in the card.
struct PanelRowStyle: ViewModifier {
    @Binding var hovering: Bool
    /// The ••• button's opacity while the pointer is elsewhere (still findable, not loud).
    static let restingActionOpacity = 0.45

    func body(content: Content) -> some View {
        content
            .padding(PanelView.rowPadding)
            .background {
                RoundedRectangle(cornerRadius: PanelView.rowRadius, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear))
            }
            .onHover { hovering = $0 }
    }
}

/// One palette in the panel: a radio (new picks go here), its name, a strip; click opens.
struct PanelPaletteRow: View {
    @Environment(\.controlActiveState) private var activeState
    let controller: AppController
    let palette: Palette
    @State private var hovering = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var model: DropperModel { controller.model }
    private var state: PanelState { controller.panelState }
    private var isActive: Bool { model.activePaletteID == palette.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Button {
                    model.activePaletteID = isActive ? nil : palette.id
                } label: {
                    Label(isActive ? "New picks go to \(palette.name)" : "Add new picks to \(palette.name)",
                          systemImage: isActive ? "largecircle.fill.circle" : "circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isActive ? AnyShapeStyle(Color.windowAccent(activeState)) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .help(isActive ? "New picks are added to this palette. Click to stop." : "Add new picks to this palette too")
                if palette.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked")
                }
                if state.renaming == palette.id {
                    TextField("Palette name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onAppear {
                            name = palette.name
                            DispatchQueue.main.async { nameFocused = true }
                        }
                        .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                } else {
                    Button {
                        state.list = .palette(palette.id)
                    } label: {
                        Text(palette.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(palette.name), \(palette.colors.count) colors")
                    .accessibilityHint("Opens the palette")
                }
                Menu {
                    ListActions(controller: controller, list: .palette(palette.id)) {
                        state.renaming = palette.id
                    }
                } label: {
                    Label("Actions for \(palette.name)", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : PanelRowStyle.restingActionOpacity)
            }
            ColorStrip(colors: palette.colors.map(\.color), vision: controller.settings.colorVision,
                       cornerRadius: PanelView.stripRadius)
                .contentShape(Rectangle())
                .onTapGesture { state.list = .palette(palette.id) }
                .accessibilityHidden(true)
        }
        .modifier(PanelRowStyle(hovering: $hovering))
        .contextMenu {
            ListActions(controller: controller, list: .palette(palette.id)) { state.renaming = palette.id }
        }
        .dropDestination(for: String.self) { strings, _ in
            let colors = strings.flatMap { PaletteCodec.colors(inText: $0) }
            for color in colors { model.add(color, to: palette.id) }
            return !colors.isEmpty
        }
    }

    private func commitRename() {
        guard state.renaming == palette.id else { return }
        model.renamePalette(palette.id, to: name)
        state.renaming = nil
    }
}

/// One list opened in the panel: its colors as rows. Click a row to copy.
struct PanelListDetail: View {
    let controller: AppController
    let list: ColorListID
    private var model: DropperModel { controller.model }

    var body: some View {
        let items = model.items(in: list)
        LazyVStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if model.isLocked(list) {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Locked")
                }
                Spacer()
                Menu {
                    ListActions(controller: controller, list: list) {
                        controller.panelState.list = nil
                        if case .palette(let id) = list { controller.panelState.renaming = id }
                    }
                } label: {
                    Label("Actions for \(title)", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            if items.isEmpty {
                Text(list == .history ? "No colors yet." : "This palette is empty. Turn on its circle in the list and pick colors, or use Add to Palette on any color.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.s)
            }
            ForEach(items) { item in
                ColorRow(controller: controller, item: item, list: list, copiesOnClick: true, highlightRadius: PanelView.rowRadius)
            }
        }
    }

    private var title: String {
        switch list {
        case .history: "Color History"
        case .palette(let id): model.palette(id)?.name ?? "Palette"
        }
    }
}

/// The system label colours resolved for the current appearance, as plain colours. Inside a
/// glass panel SwiftUI draws `.primary`/`.secondary` (and even `Color(nsColor:)` semantic
/// colours) vibrantly, blended with what's behind the glass rather than the opaque card they
/// sit on, which washes them out. Resolved colours draw as themselves.
/// (Candidate for SlopKit, next to `FloatingPanel`.)
struct PlainLabelColors: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(resolved(.labelColor), resolved(.secondaryLabelColor), resolved(.tertiaryLabelColor))
    }

    private func resolved(_ color: NSColor) -> Color {
        var result = color
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return Color(nsColor: result)
    }
}
