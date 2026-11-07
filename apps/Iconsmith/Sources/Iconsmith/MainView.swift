import IconsmithCore
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// The window, laid out like the classic icon maker: the big icon on the left with its
/// buttons underneath, the template gallery down the right side, and Create / Restore tabs
/// along the bottom.
struct MainView: View {
    @Bindable var model: AppModel

    /// What the empty drop zone accepts: pictures, plus apps and folders (their icon is used).
    static let sourceTypes: [UTType] = [.image, .pdf, .application, .folder]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    switch model.mode {
                    case .create: CreateView(model: model)
                    case .restore: RestoreView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.mode == .create {
                    Hairline(axis: .vertical)
                    TemplateGallery(model: model)
                        .frame(width: 168)
                }
            }
            .frame(maxHeight: .infinity)
            if let summary = model.resultSummary {
                Hairline()
                ResultsList(model: model, summary: summary)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, Spacing.s - HairlineGap.unusedHalf)
                    .padding(.bottom, Spacing.s)
            }
            Hairline()
            ModeBar(model: model)
        }
        .frame(minWidth: 700, minHeight: 640)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isBatch {
                    BatchPicker(model: model)
                }
                Button { model.chooseImage() } label: {
                    Label("Open Image…", systemImage: "photo.badge.plus")
                }
                .help("Choose one or more pictures to make icons from (⌘O)")
            }
        }
        .alert(model.error?.title ?? "", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
               presenting: model.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(report.message)
        }
        .alert("Change the icon of \(model.pendingApps?.names ?? "this app")?",
               isPresented: Binding(get: { model.pendingApps != nil }, set: { if !$0 { model.pendingApps = nil } }),
               presenting: model.pendingApps) { pending in
            Button("Change Icon") { model.confirmApps(pending) }
            if pending.fromDrop {
                Button("Use Its Icon as the Picture") { model.useAppIcon(pending) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The new icon is stored inside the app. Updating the app usually brings its own icon back, and macOS may ask you to allow Iconsmith under App Management. ⌘Z undoes it.")
        }
        .onAppear {
            if let scale = NSScreen.main?.backingScaleFactor { model.backingScale = scale }
            model.scheduleRender()
        }
    }

    private var subtitle: String {
        guard let source = model.source else { return "" }
        return model.isBatch ? "\(source.name) (\(model.index + 1) of \(model.sources.count))" : source.name
    }
}

/// Create / Restore, like tabs along the bottom of the window.
struct ModeBar: View {
    @Bindable var model: AppModel

    var body: some View {
        // Equal flexible sides keep the tabs centred; the leading side shows the last export,
        // like a status bar, so the result never pushes the icon around.
        HStack(spacing: Spacing.m) {
            ZStack(alignment: .leading) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    .accessibilityHidden(true)
                if model.mode == .create, let status = model.exportStatus {
                    ExportStatusLine(model: model, status: status)
                        .transition(.opacity)
                }
            }
            Picker("Mode", selection: $model.mode) {
                Text("Create").tag(Mode.create)
                Text("Restore").tag(Mode.restore)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .fixedSize()
            .help("Create icons from a picture, or restore files’ and folders’ standard icons")
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.m - HairlineGap.unusedHalf)
        .padding(.bottom, Spacing.m)
        .animation(.easeOut(duration: 0.15), value: model.exportStatus)
    }
}

/// The batch: which picture is showing (the template applies to all of them).
struct BatchPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            Picker("Picture", selection: Binding(get: { model.index }, set: { model.select($0) })) {
                ForEach(Array(model.sources.enumerated()), id: \.offset) { index, source in
                    Text(source.url?.lastPathComponent ?? source.name).tag(index)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("\(model.index + 1) of \(model.sources.count)", systemImage: "square.stack")
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
        }
        .help("\(model.sources.count) pictures loaded. Pick one to preview it; Export can save all of them.")
        .accessibilityLabel("Pictures")
        .accessibilityValue("\(model.index + 1) of \(model.sources.count)")
    }
}

/// SlopKit's `Hairline` takes 1 pt of layout and draws one device pixel along its top edge,
/// so on a Retina display the half point under the pixel reads as extra gap. Content right
/// below a hairline gives that half point back, so the gaps above and below the line match
/// (measured: bottom bar 12.5 / 12 → 12 / 12 pt).
enum HairlineGap {
    static let unusedHalf: CGFloat = 0.5
}
