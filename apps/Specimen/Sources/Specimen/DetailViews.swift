import SlopKit
import SpecimenCore
import SwiftUI

/// One family's page: a header with the style picker, then tabs (⌘1–⌘6) for every style,
/// the characters, text layouts, variable axes, OpenType features and details.
struct FamilyDetailView: View {
    @Bindable var model: AppModel
    let familyName: String
    @FocusState private var focused: Bool

    private var family: FontFamily? { model.family(named: familyName) }
    private var selectedFace: FontFace? {
        guard let family else { return nil }
        return family.faces.first { $0.id == model.detailFaceID } ?? family.representative
    }

    /// Variables only exists for variable fonts; anything else falls back to Styles.
    private var tab: DetailTab {
        model.detailTab == .variables && !(family?.isVariable ?? false) ? .styles : model.detailTab
    }

    var body: some View {
        if let family, let face = selectedFace {
            VStack(spacing: 0) {
                header(family, face: face)
                    .padding(.horizontal, Spacing.windowMargin)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.m)
                Hairline()
                Group {
                    switch tab {
                    case .styles: StylesTab(model: model, family: family, selectedFace: face)
                    case .characters: CharactersTab(face: face)
                    case .text: TextTab(model: model, face: face)
                    case .variables: VariablesTab(model: model, family: family, face: face)
                    case .features: FeaturesTab(model: model, face: face)
                    case .info: InfoTab(model: model, face: face, family: family)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onExitCommand { model.goBack() }
            // Space toggles details like in the grid (not on Characters, which has a search field).
            .onKeyPress(.space) {
                guard tab != .characters else { return .ignored }
                model.goBack()
                return .handled
            }
            .onKeyPress(.downArrow) { moveStyle(1, in: family); return .handled }
            .onKeyPress(.upArrow) { moveStyle(-1, in: family); return .handled }
        } else {
            ContentUnavailableView("This font is gone", systemImage: "questionmark.square.dashed",
                                   description: Text("It was removed or turned off elsewhere."))
                .onExitCommand { model.goBack() }
        }
    }

    private func moveStyle(_ delta: Int, in family: FontFamily) {
        guard tab == .styles || tab == .text || tab == .info,
              let current = family.faces.firstIndex(where: { $0.id == selectedFace?.id }) else { return }
        let next = min(max(current + delta, 0), family.faces.count - 1)
        model.detailFaceID = family.faces[next].id
    }

    private func header(_ family: FontFamily, face: FontFace) -> some View {
        VStack(spacing: Spacing.m) {
            HStack(alignment: .center, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(family.displayName)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    Text(summary(family))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Style", selection: Binding(get: { face.id }, set: { model.detailFaceID = $0 })) {
                    ForEach(family.faces) { option in
                        Text(option.styleName).tag(option.id)
                    }
                }
                .fixedSize()
                .disabled(family.faces.count < 2)
                .help("The style every tab shows (↑ / ↓)")
                let isFavorite = model.favorites.contains(family.name)
                Button {
                    model.setFavorite(!isFavorite, families: [family.name])
                } label: {
                    Label(isFavorite ? "Favorite" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star")
                        .labelStyle(.iconOnly)
                }
                .help(isFavorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                Button {
                    model.sheet = .tags
                } label: {
                    Label("Tags", systemImage: "tag").labelStyle(.iconOnly)
                }
                .help("Tags (⌘T)")
                .accessibilityLabel("Edit Tags")
                let inTray = model.tray.containsAny(family.faces.map(\.id))
                Button {
                    if inTray { model.removeFromTray(family.faces.map(\.id)) } else {
                        var tray = model.tray
                        tray.add(face.id)
                        model.setTray(tray, actionName: "Add to Compare")
                    }
                } label: {
                    Label(inTray ? "In Compare" : "Add to Compare", systemImage: inTray ? "checkmark.circle.fill" : "plus.circle")
                        .labelStyle(.iconOnly)
                }
                .help(inTray ? "Remove from Compare" : "Add to Compare")
                .accessibilityLabel(inTray ? "Remove from Compare" : "Add to Compare")
                activationButton(family)
            }
            Picker("Tab", selection: Binding(get: { tab }, set: { model.detailTab = $0 })) {
                ForEach(DetailTab.allCases.filter { $0 != .variables || family.isVariable }) { tab in
                    // Features shows how many are changed: they apply on every tab.
                    Text(tab == .features && !model.detailFeatures.isDefault ? "Features (\(model.detailFeatures.changeCount))" : tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Details")
        }
    }

    @ViewBuilder private func activationButton(_ family: FontFamily) -> some View {
        if let lock = model.lockReason(for: family) {
            Label(lock.title, systemImage: "lock.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help(lock.explanation)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(lock.title)
                .accessibilityHint(lock.explanation)
        } else if family.state.isOn, family.faces.contains(where: \.isTemporary) {
            Menu("Deactivate") {
                Button("Keep Active After Quitting") { model.request(true, faces: family.faces) }
            } primaryAction: {
                model.request(false, faces: family.faces)
            }
            .fixedSize()
            .help("Active until you quit Specimen. Click to turn it off now (⇧⌘;), or keep it active (⌘;).")
        } else if family.state.isOn {
            Button("Deactivate") { model.request(false, faces: family.faces) }
                .help("Turn off every style of this family (⇧⌘;)")
        } else if family.faces.contains(where: model.isInPlace) {
            Menu("Activate") {
                Button("Activate Temporarily") { model.request(true, faces: family.faces, temporary: true) }
            } primaryAction: {
                model.request(true, faces: family.faces)
            }
            .fixedSize()
            .help("Turn on every style from its folder, without copying it (⌘;). Temporarily: until you quit Specimen (⌥⌘;).")
        } else {
            Button("Activate") { model.request(true, faces: family.faces) }
                .help("Turn on every style of this family (⌘;)")
        }
    }

    private func summary(_ family: FontFamily) -> String {
        var parts = [family.faces.count == 1 ? "1 style" : "\(family.faces.count) styles", family.category.title, family.state.title]
        if let foundry = family.foundry { parts.insert(foundry, at: 0) }
        let tags = model.tags.tags(of: family.name)
        if !tags.isEmpty { parts.append(tags.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Styles

struct StylesTab: View {
    var model: AppModel
    let family: FontFamily
    let selectedFace: FontFace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(family.faces) { face in
                        StyleRow(model: model, face: face, isSelected: face.id == selectedFace.id)
                            .id(face.id)
                    }
                }
                // Rows pad their content by Spacing.s; hang that into the margin so the style
                // names and previews line up with the family name in the header.
                .padding(.horizontal, Spacing.windowMargin - Spacing.s)
                .padding(.vertical, Spacing.windowMargin - Spacing.s)
            }
            .onChange(of: selectedFace.id) { proxy.scrollTo(selectedFace.id) }
        }
    }
}

struct StyleRow: View {
    var model: AppModel
    let face: FontFace
    let isSelected: Bool
    @Environment(\.controlActiveState) private var activeState

    private var isDuplicate: Bool {
        model.family(named: face.familyName)?.faces.contains { $0.postScriptName == face.postScriptName && $0.id != face.id } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.s) {
                Image(systemName: face.isTemporary ? "circle.dashed.inset.filled" : face.isEnabled ? "circle.fill" : "circle")
                    .font(.system(size: 6))
                    .foregroundStyle(face.isEnabled ? Color.windowAccent(activeState) : .secondary)
                    .accessibilityHidden(true)
                Text(face.styleName).font(.callout.weight(.semibold))
                Text(face.postScriptName).font(.caption).foregroundStyle(.secondary)
                if isDuplicate, let path = face.path {
                    Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if !face.isEnabled {
                    Text("Inactive").font(.caption).foregroundStyle(.secondary)
                } else if face.isTemporary {
                    Text("Active until you quit").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            PreviewLine(face: face, text: model.previewText, size: CGFloat(model.previewSize), features: model.featureValues(for: face))
        }
        .padding(Spacing.s)
        // Same selection as a grid card: accent tint and a 2 pt ring.
        .background(RoundedRectangle(cornerRadius: Radius.m).fill(isSelected ? Color.selectionTint(activeState) : .clear))
        .overlay(RoundedRectangle(cornerRadius: Radius.m).strokeBorder(isSelected ? Color.selectionRing(activeState) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { model.detailFaceID = face.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(face.styleName), \(face.isTemporary ? "Active until you quit" : face.isEnabled ? "Active" : "Inactive")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.detailFaceID = face.id }
    }
}

// MARK: Characters

/// Every character the style maps, by group, searchable by character, name or code point.
struct CharactersTab: View {
    let face: FontFace
    @State private var characters: [UInt32] = []
    @State private var isLoading = true
    @State private var group: CharacterGroup = .all
    @State private var search = ""
    @State private var selected: UInt32?
    @Environment(\.controlActiveState) private var activeState

    /// Cells are square and share the row's width evenly, at least this wide.
    static let cellMinimum: CGFloat = 56
    static let glyphSize: CGFloat = 26

    private var shown: [UInt32] { CharacterCatalog.filter(characters, group: group, search: search) }

    var body: some View {
        let shown = shown
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.s) {
                    Picker("Show", selection: $group) {
                        ForEach(CharacterGroup.allCases) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    TextField("Search characters", text: $search, prompt: Text("Character, name or U+0041"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .accessibilityLabel("Search characters")
                    Spacer()
                    Text(isLoading ? "Reading…" : "\(shown.count.formatted()) of \(characters.count.formatted())")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.windowMargin)
                .padding(.vertical, Spacing.s)
                Hairline()
                if !isLoading, shown.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("No \(group.title.lowercased()) in this style", systemImage: "character",
                                               description: Text("Pick another group, or All."))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                } else {
                    grid(shown)
                }
            }
            Hairline(axis: .vertical)
            CharacterInspector(face: face, character: selected ?? shown.first)
                .frame(width: 240)
        }
        .task(id: face.id) { await load() }
    }

    private func grid(_ shown: [UInt32]) -> some View {
        let font = PreviewRenderer.shared.font(for: face, size: Self.glyphSize)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cellMinimum), spacing: Spacing.xs)], spacing: Spacing.xs) {
                ForEach(shown, id: \.self) { value in
                    let isSelected = value == (selected ?? shown.first)
                    GlyphView(font: font, character: value, selected: isSelected && activeState.isActiveWindow)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(RoundedRectangle(cornerRadius: Radius.s)
                            .fill(isSelected ? AnyShapeStyle(Color.selectionFill(activeState)) : AnyShapeStyle(.fill.quaternary)))
                        .contentShape(Rectangle())
                        .onTapGesture { selected = value }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(CharacterCatalog.name(value)), \(CharacterCatalog.codePoint(value))")
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selected = value }
                        .help("\(CharacterCatalog.name(value)) \(CharacterCatalog.codePoint(value))")
                }
            }
            // Same left and right margin as the bar above: the cells stretch to fill the width.
            .padding(.horizontal, Spacing.windowMargin)
            .padding(.vertical, Spacing.l)
        }
        .onCopyCommand {
            guard let value = selected ?? shown.first else { return [] }
            return [NSItemProvider(object: CharacterCatalog.string(value) as NSString)]
        }
    }

    private func load() async {
        isLoading = true
        let name = face.postScriptName, path = face.path, enabled = face.isEnabled
        let result = await Task.detached(priority: .userInitiated) { () -> [UInt32] in
            guard let font = FontLoader.makeFont(postScriptName: name, path: path, isEnabled: enabled, size: 12) else { return [] }
            let set = CTFontCopyCharacterSet(font)
            let planes = (0...16).filter { CFCharacterSetHasMemberInPlane(set, CFIndex($0)) }
            return CharacterCatalog.characters(planes: planes) { CFCharacterSetIsLongCharacterMember(set, $0) }
        }.value
        characters = result
        if let selected, !result.contains(selected) { self.selected = nil }
        isLoading = false
    }
}

/// One character drawn the way a type designer looks at it: its ink centred left to right
/// (side bearings don't push it off centre), and on a baseline shared by every character of
/// the font, with the cap height centred. So "," still sits low and "'" high, but each
/// glyph is in the middle of its cell. Optional guides show baseline, x-height and cap height.
struct GlyphView: View {
    let font: CTFont?
    let character: UInt32
    var selected = false
    var guides = false

    var body: some View {
        Canvas { context, size in
            guard let font else { return }
            let metrics = GlyphMetrics(font: font, character: character)
            let baseline = (size.height / 2 + metrics.capHeight / 2).rounded()
            if guides {
                let pixel = 1 / max(context.environment.displayScale, 1)
                for y in [baseline, baseline - metrics.xHeight, baseline - metrics.capHeight] where y > 0 {
                    let line = Path(CGRect(x: 0, y: (y * context.environment.displayScale).rounded() / context.environment.displayScale,
                                           width: size.width, height: pixel))
                    context.fill(line, with: .color(Color(nsColor: .separatorColor)))
                }
            }
            let text = Text(CharacterCatalog.string(character))
                .font(Font(font))
                .foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
            let resolved = context.resolve(text)
            let measured = resolved.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
            let x = metrics.inkWidth > 0 ? size.width / 2 - metrics.inkMidX : (size.width - measured.width) / 2
            let top = baseline - resolved.firstBaseline(in: measured)
            context.draw(resolved, in: CGRect(origin: CGPoint(x: x, y: top), size: measured))
        }
        .accessibilityHidden(true)
    }
}

/// Font metrics and one glyph's ink bounds, for `GlyphView`.
struct GlyphMetrics {
    var capHeight: CGFloat
    var xHeight: CGFloat
    /// Horizontal centre of the glyph's ink from its pen position, and its width (0: no ink).
    var inkMidX: CGFloat = 0
    var inkWidth: CGFloat = 0

    init(font: CTFont, character: UInt32) {
        let ascent = CTFontGetAscent(font)
        let cap = CTFontGetCapHeight(font)
        let x = CTFontGetXHeight(font)
        // Some fonts (symbol, many non-Latin) report no cap height: estimate one.
        capHeight = cap > 0 && cap <= ascent * 1.2 ? cap : ascent * 0.72
        xHeight = x > 0 && x < capHeight ? x : capHeight * 0.68
        guard let scalar = Unicode.Scalar(character) else { return }
        var units = Array(String(Character(scalar)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) else { return }
        let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, nil, 1)
        if bounds.width > 0 {
            inkMidX = bounds.midX
            inkWidth = bounds.width
        }
    }
}

struct CharacterInspector: View {
    let face: FontFace
    let character: UInt32?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let character {
                // The selected character large, on its baseline, with faint guides for
                // baseline, x-height and cap height.
                GlyphView(font: PreviewRenderer.shared.font(for: face, size: 120), character: character, guides: true)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(RoundedRectangle(cornerRadius: Radius.m).fill(.fill.quaternary))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(CharacterCatalog.name(character))
                        .font(.headline)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.xs) {
                        GridRow {
                            Text("Code point").foregroundStyle(.secondary)
                            Text(CharacterCatalog.codePoint(character)).textSelection(.enabled).monospaced()
                        }
                        GridRow {
                            Text("HTML").foregroundStyle(.secondary)
                            Text(CharacterCatalog.htmlEntity(character)).textSelection(.enabled).monospaced()
                        }
                        if let scalar = Unicode.Scalar(character) {
                            GridRow {
                                Text("Group").foregroundStyle(.secondary)
                                Text(CharacterGroup.of(scalar).title)
                            }
                        }
                    }
                    .font(.callout)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    copyButton("Copy Character", CharacterCatalog.string(character))
                        .help("Copy the character itself (⌘C)")
                    copyButton("Copy Code Point", CharacterCatalog.codePoint(character))
                    copyButton("Copy HTML Entity", CharacterCatalog.htmlEntity(character))
                }
                .controlSize(.small)
            } else {
                Text("No character selected")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Spacing.l)
    }

