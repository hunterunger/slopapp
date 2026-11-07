import AppKit
import CrateCore
import QuickLook
import SlopKit
import SwiftUI

/// An open archive, laid out like the original: the contents as an outline, the actions
/// top right (Close, Split, Convert, Extract), and the archive's name centered at the
/// bottom. After a job, a finished screen lists what was made.
struct BrowseView: View {
    @Bindable var model: BrowseModel

    var body: some View {
        @Bindable var app = model.app
        Group {
            if model.isShowingResult {
                resultPage
            } else {
                browsePage
            }
        }
        .navigationTitle(model.source.fileName)
        .acceptsDrops(model.app)
        .sheet(isPresented: $model.askingPassword) {
            PasswordEntrySheet(fileName: model.source.fileName, wrong: model.passwordWasWrong, checking: model.checkingPassword,
                               remember: $app.settings.rememberPasswords,
                               onSubmit: { model.submitPassword($0) }, onCancel: { model.cancelPassword() })
        }
        .sheet(isPresented: $model.splitting) {
            SplitSheet(fileName: model.source.fileName, fileSize: ArchiveReader.packedSize(of: model.source),
                       size: $app.settings.splitSize, unit: $app.settings.splitUnit,
                       onSplit: { size in
                           model.splitting = false
                           model.split(partSize: size)
                       },
                       onCancel: { model.splitting = false })
        }
    }

    // MARK: Browsing

