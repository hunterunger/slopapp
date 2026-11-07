import AppKit
import QuickLook
import SlopKit
import SquishCore
import SwiftUI

/// The window, in three columns like the apps it replaces: the file list, the selected
/// file before and after, and the options with the preset on top.
struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columns) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 440)
        } detail: {
            PreviewPane(model: model)
        }
        .inspector(isPresented: $model.showsOptions) {
            OptionsInspector(model: model)
                .inspectorColumnWidth(min: 280, ideal: 310, max: 420)
        }
        .frame(minWidth: 760, minHeight: 480)
        // Kept in their own small views so the window body doesn't redraw for every
        // progress tick of every file.
        .background { WindowSubtitle(model: model) }
        .background { QuickLookHost(model: model) }
        .background { CloseGuard() }
        .toolbar { toolbar }
        .alert("Replace originals?", isPresented: $model.confirmingReplace) {
            Button("Replace Originals", role: .destructive) { model.confirmReplaceOriginals() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Compressed files will take the originals’ place, and the originals will go to the Trash. Edit ▸ Undo or Put Back Original returns them.")
        }
    }

    /// The file list. Empty, the drop zone is in the middle already, so the sidebar (if
    /// someone shows it) just says what will appear here instead of offering a second one.
    @ViewBuilder private var sidebar: some View {
        if model.queue.items.isEmpty {
            ContentUnavailableView {
                Label("No Files", systemImage: "photo.on.rectangle")
            } description: {
                Text("Files you add appear here.")
            }
            .dropDestination(for: URL.self) { urls, _ in
                let accepted = urls.filter { SquishTypes.kind(of: $0) != nil || $0.hasDirectoryPath }
                guard !accepted.isEmpty else { return false }
                model.add(accepted)
                return true
            }
        } else {
            FileQueueView(
                queue: model.queue,
                selection: $model.selection,
                dropTitle: "Drop images or PDFs here",
                dropSymbol: "arrow.down.right.and.arrow.up.left",
                onFiles: { model.add($0) }
            ) { items in
                if items.contains(where: { $0.output != nil }) {
                    Button("Copy Compressed File") { model.copyCompressed() }
                }
                if items.contains(where: { model.replacement(for: $0) != nil }) {
                    Divider()
                    Button("Put Back Original") { model.putBack(items) }
                }
            }
            .fileQueueOnRemove { rows in model.removeRows(rows) }
            .fileQueueRetryTitle("Compress Again")
            // The sidebar is narrow: the output's name is in the preview's footer instead.
            .fileQueueShowsOutputName(false)
            // Arrows, Space and Delete work in the list right after a drop.
            .fileQueueFollowsNewFiles()
            .onKeyPress(.space) {
                guard !model.queue.items.isEmpty else { return .ignored }
                model.toggleQuickLook()
                return .handled
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.chooseFiles() } label: {
                Label("Add Files…", systemImage: "plus")
            }
            .help("Choose files or folders to compress (⌘O)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.queue.isBusy {
                Button { model.queue.cancelAll() } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .help("Stop compressing (⌘.)")
            } else if !model.queue.items.isEmpty {
                Button { model.clearList() } label: {
                    Label("Clear List", systemImage: "trash")
                }
                .help("Clear the list. Files aren't touched (⇧⌘⌫)")
            }
            Toggle(isOn: $model.comparing) {
                Label("Compare", systemImage: "rectangle.split.2x1")
            }
            .disabled(model.queue.items.isEmpty)
            .help("Compare before and after (⌘K)")
            ShareButton(model: model)
            Button { model.revealTargets() } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(model.queue.items.isEmpty)
            .help("Show the compressed files in Finder (⇧⌘R)")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.showsOptions) {
                Label("Options", systemImage: "sidebar.right")
            }
            .help("Show or hide the options (⌥⌘I)")
        }
    }
}

/// Shares the selected (or shown) compressed files.
struct ShareButton: View {
    let model: AppModel

    var body: some View {
        let urls = model.shareURLs
        if urls.isEmpty {
            Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }
                .disabled(true)
                .help("Share the compressed files")
        } else {
            ShareLink(items: urls) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share the compressed files")
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