    /// Full-width buttons, so the stack reads as one column rather than three ragged widths.
    private func copyButton(_ title: String, _ value: String) -> some View {
        Button {
            copy(value)
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: Text

/// Body text and a waterfall in the chosen style.
struct TextTab: View {
    var model: AppModel
    let face: FontFace
    @AppStorage("bodyTextSize") private var bodySize: Double = 16

    static let waterfallSizes: [CGFloat] = [9, 10, 12, 14, 16, 18, 24, 30, 36, 48, 60, 72, 96]
    static let paragraph = """
    Good type disappears while you read and shows itself when you look. Set a few lines at \
    the size people will read them, then check the rhythm: how evenly the words space out, \
    whether the round letters sit as tall as the flat ones, and how figures like 1984 and \
    $27.50 fit into a sentence. Punctuation matters too: “quotes”, (brackets), dashes — and \
    the humble ampersand & all have to belong to the same family.
    """

    private var headline: String {
        PreviewText.line(for: model.previewText, familyName: face.displayFamilyName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack {
                        Text("Paragraph").font(.headline)
                        Spacer()
                        Picker("Body size", selection: $bodySize) {
                            ForEach([11.0, 12, 14, 16, 18, 21, 24], id: \.self) { Text("\(Int($0)) pt").tag($0) }
                        }
                        .fixedSize()
                    }
                    let features = model.featureValues(for: face)
                    if let title = PreviewRenderer.shared.font(for: face, size: 34, features: features),
                       let body = PreviewRenderer.shared.font(for: face, size: bodySize, features: features) {
                        Text(headline)
                            .font(Font(title))
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text(Self.paragraph)
                            .font(Font(body))
                            .lineSpacing(bodySize * 0.35)
                            .frame(maxWidth: max(bodySize * 36, 420), alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("Can't preview this font").foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Waterfall").font(.headline)
                    ForEach(Self.waterfallSizes, id: \.self) { size in
                        // The size sits on the sample's baseline.
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                            Text("\(Int(size))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                                .accessibilityHidden(true)
                            PreviewLine(face: face, text: model.previewText.isEmpty ? PreviewPreset.all[1].text : model.previewText, size: size,
                                        features: model.featureValues(for: face))
                                .alignmentGuide(.firstTextBaseline) { _ in PreviewMetrics.baseline(for: size) }
                                .accessibilityLabel("\(Int(size)) point")
                        }
                    }
                }
            }
            .padding(Spacing.windowMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Variables

/// Sliders for each axis of a variable font, with sample glyphs along the range, named
/// instances, and the CSS to reproduce the setting.
struct VariablesTab: View {
    var model: AppModel
    let family: FontFamily
    let face: FontFace
    @State private var copied = false

    /// The variable faces in the same file: its named instances.
    private var instances: [FontFace] {
        family.faces.filter { $0.isVariable && $0.path == face.path }
    }

    private var sampleCharacter: String {
        let first = model.previewText.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        return first.isEmpty ? "A" : first
    }

    private var instanceSettings: VariationSettings {
        VariationSettings.from(axes: face.axes, coreText: PreviewRenderer.shared.variation(of: face))
    }

    /// Kept on the model, so the Features tab previews the same axis positions.
    private var settings: Binding<VariationSettings> {
        Binding(get: { model.detailVariation?.faceID == face.id ? model.detailVariation!.settings : instanceSettings },
                set: { model.detailVariation = (face.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if face.axes.isEmpty {
                    ContentUnavailableView("Not a variable style", systemImage: "slider.horizontal.3",
                                           description: Text("Pick a variable style of this family above."))
                } else {
                    HStack(spacing: Spacing.s) {
                        if instances.count > 1 {
                            Picker("Instance", selection: Binding(get: { face.id }, set: { model.detailFaceID = $0 })) {
                                ForEach(instances) { Text($0.styleName).tag($0.id) }
                            }
                            .fixedSize()
                        }
                        Spacer()
                        Button("Reset") { resetToInstance() }
                            .disabled(settings.wrappedValue == instanceSettings)
                            .help("Back to \(face.styleName)’s own axis values")
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.wrappedValue.css, forType: .string)
                            copied = true
                        } label: {
                            // Both labels share one slot (the wider one's width), so the
                            // button and Reset next to it don't move when it says Copied.
                            ZStack {
                                Text("Copy CSS").opacity(copied ? 0 : 1)
                                Text("Copied").opacity(copied ? 1 : 0)
                            }
                        }
                        .help(settings.wrappedValue.css)
                        .accessibilityLabel(copied ? "Copied" : "Copy CSS")
                    }
                    PreviewLine(face: face, text: model.previewText, size: CGFloat(model.previewSize),
                                variation: settings.wrappedValue.coreTextValues, features: model.featureValues(for: face))
                        .accessibilityLabel("Preview at these axis values")
                    Hairline()
                    ForEach(face.axes, id: \.tag) { axis in
                        AxisRow(face: face, axis: axis, settings: settings, sample: sampleCharacter)
                        Hairline()
                    }
                }
            }
            .padding(Spacing.windowMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if model.detailVariation?.faceID != face.id { resetToInstance() } }
        .onChange(of: face.id) { if model.detailVariation?.faceID != face.id { resetToInstance() } }
        .onChange(of: model.detailVariation?.settings) { copied = false }
    }

    private func resetToInstance() {
        model.detailVariation = (face.id, instanceSettings)
    }
}

// MARK: Features

extension AppModel {
    /// The family page's feature settings, as CoreText values for `face`.
    func featureValues(for face: FontFace) -> [FeatureValue] {
        detailFeatures.isDefault ? [] : detailFeatures.values(for: PreviewRenderer.shared.featureTypes(for: face))
    }

    /// The Variables tab's axis positions, when they're for `face`.
    func variationValues(for face: FontFace) -> [Int: Double] {
        guard let variation = detailVariation, variation.faceID == face.id, !variation.settings.isDefault else { return [:] }
        return variation.settings.coreTextValues
    }
}

/// OpenType features the style has (ligatures, figures, small caps, stylistic sets…), grouped,
/// each with a sample. They apply live to every preview on the family page.
struct FeaturesTab: View {
    @Bindable var model: AppModel
    let face: FontFace
    @State private var copied = false

    var body: some View {
        let types = PreviewRenderer.shared.featureTypes(for: face)
        let values = model.featureValues(for: face)
        let css = model.detailFeatures.css(for: types)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if types.isEmpty {
                    ContentUnavailableView("No features to switch", systemImage: "textformat.abc",
                                           description: Text("This style has no OpenType features to turn on or off. Try another style above."))
                } else {
                    HStack(spacing: Spacing.s) {
                        Text(types.count == 1 ? "1 feature" : "\(types.count) features")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Changes apply to every tab.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { model.detailFeatures.reset() }
                            .disabled(model.detailFeatures.isDefault)
                            .help("Back to the font’s defaults")
                        Button {
                            guard let css else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(css, forType: .string)
                            copied = true
                        } label: {
                            ZStack {
                                Text("Copy CSS").opacity(copied ? 0 : 1)
                                Text("Copied").opacity(copied ? 1 : 0)
                            }
                        }
                        .disabled(css == nil)
                        .help(css ?? "Turn a feature on or off to copy its CSS")
                        .accessibilityLabel(copied ? "Copied" : "Copy CSS")
                    }
                    PreviewLine(face: face, text: model.previewText, size: CGFloat(model.previewSize),
                                variation: model.variationValues(for: face), features: values)
                        .accessibilityLabel("Preview with these features")
                    ForEach(FeatureGroup.allCases, id: \.self) { group in
                        let members = types.filter { $0.group == group }
                        if !members.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Text(group.title).font(.headline)
                                Hairline()
                                ForEach(members) { type in
                                    FeatureRow(model: model, face: face, type: type, values: values)
                                    Hairline()
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.windowMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: model.detailFeatures) { copied = false }
    }
}

struct FeatureRow: View {
    @Bindable var model: AppModel
    let face: FontFace
    let type: FontFeatureType
    let values: [FeatureValue]

    static let sampleSize: CGFloat = 26

    /// The OpenType tags behind the controls ("liga, dlig"), for people who write CSS.
    private var tags: String {
        var seen = Set<String>()
        return type.selectors.compactMap { selector in
            selector.openTypeTag ?? FeatureCatalog.openType(for: FeatureValue(typeID: type.typeID, selectorID: selector.id, tag: nil, value: 1))?.0
        }.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }

    /// An exclusive type with a default and one alternative reads better as a checkbox.
    private var onOffChoice: (off: FeatureSelector, on: FeatureSelector)? {
        guard type.isExclusive, type.selectors.count == 2, let off = type.defaultSelector,
              let on = type.selectors.first(where: { $0.id != off.id }) else { return nil }
        return (off, on)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                controls
                if !tags.isEmpty {
                    Text(tags).font(.caption).monospaced().foregroundStyle(.secondary)
                }
            }
            .frame(width: 230, alignment: .leading)
            PreviewLine(face: face, text: FeatureCatalog.sample(for: type, previewText: model.previewText), size: Self.sampleSize,
                        allowSample: false, variation: model.variationValues(for: face), features: values)
                .frame(height: PreviewMetrics.height(for: Self.sampleSize))
                // The sample sits on the first control's baseline.
                .alignmentGuide(.firstTextBaseline) { _ in PreviewMetrics.baseline(for: Self.sampleSize) }
                .accessibilityLabel("Sample of \(type.title)")
        }
    }

    @ViewBuilder private var controls: some View {
        if let choice = onOffChoice {
            Toggle(isOn: Binding(get: { model.detailFeatures.isOn(choice.on, in: type) },
                                 set: { model.detailFeatures.set(choice.on, in: type, on: $0) })) {
                Text(FeatureCatalog.label(for: choice.on, in: type))
            }
        } else if type.isExclusive {
            Text(type.title).font(.callout.weight(.semibold))
            Picker(type.title, selection: Binding(get: { model.detailFeatures.chosen(in: type)?.id ?? -1 },
                                                  set: { id in model.detailFeatures.choose(type.selectors.first { $0.id == id }, in: type) })) {
                ForEach(type.selectors, id: \.id) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(type.title)
        } else {
            // A heading for several switches, unless the group heading above already says it.
            if type.selectors.count > 1, type.title != type.group.title { Text(type.title).font(.callout.weight(.semibold)) }
            ForEach(type.selectors, id: \.id) { selector in
                Toggle(isOn: Binding(get: { model.detailFeatures.isOn(selector, in: type) },
                                     set: { model.detailFeatures.set(selector, in: type, on: $0) })) {
                    Text(type.selectors.count == 1 ? FeatureCatalog.label(for: selector, in: type) : selector.name)
                }
            }
        }
    }
}

struct AxisRow: View {
    let face: FontFace
    let axis: VariationAxis
    @Binding var settings: VariationSettings
    let sample: String

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(axis.name).font(.headline)
                Text(VariationAxis.formatValue(settings.value(axis.tag), range: axis.maximum - axis.minimum))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(axis.tag).font(.caption).foregroundStyle(.secondary).monospaced()
            }
            .frame(width: 120, alignment: .leading)
            VStack(spacing: Spacing.xs) {
                HStack(spacing: 0) {
                    ForEach(VariationSettings.stops(for: axis), id: \.self) { stop in
                        var at = settings
                        let _ = at.set(axis.tag, to: stop)
                        Button {
                            settings.set(axis.tag, to: stop)
                        } label: {
                            PreviewLine(face: face, text: sample, size: 30, allowSample: false, variation: at.coreTextValues, centered: true)
                                .frame(height: PreviewMetrics.height(for: 30))
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(axis.name) \(VariationAxis.formatValue(stop))")
                    }
                }
                Slider(value: Binding(get: { settings.value(axis.tag) }, set: { settings.set(axis.tag, to: $0) }),
                       in: axis.minimum...max(axis.maximum, axis.minimum + 0.001)) {
                    Text(axis.name)
                } minimumValueLabel: {
                    Text(VariationAxis.formatValue(axis.minimum, range: axis.maximum - axis.minimum)).font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(VariationAxis.formatValue(axis.maximum, range: axis.maximum - axis.minimum)).font(.caption).foregroundStyle(.secondary)
                }
                .labelsHidden()
                .accessibilityLabel(axis.name)
                .accessibilityValue(VariationAxis.formatValue(settings.value(axis.tag), range: axis.maximum - axis.minimum))
            }
        }
    }
}

extension VariationAxis {
    /// Whole numbers for wide axes (weight 100–900); two decimals for narrow ones (0.5–3.2).
    static func formatValue(_ value: Double, range: Double = 100) -> String {
        if range < 10 { return String(format: "%.2f", value) }
        return abs(value - value.rounded()) < 0.05 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}

// MARK: Info

struct InfoTab: View {
    var model: AppModel
    let face: FontFace
    let family: FontFamily
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                InfoSection(model: model, face: face, family: family)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Tags").font(.headline)
                    HStack(spacing: Spacing.s) {
                        let tags = model.tags.tags(of: family.name)
                        if tags.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        } else {
                            ForEach(tags, id: \.self) { tag in
                                // As tall as the Edit Tags… button beside it.
                                Label(tag, systemImage: "tag")
                                    .font(.callout)
                                    .padding(.horizontal, Spacing.s)
                                    .frame(minHeight: 24)
                                    .background(Capsule().fill(Color.selectionTint(activeState, opacity: 0.14)))
                            }
                        }
                        Button("Edit Tags…") { model.sheet = .tags }
                            .help("Add or remove tags (⌘T)")
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("All Styles").font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xs) {
                        GridRow {
                            Text("Style"); Text("PostScript name"); Text("Weight"); Text("State")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ForEach(family.faces) { option in
                            GridRow {
                                Text(option.styleName)
                                Text(option.postScriptName).textSelection(.enabled)
                                Text("\(option.cssWeight)").monospacedDigit()
                                Text(option.isTemporary ? "Until you quit" : option.isEnabled ? "Active" : "Inactive").foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .fontWeight(option.id == face.id ? .semibold : .regular)
                        }
                    }
                }
            }
            .padding(Spacing.windowMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InfoSection: View {
    var model: AppModel
    let face: FontFace
    let family: FontFamily

    var body: some View {
        let info = FontInfo(face: face)
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Info: \(face.styleName)").font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
                row("Family", family.displayName == family.name ? family.name : "\(family.displayName) (\(family.name))")
                row("Style", face.styleName)
                row("PostScript name", face.postScriptName)
                row("Full name", face.fullName)
                row("Version", info.version)
                row("Designer", info.designer)
                row("Foundry", info.manufacturer)
                row("Format", info.format ?? face.format)
                row("Glyphs", info.glyphCount.map { $0.formatted() })
                row("Weight", "\(face.cssWeight)")
                row("Variable axes", face.axes.isEmpty ? "None" : face.axes.map(\.summary).joined(separator: ", "))
                row("Category", family.category.title + (model.hasCategoryOverride(family.name) ? " (set by you)" : ""))
                row("State", stateText)
                row("Copyright", info.copyright)
                row("Licence", info.license)
                GridRow {
                    Text("Location").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(face.path ?? "Built in").textSelection(.enabled)
                        if let folder = model.libraryFolder(of: face) {
                            Text("In your library folder “\(folder.name)”: activated where it is, never copied.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if face.path != nil {
                            Button("Show in Finder") { model.revealInFinder() }
                                .help("Show the font file in Finder (⇧⌘R)")
                                .disabled(model.revealableURLs.isEmpty)
                        }
                    }
                }
            }
            .font(.callout)
        }
    }

    private var stateText: String {
        let state = face.isTemporary ? "Active until you quit Specimen" : face.isEnabled ? "Active" : "Inactive"
        guard let lock = model.lockReason(for: face) else { return state }
        return "\(state). \(lock.explanation)"
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).lineLimit(6)
            }
        }
    }
}

// MARK: Compare

/// The compare tray side by side: every collected font stacked full width with the same
/// text and size, each with a style picker, a details button and remove.
struct CompareView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                Text(model.tray.count == 1 ? "1 font" : "\(model.tray.count) fonts")
                    .font(.headline)
                Text("Collect fonts with Return or the ⊕ on a card. They stay here while you browse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Clear All") { model.clearTray() }
                    .help("Empty the compare tray (⌥⌘K)")
            }
            .padding(.horizontal, Spacing.windowMargin)
            .padding(.vertical, Spacing.s)
            Hairline()
            List {
                ForEach(Array(model.tray.faceIDs.enumerated()), id: \.element) { index, id in
                    if let face = model.face(id: id), let family = model.family(named: face.familyName) {
                        // Rows on the window margin like the header above (a plain List
                        // adds Spacing.s of its own); separators span the row's content.
                        CompareRow(model: model, face: face, family: family)
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.windowMargin - Spacing.s, bottom: 0,
                                                      trailing: Spacing.windowMargin - Spacing.s))
                            .listRowSeparator(.visible)
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                    }
                }
                .onMove { model.moveInTray(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onExitCommand { model.goBack() }
    }
}

struct CompareRow: View {
    var model: AppModel
    let face: FontFace
    let family: FontFamily
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: face.isTemporary ? "circle.dashed.inset.filled" : face.isEnabled ? "circle.fill" : "circle")
                    .font(.system(size: 6))
                    .foregroundStyle(face.isEnabled ? Color.windowAccent(activeState) : .secondary)
                    .accessibilityHidden(true)
                Text(family.displayName).font(.subheadline).foregroundStyle(.secondary)
                Picker("Style", selection: Binding(get: { face.id }, set: { model.replaceInTray(face.id, with: $0) })) {
                    ForEach(family.faces) { option in
                        Text(option.styleName).tag(option.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .accessibilityLabel("Style of \(family.displayName)")
                .disabled(family.faces.count < 2)
                Spacer()
                Button {
                    model.openDetail(face: face)
                } label: {
                    Label("Show Details", systemImage: "info.circle").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Show every style of \(family.displayName)")
                .accessibilityLabel("Show details of \(family.displayName)")
                Button {
                    model.removeFromTray([face.id])
                } label: {
                    Label("Remove", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove from Compare")
                .accessibilityLabel("Remove \(family.displayName) from Compare")
            }
            PreviewLine(face: face, text: model.previewText, size: CGFloat(model.previewSize))
        }
        .padding(.vertical, Spacing.s)
    }
}
