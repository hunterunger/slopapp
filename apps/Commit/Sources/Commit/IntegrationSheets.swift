import AppKit
import CommitCore
import SlopKit
import SwiftUI

// MARK: - Merge / rebase

/// "Merge into main" / "Rebase main onto…": pick a branch or tag, see how far apart they are.
struct IntegrateSheet: View {
    let model: RepoModel
    let kind: IntegrationKind
    @State private var query = ""
    @State private var selection: String?
    @State private var divergence: Divergence?
    @State private var noFastForward = false
    @FocusState private var filterFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: RepoModel, kind: IntegrationKind, preselected: String?) {
        self.model = model
        self.kind = kind
        _selection = State(initialValue: preselected)
    }

    private var current: String { model.currentBranchName }

    var body: some View {
        let local = RefList.filter(model.refs.local.filter { !$0.isHead }, query)
        let remote = RefList.filter(model.refs.remote, query)
        let tags = RefList.filter(model.refs.tags, query)
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(kind == .merge ? "Merge into \(current)" : "Rebase \(current)")
                .font(.headline)
            Text(kind == .merge ? "Choose what to merge into \(current)." : "Choose where \(current)'s commits go on top of.")
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                TextField("Filter", text: $query, prompt: Text("Filter branches and tags"))
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
                    .padding(Spacing.s)
                    .accessibilityLabel("Filter branches and tags")
                    .onSubmit {
                        if selection == nil { selection = (local + remote + tags).first?.name }
                        start()
                    }
                Hairline()
                List(selection: $selection) {
                    if !local.isEmpty {
                        Section("Branches") { rows(local) }
                    }
                    if !remote.isEmpty {
                        Section("Remote Branches") { rows(remote) }
                    }
                    if !tags.isEmpty {
                        Section("Tags") { rows(tags) }
                    }
                    if local.isEmpty && remote.isEmpty && tags.isEmpty {
                        Text(query.isEmpty ? "There's no other branch yet." : "No matches")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                }
                .listStyle(.inset)
                .accessibilityLabel("Branches and tags")
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { names in
                    if let name = names.first { selection = name; start() }
                }
            }
            .frame(height: 240)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
                if kind == .merge {
                    Toggle("Always create a merge commit", isOn: $noFastForward)
                        .toggleStyle(.checkbox)
                        .help("Even when \(current) could simply move forward (--no-ff)")
                } else {
                    Text("Your commits get new hashes. If they're already pushed, you'll need to force push afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.status.isClean {
                    Text("Your uncommitted changes are set aside and put back afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("You can undo it with Edit › Undo right after.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.s) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(kind == .merge ? "Merge" : "Rebase", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .onAppear { filterFocused = true }
        .task(id: selection) {
            divergence = nil
            guard let selection, let repository = model.repository else { return }
            divergence = await repository.divergence(from: selection)
        }
    }

    @ViewBuilder
    private func rows(_ refs: [GitRef]) -> some View {
        ForEach(refs.prefix(150)) { ref in
            RefRow(ref: ref, status: model.status.branch).tag(ref.name)
        }
    }

    private var summary: String {
        guard let selection else { return "Nothing chosen yet." }
        guard let d = divergence else { return " " }
        let theirs = d.theirs == 1 ? "1 commit" : "\(d.theirs) commits"
        let ours = d.ours == 1 ? "1 commit" : "\(d.ours) commits"
        switch kind {
        case .merge:
            if d.theirs == 0 { return "\(current) already has everything in \(selection)." }
            if d.ours == 0 && !noFastForward { return "\(selection) has \(theirs) \(current) doesn't. \(current) moves forward to it (no merge commit)." }
            return "\(selection) has \(theirs) \(current) doesn't; \(current) has \(ours) of its own. They're combined with a merge commit."
        case .rebase:
            if d.ours == 0 { return d.theirs == 0 ? "\(current) is already on \(selection)." : "\(current) has no commits of its own; it moves forward to \(selection)." }
            return "\(current)'s \(ours) \(d.ours == 1 ? "is" : "are") replayed on top of \(selection), which has \(theirs) \(current) doesn't."
        }
    }

    private func start() {
        guard let selection else { return }
        dismiss()
        switch kind {
        case .merge: model.merge(selection, noFastForward: noFastForward)
        case .rebase: model.rebase(onto: selection)
        }
    }
}

// MARK: - Interactive rebase

/// Reorder, squash, fix up, reword or drop commits. Oldest first, as git applies them.
struct InteractiveRebaseSheet: View {
    let model: RepoModel
    let pushedCount: Int
    @State private var plan: RebasePlan
    @State private var selection: ObjectID?
    @FocusState private var listFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: RepoModel, plan: RebasePlan, pushedCount: Int) {
        self.model = model
        self.pushedCount = pushedCount
        _plan = State(initialValue: plan)
        _selection = State(initialValue: plan.steps.last?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Edit History of \(model.currentBranchName)").font(.headline)
                Text("Oldest first, in the order they'll be applied\(plan.base.map { " on top of \($0.short)" } ?? ""). Drag to reorder; press P, R, S, F or D to change what happens to the selected commit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            List(selection: $selection) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    RebaseStepRow(step: step, action: actionBinding(index))
                        .tag(step.id)
                }
                .onMove { plan.move(from: $0, to: $1) }
            }
            .listStyle(.inset)
            .focused($listFocused)
            .frame(minHeight: 200)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
            .accessibilityLabel("Commits, oldest first")
            .onKeyPress(characters: CharacterSet(charactersIn: "prsfdPRSFD"), phases: .down) { press in
                guard let key = press.characters.lowercased().first,
                      let action = RebaseAction.allCases.first(where: { $0.key == key }), let index = selectedIndex else { return .ignored }
                plan.steps[index].action = action
                return .handled
            }

            messageEditor

            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let problem = plan.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textOrange)
                } else {
                    Text(plan.summary).monospacedDigit()
                }
                if pushedCount > 0 {
                    Label(pushedCount == 1 ? "1 of these commits is already pushed. Rewriting it means force pushing afterwards."
                                           : "\(pushedCount) of these commits are already pushed. Rewriting them means force pushing afterwards.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textOrange)
                }
                Text("You can undo it with Edit › Undo right after. Git also keeps the old tip in ORIG_HEAD and the reflog.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.s) {
                Button("Move Up") { move(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled((selectedIndex ?? 0) == 0)
                    .help("Move the selected commit earlier (⌥⌘↑)")
                Button("Move Down") { move(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(selectedIndex.map { $0 >= plan.steps.count - 1 } ?? true)
                    .help("Move the selected commit later (⌥⌘↓)")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rewrite History") {
                    dismiss()
                    model.runInteractiveRebase(plan)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.problem != nil || plan.isUnchanged)
            }
            .controlSize(.regular)
        }
        .padding(Spacing.xl)
        .frame(width: 640, height: 600)
        .onAppear { listFocused = true }
    }

    private var selectedIndex: Int? { plan.steps.firstIndex { $0.id == selection } }

    private func move(_ offset: Int) {
        guard let index = selectedIndex else { return }
        plan.move(index, by: offset)
    }

    private func actionBinding(_ index: Int) -> Binding<RebaseAction> {
        Binding(get: { plan.steps.indices.contains(index) ? plan.steps[index].action : .pick },
                set: { if plan.steps.indices.contains(index) { plan.steps[index].action = $0 } })
    }

    /// The group whose message the selected commit decides (a reword, or squashes into it).
    private var editedGroup: RebaseGroup? {
        guard let index = selectedIndex else { return nil }
        let group = plan.groups.first { $0.head == index || $0.members.contains(index) }
        guard let group, plan.needsMessage(group) else { return nil }
        return group
    }

    @ViewBuilder
    private var messageEditor: some View {
        if let group = editedGroup {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(group.members.isEmpty ? "Message" : "Message of the Combined Commit")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if plan.steps[group.head].editedMessage != nil {
                        Button("Reset") { plan.steps[group.head].editedMessage = nil }
                            .controlSize(.small)
                            .help("Go back to the original message")
                    }
                }
                TextEditor(text: Binding(get: { plan.message(of: group) },
                                         set: { plan.steps[group.head].editedMessage = $0 }))
                    .font(Font(NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)))
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                    .frame(height: 96)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
                    .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
                    .accessibilityLabel("Commit message")
            }
        }
    }
}

