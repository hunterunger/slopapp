import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// The detail column for a conflicted file: each conflict with its two sides and a choice,
/// or the whole result as editable text; then Mark Resolved. Replaces the diff for conflicts.
struct ConflictResolverView: View {
    @Bindable var model: RepoModel
    let entry: StatusEntry

    var body: some View {
        VStack(spacing: 0) {
            ConflictHeader(model: model, entry: entry)
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if model.conflictShowsDiff {
            DiffContainer(model: model, state: model.diff, editable: false)
        } else if let session = model.conflict, session.path == entry.path {
            if session.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.isEditing {
                ConflictTextEditor(model: model)
            } else if let file = session.file {
                ConflictList(model: model, file: file, session: session)
            } else {
                WholeFileChoice(model: model, entry: entry, kind: session.kind)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ConflictHeader: View {
    @Bindable var model: RepoModel
    let entry: StatusEntry

    var body: some View {
        let session = model.conflict
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                let parts = entry.nameAndFolder
                Text(parts.name).font(.headline).lineLimit(1).truncationMode(.middle)
                if !parts.folder.isEmpty {
                    Text(parts.folder).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: Spacing.s)
                Group {
                    if session?.isFullyResolved == true {
                        Button("Mark Resolved") { model.markConflictResolved() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Mark Resolved") { model.markConflictResolved() }
                    }
                }
                .controlSize(.small)
                .disabled(session?.file == nil || model.conflictShowsDiff)
                .help("Save the result and stage it")
            }
            HStack(spacing: Spacing.s) {
                Text(session?.progressText ?? (entry.conflictKind ?? .bothModified).explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .monospacedDigit()
                Spacer(minLength: Spacing.s)
                if session?.file != nil && !model.conflictShowsDiff {
                    if session?.isEditing == true {
                        Button("Back to Choices") { model.stopEditingConflict() }
                            .help("Leave text editing. What you typed is discarded.")
                    } else {
                        Button("Edit Result") { model.startEditingConflict() }
                            .disabled(!model.canEditConflictAsText)
                            .help(model.canEditConflictAsText ? "Edit the merged file as text" : "This file isn't UTF-8 text, so it can't be edited here.")
                    }
                }
                if model.mergeTool.name != nil {
                    Button("Open in \(model.mergeTool.name ?? "Merge Tool")") { model.openInMergeTool(entry) }
                        .disabled(!model.canUseMergeTool)
                        .help(model.mergeToolHelp)
                }
                Menu {
                    if let file = session?.file, !model.conflictShowsDiff {
                        Button("Use Ours for Every Conflict") { model.chooseAll(.ours) }
                        Button("Use Theirs for Every Conflict") { model.chooseAll(.theirs) }
                        if file.conflicts.count > 0 { Divider() }
                    }
                    Button("Use Our Whole File") { model.takeWholeFile(ours: true, entries: [entry]) }
                    Button("Use Their Whole File") { model.takeWholeFile(ours: false, entries: [entry]) }
                    Divider()
                    Button(model.conflictShowsDiff ? "Show Conflicts" : "Show Diff") { model.conflictShowsDiff.toggle() }
                    Button("Open in Default App") { model.openInEditor(entry) }
                    if model.mergeTool.name == nil {
                        Divider()
                        Text("Set merge.tool in your Git config to open a merge tool here.")
                    }
                } label: {
                    Text("More")
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("More ways to resolve")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }
}

/// The file's text and its conflicts, top to bottom.
struct ConflictList: View {
    let model: RepoModel
    let file: ConflictFile
    let session: ConflictSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(Array(file.segments.enumerated()), id: \.offset) { offset, segment in
                        switch segment {
                        case .common(let lines):
                            CommonText(lines: lines, isFirst: offset == 0, isLast: offset == file.segments.count - 1)
                        case .conflict(let index):
                            ConflictCard(model: model, conflict: file.conflicts[index], index: index, total: file.conflicts.count,
                                         choice: session.choices[index], hasBase: file.conflicts[index].base != nil)
                                .id(index)
                        }
                    }
                }
                .padding(Spacing.m)
            }
            .onAppear {
                if let first = file.conflicts.indices.first(where: { session.choices[$0] == nil }), first > 0 {
                    proxy.scrollTo(first, anchor: .top)
                }
            }
        }
    }
}

/// Text both sides agree on. Long runs fold to their edges around the conflicts.
struct CommonText: View {
    let lines: [Data]
    let isFirst: Bool
    let isLast: Bool
    @State private var expanded = false

    static let context = 3

    var body: some View {
        let fold = lines.count > Self.context * 2 + 2 && !expanded
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if fold {
                if !isFirst { code(Array(lines.prefix(Self.context))) }
                Button {
                    expanded = true
                } label: {
                    Text("\(hiddenCount.formatted()) unchanged lines")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .help("Show them")
                if !isLast { code(Array(lines.suffix(Self.context))) }
            } else {
                code(lines)
            }
        }
        .padding(.horizontal, Spacing.s)
    }

    private var hiddenCount: Int {
        lines.count - (isFirst ? 0 : Self.context) - (isLast ? 0 : Self.context)
    }

    private func code(_ lines: [Data]) -> some View {
        Text(ConflictText.join(lines))
            .font(ConflictText.font)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ConflictText {
    static var font: Font {
        Font(NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular))
    }

    /// Lines as display text, without their final line ending.
    static func join(_ lines: [Data]) -> String {
        var text = lines.map { String(decoding: $0, as: UTF8.self) }.joined()
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
        return text
    }

    static let oursColor = NSColor.systemBlue
    static let theirsColor = NSColor.systemPurple
}

/// One conflict: both sides and the choice, or the chosen result with Change.
struct ConflictCard: View {
    let model: RepoModel
    let conflict: ConflictFile.Conflict
    let index: Int
    let total: Int
    let choice: ConflictChoice?
    let hasBase: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: choice == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(choice == nil ? Color.orange : Color.green)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(choice.map { "Conflict \(index + 1) of \(total): \($0.title)" } ?? "Conflict \(index + 1) of \(total)")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text("line \(conflict.startLine + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: Spacing.s)
                if choice != nil {
                    Button("Change") { model.choose(nil, for: index) }
                        .help("Show both sides again")
                } else {
                    Button("Ours") { model.choose(.ours, for: index) }
                        .help("Use \(label(conflict.oursLabel, fallback: "our")) side")
                        .accessibilityLabel("Use ours for conflict \(index + 1)")
                    Button("Theirs") { model.choose(.theirs, for: index) }
                        .help("Use \(label(conflict.theirsLabel, fallback: "their")) side")
                        .accessibilityLabel("Use theirs for conflict \(index + 1)")
                    Button("Both") { model.choose(.both, for: index) }
                        .help("Ours, then theirs")
                        .accessibilityLabel("Use both for conflict \(index + 1)")
                    Menu {
                        Button("Both, Theirs First") { model.choose(.bothTheirsFirst, for: index) }
                        if hasBase { Button("Base (Before Either Change)") { model.choose(.base, for: index) } }
                        Button("Neither") { model.choose(.neither, for: index) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Other choices for conflict \(index + 1)")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            Hairline()
            if let choice {
                SideText(title: nil, lines: conflict.lines(for: choice), tint: nil)
            } else {
                SideText(title: "Ours · \(conflict.oursLabel.isEmpty ? "current" : conflict.oursLabel)", lines: conflict.ours,
                         tint: ConflictText.oursColor)
                if let base = conflict.base {
                    Hairline()
                    SideText(title: "Base · \(conflict.baseLabel ?? "")", lines: base, tint: nil)
                }
                Hairline()
                SideText(title: "Theirs · \(conflict.theirsLabel.isEmpty ? "incoming" : conflict.theirsLabel)", lines: conflict.theirs,
                         tint: ConflictText.theirsColor)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.m))
        .hairlineBorder(RoundedRectangle(cornerRadius: Radius.m))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conflict \(index + 1) of \(total)")
    }

    private func label(_ text: String, fallback: String) -> String {
        text.isEmpty ? "\(fallback)" : "the \(text)"
    }
}

/// One side's lines, with a small title and a faint tint.
struct SideText: View {
    let title: String?
    let lines: [Data]
    let tint: NSColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint.map { Color(nsColor: .readable($0, on: .controlBackgroundColor, target: ReadableColor.textTarget)) } ?? Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if lines.isEmpty {
                Text("No lines")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                Text(ConflictText.join(lines))
                    .font(ConflictText.font)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.map { Color(nsColor: $0).opacity(0.07) } ?? Color.clear)
        .accessibilityElement(children: .combine)
    }
}

/// The merged file as text, for fixes no button covers.
struct ConflictTextEditor: View {
    @Bindable var model: RepoModel

    var body: some View {
        TextEditor(text: Binding(get: { model.conflict?.editedText ?? "" }, set: { model.conflict?.editedText = $0 }))
            .font(ConflictText.font)
            .scrollContentBackground(.hidden)
            .padding(Spacing.s)
            .accessibilityLabel("Merged file")
    }
}

/// Conflicts without text markers (a file deleted on one side, or a binary file): pick a side.
struct WholeFileChoice: View {
    let model: RepoModel
    let entry: StatusEntry
    let kind: ConflictKind

    var body: some View {
        ContentUnavailableView {
            Label("Choose a Version", systemImage: "arrow.triangle.branch")
        } description: {
            Text(kind.explanation + " " + (kind.oursMissing || kind.theirsMissing
                                           ? "Keep a version or delete the file."
                                           : "Its contents can't be merged line by line here."))
        } actions: {
            HStack(spacing: Spacing.s) {
                if kind == .bothDeleted {
                    Button("Delete the File") { model.takeWholeFile(ours: true, entries: [entry]) }
                } else {
                    Button(kind.oursMissing ? "Delete the File" : "Use Ours") { model.takeWholeFile(ours: true, entries: [entry]) }
                        .help(kind.oursMissing ? "Your side deleted it" : "Keep your side's file")
                    Button(kind.theirsMissing ? "Delete the File" : "Use Theirs") { model.takeWholeFile(ours: false, entries: [entry]) }
                        .help(kind.theirsMissing ? "The other side deleted it" : "Keep the other side's file")
                }
                if model.mergeTool.name != nil {
                    Button("Open in \(model.mergeTool.name ?? "")") { model.openInMergeTool(entry) }
                        .disabled(!model.canUseMergeTool)
                        .help(model.mergeToolHelp)
                }
            }
        }
    }
}
