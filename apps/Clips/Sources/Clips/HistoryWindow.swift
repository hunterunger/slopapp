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
            pinTitle: selectedClips.allSatisfy(\.isPinned) && !selectedClips.isEmpty ? "Unpin" : "Pin",
            copy: { copy(plain: false) },
            copyPlain: { copy(plain: true) },
            togglePin: togglePin,
            delete: { requestDelete(selectedClips) },
            find: { focusSearch &+= 1 }
        ))
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
        .background(WindowSharing(type: model.windowSharingType))
    }

    /// Runs the search once per change (not once per view update), and drops selected clips
    /// that are no longer listed.
    private func recompute() {
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
            ForEach(ClipFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.systemImage)
                    .badge(count(for: filter))
                    .tag(SidebarItem.filter(filter))
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
                delete: { ids in requestDelete(results.filter { ids.contains($0.id) }) }
            )
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
        if clips.count == 1, let clip = clips.first {
            VStack(spacing: 0) {
                ClipContentView(clip: clip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ClipSourceLine(clip: clip, now: now)
                    HStack(spacing: Spacing.s) {
                        Spacer(minLength: 0)
                        Button(clip.isPinned ? "Unpin" : "Pin", action: togglePin)
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
            } actions: {
                Button("Delete \(clips.count) Clips") { requestDelete(clips) }
            }
        } else {
            ContentUnavailableView("No Clip Selected", systemImage: "doc.on.clipboard",
                                   description: Text("Select a clip to see all of it."))
        }
    }

    // MARK: Actions

    private func copy(plain: Bool) {
        let clips = selectedClips
        if clips.count == 1, let clip = clips.first {
            model.use(clip, .copy, plainText: plain ? true : nil)
        } else if clips.count > 1 {
            // Several clips: their text, newest first, one per line.
            let text = clips.filter { $0.kind != .image }.map(\.text).joined(separator: "\n")
            model.copyText(text)
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
    var pinTitle: String
    var copy: () -> Void
    var copyPlain: () -> Void
    var togglePin: () -> Void
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
        CommandGroup(replacing: .help) {
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
            Button(actions?.pinTitle ?? "Pin") { actions?.togglePin() }
                .keyboardShortcut("p")
                .disabled(actions?.hasSelection != true)
            Divider()
            Button("Delete") { actions?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.hasSelection != true)
        }
    }
}
