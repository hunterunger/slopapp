import AppKit
import ConvertCore
import QuickLook
import SlopKit
import SwiftUI

/// The window: the queue (or the big drop zone), and the format bar under it.
struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            FileQueueView(
                queue: model.queue,
                selection: $model.selection,
                dropTitle: "Drop videos, audio or images",
                dropSymbol: "arrow.triangle.2.circlepath",
                onFiles: { model.add($0) }
            )
            .fileQueueSizeStyle(.neutral)
            .fileQueueRetryTitle("Convert Again")
            .fileQueueDetail { [model] item in model.detail(for: item) }
            .fileQueueFollowsNewFiles()
            .onKeyPress(.space) {
                guard !model.queue.items.isEmpty else { return .ignored }
                model.toggleQuickLook()
                return .handled
            }
            OutdatedNotice(model: model)
            Divider()
            FormatBar(model: model)
        }
        .frame(minWidth: 720, minHeight: 340)
        .background { WindowCloseGuard() }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: model.queue.items.map(\.id)) { model.rowsChanged() }
        .onChange(of: undoManager) { _, manager in model.undoManager = manager }
        // Kept in their own small views so the window body doesn't redraw for every
        // progress tick of every file.
        .background { WindowSubtitle(model: model) }
        .background { QuickLookHost(model: model) }
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.queue.isBusy {
                Button { model.queue.cancelAll() } label: {
                    Label("Stop All", systemImage: "stop.circle")
                }
                .help("Stop converting (⌘.)")
            } else if !model.queue.items.isEmpty {
                Button { model.clearList() } label: {
                    Label("Clear List", systemImage: "xmark.circle")
                }
                .help("Clear the list. Files aren't touched (⇧⌘⌫)")
            }
            Button { model.chooseFiles() } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .help("Choose files or folders to convert (⌘O)")
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

/// "Settings changed for 3 files. [Convert Again]", under the list, when finished files
/// were made with other settings than the current ones.
struct OutdatedNotice: View {
    let model: AppModel

    var body: some View {
        let count = model.queue.isBusy ? 0 : model.outdatedItems.count
        if count > 0 {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(count == 1 ? "1 file was converted with other settings." : "\(count) files were converted with other settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.s)
                Button("Convert Again") { model.convertAgain() }
                    .help("Convert those files again with the current settings, replacing what they made before (⌘R)")
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
    }
}

/// One target per kind, then quality, size and destination: each a compact menu with an
/// icon, showing its current value. Every choice is also in the Format menu.
struct FormatBar: View {
    @Bindable var model: AppModel

    var body: some View {
        FormatMenus(model: model)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s + 2)
    }
}

struct FormatMenus: View {
    @Bindable var model: AppModel

    private var settings: ConvertSettings { model.settings }

    var body: some View {
        HStack(spacing: Spacing.m) {
            BarMenuButton(name: "Video format", value: settings.video.title, symbol: "film",
                          help: "What videos become: \(settings.video.title). \(settings.video.detail).") {
                MenuEntries.video(model)
            }
            BarMenuButton(name: "Audio format", value: settings.audio.title, symbol: "waveform",
                          help: "What audio files become: \(settings.audio.title). \(settings.audio.detail).") {
                MenuEntries.audio(model)
            }
            BarMenuButton(name: "Image format", value: settings.image.title, symbol: "photo",
                          help: "What images become: \(settings.image.title). \(settings.image.detail).") {
                MenuEntries.image(model)
            }
            Divider().frame(height: 16)
            BarMenuButton(name: "Quality", value: settings.quality.title, symbol: "dial.medium",
                          help: "Quality: \(settings.quality.detail).") {
                MenuEntries.quality(model)
            }
            BarMenuButton(name: "Size", value: settings.size.shortTitle, symbol: "arrow.up.left.and.arrow.down.right",
                          help: "Make videos and images no bigger than this. Smaller ones are never enlarged. GIFs are also capped by Quality (\(QualityTable.gif(settings.quality).longEdge) px now).") {
                MenuEntries.size(model)
            }
            BarMenuButton(name: "Save To", value: DestinationText.short(settings.destination),
                          symbol: settings.destination == .alongside ? "doc.on.doc" : "folder",
                          help: DestinationText.help(settings.destination)) {
                MenuEntries.destination(model)
            }
        }
        .fixedSize()
    }
}

/// The bar menus' contents (the Format menu shows the same choices).
@MainActor
enum MenuEntries {
    static func video(_ model: AppModel) -> [BarMenuEntry] {
        model.capabilities.videoTargets.flatMap { target -> [BarMenuEntry] in
            let item = BarMenuEntry.choice(target.title, detail: target.detail, isOn: model.settings.video == target) {
                model.settings.video = target
            }
            return target == .gif ? [item, .separator] : [item]
        }
    }