    private var browsePage: some View {
        VStack(spacing: 0) {
            if let banner { banner }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if case .failed(let message) = model.job {
                Hairline()
                FailureLine(message: message) { model.dismissResult() }
            }
            PageFooter(summary: footerSummary, progress: progress, stop: { model.cancel() }) {
                DestinationMenu(app: model.app)
                    .disabled(!model.isLoaded || model.isWorking)
            }
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Filter")
        .toolbar { browseToolbar }
        .modifier(HiddenToolbarTitle())
    }

    private var footerSummary: String {
        let summary = model.summary
        return summary.isEmpty ? model.source.name : "\(model.source.name) — \(summary)"
    }

    private var progress: (title: String, fraction: Double?)? {
        if case .working(let title, let fraction) = model.job { return (title, fraction) }
        return nil
    }

    @ToolbarContentBuilder private var browseToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.app.closeCurrent() } label: {
                Label("Close Archive", systemImage: "xmark")
            }
            .help("Close this archive (⇧⌘W)")
            if model.canJoin {
                Button { model.join() } label: {
                    Label("Join Parts", systemImage: "square.stack.3d.up")
                }
                .help("Put the parts back together into one file")
            }
            Button { model.splitting = true } label: {
                Label("Split", systemImage: "scissors")
            }
            .help("Split this archive into parts of a size you choose")
            .disabled(!model.canSplit)
            Button { model.convert() } label: {
                Label {
                    Text("Convert")
                } icon: {
                    Image(systemName: "arrow.left.arrow.right").accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Convert")
            .help("Make a copy of this archive in another format")
            .disabled(!model.canExtract)
        }
        // The primary action in its own item, so it keeps its own prominent capsule.
        ToolbarItem(placement: .primaryAction) {
            Button { model.extractPrimary() } label: {
                Label("Extract", systemImage: "arrow.down.doc")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel(extractTitle)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .help(model.hasSelection ? "Extract the selected items (Return)" : "Extract everything (Return)")
            .disabled(!model.canExtract)
        }
    }

    /// One fixed title, so the toolbar never shifts and still fits at the window's usual
    /// width; VoiceOver, the tooltip, the footer ("2 of 12 items selected") and the Archive
    /// menu say whether it's everything or the selection.
    private var extractTitle: String {
        model.hasSelection ? "Extract Selected" : "Extract All"
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading(let fraction):
            VStack(spacing: Spacing.m) {
                if let fraction, fraction > 0.02 {
                    ProgressView(value: fraction).frame(width: 220)
                } else {
                    ProgressView().controlSize(.regular)
                }
                Text("Reading “\(model.source.fileName)”…")
                    .foregroundStyle(.secondary)
                Button("Cancel") { model.app.closeCurrent() }
                    .keyboardShortcut(.cancelAction)
            }
        case .failed(let error):
            ContentUnavailableView {
                Label(failureTitle(error), systemImage: icon(for: error))
            } description: {
                Text(failureDetail(error))
            } actions: {
                if error.needsPassword {
                    Button("Enter Password…") { model.unlockToList() }
                        .keyboardShortcut(.defaultAction)
                } else if model.canJoin {
                    Button("Join Parts") { model.join() }
                        .keyboardShortcut(.defaultAction)
                }
                Button("Choose Another…") { model.app.chooseFiles() }
            }
            .overlay(alignment: .bottom) {
                if model.tryingSavedPasswords {
                    Label("Trying saved passwords…", systemImage: "key")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        case .loaded:
            if model.tree.roots.isEmpty {
                ContentUnavailableView("This archive is empty", systemImage: "archivebox",
                                       description: Text("There's nothing inside “\(model.source.fileName)”."))
            } else if model.visibleTree.roots.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else {
                ArchiveOutline(model: model, tree: model.visibleTree, expandAll: !model.query.isEmpty)
            }
        }
    }

    private var isSplitFile: Bool {
        if case .failed(.notAnArchive) = model.phase { return model.canJoin }
        return false
    }

    private func failureTitle(_ error: CrateError) -> String {
        if isSplitFile { return "“\(model.source.fileName)” is one part of a split file" }
        return Self.headline(error.errorDescription ?? "Couldn't open the archive")
    }

    /// A sentence used as a heading: no closing period (HIG).
    static func headline(_ sentence: String) -> String {
        sentence.hasSuffix(".") && !sentence.hasSuffix("..") ? String(sentence.dropLast()) : sentence
    }

    private func failureDetail(_ error: CrateError) -> String {
        if isSplitFile {
            let whole = (model.source.fileName as NSString).deletingPathExtension
            return "Join Parts puts its \(model.source.parts.count) parts back together as “\(whole)”."
        }
        if error.needsPassword { return "Its file names are hidden too. Enter the password to see what's inside." }
        return error.recoverySuggestion ?? ""
    }

    private func icon(for error: CrateError) -> String {
        switch error {
        case .unsupportedEncryption, .passwordRequired, .wrongPassword: "lock.fill"
        case .missingPart: "puzzlepiece.extension"
        case .notAnArchive where model.canJoin: "square.stack.3d.up"
        default: "exclamationmark.triangle"
        }
    }

    // MARK: Finished

    private var resultPage: some View {
        ResultPage(title: resultTitle, detail: resultDetail, items: model.resultItems, warning: resultWarning)
            .toolbar {
                ResultToolbar(back: { model.dismissResult() }, reveal: { model.revealResult() }, done: { model.finish() })
            }
    }

    private var resultTitle: String {
        switch model.job {
        case .extracted(let result, _):
            result.primary.map { "Extracted to “\($0.lastPathComponent)”" } ?? "Extracted"
        case .split(let parts):
            "Split into \(parts.count) parts"
        case .joined(let file):
            "Joined into “\(file.lastPathComponent)”"
        default: ""
        }
    }

    private var resultDetail: String {
        switch model.job {
        case .extracted(let result, let trashed):
            var parts = [result.fileCount == 1 ? "1 file" : "\(result.fileCount.formatted()) files",
                         ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)]
            if trashed == true { parts.append("archive moved to the Trash (Edit ▸ Undo puts it back)") }
            return parts.joined(separator: " · ")
        case .split(let parts):
            let total = parts.reduce(Int64(0)) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0) }
            return "“\(model.source.fileName)” is unchanged · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) in all"
        case .joined:
            return "The parts are unchanged."
        default: return ""
        }
    }

    private var resultWarning: String? {
        guard case .extracted(let result, let trashed) = model.job else { return nil }
        let notes = [result.skippedNote, trashed == false ? "Couldn't move the archive to the Trash." : nil, model.keptNote].compactMap { $0 }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    private var banner: Banner? {
        guard let listing = model.listing, model.isLoaded else { return nil }
        if listing.encryptionUnsupported {
            return Banner(symbol: "lock.fill",
                          text: "This RAR archive is protected with a password. Crate can't decrypt RAR yet, but you can see what's inside. Try Keka or The Unarchiver to extract it.")
        }
        if !listing.unsafeEntries.isEmpty {
            let count = listing.unsafeEntries.count
            let first = listing.unsafeEntries[0]
            return Banner(symbol: "exclamationmark.shield.fill",
                          text: count == 1
                            ? "One item, “\(first)”, would land outside the folder or is a special file. Crate won't extract it."
                            : "\(count) items, such as “\(first)”, would land outside the folder or are special files. Crate won't extract them.")
        }
        let limit = ExtractionLimits.standard.maximumUnpacked(forPacked: listing.packedBytes)
        if listing.unpackedBytes > limit {
            let packed = ByteCountFormatter.string(fromByteCount: listing.packedBytes, countStyle: .file)
            let unpacked = ByteCountFormatter.string(fromByteCount: listing.unpackedBytes, countStyle: .file)
            return Banner(symbol: "exclamationmark.shield.fill",
                          text: "This \(packed) archive says it unpacks to \(unpacked). That's how zip bombs look, so Crate won't extract all of it. Small selections still work.")
        }
        if let problem = listing.problem {
            return Banner(symbol: "exclamationmark.triangle.fill",
                          text: problem.isTruncated
                            ? "Only part of “\(model.source.fileName)” could be read: it ends early. It may still be downloading, or be missing its last part."
                            : "Only part of “\(model.source.fileName)” could be read: it's damaged after this point.")
        }
        return nil
    }
}

