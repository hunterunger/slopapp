import AppKit
import CrateCore
import QuickLook
import SlopKit
import SwiftUI

/// An open archive: its contents as an outline, and the bar that extracts them.
struct BrowseView: View {
    @Bindable var model: BrowseModel

    var body: some View {
        VStack(spacing: 0) {
            if let banner { banner }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            BrowseBar(model: model)
        }
        .navigationTitle(model.source.fileName)
        .navigationSubtitle(model.summary)
        .searchable(text: $model.query, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(model.conversionFormats) { format in
                        Button("\(format.title) (\(format.summary))") { model.convert(to: format) }
                    }
                } label: {
                    Label {
                        Text("Convert")
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath").accessibilityHidden(true)
                    }
                    .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Convert")
                .help("Make a copy of this archive in another format")
                .disabled(!model.canExtract)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.app.closeCurrent() } label: {
                    Label("Close Archive", systemImage: "xmark")
                }
                .help("Close this archive (⇧⌘W)")
            }
        }
        .acceptsDrops(model.app)
        .sheet(isPresented: $model.askingPassword) {
            PasswordEntrySheet(fileName: model.source.fileName, wrong: model.passwordWasWrong, checking: model.checkingPassword,
                               onSubmit: { model.submitPassword($0) }, onCancel: { model.cancelPassword() })
        }
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
                Label(error.errorDescription ?? "Couldn't open the archive", systemImage: icon(for: error))
            } description: {
                Text(error.recoverySuggestion ?? "")
            } actions: {
                Button("Choose Another…") { model.app.chooseFiles() }
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

    private func icon(for error: CrateError) -> String {
        switch error {
        case .unsupportedEncryption, .passwordRequired, .wrongPassword: "lock.fill"
        case .missingPart: "puzzlepiece.extension"
        default: "exclamationmark.triangle"
        }
    }

    private var banner: Banner? {
        guard let listing = model.listing, model.isLoaded else { return nil }
        if listing.encryptionUnsupported {
            let format = listing.formatName.hasPrefix("RAR") ? "RAR" : "7z"
            return Banner(symbol: "lock.fill",
                          text: "This \(format) archive is protected with a password. Crate can't open password-protected 7z and RAR archives yet, but you can see what's inside. Try Keka or The Unarchiver to extract it.")
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
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

/// Destination, progress or result on the left; the main button on the right.
struct BrowseBar: View {
    @Bindable var model: BrowseModel

    var body: some View {
        HStack(spacing: Spacing.m) {
            status
            Spacer(minLength: Spacing.s)
            primaryButton
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(minHeight: 52)
    }

    @ViewBuilder private var status: some View {
        switch model.job {
        case .idle:
            DestinationMenu(app: model.app)
                .disabled(!model.isLoaded)
        case .working(let title, let progress):
            HStack(spacing: Spacing.s) {
                Text(title).font(.callout).lineLimit(1)
                ProgressView(value: progress ?? 0)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                    .accessibilityLabel("Progress")
                Button("Stop") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        case .extracted(let result, let trashed):
            ResultLine(
                symbol: result.skipped.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: result.skipped.isEmpty ? .green : .orange,
                title: result.primary.map { "Extracted to “\($0.lastPathComponent)”" } ?? "Extracted",
                detail: [result.skippedNote, trashed == true ? "The archive is in the Trash (Edit ▸ Undo puts it back)." : nil,
                         trashed == false ? "Couldn't move the archive to the Trash." : nil, model.keptNote].compactMap { $0 }.joined(separator: " "),
                reveal: { model.revealResult() }
            )
        case .converted(let result):
            ResultLine(symbol: "checkmark.circle.fill", tint: .green,
                       title: "Saved “\(result.primary?.lastPathComponent ?? "")”",
                       detail: ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file),
                       reveal: { model.revealResult() })
        case .failed(let message):
            HStack(spacing: Spacing.s) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .help(message)
                Button("OK") { model.dismissResult() }
            }
        }
    }

    private var primaryButton: some View {
        let count = model.selection.count
        let title = count == 0 ? "Extract All" : count == 1 ? "Extract 1 Item" : "Extract \(count) Items"
        return Button(title) { model.extractPrimary() }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canExtract)
            .help(count == 0 ? "Extract everything (Return)" : "Extract the selected items (Return)")
    }
}

/// "Extracted to …" with a Show in Finder button.
struct ResultLine: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).lineLimit(1).truncationMode(.middle)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
            Button("Show in Finder", action: reveal)
        }
    }
}

/// Where extracted files go (the same setting as in Settings).
struct DestinationMenu: View {
    @Bindable var app: AppModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text("Extract to:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Menu(label) {
                Picker("Extract to", selection: choice) {
                    Text("Next to Archive").tag(0)
                    Text("Ask Each Time").tag(1)
                    if case .folder(let path) = app.settings.destination {
                        Text(FileManager.default.displayName(atPath: path)).tag(2)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button("Choose Folder…") {
                    app.chooseFolder(message: "Choose where extracted files go.", prompt: "Choose", near: nil) { url in
                        app.settings.destination = .folder(url.path)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Extract to: \(label)")
        }
    }

    private var choice: Binding<Int> {
        Binding(
            get: {
                switch app.settings.destination {
                case .nextToArchive: 0
                case .ask: 1
                case .folder: 2
                }
            },
            set: { value in
                switch value {
                case 0: app.settings.destination = .nextToArchive
                case 1: app.settings.destination = .ask
                default: break
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
