import AppKit
import ShorthandCore
import SlopKit
import SwiftUI

/// The snippet library: groups in the sidebar, snippets in the list, the editor on the right.
struct LibraryWindow: View {
    static let id = "library"

    @Bindable var model: AppModel
    @State private var sidebar: SidebarItem?
    @State private var selection: Set<UUID>
    @State private var query = ""
    @State private var searchFocusRequest = 0
    @State private var focusAbbreviation = 0
    @State private var showsImport = false
    @State private var groupToDelete: SnippetGroup?
    @State private var renaming: UUID?
    @FocusState private var listFocused: Bool
    @Environment(\.undoManager) private var undoManager

    enum SidebarItem: Hashable {
        case all
        case group(UUID)
    }

    init(model: AppModel, sidebar: SidebarItem = .all, selection: Set<UUID> = []) {
        self.model = model
        _sidebar = State(initialValue: sidebar)
        _selection = State(initialValue: selection)
    }

    private var groupID: UUID? {
        if case .group(let id) = sidebar { return id }
        return nil
    }

    private var visible: [Snippet] {
        SnippetSearch.search(model.library.snippets(in: groupID), query: query)
    }

    private var selectedSnippet: Snippet? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return model.library.snippet(id)
    }

    var body: some View {
        NavigationSplitView {
            GroupSidebar(model: model, selection: $sidebar, renaming: $renaming, groupToDelete: $groupToDelete)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } content: {
            snippetList
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            if let snippet = selectedSnippet {
                SnippetEditor(model: model, snippetID: snippet.id, focusAbbreviation: focusAbbreviation)
                    .id(snippet.id)
            } else if selection.count > 1 {
                ContentUnavailableView("\(selection.count) Snippets Selected", systemImage: "square.stack",
                                       description: Text("Press ⌘⌫ to delete them, or drag them to a group."))
            } else {
                ContentUnavailableView("No Snippet Selected", systemImage: "character.cursor.ibeam",
                                       description: Text("Choose a snippet to edit it."))
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search snippets")
        .modifier(SearchFocus(request: searchFocusRequest))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newSnippet() } label: { Label("New Snippet", systemImage: "square.and.pencil") }
                    .help("New snippet (⌘N)")
            }
        }
        .navigationTitle(navigationTitle)
        .focusedSceneValue(\.libraryActions, actions)
        .sheet(isPresented: $showsImport) { ImportSheet(model: model) }
        .confirmationDialog(groupToDelete.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(
            get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } }
        )) {
            Button("Delete Group", role: .destructive) {
                if let group = groupToDelete { deleteGroup(group) }
                groupToDelete = nil
            }
            Button("Cancel", role: .cancel) { groupToDelete = nil }
        } message: {
            if let group = groupToDelete {
                let count = model.library.snippets(in: group.id).count
                Text("This deletes the group and its \(count == 1 ? "snippet" : "\(count) snippets"). You can undo this with ⌘Z.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryRequest)) { _ in takeRequest() }
        .onAppear { takeRequest() }
        .onChange(of: sidebar) { _, _ in selection = selection.filter { id in visible.contains { $0.id == id } } }
    }

    private var navigationTitle: String {
        if let groupID, let group = model.library.group(groupID) { return group.name }
        return "All Snippets"
    }

    // MARK: List

    private var snippetList: some View {
        VStack(spacing: 0) {
            NoticeStack(model: model)
            Group {
                if model.library.snippets.isEmpty {
                    ContentUnavailableView {
                        Label("No Snippets Yet", systemImage: "character.cursor.ibeam")
                    } description: {
                        Text("Make one, or bring in your Text Replacements or another expander's snippets.")
                    } actions: {
                        Button("New Snippet") { newSnippet() }
                            .buttonStyle(.borderedProminent)
                        Button("Import Snippets…") { showsImport = true }
                    }
                } else if visible.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if visible.isEmpty {
                    ContentUnavailableView {
                        Label("No Snippets in This Group", systemImage: "folder")
                    } actions: {
                        Button("New Snippet") { newSnippet() }
                    }
                } else {
                    let lookup = model.library.lookup
                    List(selection: $selection) {
                        ForEach(visible) { snippet in
                            SnippetRow(snippet: snippet, enabled: model.library.group(snippet.groupID)?.isEnabled ?? true,
                                       duplicate: isDuplicate(snippet), hasFields: FillIn.hasFields(snippet, lookup: lookup))
                                .tag(snippet.id)
                                .draggable(snippet.id.uuidString)
                                .contextMenu { rowMenu(snippet) }
                        }
                    }
                    .focused($listFocused)
                    .onDeleteCommand { deleteSelection() }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func isDuplicate(_ snippet: Snippet) -> Bool {
        ConflictChecker.warnings(for: snippet, in: model.library).contains { $0.blocksExpansion }
    }

    @ViewBuilder private func rowMenu(_ snippet: Snippet) -> some View {
        Button("Duplicate") { duplicate(snippet.id) }
        if model.library.groups.count > 1 {
            Menu("Move to") {
                ForEach(model.library.groups.filter { $0.id != snippet.groupID }) { group in
                    Button(group.name) { model.move(targets(snippet), to: group.id) }
                }
            }
        }
        Divider()
        Button("Delete") { model.deleteSnippets(targets(snippet), undoManager: undoManager) }
    }

    /// The clicked row, or the whole selection when the row is part of it.
    private func targets(_ snippet: Snippet) -> Set<UUID> {
        selection.contains(snippet.id) ? selection : [snippet.id]
    }

    // MARK: Actions

    private var actions: LibraryActions {
        var duplicateAction: (() -> Void)?
        if let id = selectedSnippet?.id { duplicateAction = { duplicate(id) } }
        var deleteAction: (() -> Void)?
        if !selection.isEmpty && listFocused { deleteAction = { deleteSelection() } }
        let model = self.model
        let group: SnippetGroup? = groupID.flatMap { model.library.group($0) }
        return LibraryActions(
            newSnippet: { newSnippet() },
            newGroup: { newGroup() },
            importReplacements: { showsImport = true },
            exportSnippets: { exportSnippets() },
            duplicate: duplicateAction,
            delete: deleteAction,
            find: { searchFocusRequest &+= 1 },
            selectedGroup: group,
            toggleGroup: { if let group { model.setGroup(group.id, enabled: !group.isEnabled) } }
        )
    }

    private func newSnippet() {
        query = ""
        let snippet = model.newSnippet(in: groupID)
        selection = [snippet.id]
        focusAbbreviation &+= 1
    }

    private func newGroup() {
        let group = model.newGroup()
        sidebar = .group(group.id)
        renaming = group.id
    }

    private func duplicate(_ id: UUID) {
        if let copy = model.duplicate(id) {
            selection = [copy.id]
            focusAbbreviation &+= 1
        }
    }

    private func deleteSelection() {
        let ids = selection
        let order = visible.map(\.id)
        // Select the next row, like Finder and Mail.
        let next = order.drop { !ids.contains($0) }.first { !ids.contains($0) } ?? order.last { !ids.contains($0) }
        model.deleteSnippets(ids, undoManager: undoManager)
        selection = next.map { [$0] } ?? []
    }

    private func deleteGroup(_ group: SnippetGroup) {
        if sidebar == .group(group.id) { sidebar = .all }
        model.deleteGroup(group.id, undoManager: undoManager)
    }

    private func takeRequest() {
        guard let request = LibraryOpener.pendingRequest else { return }
        LibraryOpener.pendingRequest = nil
        switch request {
        case .newSnippet: newSnippet()
        case .importReplacements: showsImport = true
        case .importFile(let url):
            ImportSheet.pendingFile = url
            showsImport = true
        case .select(let abbreviation):
            guard let snippet = model.library.snippet(abbreviation: abbreviation) else { return }
            query = ""
            sidebar = .all
            selection = [snippet.id]
        }
    }

    private func exportSnippets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Shorthand Snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LibraryExport.data(model.library).write(to: url, options: .atomic)
            HUD.show("Exported", systemImage: "square.and.arrow.up")
        } catch {
            HUD.show("Couldn't save the export there. Try another folder.", systemImage: "exclamationmark.triangle")
        }
    }
}

/// One snippet in the list: abbreviation, then its name or first line.
struct SnippetRow: View {
    let snippet: Snippet
    let enabled: Bool
    let duplicate: Bool
    var hasFields = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.abbreviation.isEmpty ? "No abbreviation" : snippet.abbreviation)
                    .font(.body.monospaced())
                    .foregroundStyle(snippet.abbreviation.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(snippet.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if snippet.isFormatted {
                Image(systemName: "textformat")
                    .foregroundStyle(.secondary)
                    .help("Formatted text")
                    .accessibilityLabel("Formatted")
            }
            if hasFields {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .foregroundStyle(.secondary)
                    .help("Asks for fill-ins")
                    .accessibilityLabel("Asks for fill-ins")
            }
            if duplicate {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Another snippet uses this abbreviation")
                    .accessibilityLabel("Abbreviation used twice")
            }
        }
        .opacity(enabled ? 1 : 0.55)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint(enabled ? "" : "In a group that's turned off")
    }
}

/// Groups: All Snippets, then each group with its on/off state.
struct GroupSidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: LibraryWindow.SidebarItem?
    @Binding var renaming: UUID?
    @Binding var groupToDelete: SnippetGroup?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        List(selection: $selection) {
            Label("All Snippets", systemImage: "tray.full")
                .badge(model.library.snippets.count)
                .tag(LibraryWindow.SidebarItem.all)
            Section("Groups") {
                ForEach(model.library.groups) { group in
                    GroupRow(model: model, group: group, renaming: $renaming)
                        .tag(LibraryWindow.SidebarItem.group(group.id))
                        .dropDestination(for: String.self) { items, _ in
                            let ids = Set(items.compactMap(UUID.init(uuidString:)))
                            model.move(ids, to: group.id)
                            return !ids.isEmpty
                        }
                        .contextMenu {
                            Button("Rename") { renaming = group.id }
                            Button(group.isEnabled ? "Turn Off Group" : "Turn On Group") {
                                model.setGroup(group.id, enabled: !group.isEnabled)
                            }
                            Divider()
                            Button("Delete Group…") { askToDelete(group) }
                                .disabled(model.library.groups.count < 2)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button { selectNewGroup() } label: { Label("New Group", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .help("New group (⇧⌘N)")
                Spacer()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
    }

    private func selectNewGroup() {
        let group = model.newGroup()
        selection = .group(group.id)
        renaming = group.id
    }

    private func askToDelete(_ group: SnippetGroup) {
        if model.library.snippets(in: group.id).isEmpty {
            if selection == .group(group.id) { selection = .all }
            model.deleteGroup(group.id, undoManager: undoManager)
        } else {
            groupToDelete = group
        }
    }
}

struct GroupRow: View {
    @Bindable var model: AppModel
    let group: SnippetGroup
    @Binding var renaming: UUID?
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        if renaming == group.id {
            TextField("Group name", text: $name)
                .focused($focused)
                .onAppear {
                    name = group.name
                    focused = true
                }
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { renaming = nil }
        } else {
            Label {
                Text(group.name)
                    .foregroundStyle(group.isEnabled ? .primary : .secondary)
            } icon: {
                Image(systemName: group.isEnabled ? "folder" : "folder.badge.minus")
            }
            .badge(model.library.snippets(in: group.id).count)
            .accessibilityValue(group.isEnabled ? "" : "Turned off")
            .help(group.isEnabled ? "" : "Turned off: its snippets don't expand")
        }
    }

    private func commit() {
        guard renaming == group.id else { return }
        model.renameGroup(group.id, to: name)
        renaming = nil
    }
}

/// Rows above the list: permission, paste privacy, a recovered library.
struct NoticeStack: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.loadNotice {
                NoticeRow(systemImage: "exclamationmark.triangle", text: notice, button: "OK") { model.loadNotice = nil }
            }
            if model.isEnabled, model.hasExpandableSnippets, let needed = model.nextPermission {
                switch needed {
                case .accessibility:
                    NoticeRow(systemImage: "hand.raised",
                              text: "To expand abbreviations, Shorthand needs to see what you type and type for you. Nothing you type is stored.",
                              button: "Open System Settings") { Permission.accessibility.request() }
                case .inputMonitoring:
                    NoticeRow(systemImage: "keyboard",
                              text: "macOS also needs to let Shorthand notice the keys you type (Input Monitoring). Nothing you type is stored.",
                              button: "Open System Settings") { KeyboardPermissions.requestListening() }
                }
            }
            if model.tapGaveUp {
                NoticeRow(systemImage: "exclamationmark.triangle", text: "macOS kept switching off Shorthand's keyboard listening.",
                          button: "Try Again") { model.retryAfterGivingUp() }
            }
        }
    }
}

struct NoticeRow: View {
    let systemImage: String
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(button, action: action)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.m)
            Hairline()
        }
        .background(.bar)
    }
}

