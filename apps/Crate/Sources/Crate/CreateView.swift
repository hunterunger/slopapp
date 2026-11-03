import AppKit
import CrateCore
import SlopKit
import SwiftUI

/// Making a new archive: the items, the options, and Create.
struct CreateView: View {
    @Bindable var model: CreateModel

    var body: some View {
        VStack(spacing: 0) {
            itemList
            Divider()
            options
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.m)
                .disabled(model.isWorking || model.isDone)
            Divider()
            bottomBar
        }
        .navigationTitle("New Archive")
        .navigationSubtitle(model.items.count == 1 ? "1 item" : "\(model.items.count) items")
        .acceptsDrops(model.app)
        .sheet(isPresented: $model.editingPassword) {
            SetPasswordSheet(model: model)
        }
    }

    // MARK: Items

    private var itemList: some View {
        VStack(spacing: 0) {
            List(selection: $model.itemSelection) {
                ForEach(model.items, id: \.self) { url in
                    ItemRow(url: url).tag(url)
                }
            }
            .listStyle(.inset)
            .onDeleteCommand { model.remove(model.itemSelection) }
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
                Button("Remove from Archive") { model.remove(urls) }
            }
            HStack(spacing: 0) {
                Button { addFiles() } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                    .help("Add files or folders")
                    .accessibilityLabel("Add Files")
                Divider().frame(height: 16)
                Button { model.remove(model.itemSelection) } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                    .help("Remove the selected items from the list (Delete)")
                    .accessibilityLabel("Remove Selected Items")
                    .disabled(model.itemSelection.isEmpty)
                Spacer()
                Text("Drop more files here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .disabled(model.isWorking || model.isDone)
        }
    }

    private func addFiles() {
        FileQueueActions.chooseFiles(types: [.item, .folder]) { model.add($0) }
    }

    // MARK: Options

    private var options: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.s) {
            GridRow {
                Text("Name:").gridColumnAlignment(.trailing)
                HStack(spacing: Spacing.xs) {
                    TextField("Name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onChange(of: model.name) { model.nameChanged() }
                        .accessibilityLabel("Archive name")
                    Text("." + model.format.fileExtension)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .gridCellColumns(3)
            }
            GridRow {
                Text("Format:").gridColumnAlignment(.trailing)
                Picker("Format", selection: $model.format) {
                    ForEach(CreateFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(model.formatHint)
                Text("Compression:").gridColumnAlignment(.trailing)
                Picker("Compression", selection: $model.level) {
                    ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Text(model.formatHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridCellColumns(3)
            }
            GridRow {
                Text("Password:").gridColumnAlignment(.trailing)
                HStack(spacing: Spacing.s) {
                    Button(model.password == nil ? "Add Password…" : "Change Password…") { model.editingPassword = true }
                        .disabled(!model.format.supportsPassword)
                    if !model.format.supportsPassword {
                        Text("Zip only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.password != nil {
                        Label(model.encryption == .aes256 ? "AES-256" : "ZipCrypto", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Split:").gridColumnAlignment(.trailing)
                SplitPicker(model: model)
            }
            GridRow {
                Text("Save to:").gridColumnAlignment(.trailing)
                Menu(saveToLabel) {
                    Picker("Save to", selection: saveToChoice) {
                        Text("Next to Originals").tag(0)
                        if let folder = model.folder {
                            Text(FileManager.default.displayName(atPath: folder.path)).tag(1)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Divider()
                    Button("Choose Folder…") { model.chooseFolder() }
                }
                .fixedSize()
                .accessibilityLabel("Save to: \(saveToLabel)")
                .gridCellColumns(3)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveToChoice: Binding<Int> {
        Binding(get: { model.folder == nil ? 0 : 1 }, set: { if $0 == 0 { model.folder = nil } })
    }

    private var saveToLabel: String {
        guard let folder = model.folder else {
            guard let target = model.targetFolder else { return "Next to Originals" }
            if let first = model.items.first, TrashLocation.contains(first) {
                return FileManager.default.displayName(atPath: target.path)
            }
            return "Next to Originals (\(FileManager.default.displayName(atPath: target.path)))"
        }
        return FileManager.default.displayName(atPath: folder.path)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Spacing.m) {
            switch model.job {
            case .idle:
                if let problem = model.splitProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(leftOutNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") { model.app.closeCurrent() }
                    .keyboardShortcut(.cancelAction)
                Button("Create \(model.format.title)") { model.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreate)
            case .working(let fraction):
                Text("Creating “\(model.fileName)”…").font(.callout).lineLimit(1)
                ProgressView(value: fraction ?? 0)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Progress")
                Spacer()
                Button("Stop") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .done(let result):
                ResultLine(symbol: "checkmark.circle.fill", tint: .green,
                           title: "Created “\(result.primary?.lastPathComponent ?? model.fileName)”",
                           detail: resultDetail(result),
                           reveal: { model.reveal() })
                Spacer()
                Button("Done") { model.app.closeCurrent() }
                    .keyboardShortcut(.defaultAction)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .help(message)
                Spacer()
                Button("OK") { model.dismissError() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(minHeight: 52)
    }

    private var leftOutNote: String {
        model.app.settings.leaveOutMacFiles ? "Mac-only files like .DS_Store are left out." : ""
    }

    private func resultDetail(_ result: CreateResult) -> String {
        var parts = [ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)]
        parts.append(result.fileCount == 1 ? "1 file" : "\(result.fileCount) files")
        if let protection = model.lastProtection {
            parts.append(protection == .aes256 ? "password (AES-256)" : "password (ZipCrypto)")
        }
        if result.wasSplit {
            parts.append("in \(result.outputs.count) parts")
        }
        var text = parts.joined(separator: " · ")
        if result.wasSplit { text += ". Open split archives with 7-Zip, Keka, The Unarchiver or Crate." }
        return text
    }
}

/// One dropped item: icon, name, and size or "Folder".
struct ItemRow: View {
    let url: URL
    @State private var detail = ""

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent), \(detail.lowercased())")
        .task(id: url) {
            let url = self.url
            detail = await Task.detached { ItemRow.describe(url) }.value
        }
    }

    nonisolated static func describe(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
        if values?.isDirectory == true, values?.isPackage != true {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
            return count == 1 ? "Folder, 1 item" : "Folder, \(count) items"
        }
        return values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
    }
}

/// Don't Split / 25 MB / … / Custom, with a size field for Custom.
struct SplitPicker: View {
    @Bindable var model: CreateModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Picker("Split", selection: choice) {
                ForEach(SplitSize.presets) { Text($0.title).tag(Optional($0)) }
                Divider()
                Text("Custom…").tag(SplitSize?.none)
            }
            .labelsHidden()
            .fixedSize()
            .help("Split the archive into parts of this size. Archive Utility can't open split archives; 7-Zip, Keka, The Unarchiver and Crate can.")
            if model.usesCustomSplit {
                TextField("Size", value: $model.customSplitMB, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .accessibilityLabel("Part size in megabytes")
                Text("MB").foregroundStyle(.secondary)
                if let problem = model.splitProblem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(problem)
                        .accessibilityLabel(problem)
                }
            }
        }
    }

    private var choice: Binding<SplitSize?> {
        Binding(
            get: { model.usesCustomSplit ? nil : model.split },
            set: { value in
                if let value {
                    model.usesCustomSplit = false
                    model.split = value
                } else {
                    model.usesCustomSplit = true
                }
            }
        )
    }
}

/// Set or change the zip password, with the encryption choice.
struct SetPasswordSheet: View {
    @Bindable var model: CreateModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""
    @State private var show = false
    @State private var encryption: ZipEncryption = .aes256
    @FocusState private var focused: Bool

    private var matches: Bool { !password.isEmpty && password == repeated }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Protect “\(model.fileName)” with a Password")
                .font(.headline)
            Group {
                if show {
                    TextField("Password", text: $password)
                    TextField("Repeat password", text: $repeated)
                } else {
                    SecureField("Password", text: $password)
                    SecureField("Repeat password", text: $repeated)
                }
            }
            .textFieldStyle(.roundedBorder)
            Toggle("Show password", isOn: $show)
            if !repeated.isEmpty, !matches {
                Label("The passwords don't match.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Divider()
            Picker("Encryption", selection: $encryption) {
                ForEach(ZipEncryption.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text(encryption.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.password != nil {
                    Button("Remove Password") {
                        model.password = nil
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Set Password") {
                    model.password = password
                    model.encryption = encryption
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!matches)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear {
            encryption = model.encryption
            focused = true
        }
    }
}