/// A one-line notice above the list.
struct Banner: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(.orange.opacity(0.08))
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }
}

/// A failed job's message, with OK.
struct FailureLine: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.textOrange)
                .lineLimit(3)
                .help(message)
            Spacer()
            Button("OK", action: dismiss)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }
}

/// Where extracted files go (the same setting as in Settings).
struct DestinationMenu: View {
    @Bindable var app: AppModel

    var body: some View {
        Menu {
            Picker("Extract to", selection: choice) {
                Text("Next to Archive").tag("next")
                Text("Ask Each Time").tag("ask")
                Divider()
                ForEach(DestinationPresets.folders(for: app.settings), id: \.self) { path in
                    // Text only (Golden Gate menus carry no decorative icons).
                    Text(FileManager.default.displayName(atPath: path))
                        .tag("folder:" + path)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Choose Folder…") {
                app.chooseFolder(message: "Choose where extracted files go.", prompt: "Choose", near: nil) { url in
                    app.settings.destination = .folder(url.path)
                    app.settings.noteRecentFolder(url)
                }
            }
        } label: {
            Text("Extract to: \(label)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.callout)
        // A borderless menu draws its title 4 pt in; this puts the text on the footer's
        // 16 pt margin, like every other footer.
        .padding(.leading, -Spacing.xs)
        .accessibilityLabel("Extract to: \(label)")
        .help("Where extracted files go")
    }

    private var choice: Binding<String> {
        Binding(
            get: {
                switch app.settings.destination {
                case .nextToArchive: "next"
                case .ask: "ask"
                case .folder(let path): "folder:" + path
                }
            },
            set: { value in
                switch value {
                case "next": app.settings.destination = .nextToArchive
                case "ask": app.settings.destination = .ask
                default:
                    let path = String(value.dropFirst("folder:".count))
                    app.settings.destination = .folder(path)
                    app.settings.noteRecentFolder(URL(fileURLWithPath: path, isDirectory: true))
                }
            }
        )
    }

    private var label: String {
        switch app.settings.destination {
        case .nextToArchive: "Next to Archive"
        case .ask: "Ask Each Time"
        case .folder(let path): FileManager.default.displayName(atPath: path)
        }
    }
}

/// Folders offered in Extract to: the current choice, recent ones, Desktop and Downloads.
enum DestinationPresets {
    static func folders(for settings: CrateSettings) -> [String] {
        var result: [String] = []
        if case .folder(let path) = settings.destination { result.append(path) }
        result += settings.recentFolders
        for directory in [FileManager.SearchPathDirectory.desktopDirectory, .downloadsDirectory] {
            if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first { result.append(url.path) }
        }
        var seen = Set<String>()
        return result.filter { seen.insert(URL(fileURLWithPath: $0).standardizedFileURL.path).inserted }
    }
}

/// The open archive's name is in the footer (centered, with its size and format), so the
/// toolbar doesn't repeat it. The title alone reserved about 160 pt, which sent Convert and
/// Extract to the overflow menu at the default width once the filter field opened. Without
/// it the filter stays open beside the actions, and nothing moves when you start typing.
/// The window keeps its title for the Window menu, Mission Control and VoiceOver.
struct HiddenToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