/// ⌘F focuses the toolbar search field (macOS 15+; on 14 the field is a click away).
struct SearchFocus: ViewModifier {
    let request: Int
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .searchFocused($focused)
                .onChange(of: request) { _, _ in focused = true }
        } else {
            content
        }
    }
}

// MARK: - Commands

struct LibraryActions {
    var newSnippet: () -> Void
    var newGroup: () -> Void
    var importReplacements: () -> Void
    var exportSnippets: () -> Void
    var duplicate: (() -> Void)?
    var delete: (() -> Void)?
    var find: () -> Void
    var selectedGroup: SnippetGroup?
    var toggleGroup: () -> Void
}

struct LibraryActionsKey: FocusedValueKey {
    typealias Value = LibraryActions
}

/// The focused editor's "insert this placeholder at the caret".
struct PlaceholderInserterKey: FocusedValueKey {
    typealias Value = (Placeholder) -> Void
}

extension FocusedValues {
    var libraryActions: LibraryActions? {
        get { self[LibraryActionsKey.self] }
        set { self[LibraryActionsKey.self] = newValue }
    }

    var placeholderInserter: ((Placeholder) -> Void)? {
        get { self[PlaceholderInserterKey.self] }
        set { self[PlaceholderInserterKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    let model: AppModel
    @FocusedValue(\.libraryActions) private var actions
    @FocusedValue(\.placeholderInserter) private var insertPlaceholder
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Snippet") { withLibrary { $0.newSnippet() } }
                .keyboardShortcut("n")
            Button("New Group") { withLibrary { $0.newGroup() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Import Snippets…") { withLibrary { $0.importReplacements() } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Snippets…") { actions?.exportSnippets() }
                .disabled(actions == nil)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Insert a Snippet…") { model.toggleSearch() }
        }
        TextFormattingCommands()
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") { actions?.duplicate?() }
                .keyboardShortcut("d")
                .disabled(actions?.duplicate == nil)
            Button("Delete") { actions?.delete?() }
                .keyboardShortcut(.delete)
                .disabled(actions?.delete == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find Snippets") { actions?.find() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }
        CommandMenu("Snippet") {
            PlaceholderMenu(snippets: model.library.snippets) { insertPlaceholder?($0) }
                .disabled(insertPlaceholder == nil)
            Divider()
            Button(actions?.selectedGroup?.isEnabled == false ? "Turn On Group" : "Turn Off Group") { actions?.toggleGroup() }
                .disabled(actions?.selectedGroup == nil)
        }
    }

    /// Runs in the library, opening it first when the action comes from elsewhere.
    private func withLibrary(_ body: (LibraryActions) -> Void) {
        if let actions {
            body(actions)
        } else {
            openWindow(id: LibraryWindow.id)
        }
    }
}

/// The "Insert Placeholder" menu: in the editor and the Snippet menu.
struct PlaceholderMenu: View {
    /// Snippets that can be included (with an abbreviation).
    var snippets: [Snippet] = []
    let insert: (Placeholder) -> Void

    var body: some View {
        Menu("Insert Placeholder") {
            Menu("Date") {
                ForEach(DateSpec.Style.allCases, id: \.self) { style in
                    Button(sample(DateSpec(kind: .date, style: style))) { insert(.date(DateSpec(kind: .date, style: style))) }
                }
                Divider()
                Button("Tomorrow") { insert(.date(DateSpec(kind: .date, offset: DateOffset(amount: 1, unit: .day)))) }
                Button("In a Week") { insert(.date(DateSpec(kind: .date, offset: DateOffset(amount: 1, unit: .week)))) }
                Button("Custom Format") { insert(.date(DateSpec(kind: .date, format: "EEEE d MMMM"))) }
            }
            Menu("Time") {
                ForEach([DateSpec.Style.short, .medium, .iso], id: \.self) { style in
                    Button(sample(DateSpec(kind: .time, style: style))) { insert(.date(DateSpec(kind: .time, style: style))) }
                }
            }
            Button("Date and Time") { insert(.date(DateSpec(kind: .datetime))) }
            Divider()
            Button("Clipboard") { insert(.clipboard) }
            Button("Cursor Position") { insert(.cursor) }
            Divider()
            Button("Fill-In Field") { insert(.field(name: "Name", defaultValue: "")) }
            Button("Choice") { insert(.choice(name: "Choice", options: ["First", "Second"])) }
            Button("Optional Section") { insert(.optionalStart(name: "Section", defaultOn: true)) }
            Menu("Another Snippet") {
                let named = snippets.filter { !$0.abbreviation.isEmpty }
                if named.isEmpty {
                    Text("No other snippets with an abbreviation")
                } else {
                    ForEach(named) { snippet in
                        Button("\(snippet.title) (\(snippet.abbreviation))") { insert(.snippet(abbreviation: snippet.abbreviation)) }
                    }
                }
            }
        }
    }

    private func sample(_ spec: DateSpec) -> String {
        PlaceholderResolver(now: Date()).format(spec)
    }
}
