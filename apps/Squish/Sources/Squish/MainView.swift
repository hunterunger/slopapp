import AppKit
import QuickLook
import SlopKit
import SquishCore
import SwiftUI

/// The window: the queue (or the big drop zone), and the options bar under it.
struct MainView: View {
    @Bindable var model: AppModel
    @State private var windowWidth: CGFloat = .infinity

    var body: some View {
        VStack(spacing: 0) {
            FileQueueView(
                queue: model.queue,
                selection: $model.selection,
                dropTitle: "Drop images or PDFs here",
                dropSymbol: "arrow.down.right.and.arrow.up.left",
                onFiles: { model.add($0) }
            ) { items in
                if items.contains(where: { model.replacement(for: $0) != nil }) {
                    Divider()
                    Button("Put Back Original") { model.putBack(items) }
                }
            }
            .fileQueueOnRemove { rows in model.removeRows(rows) }
            .onKeyPress(.space) {
                guard !model.queue.items.isEmpty else { return .ignored }
                model.toggleQuickLook()
                return .handled
            }
            Divider()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
            OptionsBar(model: model, windowWidth: windowWidth)
        }
        .frame(minWidth: 520, minHeight: 340)
        // Kept in their own small views so the window body doesn't redraw for every
        // progress tick of every file.
        .background { WindowSubtitle(model: model) }
        .background { QuickLookHost(model: model) }
        .background { CloseGuard() }
        .toolbar { toolbar }
        .alert("Replace originals?", isPresented: $model.confirmingReplace) {
            Button("Replace Originals") { model.confirmReplaceOriginals() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Compressed files will take the originals’ place, and the originals will go to the Trash. Until you quit, Edit ▸ Undo or Put Back Original returns them.")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            let outdated = model.queue.isBusy ? 0 : model.outdatedItems.count
            if outdated > 0 {
                Button { model.redoOutdated() } label: {
                    Label("Redo All", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .help("Compress the \(outdated) \(outdated == 1 ? "file" : "files") made with older settings again, with the current ones")
            }
            if model.queue.isBusy {
                Button { model.queue.cancelAll() } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .help("Stop compressing (⌘.)")
            } else if !model.queue.items.isEmpty {
                Button { model.clearList() } label: {
                    Label("Clear List", systemImage: "xmark.circle")
                }
                .help("Clear the list. Files aren't touched (⇧⌘⌫)")
            }
            Button { model.chooseFiles() } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .help("Choose files or folders to compress (⌘O)")
        }
    }
}

struct WindowSubtitle: View {
    let model: AppModel

    var body: some View {
        Color.clear.navigationSubtitle(model.summaryText)
    }
}

struct QuickLookHost: View {
    @Bindable var model: AppModel

    var body: some View {
        Color.clear.quickLookPreview($model.previewURL, in: model.previewURL == nil ? [] : model.queue.items.map(\.revealURL))
    }
}

/// Quality, size, format and destination, each a compact menu showing its current value.
struct OptionsBar: View {
    @Bindable var model: AppModel
    let windowWidth: CGFloat
    /// The width the menus need with their icons.
    @State private var neededWithIcons: CGFloat = 0

    private var showIcons: Bool {
        neededWithIcons <= windowWidth - 2 * Spacing.l
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            // Icons drop out when the window is too narrow, and come back when it widens.
            OptionMenus(model: model, showIcons: showIcons)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    OptionMenus(model: model, showIcons: true)
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { neededWithIcons = $0 }
                }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s + 2)
        // Anchored over the menus they belong to, but kept inside the window.
        .popover(isPresented: $model.editingQuality, attachmentAnchor: .point(UnitPoint(x: 0.2, y: 0)), arrowEdge: .top) {
            CustomQualityView(model: model)
        }
        .popover(isPresented: $model.editingSize, attachmentAnchor: .point(UnitPoint(x: 0.4, y: 0)), arrowEdge: .top) {
            CustomSizeView(model: model)
        }
    }
}

struct OptionMenus: View {
    @Bindable var model: AppModel
    let showIcons: Bool

    private var settings: SquishSettings { model.settings }

