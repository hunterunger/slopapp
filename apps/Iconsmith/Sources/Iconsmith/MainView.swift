import IconsmithCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// The window: a big drop zone until there's a picture, then the editor. The Finder icon
/// wells sit along the bottom either way.
struct MainView: View {
    @Bindable var model: AppModel

    /// What the source drop zone accepts: pictures, plus apps and folders (their icon is used).
    static let sourceTypes: [UTType] = [.image, .pdf, .application, .folder]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.hasSource {
                    EditorView(model: model)
                } else {
                    DropZone("Drop a picture here", systemImage: "photo.on.rectangle.angled", types: Self.sourceTypes,
                             allowsMultiple: false) { model.load($0) }
                        .overlay {
                            if model.isLoading { ProgressView().controlSize(.large) }
                        }
                        .padding(Spacing.windowMargin)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            FinderWell(model: model)
        }
        .frame(minWidth: 740, minHeight: 680)
        .navigationSubtitle(model.source?.name ?? "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.chooseImage() } label: {
                    Label("Open Image…", systemImage: "photo.badge.plus")
                }
                .help("Choose a picture to make an icon from (⌘O)")
                Button { model.export() } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Export \(model.prefs.format.title) (⌘E)")
                .disabled(!model.hasSource)
            }
        }
        .alert(model.error?.title ?? "", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
               presenting: model.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(report.message)
        }
        .onAppear {
            if let scale = NSScreen.main?.backingScaleFactor { model.backingScale = scale }
        }
    }
}

struct EditorView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            PreviewPane(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Inspector(model: model)
                .frame(width: 290)
        }
    }
}
