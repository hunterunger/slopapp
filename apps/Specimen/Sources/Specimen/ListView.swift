import SlopKit
import SpecimenCore
import SwiftUI

/// One row of the list: a family (with its styles as children) or a single style.
struct ListRow: Identifiable, Hashable {
    let id: String
    /// The grid entry this row belongs to (selection and actions work on entries).
    let entryID: String
    let family: FontFamily
    let face: FontFace?
    var children: [ListRow]?

    static func == (a: ListRow, b: ListRow) -> Bool { a.id == b.id && a.face == b.face && a.family == b.family }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var name: String { face.map { family.faces.count > 1 ? $0.styleName : family.displayName } ?? family.displayName }
    var styleCount: Int { face == nil ? family.faces.count : 1 }
    var categoryOrder: Int { FontCategory.allCases.firstIndex(of: family.category) ?? 0 }
    var foundry: String { (face?.foundry ?? family.foundry) ?? "" }
    var dateAdded: Date { (face?.fileModified ?? family.dateAdded) ?? .distantPast }
    var faces: [FontFace] { face.map { [$0] } ?? family.faces }
    var state: ActivationState { ActivationState(faces: faces) }

    var weightText: String {
        if let face { return "\(face.cssWeight)" }
        guard let range = family.weightRange else { return "" }
        return range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }

    var formatText: String {
        let formats = Set(faces.map(\.format))
        return formats.count == 1 ? formats.first ?? "" : "Mixed"
    }

    var versionText: String {
        let versions = Set(faces.compactMap(\.version))
        return versions.count == 1 ? versions.first ?? "" : versions.isEmpty ? "" : "Mixed"
    }

    var locationText: String {
        let locations = Set(faces.map(\.location))
        if locations.count == 1, let location = locations.first {
            if location == .other, let path = faces.first?.path {
                return URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            }
            return location.title
        }
        return "Several"
    }
}

/// The library as a table: one row per family (disclose for styles), sortable columns, and
/// a preview of the selected font above it.
struct FontListView: View {
    @Bindable var model: AppModel
    @State private var selection: Set<String> = []
    @FocusState private var focused: Bool
    @Environment(\.controlActiveState) private var activeState

    private var rows: [ListRow] {
        model.items.map { entry in
            if model.groupByFamily {
                let children = entry.family.faces.count > 1
                    ? entry.faces.map { ListRow(id: "face:\($0.id)", entryID: entry.id, family: entry.family, face: $0, children: nil) }
                    : nil
                return ListRow(id: entry.id, entryID: entry.id, family: entry.family, face: nil, children: children)
            }
            return ListRow(id: entry.id, entryID: entry.id, family: entry.family, face: entry.representative, children: nil)
        }
    }

    /// The face the preview shows: a selected style row, else the selected family's representative.
    private var previewFace: FontFace? {
        if let id = selection.sorted().first {
            if id.hasPrefix("face:"), let face = model.face(id: String(id.dropFirst(5))) { return face }
            if let entry = model.items.first(where: { $0.id == id }) { return entry.representative }
        }
        return model.items.first?.representative
    }

    var body: some View {
        VStack(spacing: 0) {
            if let face = previewFace {
                preview(face)
                Hairline()
            }
            table
        }
        .onAppear {
            selection = model.selection
            focused = true
        }
        .onChange(of: selection) { pushSelection() }
        .onChange(of: model.selection) {
            let entries = Set(selection.compactMap(entryID(for:)))
            if entries != model.selection { selection = model.selection }
        }
        .onChange(of: model.focusGridRequest) { focused = true }
    }

