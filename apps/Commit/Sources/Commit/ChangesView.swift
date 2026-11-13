import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// The middle column for the current sidebar item, with banners on top.
struct ContentColumn: View {
    @Bindable var model: RepoModel

    var body: some View {
        Group {
            switch model.sidebarSelection {
            case .history, .ref:
                HistoryColumn(model: model)
            case .stashes:
                StashListColumn(model: model)
            default:
                ChangesColumn(model: model)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BannerStack(model: model)
        }
    }
}

/// The right column: a diff, or a commit or stash with its files and diff.
struct DetailColumn: View {
    @Bindable var model: RepoModel

    var body: some View {
        switch model.sidebarSelection {
        case .history, .ref:
            CommitDetailView(model: model)
        case .stashes:
            StashDetailView(model: model)
        default:
            if case .workingCopy(let entry, _) = model.diff.source, entry.isConflicted {
                ConflictResolverView(model: model, entry: entry)
            } else {
                DiffPane(model: model)
            }
        }
    }
}

/// Staged and unstaged files, with the composer docked underneath.
struct ChangesColumn: View {
    @Bindable var model: RepoModel

    var body: some View {
        VStack(spacing: 0) {
            if model.status.isClean {
                ContentUnavailableView {
                    Label("No Changes", systemImage: "checkmark.circle")
                } description: {
                    Text("Your files match the last commit.")
                } actions: {
                    if !model.status.branch.isUnborn {
                        Button("Show History") { model.sidebarSelection = .history }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                FileList(model: model)
            }
            Hairline()
            ComposerView(model: model)
        }
    }
}

struct FileList: View {
    @Bindable var model: RepoModel

    var body: some View {
        let conflicted = model.status.conflicted.filter(model.matchesSearch)
        let staged = model.status.staged.filter(model.matchesSearch)
        let unstaged = model.status.unstaged.filter(model.matchesSearch)
        List(selection: $model.fileSelection) {
            if !conflicted.isEmpty {
                Section {
                    ForEach(conflicted, id: \.path) { entry in
                        FileRow(entry: entry, area: .conflicted, model: model)
                            .id(FileRowID(path: entry.path, area: .conflicted))
                            .tag(FileRowID(path: entry.path, area: .conflicted))
                    }
                } header: {
                    SectionHeader(title: "Conflicts", count: conflicted.count)
                }
            }
            Section {
                ForEach(staged, id: \.path) { entry in
                    FileRow(entry: entry, area: .staged, model: model)
                        .id(FileRowID(path: entry.path, area: .staged))
                        .tag(FileRowID(path: entry.path, area: .staged))
                }
                if staged.isEmpty {
                    Text(!model.searchText.isEmpty ? "No matches" : conflicted.isEmpty ? "Nothing staged yet. Tick a file below, or select lines in its diff." : "Nothing staged yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            } header: {
                SectionHeader(title: "Staged", count: staged.count) {
                    Button("Unstage All") { model.unstageAll() }
                        .disabled(model.status.staged.isEmpty)
                }
            }
            Section {
                ForEach(unstaged, id: \.path) { entry in
                    FileRow(entry: entry, area: .unstaged, model: model)
                        .id(FileRowID(path: entry.path, area: .unstaged))
                        .tag(FileRowID(path: entry.path, area: .unstaged))
                }
                if unstaged.isEmpty {
                    Text(!model.searchText.isEmpty ? "No matches" : conflicted.isEmpty ? "Everything is staged." : "No other changes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            } header: {
                SectionHeader(title: "Changes", count: unstaged.count) {
                    Button("Stage All") { model.stageAll() }
                        .disabled(model.status.unstaged.isEmpty)
                }
            }
        }
        .onKeyPress(.space) {
            model.toggleSelection()
            return .handled
        }
        .onKeyPress(.return) {
            model.toggleSelection()
            return .handled
        }
        .contextMenu(forSelectionType: FileRowID.self) { rows in
            FileMenu(rows: rows, model: model)
        } primaryAction: { rows in
            if rows.count == 1, let row = rows.first, let entry = model.entry(for: row) { model.openInEditor(entry) }
        }
        .accessibilityLabel("Changed files")
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    let count: Int
    @ViewBuilder var trailing: Trailing

    init(title: String, count: Int, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.count = count
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(title)
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            trailing
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption)
        }
    }
}

/// Checkbox (staged), status symbol, file name and folder.
struct FileRow: View {
    let entry: StatusEntry
    let area: FileRowID.Area
    let model: RepoModel

    var body: some View {
        HStack(spacing: Spacing.s) {
            Toggle(isOn: Binding(get: { area == .staged },
                                 set: { model.setStaged(entry, area: area, staged: $0) })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(toggleLabel)
            .disabled(area == .conflicted)
            StatusSymbol(change: change, conflicted: area == .conflicted, folder: entry.path.hasSuffix("/"))
            let parts = entry.nameAndFolder
            HStack(spacing: Spacing.xs) {
                Text(parts.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if let original = entry.originalPath, area == .staged {
                    Text("from \(StatusEntry.split(original).name)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !parts.folder.isEmpty {
                    Text(parts.folder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        .help(entry.path)
        .accessibilityElement(children: .contain)
    }

    private var change: ChangeKind {
        switch area {
        case .conflicted: .updatedUnmerged
        case .staged: entry.staged
        case .unstaged: entry.isUntracked ? .untracked : entry.unstaged
        }
    }

    private var toggleLabel: String {
        let name = entry.nameAndFolder.name
        switch area {
        case .staged: return "Unstage \(name)"
        case .unstaged: return "Stage \(name)"
        case .conflicted: return "\(name) has conflicts"
        }
    }
}

/// A small coloured symbol for what happened to a file, with a spoken label.
struct StatusSymbol: View {
    let change: ChangeKind
    var conflicted = false
    var folder = false

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.readable(color, on: .controlBackgroundColor, target: ReadableColor.symbolTarget))
            .frame(width: 16)
            .help(change.label)
            .accessibilityLabel(change.label)
    }

    private var symbol: String {
        if conflicted { return "exclamationmark.triangle.fill" }
        switch change {
        case .added: return "plus.circle.fill"
        case .untracked: return folder ? "folder.badge.plus" : "plus.circle"
        case .deleted: return "minus.circle.fill"
        case .renamed, .copied: return "arrow.right.circle.fill"
        case .typeChanged: return "circle.lefthalf.filled"
        case .updatedUnmerged: return "exclamationmark.triangle.fill"
        default: return "pencil.circle.fill"
        }
    }

    private var color: NSColor {
        if conflicted { return .systemRed }
        switch change {
        case .added, .untracked: return .systemGreen
        case .deleted: return .systemRed
        case .renamed, .copied: return .systemBlue
        default: return .systemOrange
        }
    }
}

struct FileMenu: View {
    let rows: Set<FileRowID>
    let model: RepoModel

    var body: some View {
        let entries = rows.compactMap { row in model.entry(for: row).map { (row, $0) } }
        let unstaged = entries.filter { $0.0.area == .unstaged }.map(\.1)
        let staged = entries.filter { $0.0.area == .staged }.map(\.1)
        let conflicted = entries.filter { $0.0.area == .conflicted }.map(\.1)
        if !unstaged.isEmpty {
            Button(unstaged.count == 1 ? "Stage" : "Stage \(unstaged.count) Files") { model.stage(unstaged) }
        }
        if !staged.isEmpty {
            Button(staged.count == 1 ? "Unstage" : "Unstage \(staged.count) Files") { model.unstage(staged) }
        }
        if !conflicted.isEmpty {
            Button("Mark Resolved") { model.markResolved(conflicted) }
        }
        if !unstaged.isEmpty || !staged.isEmpty {
            Divider()
            Button("Discard Changes…") {
                model.discardFiles(unstaged + staged.filter { s in !unstaged.contains { $0.path == s.path } },
                                   keepStaged: staged.isEmpty)
            }
        }
        if !conflicted.isEmpty {
            Button("Use Our Whole File") { model.takeWholeFile(ours: true, entries: conflicted) }
            Button("Use Their Whole File") { model.takeWholeFile(ours: false, entries: conflicted) }
            if conflicted.count == 1, model.mergeTool.name != nil {
                Button("Open in \(model.mergeTool.name ?? "Merge Tool")") { model.openInMergeTool(conflicted[0]) }
                    .disabled(!model.canUseMergeTool)
            }
        }
        if entries.count == 1, let entry = entries.first?.1 {
            Divider()
            if !entry.isUntracked && !entry.path.hasSuffix("/") {
                Button("Show File History") { model.openFileHistory(entry.path, blame: false) }
                Button("Show Blame") { model.openFileHistory(entry.path, blame: true) }
                    .disabled(entry.unstaged == .deleted || entry.staged == .deleted)
                Divider()
            }
            Button("Open in Default App") { model.openInEditor(entry) }
            Button("Show in Finder") { model.revealInFinder(entry.path) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path, forType: .string)
            }
        }
    }
}

/// The commit message editor, docked under the file list. Never modal.
struct ComposerView: View {
    @Bindable var model: RepoModel
    @FocusState private var focus: Field?
    @State private var editingIdentity = false

    enum Field { case subject, body }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                TextField("Subject", text: $model.message.subject, prompt: Text("Summary of the change"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .subject)
                    .onSubmit { focus = .body }
                    .accessibilityLabel("Commit subject")
                Text(model.message.counterText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(counterColor)
                    .frame(minWidth: 40, alignment: .trailing)
                    .accessibilityLabel("\(model.message.subject.count) characters")
            }
            if let hint = model.message.subjectHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(model.message.subjectLength == .tooLong ? Color.textOrange : Color.secondary)
            }
            BodyEditor(text: $model.message.body)
                .focused($focus, equals: .body)
                .frame(height: 84)
            if model.amend && model.headPushed {
                Label("This commit is already pushed. Amending rewrites it for everyone who has it.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.textOrange)
            }
            HStack(alignment: .center, spacing: Spacing.s) {
                Toggle("Amend last commit", isOn: Binding(get: { model.amend }, set: { _ in model.toggleAmend() }))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .disabled(model.status.branch.isUnborn || model.inProgress != nil)
                Spacer(minLength: Spacing.s)
                if let hint = model.commitHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(hint)
                }
                // Prominent only when it can commit: a disabled prominent button still reads
                // as accent-coloured in a key window.
                Group {
                    if model.canCommit {
                        Button(model.commitButtonTitle) { model.commit(thenPush: false) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(model.commitButtonTitle) {}
                            .buttonStyle(.bordered)
                            .disabled(true)
                    }
                }
                .fixedSize()
                .layoutPriority(1)
                .help("Commit (⌘Return). Commit and Push: ⌥⌘Return")
            }
            identityLine
        }
        .padding(Spacing.m)
        .onChange(of: focus) { _, value in model.composerFocused = value != nil }
        .onChange(of: model.composerFocusRequest) { _, _ in focus = .subject }
        .onChange(of: model.composerResignRequest) { _, _ in
            focus = nil
            // Drop the typing undo steps too, so the next ⌘Z undoes the commit itself.
            if let window = NSApp.keyWindow {
                window.makeFirstResponder(nil)
                if let editor = window.fieldEditor(false, for: nil) { window.undoManager?.removeAllActions(withTarget: editor) }
            }
        }
    }

    @ViewBuilder
    private var identityLine: some View {
        if model.identity.isComplete {
            Text("Committing as \(model.identity.name ?? "") <\(model.identity.email ?? "")>")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help("From your Git config (user.name and user.email)")
        } else {
            Button("Set Your Name and Email…") { model.sheet = .identity }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var counterColor: Color {
        switch model.message.subjectLength {
        case .fine: .secondary
        case .long: .secondary
        case .tooLong: .textOrange
        }
    }
}

/// A plain-text body editor in the monospaced font, with a faint guide at 72 columns.
struct BodyEditor: View {
    @Binding var text: String
    @Environment(\.font) private var font

    /// NSTextView's line fragment padding: where the text (and so the placeholder) starts.
    static let textInset = NSTextContainer().lineFragmentPadding

    private static var monoFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(Font(Self.monoFont))
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Commit description")
            if text.isEmpty {
                Text("Description (optional)")
                    .font(Font(Self.monoFont))
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .padding(.leading, Self.textInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            GeometryReader { proxy in
                let x = Self.textInset + CGFloat(CommitMessage.bodyGuide) * ("0" as NSString).size(withAttributes: [.font: Self.monoFont]).width
                if x < proxy.size.width {
                    Hairline(axis: .vertical)
                        .offset(x: x)
                        .opacity(0.6)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(Spacing.xs)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.s))
        .hairlineBorder(RoundedRectangle(cornerRadius: Radius.s))
    }
}