    static func audio(_ model: AppModel) -> [BarMenuEntry] {
        AudioTarget.allCases.map { target in
            .choice(target.title, detail: target.detail, isOn: model.settings.audio == target) { model.settings.audio = target }
        }
    }

    static func image(_ model: AppModel) -> [BarMenuEntry] {
        model.capabilities.imageTargets.map { target in
            .choice(target.title, detail: target.detail, isOn: model.settings.image == target) { model.settings.image = target }
        }
    }

    static func quality(_ model: AppModel) -> [BarMenuEntry] {
        Quality.allCases.map { quality in
            .choice(quality.title, detail: quality.detail, isOn: model.settings.quality == quality) { model.settings.quality = quality }
        }
    }

    static func size(_ model: AppModel) -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = []
        for size in SizeLimit.allCases {
            entries.append(.choice(size.title, detail: nil, isOn: model.settings.size == size) { model.settings.size = size })
            if size == .original { entries.append(.separator) }
        }
        entries.append(.separator)
        entries.append(.note(GIFText.menuNote(model.settings.quality)))
        return entries
    }

    static func destination(_ model: AppModel) -> [BarMenuEntry] {
        var entries: [BarMenuEntry] = [
            .choice("Next to Originals", detail: nil, isOn: model.settings.destination == .alongside) {
                model.settings.destination = .alongside
            },
        ]
        for folder in model.recentFolders {
            entries.append(.choice(folder.lastPathComponent, detail: folder.deletingLastPathComponent().path,
                                   isOn: model.settings.destination == .folder(folder)) { model.useFolder(folder) })
        }
        entries.append(.separator)
        entries.append(.action("Choose Folder…") { model.chooseFolder() })
        return entries
    }
}

// MARK: Menu contents (shared by the format bar and the Format menu)

/// A checkmarked menu item with a one-line subtitle.
struct ChoiceItem: View {
    let title: String
    let detail: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { if $0 { action() } })) {
            Text(title)
            if let detail { Text(detail) }
        }
    }
}

struct VideoMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        let targets = model.capabilities.videoTargets
        ForEach(targets) { target in
            ChoiceItem(title: target.title, detail: target.detail, isOn: model.settings.video == target) {
                model.settings.video = target
            }
            if target == .gif { Divider() }
        }
    }
}

struct AudioMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(AudioTarget.allCases) { target in
            ChoiceItem(title: target.title, detail: target.detail, isOn: model.settings.audio == target) {
                model.settings.audio = target
            }
        }
    }
}

struct ImageMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(model.capabilities.imageTargets) { target in
            ChoiceItem(title: target.title, detail: target.detail, isOn: model.settings.image == target) {
                model.settings.image = target
            }
        }
    }
}

struct QualityMenuItems: View {
    @Bindable var model: AppModel
    /// Adds ⌘1–⌘3 (for the Format menu).
    var withShortcuts = false

    var body: some View {
        ForEach(Array(Quality.allCases.enumerated()), id: \.element) { index, quality in
            let item = ChoiceItem(title: quality.title, detail: withShortcuts ? nil : quality.detail,
                                  isOn: model.settings.quality == quality) {
                model.settings.quality = quality
            }
            if withShortcuts {
                item.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            } else {
                item
            }
        }
    }
}

struct SizeMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ForEach(SizeLimit.allCases) { size in
            ChoiceItem(title: size.title, detail: nil, isOn: model.settings.size == size) {
                model.settings.size = size
            }
            if size == .original { Divider() }
        }
        Divider()
        Text(GIFText.menuNote(model.settings.quality))
    }
}

struct DestinationMenuItems: View {
    @Bindable var model: AppModel

    var body: some View {
        ChoiceItem(title: "Next to Originals", detail: nil, isOn: model.settings.destination == .alongside) {
            model.settings.destination = .alongside
        }
        ForEach(model.recentFolders, id: \.self) { folder in
            ChoiceItem(title: folder.lastPathComponent, detail: nil, isOn: model.settings.destination == .folder(folder)) {
                model.useFolder(folder)
            }
        }
        Divider()
        Button("Choose Folder…") { model.chooseFolder() }
    }
}

enum DestinationText {
    static func short(_ destination: Destination) -> String {
        switch destination {
        case .alongside: "Next to Originals"
        case .folder(let url): url.lastPathComponent
        }
    }

    static func help(_ destination: Destination) -> String {
        switch destination {
        case .alongside: "New files are saved next to the originals. Originals aren't touched, and nothing is overwritten."
        case .folder(let url): "New files are saved into \(url.path). Originals aren't touched, and nothing is overwritten."
        }
    }
}
