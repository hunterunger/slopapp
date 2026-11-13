import SlopKit
import SpecimenCore
import SwiftUI

/// Every sheet over the library window.
struct LibrarySheetView: View {
    @Bindable var model: AppModel
    let sheet: LibrarySheet

    var body: some View {
        switch sheet {
        case .tags: TagPanel(model: model)
        case .newTag: TagNameSheet(model: model, renaming: nil)
        case .renameTag(let name): TagNameSheet(model: model, renaming: name)
        case .smartCollection(let collection, let isNew): SmartCollectionEditor(model: model, collection: collection, isNew: isNew)
        case .install(let report): InstallReportSheet(model: model, report: report)
        }
    }
}

/// ⌘T: tick tags on and off for the selected fonts. Type to filter; Return toggles the
/// highlighted tag, or creates one from the text when nothing matches.
struct TagPanel: View {
    @Bindable var model: AppModel
    @State private var filter = ""
    @State private var highlighted: String?
    @FocusState private var fieldFocused: Bool

    private var families: [String] { model.actionFamilies }

    private var matches: [String] {
        let tokens = LibraryFilter.searchTokens(filter)
        return model.tags.names.filter { name in tokens.isEmpty || tokens.allSatisfy { LibraryFilter.fold(name).contains($0) } }
    }

