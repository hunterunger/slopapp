import AppKit
import CrateCore
import SlopKit
import SwiftUI

/// Making a new archive, in the original's order: review the dropped items (add, remove),
/// then a format page (cards, name, compression, encryption), then a finished screen.
/// Converting an open archive starts at the format page.
struct CreateView: View {
    @Bindable var model: CreateModel

    var body: some View {
        @Bindable var app = model.app
        Group {
            if model.isDone {
                ResultPage(title: resultTitle, detail: resultDetail, items: model.resultItems)
                    .toolbar {
                        ResultToolbar(back: model.isConverting ? { model.back() } : nil,
                                      reveal: { model.reveal() }, done: { model.finish() })
                    }
            } else if model.page == .review {
                reviewPage
            } else {
                optionsPage
            }
        }
        .navigationTitle(model.isConverting ? "Convert “\(model.items.first?.lastPathComponent ?? "")”" : "New Archive")
        .acceptsDrops(model.app)
        .sheet(isPresented: $model.splittingFile) {
            SplitSheet(fileName: model.items.first?.lastPathComponent ?? "",
                       fileSize: (try? model.items.first?.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init),
                       size: $app.settings.splitSize, unit: $app.settings.splitUnit,
                       onSplit: { size in
                           model.splittingFile = false
                           model.splitFile(partSize: size)
                       },
                       onCancel: { model.splittingFile = false })
        }
    }

    // MARK: Review

