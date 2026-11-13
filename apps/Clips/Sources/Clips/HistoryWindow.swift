import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// The library view of the history: browse by kind or source app, search, pin, copy and
/// clean up, with full keyboard support.
struct HistoryWindow: View {
    static let id = "history"

    @Bindable var model: AppModel
    @State private var sidebar: SidebarItem? = .filter(.all)
    @State private var query = ""
    @State private var results: [Clip] = []
    @State private var resultsVersion = 0
    @State private var selection = Set<UUID>()
    @State private var now = Date()
    @State private var focusSearch = 0
    /// Clips waiting for "Delete N clips?" confirmation (several, or pinned ones).
    @State private var pendingDeletion: [Clip] = []
    /// The clip being edited in the detail pane.
    @State private var editor: ClipEditSession?
    /// A board or clip whose name is being typed in a Rename alert.
    @State private var renaming: Renaming?
    @State private var renameDraft = ""
    /// A board with clips, waiting for "Delete Board?".
    @State private var pendingBoardDelete: Board?

    enum Renaming: Equatable {
        case board(UUID)
        case clip(UUID)
    }

    enum SidebarItem: Hashable {
        case filter(ClipFilter)
        case app(String)
    }

    /// Selected clips that are visible right now. Actions only ever touch these, so a clip
    /// hidden by a search can't be pinned, copied or deleted by accident.
    private var selectedClips: [Clip] {
        results.filter { selection.contains($0.id) }
    }

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } content: {
            clipList
                .navigationSplitViewColumnWidth(min: 260, ideal: 340)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem {
                Button {
                    model.isPaused ? model.resume() : model.pause(for: nil)
                } label: {
                    Label(model.isPaused ? "Resume Recording" : "Pause Recording",
                          systemImage: model.isPaused ? "play.circle" : "pause.circle")
                }
                .help(model.isPaused ? "Resume recording" : "Pause recording")
            }
            ToolbarItem {
                SearchField(text: $query, prompt: "Search clips", focusRequest: focusSearch)
                    .frame(width: 220)
            }
        }
        .focusedSceneValue(\.historyActions, HistoryActions(
            hasSelection: !selectedClips.isEmpty,
            canEdit: selectedClips.count == 1 && selectedClips.first.map(ClipEdit.canEditText) == true,
            canRename: selectedClips.count == 1,
            pinTitle: selectedClips.allSatisfy(\.isPinned) && !selectedClips.isEmpty ? "Unpin" : "Pin",
            boards: model.boards.all,
            copy: { copy(plain: false) },
            copyPlain: { copy(plain: true) },
            togglePin: togglePin,
            pin: { board in model.pin(Set(selectedClips.map(\.id)), to: board) },
            edit: { if let clip = selectedClips.first { startEditing(clip) } },
            rename: { if let clip = selectedClips.first { beginRename(.clip(clip.id), name: clip.label ?? "") } },
            delete: { requestDelete(selectedClips) },
            find: { focusSearch &+= 1 }
        ))
        .alert(renameTitle, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(renamePrompt, text: $renameDraft)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(pendingBoardDelete.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(
            get: { pendingBoardDelete != nil }, set: { if !$0 { pendingBoardDelete = nil } }
        )) {
            Button("Delete Board", role: .destructive) {
                if let board = pendingBoardDelete { deleteBoard(board) }
                pendingBoardDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingBoardDelete = nil }
        } message: {
            let count = pendingBoardDelete.map { model.clipCount(onBoard: $0.id) } ?? 0
            Text("Its \(count == 1 ? "clip stays" : "\(count) clips stay") in your history, no longer pinned, and will be removed with the rest after the time set in Settings.")
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(
            get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }
        )) {
            Button("Delete", role: .destructive) {
                delete(pendingDeletion)
                pendingDeletion = []
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("You can undo this with ⌘Z.")
        }
        .onAppear {
            now = Date()
            recompute()
        }
        .onChange(of: model.revision) {
            now = Date()
            recompute()
        }
        .onChange(of: query) {
            let started = Diagnostics.now()
            recompute()
            Diagnostics.recordWhenIdle("history search settled results=\(results.count)", since: started)
        }
        .onChange(of: sidebar) { recompute() }
        .onChange(of: selection) { if let editor, !selection.contains(editor.clipID) { finishEditing(save: true) } }
        .background(WindowSharing(type: model.windowSharingType))
    }

    /// Runs the search once per change (not once per view update), and drops selected clips
    /// that are no longer listed.
    private func recompute() {
        if case .filter(.board(let id)) = sidebar, model.boards.board(id: id) == nil { sidebar = .filter(.all) }
        switch sidebar {
        case .app(let id): results = ClipSearch.run(model.history.clips, query: query, sourceBundleID: id)
        case .filter(let filter): results = ClipSearch.run(model.history.clips, query: query, filter: filter)
        case nil: results = ClipSearch.run(model.history.clips, query: query)
        }
        resultsVersion &+= 1
        if !selection.isEmpty {
            let visible = Set(results.map(\.id))
            let kept = selection.intersection(visible)
            if kept != selection { selection = kept }
        }
    }

    // MARK: Sidebar

    private var sidebarList: some View {
        List(selection: $sidebar) {
            // No untitled Section here: it adds an empty row that VoiceOver reads.
            ForEach([ClipFilter.all] + ClipFilter.kinds) { filter in
                Label(filter.title ?? "", systemImage: filter.systemImage)
                    .badge(count(for: filter))
                    .tag(SidebarItem.filter(filter))
            }
            Section("Boards") {
                ForEach(model.boards.all) { board in
                    Label {
                        Text(board.name)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(board.color.color)
                            .imageScale(.small)
                    }
                    .badge(model.clipCount(onBoard: board.id))
                    .tag(SidebarItem.filter(.board(board.id)))
                    .contextMenu { boardMenu(board) }
                }
                .onMove { model.moveBoards(fromOffsets: $0, toOffset: $1) }
            }
            let sources = sourceApps
            if !sources.isEmpty {
                Section("Apps") {
                    ForEach(sources, id: \.id) { source in
                        Label {
                            Text(source.name)
                        } icon: {
                            if let icon = AppIcons.icon(for: source.id) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "app")
                            }
                        }
                        .badge(source.count)
                        .tag(SidebarItem.app(source.id))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    let board = model.createBoard()
                    sidebar = .filter(.board(board.id))
                    beginRename(.board(board.id), name: board.name)
                } label: {
                    Label("New Board", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Make a board for clips you keep. Drag boards to reorder them.")
                Spacer()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
    }

    @ViewBuilder private func boardMenu(_ board: Board) -> some View {
        Button("Rename…") { beginRename(.board(board.id), name: board.name) }
        Menu("Color") {
            ForEach(BoardColor.allCases) { color in
                Toggle(isOn: Binding(get: { board.color == color }, set: { if $0 { model.setColor(color, ofBoard: board.id) } })) {
                    Label { Text(color.title) } icon: { Image(nsImage: BoardSwatch.image(color)) }
                }
            }
        }
        Divider()
        Button(model.clipCount(onBoard: board.id) > 0 ? "Delete Board…" : "Delete Board") {
            if model.clipCount(onBoard: board.id) > 0 { pendingBoardDelete = board } else { deleteBoard(board) }
        }
    }

    private func deleteBoard(_ board: Board) {
        if sidebar == .filter(.board(board.id)) { sidebar = .filter(.all) }
        model.deleteBoard(board.id)
    }

    private func count(for filter: ClipFilter) -> Int {
        filter == .all ? model.history.clips.count : model.history.clips.reduce(0) { $0 + (filter.includes($1) ? 1 : 0) }
    }

    private var sourceApps: [(id: String, name: String, count: Int)] {
        var counts: [String: (String, Int)] = [:]
        for clip in model.history.clips {
            guard let id = clip.sourceBundleID else { continue }
            counts[id, default: (clip.sourceName ?? id, 0)].1 += 1
        }
        return counts.map { (id: $0.key, name: $0.value.0, count: $0.value.1) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(12).map { $0 }
    }

    // MARK: List

    private var clipList: some View {
        HistoryTable(
            clips: results, version: resultsVersion, query: query, now: now, selection: $selection,
            actions: HistoryTable.Actions(
                copy: { ids in selection = ids; copy(plain: false) },
                copyPlain: { ids in selection = ids; copy(plain: true) },
                togglePin: { ids in selection = ids; togglePin() },
                pin: { ids, board in model.pin(ids, to: board) },
                edit: { id in
                    selection = [id]
                    if let clip = results.first(where: { $0.id == id }) { startEditing(clip) }
                },
                rename: { id in
                    selection = [id]
                    beginRename(.clip(id), name: model.history.clip(id: id)?.label ?? "")
                },
                delete: { ids in requestDelete(results.filter { ids.contains($0.id) }) }
            ),
            boards: model.boards.all
        )
        .overlay {
            if !model.isLoaded {
                ProgressView()
            } else if results.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if model.history.clips.isEmpty {
                    ContentUnavailableView("No Clips Yet", systemImage: "doc.on.clipboard",
                                           description: Text("Copy text, links, images or files in any app and they show up here."))
                } else {
                    ContentUnavailableView("Nothing Here", systemImage: "tray",
                                           description: Text("No clips of this kind yet."))
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        let clips = selectedClips
        if clips.count == 1, let clip = clips.first, let editor, editor.clipID == clip.id {
            ClipEditorView(session: editor, clip: clip, onDone: finishEditing)
                .padding(.bottom, Spacing.s)
        } else if clips.count == 1, let clip = clips.first {
            VStack(spacing: 0) {
                if let label = clip.label {
                    Text(label)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top], Spacing.l)
                }
                ClipContentView(clip: clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ClipSourceLine(clip: clip, now: now)
                    HStack(spacing: Spacing.s) {
                        if ClipEdit.canEditText(clip) {
                            Button("Edit") { startEditing(clip) }
                                .help("Edit the text and title (⌘E)")
                        } else {
                            Button(clip.label == nil ? "Add Title" : "Rename") { beginRename(.clip(clip.id), name: clip.label ?? "") }
                                .help("Give the clip a title (⌘R)")
                        }
                        if let text = clip.imageText {
                            Button("Copy Text") { model.copyText(text) }
                                .help("Copy the text found in this image")
                        }
                        Spacer(minLength: 0)
                        pinMenu(clips)
                        Button("Delete") { requestDelete(clips) }
                        Button("Copy") { copy(plain: false) }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                }
                // Same leading edge as the clip's content above (Spacing.l).
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
            }
        } else if clips.count > 1 {
            ContentUnavailableView {
                Label("\(clips.count) Clips Selected", systemImage: "square.stack")
            } description: {
                Text("Copy puts them on the clipboard together, oldest first.")
            } actions: {
                HStack(spacing: Spacing.s) {
                    Button("Copy \(ClipJoin.describe(clips))") { copy(plain: false) }
                    pinMenu(clips)
                    Button("Delete \(clips.count) Clips") { requestDelete(clips) }
                }
            }
        } else {
            ContentUnavailableView("No Clip Selected", systemImage: "doc.on.clipboard",
                                   description: Text("Select a clip to see all of it."))
        }
    }

    /// "Pin ▾": Unpin, each board, New Board.
    private func pinMenu(_ clips: [Clip]) -> some View {
        Menu(clips.allSatisfy(\.isPinned) ? "Pinned" : "Pin") {
            if clips.contains(where: \.isPinned) {
                Button("Unpin") { model.pin(Set(clips.map(\.id)), to: nil) }
                Divider()
            }
            ForEach(model.boards.all) { board in
                Toggle(isOn: Binding(get: { clips.allSatisfy { $0.boardID == board.id } },
                                     set: { model.pin(Set(clips.map(\.id)), to: $0 ? board.id : nil) })) {
                    Label { Text(board.name) } icon: { Image(nsImage: BoardSwatch.image(board.color)) }
                }
            }
            Divider()
            Button("New Board…") {
                let board = model.createBoard(with: Set(clips.map(\.id)))
                beginRename(.board(board.id), name: board.name)
            }
        }
        .fixedSize()
        .help("Pin to a board. Pinned clips are never removed automatically.")
    }

    // MARK: Editing and renaming

    private func startEditing(_ clip: Clip) {
        finishEditing(save: true)
        let session = ClipEditSession(clip: clip, startsInTitle: false)
        editor = session
        Task { await session.load(model: model, clip: clip) }
    }

    private func finishEditing(save: Bool) {
        guard let session = editor else { return }
        if save, !session.save(model: model) { return }
        editor = nil
    }

    private func beginRename(_ target: Renaming, name: String) {
        renameDraft = name
        renaming = target
    }

    private func commitRename() {
        switch renaming {
        case .board(let id): model.renameBoard(id, to: renameDraft)
        case .clip(let id): model.setLabel(renameDraft, for: id)
        case nil: break
        }
        renaming = nil
    }

    private var renameTitle: String {
        if case .board = renaming { return "Rename Board" }
        return "Clip Title"
    }

    private var renamePrompt: String {
        if case .board = renaming { return "Board name" }
        return "Title"
    }

    // MARK: Actions

    private func copy(plain: Bool) {
        let clips = selectedClips
        if clips.count == 1, let clip = clips.first {
            model.use(clip, .copy, plainText: plain ? true : nil)
        } else if clips.count > 1 {
            // Several clips: joined the way the strip pastes them (oldest first, one per line).
            model.use(clips, .copy)
        }
    }

    private func togglePin() {
        let clips = selectedClips
        let pin = !clips.allSatisfy(\.isPinned)
        for clip in clips where clip.isPinned != pin { model.togglePin(clip) }
    }

    /// Deletes right away, or asks first when it's several clips or a pinned one.
    private func requestDelete(_ clips: [Clip]) {
        guard !clips.isEmpty else { return }
        if clips.count > 1 || clips.contains(where: \.isPinned) {
            pendingDeletion = clips
        } else {
            delete(clips)
        }
    }

    private func delete(_ clips: [Clip]) {
        let ids = Set(clips.map(\.id))
        let index = results.firstIndex { ids.contains($0.id) }
        model.delete(ids)
        // Keep a selection so the keyboard user can carry on: the clip that took the place.
        recompute()
        if let index, !results.isEmpty {
            selection = [results[min(index, results.count - 1)].id]
        } else {
            selection = []
        }
    }

    private var confirmTitle: String {
        let count = pendingDeletion.count
        if count == 1 { return "Delete this pinned clip?" }
        let pinned = pendingDeletion.filter(\.isPinned).count
        return pinned > 0 ? "Delete \(count) clips, including \(pinned) pinned?" : "Delete \(count) clips?"
    }
}

/// Applies the "hide from screen sharing" setting to the window hosting this view.
struct WindowSharing: NSViewRepresentable {
    let type: NSWindow.SharingType

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.sharingType = type }
    }
}

/// A plain `NSSearchField` bound to a string. Unlike `.searchable`, every way of changing
/// it (typing, the clear button, Accessibility) updates the binding, and ⌘F can focus it.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    /// Bump to move keyboard focus into the field.
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        context.coordinator.focusRequest = focusRequest
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var focusRequest = 0

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func changed(_ sender: NSSearchField) {
            if text.wrappedValue != sender.stringValue { text.wrappedValue = sender.stringValue }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            changed(field)
        }
    }
}

