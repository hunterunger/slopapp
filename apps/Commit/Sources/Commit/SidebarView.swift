import CommitCore
import SlopKit
import SwiftUI

/// Sources on the left: Changes, History, Stashes, then branches, remotes and tags.
struct SidebarView: View {
    @Bindable var model: RepoModel
    @State private var branchesExpanded = true
    @State private var remotesExpanded = false
    @State private var tagsExpanded = false
    @FocusState private var filterFocused: Bool

    /// Big repositories have thousands of branches; showing them all makes the sidebar slow
    /// and useless. The filter finds the rest.
    static let displayLimit = 200

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                Label("Changes", systemImage: "square.and.pencil")
                    .badge(model.status.changedCount)
                    .tag(SidebarItem.changes)
                Label("History", systemImage: "clock")
                    .tag(SidebarItem.history)
                Label("Stashes", systemImage: "tray.full")
                    .badge(model.stashes.count)
                    .tag(SidebarItem.stashes)
            }

            Section("Branches", isExpanded: $branchesExpanded) {
                refRows(model.filteredLocalBranches)
            }
            if !model.refs.remote.isEmpty {
                Section("Remotes", isExpanded: $remotesExpanded) {
                    refRows(model.filteredRemoteBranches)
                }
            }
            if !model.refs.tags.isEmpty {
                Section("Tags", isExpanded: $tagsExpanded) {
                    refRows(model.filteredTags)
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarItem.self) { items in
            if let item = items.first, case .ref(let name) = item, let ref = ref(named: name) {
                RefMenu(ref: ref, model: model)
            }
        } primaryAction: { items in
            guard let item = items.first, case .ref(let name) = item, let ref = ref(named: name) else { return }
            model.switchTo(ref)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Hairline()
                TextField("Filter branches", text: $model.branchFilter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .padding(Spacing.s)
                    .accessibilityLabel("Filter branches")
                    .focused($filterFocused)
                    .onChange(of: filterFocused) { _, value in model.branchFilterFocused = value }
                    .onChange(of: model.branchFilter) { _, value in
                        if !value.isEmpty { branchesExpanded = true; remotesExpanded = true; tagsExpanded = true }
                    }
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private func refRows(_ refs: [GitRef]) -> some View {
        ForEach(refs.prefix(Self.displayLimit)) { ref in
            RefRow(ref: ref, status: model.status.branch)
                .tag(SidebarItem.ref(ref.fullName))
        }
        if refs.count > Self.displayLimit {
            Text("\(refs.count - Self.displayLimit) more. Type in the filter to find one.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .selectionDisabled()
        } else if refs.isEmpty && !model.branchFilter.isEmpty {
            Text("No matches")
                .font(.caption)
                .foregroundStyle(.secondary)
                .selectionDisabled()
        }
    }

    private func ref(named fullName: String) -> GitRef? {
        model.refs.local.first { $0.fullName == fullName }
            ?? model.refs.remote.first { $0.fullName == fullName }
            ?? model.refs.tags.first { $0.fullName == fullName }
    }
}

struct RefRow: View {
    let ref: GitRef
    let status: BranchStatus

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Label {
                Text(ref.name)
                    .fontWeight(ref.isHead ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: icon)
            }
            Spacer(minLength: Spacing.xs)
            if ref.isHead {
                if status.ahead > 0 { Text("↑\(status.ahead)").monospacedDigit().foregroundStyle(.secondary) }
                if status.behind > 0 { Text("↓\(status.behind)").monospacedDigit().foregroundStyle(.secondary) }
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .help(ref.upstreamName.map { "\(ref.name) tracks \($0)" } ?? ref.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var icon: String {
        switch ref.kind {
        case .local: "arrow.triangle.branch"
        case .remote: "network"
        case .tag: "tag"
        }
    }

    private var accessibilityText: String {
        var parts = [ref.name]
        if ref.isHead {
            parts.append("current branch")
            if status.ahead > 0 { parts.append("\(status.ahead) to push") }
            if status.behind > 0 { parts.append("\(status.behind) to pull") }
        }
        return parts.joined(separator: ", ")
    }
}

/// Right-click on a branch, remote branch or tag.
struct RefMenu: View {
    let ref: GitRef
    let model: RepoModel

    var body: some View {
        switch ref.kind {
        case .local:
            Button("Switch to \(ref.name)") { model.switchTo(ref) }
                .disabled(ref.isHead)
            Button("New Branch from \(ref.name)…") { model.showNewBranch(from: ref.target) }
            Divider()
            Button("Delete \(ref.name)…") { model.confirmDelete(ref) }
                .disabled(ref.isHead)
        case .remote:
            Button("Check Out \(ref.nameOnRemote ?? ref.name)") { model.switchTo(ref) }
            Button("New Branch from \(ref.name)…") { model.showNewBranch(from: ref.target) }
        case .tag:
            Button("New Branch from \(ref.name)…") { model.showNewBranch(from: ref.target) }
        }
        Divider()
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ref.name, forType: .string)
        }
    }
}
