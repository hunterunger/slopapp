import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// A commit: message, author, hash; its files; the selected file's diff.
struct CommitDetailView: View {
    @Bindable var model: RepoModel

    var body: some View {
        if model.historySelection == nil && model.showsUncommittedRow {
            ContentUnavailableView {
                Label("Uncommitted Changes", systemImage: "square.and.pencil")
            } description: {
                Text("\(model.status.changedCount) changed \(model.status.changedCount == 1 ? "file" : "files") not committed yet.")
            } actions: {
                Button("Show Changes") { model.sidebarSelection = .changes }
            }
        } else if let detail = model.commitDetail {
            VSplitView {
                VStack(spacing: 0) {
                    CommitHeader(detail: detail, model: model)
                    Hairline()
                    ChangedFileList(files: model.commitFiles, selection: $model.commitFileSelection)
                }
                .frame(minHeight: 150, idealHeight: 240)
                DiffContainer(model: model, state: model.diff, editable: false)
                    .frame(minHeight: 200)
            }
        } else if model.historySelection != nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Commit Selected", systemImage: "clock", description: Text("Select a commit to see what it changed."))
        }
    }
}

struct CommitHeader: View {
    let detail: CommitDetail
    let model: RepoModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(detail.subject)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.body.isEmpty {
                ScrollView {
                    Text(detail.body)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            Grid(alignment: .leading, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.xs) {
                GridRow {
                    Text("Author").foregroundStyle(.secondary)
                    Text("\(detail.authorName) <\(detail.authorEmail)>").textSelection(.enabled).lineLimit(1)
                }
                GridRow {
                    Text("Date").foregroundStyle(.secondary)
                    Text(detail.authorDate.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    Text("Commit").foregroundStyle(.secondary)
                    HStack(spacing: Spacing.xs) {
                        Text(detail.id.hex)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            model.copyHash(detail.id)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy hash")
                        .accessibilityLabel("Copy hash")
                    }
                }
                if !detail.parents.isEmpty {
                    GridRow {
                        Text(detail.parents.count > 1 ? "Parents" : "Parent").foregroundStyle(.secondary)
                        HStack(spacing: Spacing.s) {
                            ForEach(detail.parents, id: \.self) { parent in
                                Button(parent.short) { model.historySelection = parent }
                                    .buttonStyle(.link)
                                    .font(.callout.monospaced())
                                    .help("Show \(parent.short)")
                            }
                        }
                    }
                }
                let labels = RefLabel.parse(detail.decorations).filter { $0.kind != .head }
                if !labels.isEmpty {
                    GridRow {
                        Text("Refs").foregroundStyle(.secondary)
                        Text(labels.map(\.name).joined(separator: ", ")).lineLimit(2)
                    }
                }
            }
            .font(.callout)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Files in a commit or stash.
struct ChangedFileList: View {
    let files: [ChangedFile]
    @Binding var selection: ChangedFile.ID?

    var body: some View {
        if files.isEmpty {
            Text("No file changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(files) { file in
                    HStack(spacing: Spacing.s) {
                        StatusSymbol(change: file.change == .untracked ? .added : file.change)
                        let parts = StatusEntry.split(file.path)
                        Text(parts.name).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                        if !parts.folder.isEmpty {
                            Text(parts.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        if file.fromUntrackedStash {
                            Text("untracked").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .help(file.originalPath.map { "\($0) → \(file.path)" } ?? file.path)
                    .tag(file.id)
                }
            }
            .listStyle(.inset)
            .accessibilityLabel("Changed files")
        }
    }
}

/// The Stashes column.
struct StashListColumn: View {
    @Bindable var model: RepoModel

    var body: some View {
        let stashes = model.stashes.filter { model.searchText.isEmpty || $0.summary.localizedCaseInsensitiveContains(model.searchText) }
        if model.stashes.isEmpty {
            ContentUnavailableView {
                Label("No Stashes", systemImage: "tray")
            } description: {
                Text("Stash changes to set them aside and come back to them later.")
            } actions: {
                Button("Stash Changes…") { model.showStashSheet() }
                    .disabled(model.status.isClean)
            }
        } else {
            List(selection: $model.stashSelection) {
                ForEach(stashes) { stash in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stash.message.isEmpty ? "Stash" : stash.message).lineLimit(1)
                        Text([stash.branch.map { "On \($0)" }, RelativeDate.string(for: stash.date, now: Date())]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(stash.id)
                    .contextMenu {
                        Button("Apply") { model.applyStash(stash, pop: false) }
                        Button("Apply and Remove") { model.applyStash(stash, pop: true) }
                        Divider()
                        Button("Drop…") { model.dropStash(stash) }
                    }
                }
            }
            .accessibilityLabel("Stashes")
        }
    }
}

/// A stash: what it is, Apply / Pop / Drop, its files and diff.
struct StashDetailView: View {
    @Bindable var model: RepoModel

    var body: some View {
        if let id = model.stashSelection, let stash = model.stashes.first(where: { $0.id == id }) {
            VSplitView {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(stash.message.isEmpty ? "Stash" : stash.message)
                                .font(.title3.weight(.semibold))
                                .textSelection(.enabled)
                            Text([stash.branch.map { "Made on \($0)" }, stash.date.formatted(date: .abbreviated, time: .shortened)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: Spacing.s) {
                            Button("Drop…") { model.dropStash(stash) }
                            Button("Apply") { model.applyStash(stash, pop: false) }
                                .help("Apply the changes and keep the stash")
                            Button("Apply and Remove") { model.applyStash(stash, pop: true) }
                                .buttonStyle(.borderedProminent)
                                .help("Apply the changes and remove the stash (pop)")
                        }
                    }
                    .padding(Spacing.m)
                    Hairline()
                    ChangedFileList(files: model.stashFiles, selection: $model.stashFileSelection)
                }
                .frame(minHeight: 150, idealHeight: 220)
                DiffContainer(model: model, state: model.diff, editable: false)
                    .frame(minHeight: 200)
            }
        } else {
            ContentUnavailableView("No Stash Selected", systemImage: "tray", description: Text("Select a stash to see what's in it."))
        }
    }
}