// MARK: - Menu commands for the window

struct HistoryActions {
    var hasSelection: Bool
    var canEdit: Bool
    var canRename: Bool
    var pinTitle: String
    var boards: [Board]
    var copy: () -> Void
    var copyPlain: () -> Void
    var togglePin: () -> Void
    var pin: (UUID?) -> Void
    var edit: () -> Void
    var rename: () -> Void
    var delete: () -> Void
    var find: () -> Void
}

private struct HistoryActionsKey: FocusedValueKey {
    typealias Value = HistoryActions
}

extension FocusedValues {
    var historyActions: HistoryActions? {
        get { self[HistoryActionsKey.self] }
        set { self[HistoryActionsKey.self] = newValue }
    }
}

struct HistoryCommands: Commands {
    let model: AppModel
    let info: AppInfo
    @FocusedValue(\.historyActions) private var actions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Clip History") {
                NSApp.activate()
                openWindow(id: HistoryWindow.id)
            }
            .keyboardShortcut("y")
            Divider()
        }
        HelpCommands(info: info) {
            Button("Clips Help") {
                NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Clips"))
            }
        }
        // Undo prefers bringing back deleted clips; otherwise it's the usual text undo.
        CommandGroup(replacing: .undoRedo) {
            Button(model.canUndoDelete ? "Undo Delete" : "Undo") {
                if model.canUndoDelete {
                    model.undoDelete()
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") { actions?.find() }
                .keyboardShortcut("f")
                .disabled(actions == nil)
        }
        CommandMenu("Clip") {
            Button("Copy as Plain Text") { actions?.copyPlain() }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(actions?.hasSelection != true)
            Divider()
            Button("Edit…") { actions?.edit() }
                .keyboardShortcut("e")
                .disabled(actions?.canEdit != true)
            Button("Rename…") { actions?.rename() }
                .keyboardShortcut("r")
                .disabled(actions?.canRename != true)
            Divider()
            Button(actions?.pinTitle ?? "Pin") { actions?.togglePin() }
                .keyboardShortcut("p")
                .disabled(actions?.hasSelection != true)
            Menu("Pin to") {
                ForEach(Array((actions?.boards ?? []).enumerated()), id: \.element.id) { index, board in
                    if index < 9 {
                        Button(board.name) { actions?.pin(board.id) }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                    } else {
                        Button(board.name) { actions?.pin(board.id) }
                    }
                }
            }
            .disabled(actions?.hasSelection != true)
            Divider()
            Button("Delete") { actions?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.hasSelection != true)
        }
    }
}