    private var canCreate: Bool {
        let clean = TagLibrary.normalize(filter)
        return !clean.isEmpty && model.tags.existing(clean) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(families.count == 1 ? "Tags for \(model.family(named: families[0])?.displayName ?? families[0])" : "Tags for \(families.count) fonts")
                .font(.headline)
            TextField("Find or create a tag", text: $filter)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.tab) { toggleHighlighted(); return .handled }
                .accessibilityLabel("Find or create a tag")
            List(selection: $highlighted) {
                ForEach(matches, id: \.self) { name in
                    Toggle(isOn: Binding(
                        get: { model.tags.membership(name, families: families) == .all },
                        set: { _ in model.toggleTag(name, families: families) }
                    )) {
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(model.counts[.tag(name)] ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .toggleStyle(MixedCheckboxStyle(isMixed: model.tags.membership(name, families: families) == .some))
                    .tag(name)
                    .listRowSeparator(.hidden)
                }
                if canCreate {
                    Button {
                        submit()
                    } label: {
                        Label("Create “\(TagLibrary.normalize(filter))”", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            // A rounded box on the field's edges, its corners matching the field's.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Radius.m))
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m))
            .frame(minHeight: 180)
            .overlay {
                if model.tags.isEmpty && !canCreate {
                    Text("No tags yet. Type a name and press Return.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            HStack {
                Text("Return toggles · Tab toggles · Esc closes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.sheet = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 380, height: 380)
        .onAppear { fieldFocused = true }
        .onChange(of: filter) { highlighted = matches.first }
        .disabled(families.isEmpty)
    }

    private func move(_ delta: Int) {
        let list = matches
        guard !list.isEmpty else { return }
        let index = highlighted.flatMap(list.firstIndex(of:)) ?? (delta > 0 ? -1 : list.count)
        highlighted = list[min(max(index + delta, 0), list.count - 1)]
    }

    private func toggleHighlighted() {
        if let highlighted { model.toggleTag(highlighted, families: families) }
    }

    private func submit() {
        if let highlighted, matches.contains(highlighted) {
            model.toggleTag(highlighted, families: families)
        } else if canCreate, let tag = model.createTag(filter, families: families) {
            filter = ""
            highlighted = tag
        } else if let first = matches.first {
            model.toggleTag(first, families: families)
        }
    }
}

/// A checkbox that can show "some of the selection" (–).
struct MixedCheckboxStyle: ToggleStyle {
    let isMixed: Bool
    @Environment(\.controlActiveState) private var activeState

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: isMixed ? "minus.square.fill" : configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn || isMixed ? Color.windowAccent(activeState) : .secondary)
                    .accessibilityHidden(true)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isMixed ? "Some" : configuration.isOn ? "On" : "Off")
    }
}

/// New Tag (⌘N) and Rename Tag.
struct TagNameSheet: View {
    @Bindable var model: AppModel
    let renaming: String?
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(renaming == nil ? "New Tag" : "Rename Tag").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
                .accessibilityLabel("Tag name")
            if renaming == nil, !model.actionFamilies.isEmpty {
                Text(model.actionFamilies.count == 1 ? "It will be added to the selected font." : "It will be added to the \(model.actionFamilies.count) selected fonts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.textRed)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button(renaming == nil ? "Create" : "Rename", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(TagLibrary.normalize(name).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 360)
        .onAppear { name = renaming ?? model.tags.unusedName() }
    }

    private func save() {
        let clean = TagLibrary.normalize(name)
        guard !clean.isEmpty else { return }
        if let renaming {
            if model.renameTag(renaming, to: clean) { model.sheet = nil } else { error = "Another tag is already called “\(clean)”." }
        } else {
            if let existing = model.tags.existing(clean) {
                error = "“\(existing)” already exists."
                return
            }
            if let tag = model.createTag(clean, families: model.actionFamilies) {
                model.sheet = nil
                model.sidebar = .tag(tag)
            }
        }
    }
}

/// Smart collection rules, with a live count.
struct SmartCollectionEditor: View {
    @Bindable var model: AppModel
    @State var collection: SmartCollection
    let isNew: Bool

    init(model: AppModel, collection: SmartCollection, isNew: Bool) {
        self.model = model
        self._collection = State(initialValue: collection)
        self.isNew = isNew
    }

    var body: some View {
        // The grouped form insets its sections by the window margin itself, so the title and
        // the buttons get the same margin and everything shares one left and right edge.
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "New Smart Collection" : "Edit Smart Collection").font(.headline)
                .padding([.horizontal, .top], Spacing.xl)
            Form {
                TextField("Name", text: $collection.name)
                TextField("Name contains", text: $collection.rules.nameContains, prompt: Text("Any name"))
                Picker("Category", selection: $collection.rules.category) {
                    Text("Any").tag(FontCategory?.none)
                    ForEach(FontCategory.allCases) { Text($0.title).tag(FontCategory?.some($0)) }
                }
                Picker("State", selection: $collection.rules.state) {
                    ForEach(SmartRules.State.allCases) { Text($0.title).tag($0) }
                }
                Picker("Location", selection: $collection.rules.source) {
                    ForEach(SmartRules.Source.allCases) { Text($0.title).tag($0) }
                }
                Picker("Tag", selection: $collection.rules.tag) {
                    Text("Any").tag(String?.none)
                    ForEach(model.tags.names, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Stepper(value: $collection.rules.minimumStyles, in: 0...40) {
                    Text(collection.rules.minimumStyles <= 1 ? "Any number of styles" : "At least \(collection.rules.minimumStyles) styles")
                }
                Toggle("Variable fonts only", isOn: $collection.rules.variableOnly)
                Toggle("Favorites only", isOn: $collection.rules.favoritesOnly)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                let count = model.matchCount(collection.rules)
                Text(count == 1 ? "1 family matches" : "\(count.formatted()) families match")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel", role: .cancel) { model.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    var saved = collection
                    saved.name = TagLibrary.normalize(saved.name).isEmpty ? "Smart Collection" : TagLibrary.normalize(saved.name)
                    model.sheet = nil
                    model.saveSmartCollection(saved)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], Spacing.xl)
        }
        .frame(width: 460)
    }
}

/// What Add Fonts… couldn't do.
struct InstallReportSheet: View {
    var model: AppModel
    let report: InstallReport

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(report.added.isEmpty ? "No fonts were installed" : report.added.count == 1 ? "Installed 1 font" : "Installed \(report.added.count) fonts")
                .font(.headline)
            if !report.added.isEmpty {
                Text("Copied to \(report.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).")
                    .foregroundStyle(.secondary)
            }
            if !report.problems.isEmpty {
                Text(report.problems.count == 1 ? "1 file was skipped:" : "\(report.problems.count) files were skipped:")
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(report.problems.indices, id: \.self) { index in
                            let problem = report.problems[index]
                            (Text(problem.file).bold() + Text(" — \(problem.reason)"))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            HStack {
                Spacer()
                Button("OK") { model.sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }
}