    var body: some View {
        HStack(spacing: Spacing.m) {
            Menu {
                QualityMenuItems(model: model)
            } label: {
                label(settings.preset == .custom ? "Custom \(Int((settings.customQuality * 100).rounded()))%" : settings.preset.shortTitle,
                      "dial.medium", name: "Quality")
            }
            .help("Quality: \(settings.preset.detail)")
            .accessibilityLabel("Quality")
            .accessibilityValue(settings.preset == .custom ? "Custom \(Int((settings.customQuality * 100).rounded())) percent" : settings.preset.title)

            Menu {
                SizeMenuItems(model: model)
            } label: {
                label(SizeChoice.title(for: settings.maxDimension), "arrow.up.left.and.arrow.down.right", name: "Size")
            }
            .help("Make images no bigger than this. Smaller images are never enlarged.")
            .accessibilityLabel("Size")
            .accessibilityValue(SizeChoice.title(for: settings.maxDimension))

            Menu {
                FormatMenuItems(model: model)
            } label: {
                label(settings.format == .original ? "Same Format" : settings.format.title, "photo", name: "Format")
            }
            .help("The image format to save in. PDFs stay PDFs.")
            .accessibilityLabel("Format")
            .accessibilityValue(settings.format.title)

            Menu {
                DestinationMenuItems(model: model)
            } label: {
                label(DestinationText.short(settings.destination), DestinationText.symbol(settings.destination), name: "Save To")
            }
            .help(DestinationText.help(settings.destination, suffix: settings.effectiveSuffix))
            .accessibilityLabel("Save To")
            .accessibilityValue(DestinationText.short(settings.destination))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .lineLimit(1)
        .fixedSize()
    }

    /// `name` is what VoiceOver calls the menu. It's also the icon's description, because
    /// AppKit sometimes reads the menu's name from its icon instead of from SwiftUI.
    @ViewBuilder private func label(_ title: String, _ symbol: String, name: String) -> some View {
        if showIcons, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) {
            Label {
                Text(title).accessibilityLabel(name)
            } icon: {
                Image(nsImage: image)
            }
        } else {
            Text(title).accessibilityLabel(name)
        }
    }
}

// MARK: Menu contents (shared by the options bar and the Compression menu)

struct QualityMenuItems: View {
    @Bindable var model: AppModel
    /// Adds ⌘1–⌘4 (for the Compression menu).
    var withShortcuts = false

    var body: some View {
        ForEach(Array(QualityPreset.allCases.enumerated()), id: \.element) { index, preset in
            let toggle = Toggle(isOn: Binding(
                get: { model.settings.preset == preset },
                // Choosing Custom… always opens its popover, even when it's already chosen.
                set: { _ in preset == .custom ? model.editCustomQuality() : (model.settings.preset = preset) }
            )) {
                Text(preset == .custom ? "Custom…" : preset.title)
                if preset != .custom || !withShortcuts { Text(preset.detail) }
            }
            if withShortcuts {
                toggle.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            } else {
                toggle
            }
            if preset == .small { Divider() }
        }
    }
}

enum SizeChoice {
    static let presets = [3840, 2560, 1920, 1280, 800]

    static func title(for maxDimension: Int?) -> String {
        guard let maxDimension else { return "Full Size" }
        return "Up to \(maxDimension) px"
    }
}

struct SizeMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("Full Size", isOn: Binding(get: { model.settings.maxDimension == nil }, set: { if $0 { model.settings.maxDimension = nil } }))
        Divider()
        ForEach(SizeChoice.presets, id: \.self) { size in
            Toggle(SizeChoice.title(for: size), isOn: Binding(get: { model.settings.maxDimension == size }, set: { if $0 { model.settings.maxDimension = size } }))
        }
        Divider()
        let custom = model.settings.maxDimension.map { !SizeChoice.presets.contains($0) } ?? false
        Toggle(custom ? "Custom (\(String(model.settings.maxDimension ?? 0)) px)…" : "Custom…",
               isOn: Binding(get: { custom }, set: { _ in model.editingSize = true }))
    }
}