    private var reviewPage: some View {
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
            .overlay {
                if model.items.isEmpty {
                    ContentUnavailableView("No items", systemImage: "tray",
                                           description: Text("Drop files and folders here, or click + to add them."))
                }
            }
            if case .failed(let message) = model.job {
                Hairline()
                FailureLine(message: message) { model.dismissError() }
            }
            PageFooter(summary: itemCount, progress: progress, stop: { model.cancel() }) {
                HStack(spacing: 0) {
                    Button { addFiles() } label: { FooterGlyph(systemName: "plus") }
                        .help("Add files or folders")
                        .accessibilityLabel("Add Files")
                    Button { model.remove(model.itemSelection) } label: { FooterGlyph(systemName: "minus") }
                        .help("Remove the selected items from the list (Delete)")
                        .accessibilityLabel("Remove Selected Items")
                        .disabled(model.itemSelection.isEmpty)
                }
                .buttonStyle(.borderless)
                // The first glyph's edge sits on the footer's 16 pt text margin.
                .padding(.leading, -FooterGlyph.inset)
                .disabled(model.isWorking)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.app.closeCurrent() } label: { Label("Cancel", systemImage: "xmark") }
                    .help("Forget these items (Esc)")
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                if model.canSplitFile {
                    Button { model.splittingFile = true } label: { Label("Split", systemImage: "scissors") }
                        .help("Split this file into parts without compressing it")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.next() } label: {
                    Label("Compress", systemImage: "archivebox").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Choose a format and make the archive (Return)")
                .disabled(model.items.isEmpty || model.isWorking)
            }
        }
    }

    private var itemCount: String {
        model.items.count == 1 ? "1 item" : "\(model.items.count) items"
    }

    private var progress: (title: String, fraction: Double?)? {
        if case .working(let fraction) = model.job {
            return (model.splittingFileJob ? "Splitting…" : "Creating “\(model.fileName)”…", fraction)
        }
        return nil
    }

    private func addFiles() {
        FileQueueActions.chooseFiles(types: [.item, .folder]) { model.add($0) }
    }

    // MARK: Options

    /// The form's two columns. Fixed, so ticking Encrypt or picking another format never
    /// moves the labels (the grid used to re-centre on its widest row).
    private enum FormMetrics {
        static let labelWidth: CGFloat = 104
        static let controlWidth: CGFloat = 320
        static var width: CGFloat { labelWidth + Spacing.s + controlWidth }
        /// Every row is as tall as a text field, so rows sit on an even 36 pt pitch.
        static let rowHeight: CGFloat = 24
    }

    private var optionsPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    VStack(spacing: Spacing.m) {
                        Text(model.isConverting ? "Convert to" : "Choose a format")
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: Spacing.m) {
                            ForEach(model.formats) { format in
                                FormatCard(format: format, selected: model.format == format) { model.format = format }
                            }
                        }
                        Text(model.formatHint)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Hairline()
                    form
                }
                .padding(Spacing.windowMargin)
                .disabled(model.isWorking)
            }
            if case .failed(let message) = model.job {
                Hairline()
                FailureLine(message: message) { model.dismissError() }
            }
            PageFooter(summary: optionsSummary, warning: model.hasInputProblem,
                       isNextStep: model.passwordProblem != nil || model.splitProblem != nil, progress: progress,
                       stop: { model.cancel() }) { EmptyView() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.back() } label: { Label("Back", systemImage: "chevron.left") }
                    .help(model.isConverting ? "Back to the archive (Esc)" : "Back to the items (Esc)")
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.create() } label: {
                    Label(model.isConverting ? "Convert" : "Create", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help(model.isConverting ? "Make the converted copy (Return)" : "Make the \(model.format.title) archive (Return)")
                .disabled(!model.canCreate)
            }
        }
    }

    private var optionsSummary: String {
        if let problem = model.passwordProblem ?? model.splitProblem { return problem }
        if model.isConverting { return "Makes “\(model.fileName)” next to the archive. The original stays." }
        return model.app.settings.leaveOutMacFiles ? "\(itemCount) · Mac-only files like .DS_Store are left out" : itemCount
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .frame(width: FormMetrics.labelWidth, alignment: .trailing)
    }

    /// A control cell: as tall as a row, leading-aligned in the control column.
    private func cell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(minHeight: FormMetrics.rowHeight, alignment: .leading)
            .frame(width: FormMetrics.controlWidth, alignment: .leading)
    }

    /// A caption under a control, wrapping in the control column.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: FormMetrics.controlWidth, alignment: .leading)
    }

    private var form: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.m) {
            GridRow {
                label("Archive name:")
                cell {
                    HStack(spacing: Spacing.xs) {
                        TextField("Archive name", text: $model.name)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onChange(of: model.name) { model.nameChanged() }
                            .accessibilityLabel("Archive name")
                        // A fixed slot for ".zip", ".7z", ".tar.gz": the field keeps its width.
                        ZStack(alignment: .leading) {
                            Text(".tar.gz").hidden()
                            Text("." + model.format.fileExtension).foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            GridRow {
                label("Compression:")
                cell {
                    Picker("Compression", selection: $model.level) {
                        ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            GridRow {
                label("")
                cell {
                    Toggle("Encrypt", isOn: $model.encrypt)
                        .disabled(!model.format.supportsPassword)
                        .onChange(of: model.encrypt) { _, on in
                            // The fields appear in this update; focus them on the next.
                            if on { DispatchQueue.main.async { passwordFocused = true } }
                        }
                        .help(model.format.supportsPassword ? "Protect the archive with a password" : "Only Zip and 7z archives can have a password")
                }
            }
            if model.encrypt, model.format.supportsPassword {
                GridRow {
                    label("Password:")
                    cell {
                        passwordField("Password", text: $model.passwordText)
                            .focused($passwordFocused)
                    }
                }
                GridRow {
                    label("Repeat:")
                    cell { passwordField("Repeat password", text: $model.repeatText) }
                }
                GridRow {
                    label("")
                    cell { Toggle("Show password", isOn: $model.showPassword) }
                }
                if model.format == .zip {
                    GridRow {
                        label("Encryption:")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Picker("Encryption", selection: $model.encryption) {
                                ForEach(ZipEncryption.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()
                            // A radio is 16 pt tall: centre the first one in a 24 pt row,
                            // so this row keeps the form's 36 pt pitch.
                            .padding(.top, (FormMetrics.rowHeight - 16) / 2) // lint:allow radio height
                            note(model.encryption.note)
                        }
                    }
                } else {
                    GridRow {
                        label("")
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            cell { Toggle("Hide file names", isOn: $model.hideNames) }
                            note(model.hideNames
                                 ? "Without the password, nobody can see what's inside, not even the names. Crate doesn't keep this password."
                                 : "Anyone can see the names inside; the files need the password. Crate doesn't keep this password.")
                        }
                    }
                }
            }
            GridRow {
                label("Split:")
                cell { SplitPicker(model: model) }
            }
            if !model.isConverting {
                GridRow {
                    label("Save to:")
                    cell {
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
                    }
                }
            }
        }
        .frame(width: FormMetrics.width)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @FocusState private var passwordFocused: Bool

    @ViewBuilder private func passwordField(_ title: String, text: Binding<String>) -> some View {
        Group {
            if model.showPassword {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .accessibilityLabel(title)
        .frame(width: 260)
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

    // MARK: Finished

    private var resultTitle: String {
        switch model.job {
        case .done(let result): "\(model.isConverting ? "Converted to" : "Created") “\(result.primary?.lastPathComponent ?? model.fileName)”"
        case .split(let parts): "Split into \(parts.count) parts"
        default: ""
        }
    }

    private var resultDetail: String {
        switch model.job {
        case .done(let result):
            var parts = [ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)]
            parts.append(result.fileCount == 1 ? "1 file" : "\(result.fileCount.formatted()) files")
            if let protection = model.lastProtection { parts.append(protection) }
            if result.wasSplit { parts.append("in \(result.outputs.count) parts") }
            var text = parts.joined(separator: " · ")
            if result.wasSplit { text += ". Open split archives with Crate, 7‑Zip, Keka or The Unarchiver." }
            return text
        case .split:
            return "“\(model.items.first?.lastPathComponent ?? "")” is unchanged. Join Parts puts it back together."
        default:
            return ""
        }
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
                .font(.callout)
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
            .help("Split the archive into parts of this size. Archive Utility can't open split archives; 7‑Zip, Keka, The Unarchiver and Crate can.")
            if model.usesCustomSplit {
                TextField("Size", value: $model.customSplitMB, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .accessibilityLabel("Part size in megabytes")
                Text("MB").foregroundStyle(.secondary)
                if let problem = model.splitProblem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.textOrange)
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


/// A + or − glyph in a footer: a 24 × 20 pt hit area, the glyph centred in it.
struct FooterGlyph: View {
    static let size = CGSize(width: 24, height: 20)
    /// How far the glyph's left edge sits inside the hit area (for lining it up with text).
    static let inset: CGFloat = 6
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .frame(width: Self.size.width, height: Self.size.height)
            .contentShape(Rectangle())
    }
}
