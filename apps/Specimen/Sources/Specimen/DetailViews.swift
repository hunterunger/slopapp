import SlopKit
import SpecimenCore
import SwiftUI

/// One family on one scrolling page: every style in the preview text, a waterfall of the
/// chosen style, and its details.
struct FamilyDetailView: View {
    @Bindable var model: AppModel
    let familyName: String
    @FocusState private var focused: Bool

    static let waterfallSizes: [CGFloat] = [12, 16, 24, 36, 48, 72]

    private var family: FontFamily? { model.family(named: familyName) }
    private var selectedFace: FontFace? {
        guard let family else { return nil }
        return family.faces.first { $0.id == model.detailFaceID } ?? family.representative
    }

    var body: some View {
        if let family {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header(family)
                    stylesSection(family)
                    if let face = selectedFace {
                        waterfall(face)
                        InfoSection(model: model, face: face, family: family)
                    }
                }
                .padding(Spacing.windowMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onExitCommand { model.goBack() }
            .onKeyPress(.downArrow) { moveStyle(1, in: family); return .handled }
            .onKeyPress(.upArrow) { moveStyle(-1, in: family); return .handled }
        } else {
            ContentUnavailableView("This font is gone", systemImage: "questionmark.square.dashed",
                                   description: Text("It was removed or turned off elsewhere."))
                .onExitCommand { model.goBack() }
        }
    }

    private func moveStyle(_ delta: Int, in family: FontFamily) {
        guard let current = family.faces.firstIndex(where: { $0.id == selectedFace?.id }) else { return }
        let next = min(max(current + delta, 0), family.faces.count - 1)
        model.detailFaceID = family.faces[next].id
    }

    private func header(_ family: FontFamily) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(family.displayName)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text(summary(family))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let isFavorite = model.favorites.contains(family.name)
            Button {
                model.setFavorite(!isFavorite, families: [family.name])
            } label: {
                Label(isFavorite ? "Favorite" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star")
            }
            .help(isFavorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            activationButton(family)
        }
    }

    @ViewBuilder private func activationButton(_ family: FontFamily) -> some View {
        if let lock = model.lockReason(for: family) {
            Label(lock.title, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
                .help(lock.explanation)
                .accessibilityElement(children: .combine)
                .accessibilityHint(lock.explanation)
        } else if family.state == .active {
            Button("Deactivate") { model.request(false, faces: family.faces) }
                .help("Turn off every style of this family (⇧⌘;)")
        } else {
            Button("Activate") { model.request(true, faces: family.faces) }
                .help("Turn on every style of this family (⌘;)")
        }
    }

    private func summary(_ family: FontFamily) -> String {
        let styles = family.faces.count == 1 ? "1 style" : "\(family.faces.count) styles"
        return [styles, family.category.title, family.state.title].joined(separator: " · ")
    }

    private func stylesSection(_ family: FontFamily) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Styles").font(.headline)
            ForEach(family.faces) { face in
                StyleRow(model: model, face: face, isSelected: face.id == selectedFace?.id)
            }
        }
    }

    private func waterfall(_ face: FontFace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Sizes: \(face.styleName)").font(.headline)
            ForEach(Self.waterfallSizes, id: \.self) { size in
                HStack(alignment: .center, spacing: Spacing.m) {
                    Text("\(Int(size))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                        .accessibilityHidden(true)
                    PreviewLine(face: face, text: model.previewText.isEmpty ? PreviewPreset.all[1].text : model.previewText, size: size)
                        .accessibilityLabel("\(Int(size)) point")
                }
            }
        }
    }
}

struct StyleRow: View {
    var model: AppModel
    let face: FontFace
    let isSelected: Bool

    private var isDuplicate: Bool {
        model.family(named: face.familyName)?.faces.contains { $0.postScriptName == face.postScriptName && $0.id != face.id } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.s) {
                Text(face.styleName).font(.callout.weight(.semibold))
                Text(face.postScriptName).font(.caption).foregroundStyle(.secondary)
                if isDuplicate, let path = face.path {
                    Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if !face.isEnabled {
                    Text("Inactive").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            PreviewLine(face: face, text: model.previewText, size: CGFloat(model.previewSize))
        }
        .padding(Spacing.s)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.12) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { model.detailFaceID = face.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(face.styleName), \(face.isEnabled ? "Active" : "Inactive")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.detailFaceID = face.id }
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
                row("Variable axes", face.axes.isEmpty ? "None" : face.axes.map(\.summary).joined(separator: ", "))
                row("Category", family.category.title + (model.hasCategoryOverride(family.name) ? " (set by you)" : ""))
                row("State", stateText)
                row("Copyright", info.copyright)
                GridRow {
                    Text("Location").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(face.path ?? "Built in").textSelection(.enabled)
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
        let state = face.isEnabled ? "Active" : "Inactive"
        guard let lock = model.lockReason(for: face) else { return state }
        return "\(state). \(lock.explanation)"
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 2–8 faces stacked full width, same text and size, each with a style picker and remove.
struct CompareView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(Array(model.compareFaceIDs.enumerated()), id: \.offset) { index, id in
                    if let face = model.face(id: id), let family = model.family(named: face.familyName) {
                        CompareRow(model: model, index: index, face: face, family: family)
                        Divider()
                    }
                }
            }
            .padding(Spacing.windowMargin)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onExitCommand { model.goBack() }
        .onChange(of: model.compareFaceIDs) {
            if model.compareFaceIDs.count < 1 { model.goBack() }
        }
    }
}

struct CompareRow: View {
    var model: AppModel
    let index: Int
    let face: FontFace
    let family: FontFamily

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(family.displayName).font(.headline)
                Picker("Style", selection: Binding(
                    get: { face.id },
                    set: { newID in
                        guard index < model.compareFaceIDs.count else { return }
                        model.compareFaceIDs[index] = newID
                    }
                )) {
                    ForEach(family.faces) { option in
                        Text(option.styleName).tag(option.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Style of \(family.displayName)")
                .disabled(family.faces.count < 2)
                Spacer()
                Button {
                    model.compareFaceIDs.removeAll { $0 == face.id }
                } label: {
                    Label("Remove", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove from comparison")
                .accessibilityLabel("Remove \(family.displayName) from comparison")
            }
            PreviewLine(face: face, text: model.previewText, size: CGFloat(model.previewSize))
        }
    }
}