struct FormatMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(model.capabilities.formatChoices) { format in
            Toggle(format.title, isOn: Binding(get: { model.settings.format == format }, set: { if $0 { model.settings.format = format } }))
        }
        Divider()
        Toggle("Remove Metadata", isOn: $model.settings.stripMetadata)
    }
}

struct DestinationMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("Next to Originals", isOn: Binding(get: { model.settings.destination == .alongside },
                                                  set: { if $0 { model.settings.destination = .alongside } }))
        ForEach(model.recentFolders, id: \.self) { folder in
            Toggle(folder.lastPathComponent, isOn: Binding(get: { model.settings.destination == .folder(folder) },
                                                           set: { if $0 { model.useFolder(folder) } }))
        }
        Button("Choose Folder…") { model.chooseFolder() }
        Divider()
        Toggle("Replace Originals", isOn: Binding(get: { model.settings.destination == .replaceOriginal },
                                                  set: { if $0 { model.requestReplaceOriginals() } else { model.settings.destination = .alongside } }))
    }
}

enum DestinationText {
    static func short(_ destination: Destination) -> String {
        switch destination {
        case .alongside: "Next to Originals"
        case .folder(let url): url.lastPathComponent
        case .replaceOriginal: "Replace Originals"
        }
    }

    static func symbol(_ destination: Destination) -> String {
        switch destination {
        case .alongside: "doc.on.doc"
        case .folder: "folder"
        case .replaceOriginal: "arrow.triangle.2.circlepath"
        }
    }

    static func help(_ destination: Destination, suffix: String) -> String {
        switch destination {
        case .alongside: "Saved next to each original, named with “\(suffix)”. Originals aren't touched."
        case .folder(let url): "Saved into \(url.path). Originals aren't touched."
        case .replaceOriginal: "Compressed files replace the originals. Originals go to the Trash."
        }
    }
}

// MARK: Popovers

struct CustomQualityView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var percent: Int { Int((model.settings.customQuality * 100).rounded()) }

    private var percentBinding: Binding<Int> {
        Binding(get: { percent },
                set: { model.settings.customQuality = Double(min(100, max(10, $0))) / 100 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Custom Quality").font(.headline)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text("Images")
                    Spacer()
                    // Typing a number works too (and lets VoiceOver users set it exactly).
                    TextField("Image quality percent", value: percentBinding, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 40)
                        .accessibilityLabel("Image quality percent")
                    Text("%")
                }
                Slider(value: $model.settings.customQuality, in: 0.1...1, step: 0.05) {
                    Text("Image quality")
                } minimumValueLabel: {
                    Text("Smaller").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Better").font(.caption).foregroundStyle(.secondary)
                }
                .labelsHidden()
                .accessibilityValue("\(percent) percent")
            }
            HStack {
                Text("Images in PDFs")
                Spacer()
                Picker("Images in PDFs", selection: $model.settings.customPDFResolution) {
                    ForEach([72, 96, 144, 200, 300], id: \.self) { Text("\(String($0)) dpi").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text("Higher quality means bigger files. At 90% and up, PNGs stay lossless.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 280)
        .onExitCommand { dismiss() }
    }
}

struct CustomSizeView: View {
    @Bindable var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Custom Size").font(.headline)
            HStack {
                Text("Longest edge")
                TextField("Pixels", text: $text)
                    .frame(width: 70)
                    .focused($focused)
                    .onSubmit(apply)
                    .accessibilityLabel("Longest edge in pixels")
                Text("px")
            }
            Text(value == nil
                 ? "Enter a whole number from 16 to 20000."
                 : "Bigger images are scaled down to this. Smaller ones keep their size.")
                .font(.caption)
                .foregroundStyle(value == nil ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value == nil)
            }
        }
        .padding(Spacing.l)
        .frame(width: 260)
        .onAppear {
            text = model.settings.maxDimension.map(String.init) ?? "1600"
        }
        .task {
            // Focus once the popover is on screen, so typing goes straight into the field.
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
        }
    }

    private var value: Int? {
        Int(text.trimmingCharacters(in: .whitespaces)).flatMap { (16...20_000).contains($0) ? $0 : nil }
    }

    private func apply() {
        guard let value else { return }
        model.settings.maxDimension = value
        dismiss()
    }
}