struct RebaseStepRow: View {
    let step: RebaseStep
    @Binding var action: RebaseAction

    var body: some View {
        HStack(spacing: Spacing.s) {
            Picker("Action", selection: $action) {
                ForEach(RebaseAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 96)
            .help(action.explanation)
            .accessibilityLabel("Action for \(step.subject)")
            if action.combinesWithPrevious {
                Image(systemName: "arrow.turn.left.up")
                    .foregroundStyle(.secondary)
                    .help("Combined into the commit above")
                    .accessibilityLabel("Combined into the commit above")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(step.subject.isEmpty ? "(no message)" : step.subject)
                    .strikethrough(action == .drop)
                    .foregroundStyle(action == .drop ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(step.id.short) · \(step.authorName) · \(RelativeDate.string(for: step.date, now: Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.leading, action.combinesWithPrevious ? Spacing.l : 0)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Tags

struct NewTagSheet: View {
    let model: RepoModel
    let commit: ObjectID
    let label: String
    @State private var name = ""
    @State private var message = ""
    @State private var push = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetLayout(title: "New Tag") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                TextField("Name", text: $name, prompt: Text("v1.0"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Tag name")
                    .onSubmit(create)
                Text(problem ?? "Tags \(label).")
                    .font(.caption)
                    .foregroundStyle(problem == nil ? Color.secondary : Color.textOrange)
                    .lineLimit(2)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $message)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Tag message")
                    if message.isEmpty {
                        Text("Message (optional)")
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .padding(.leading, BodyEditor.textInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(Spacing.xs)
                .frame(height: 72)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
                .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
                Text(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "Without a message it's a lightweight tag: just a name for the commit."
                     : "With a message it's an annotated tag, with your name and the date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let remote = model.defaultRemote {
                    Toggle("Push to \(remote)", isOn: $push)
                        .toggleStyle(.checkbox)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create Tag", action: create)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private var problem: String? {
        guard !trimmed.isEmpty else { return nil }
        if let p = RefNameRules.problem(with: trimmed, noun: "Tag") { return p }
        if model.refs.tags.contains(where: { $0.name == trimmed }) { return "A tag called \(trimmed) already exists." }
        return nil
    }

    private var canCreate: Bool { !trimmed.isEmpty && problem == nil }

    private func create() {
        guard canCreate else { return }
        model.createTag(trimmed, at: commit, message: message, push: push)
        dismiss()
    }
}

// MARK: - Remotes

/// Add, rename, change the address of, or remove remotes.
struct RemotesSheet: View {
    let model: RepoModel
    @State private var remotes: [Remote] = []
    @State private var selection: String?
    @State private var editing: Editing?
    @State private var name = ""
    @State private var url = ""
    @State private var confirmingRemoval: String?
    @State private var busy = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    enum Editing: Equatable {
        case add
        case edit(Remote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title).font(.headline)
            if editing == nil { list } else { form }
        }
        .padding(Spacing.xl)
        .frame(width: 500)
        .task { await reload() }
        .alert("Remove the remote “\(confirmingRemoval ?? "")”?", isPresented: Binding(get: { confirmingRemoval != nil },
                                                                                   set: { if !$0 { confirmingRemoval = nil } })) {
            Button("Remove Remote", role: .destructive) {
                guard let name = confirmingRemoval else { return }
                Task {
                    if await model.removeRemote(name) { selection = nil }
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Its remote branches disappear from the sidebar and branches tracking it stop tracking. Nothing on the server changes. Undo puts it all back.")
        }
    }

    private var title: String {
        switch editing {
        case nil: "Remotes"
        case .add: "Add Remote"
        case .edit(let remote): "Edit “\(remote.name)”"
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Group {
                if remotes.isEmpty {
                    ContentUnavailableView {
                        Label("No Remotes", systemImage: "network")
                    } description: {
                        Text("Add a remote to fetch from and push to.")
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(remotes) { remote in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.name).fontWeight(.medium)
                                Text(remote.fetchURL)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                if let push = remote.pushURL {
                                    Text("Pushes to \(push)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(remote.name)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .listStyle(.inset)
                    .contextMenu(forSelectionType: String.self) { names in
                        if let name = names.first, let remote = remotes.first(where: { $0.name == name }) {
                            Button("Edit…") { beginEdit(remote) }
                            Button("Remove…") { confirmingRemoval = name }
                        }
                    } primaryAction: { names in
                        if let name = names.first, let remote = remotes.first(where: { $0.name == name }) { beginEdit(remote) }
                    }
                    .accessibilityLabel("Remotes")
                }
            }
            .frame(height: 200)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
            HStack(spacing: Spacing.s) {
                Button("Add…") { beginAdd() }
                Button("Edit…") { if let remote = selectedRemote { beginEdit(remote) } }
                    .disabled(selectedRemote == nil)
                Button("Remove…") { confirmingRemoval = selection }
                    .disabled(selectedRemote == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Form {
                TextField("Name", text: $name, prompt: Text("origin"))
                    .focused($nameFocused)
                TextField("URL", text: $url, prompt: Text("https://example.com/owner/project.git"))
            }
            .formStyle(.columns)
            Text(problem ?? "Fetch and push use this address with your own Git credentials and SSH keys.")
                .font(.caption)
                .foregroundStyle(problem == nil ? Color.secondary : Color.textOrange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s) {
                Spacer()
                Button("Cancel", role: .cancel) { editing = nil }
                    .keyboardShortcut(.cancelAction)
                Button(editing == .add ? "Add Remote" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || trimmedName.isEmpty || trimmedURL.isEmpty || busy)
            }
        }
        .onAppear { nameFocused = true }
    }

    private var selectedRemote: Remote? { remotes.first { $0.name == selection } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var problem: String? {
        if !trimmedName.isEmpty {
            if let p = RefNameRules.problem(with: trimmedName, noun: "Remote", allowSlash: false) { return p }
            let original: String? = if case .edit(let remote) = editing { remote.name } else { nil }
            if trimmedName != original, remotes.contains(where: { $0.name == trimmedName }) { return "A remote called \(trimmedName) already exists." }
        }
        if !trimmedURL.isEmpty, let p = CloneAddress.problem(with: trimmedURL) { return p }
        return nil
    }

    private func beginAdd() {
        name = remotes.isEmpty ? "origin" : ""
        url = ""
        editing = .add
    }

    private func beginEdit(_ remote: Remote) {
        name = remote.name
        url = remote.fetchURL
        editing = .edit(remote)
    }

    private func save() {
        let newName = trimmedName, newURL = trimmedURL
        let mode = editing
        busy = true
        Task {
            var ok = true
            switch mode {
            case .add:
                ok = await model.changeRemotes(.addRemote) { try await $0.addRemote(name: newName, url: newURL) }
                if ok {
                    model.registerUndo("Add Remote") { [weak model] in
                        guard let model else { return }
                        Task { _ = await model.changeRemotes(.removeRemote) { _ = try await $0.removeRemote(newName) } }
                    }
                }
            case .edit(let remote):
                if newName != remote.name {
                    ok = await model.changeRemotes(.renameRemote) { try await $0.renameRemote(remote.name, to: newName) }
                }
                if ok, newURL != remote.fetchURL {
                    ok = await model.changeRemotes(.editRemote) { try await $0.setRemoteURL(newName, url: newURL) }
                }
            case nil:
                break
            }
            busy = false
            if ok {
                editing = nil
                selection = newName
            }
            await reload()
        }
    }

    private func reload() async {
        remotes = await model.loadRemotes()
    }
}