    private func preview(_ face: FontFace) -> some View {
        let size = min(CGFloat(model.previewSize), 120)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(face.fullName).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let family = model.family(named: face.familyName), family.faces.count > 1 {
                    Text("\(family.faces.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            PreviewLine(face: face, text: model.previewText, size: size, centered: true)
                .frame(height: PreviewMetrics.height(for: size))
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of \(face.fullName)")
    }

    private var table: some View {
        Table(rows, children: \.children, selection: $selection, sortOrder: sortOrder) {
            TableColumn("State") { row in
                Image(systemName: stateSymbol(row))
                    .font(.system(size: 7))
                    // Same colours as the grid's cards: accent when on, secondary when off or locked.
                    .foregroundStyle(row.state == .inactive || stateSymbol(row) == "lock.fill" ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.windowAccent(activeState)))
                    .help(row.state.title)
                    .accessibilityLabel(row.state.title)
            }
            .width(52)
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: Spacing.xs) {
                    Text(row.name).fontWeight(row.face == nil ? .medium : .regular)
                    if model.favorites.contains(row.family.name), row.face == nil || !model.groupByFamily {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.windowAccent(activeState))
                            .accessibilityLabel("Favorite")
                    }
                    if model.tray.containsAny(row.faces.map(\.id)) {
                        Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(Color.windowAccent(activeState))
                            .accessibilityLabel("In Compare")
                    }
                }
            }
            .width(min: 160, ideal: 220)
            TableColumn("Styles", value: \.styleCount) { row in
                Text(row.face == nil ? "\(row.styleCount)" : "").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(50)
            TableColumn("Weight") { row in
                Text(row.weightText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Category", value: \.categoryOrder) { row in
                Text(row.family.category.title)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Format") { row in
                Text(row.formatText).foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Version") { row in
                Text(row.versionText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)
            TableColumn("Foundry", value: \.foundry) { row in
                Text(row.foundry).lineLimit(1)
            }
            .width(min: 90, ideal: 160)
            TableColumn("Location") { row in
                Text(row.locationText).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 110)
            TableColumn("Date Added", value: \.dateAdded) { row in
                Text(row.dateAdded == .distantPast ? "" : row.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .focused($focused)
        .contextMenu(forSelectionType: String.self) { ids in
            FontMenuItems(model: model, entryIDs: Set(ids.compactMap(entryID(for:))))
        } primaryAction: { ids in
            if let entry = ids.compactMap(entryID(for:)).first.flatMap({ id in model.items.first { $0.id == id } }) {
                model.selection = [entry.id]
                if let faceID = ids.first(where: { $0.hasPrefix("face:") }), let face = model.face(id: String(faceID.dropFirst(5))) {
                    model.openDetail(face: face)
                } else {
                    model.openDetail(entry)
                }
            }
        }
        .onKeyPress(.space) {
            model.openDetail()
            return .handled
        }
        .onKeyPress(.return) {
            model.toggleTraySelection()
            return .handled
        }
        .onCopyCommand {
            model.copyNames(postScript: false)
            return []
        }
        .accessibilityLabel("Fonts")
    }

    private func stateSymbol(_ row: ListRow) -> String {
        if row.state == .active, model.lockReason(for: row.family) != nil, row.face == nil { return "lock.fill" }
        switch row.state {
        case .active: return "circle.fill"
        case .inactive: return "circle"
        case .mixed: return "circle.lefthalf.filled"
        }
    }

    private func entryID(for rowID: String) -> String? {
        if !model.groupByFamily || !rowID.hasPrefix("face:") { return rowID }
        let faceID = String(rowID.dropFirst(5))
        guard let face = model.face(id: faceID) else { return nil }
        return "family:\(face.familyName)"
    }

    private func pushSelection() {
        let entries = Set(selection.compactMap(entryID(for:)))
        if entries != model.selection { model.selection = entries }
    }

    /// Column headers drive the same sort as View ▸ Sort By.
    private var sortOrder: Binding<[KeyPathComparator<ListRow>]> {
        Binding {
            let order: SortOrder = model.sort.ascending ? .forward : .reverse
            switch model.sort.key {
            case .name: return [KeyPathComparator(\ListRow.name, order: order)]
            case .styles: return [KeyPathComparator(\ListRow.styleCount, order: order)]
            case .category: return [KeyPathComparator(\ListRow.categoryOrder, order: order)]
            case .foundry: return [KeyPathComparator(\ListRow.foundry, order: order)]
            case .recentlyAdded: return [KeyPathComparator(\ListRow.dateAdded, order: order)]
            }
        } set: { comparators in
            guard let first = comparators.first else { return }
            let path: AnyKeyPath = first.keyPath
            let key: LibrarySort.Key
            if path == \ListRow.styleCount { key = .styles }
            else if path == \ListRow.categoryOrder { key = .category }
            else if path == \ListRow.foundry { key = .foundry }
            else if path == \ListRow.dateAdded { key = .recentlyAdded }
            else { key = .name }
            model.sort = LibrarySort(key: key, ascending: first.order == .forward)
        }
    }
}

/// The font actions as SwiftUI menu items (list context menu). Same as the Font menu.
struct FontMenuItems: View {
    var model: AppModel
    /// The entries the menu is for (the clicked rows); selected first.
    let entryIDs: Set<String>

    private func run(_ action: @escaping () -> Void) -> () -> Void {
        {
            if !entryIDs.isEmpty, entryIDs != model.selection { model.selection = entryIDs }
            action()
        }
    }

    var body: some View {
        let families = Array(Set(model.items.filter { entryIDs.contains($0.id) }.map(\.family.name))).sorted()
        Button("Show Details", action: run { model.openDetail() })
        Button(isAllInTray ? "Remove from Compare" : "Add to Compare", action: run { model.toggleTraySelection() })
        Divider()
        Button(families.allSatisfy(model.favorites.contains) && !families.isEmpty ? "Remove from Favorites" : "Add to Favorites",
               action: run { model.toggleFavorite() })
        Menu("Tags") {
            ForEach(model.tags.names, id: \.self) { tag in
                Toggle(tag, isOn: Binding(get: { model.tags.membership(tag, families: families) == .all },
                                          set: { _ in model.selection = entryIDs; model.toggleTag(tag, families: families) }))
            }
            if !model.tags.isEmpty { Divider() }
            Button("New Tag…", action: run { model.sheet = .newTag })
            Button("Edit Tags…", action: run { model.sheet = .tags })
        }
        Divider()
        Button("Activate", action: run { model.activate(true) })
        Button("Deactivate", action: run { model.activate(false) })
        Divider()
        Button("Copy Name", action: run { model.copyNames(postScript: false) })
        Button("Copy PostScript Name", action: run { model.copyNames(postScript: true) })
        Button("Show in Finder", action: run { model.revealInFinder() })
    }

    private var isAllInTray: Bool {
        let entries = model.items.filter { entryIDs.contains($0.id) }
        return !entries.isEmpty && entries.allSatisfy(model.isInTray)
    }
}
