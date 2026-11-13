import AppKit
import CommitCore
import SlopKit
import SwiftUI

/// The first window: open a repository (button, ⌘O or drop a folder) or pick a recent one.
struct WelcomeView: View {
    let app: AppModel
    @State private var selection: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: Spacing.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.xs) {
                    Text("Commit").font(.title.weight(.semibold))
                    Text(AppInfo.current(fallbackName: "Commit").tagline)
                        .foregroundStyle(.secondary)
                }
                gitState
                FolderDropZone(title: "Drop a repository folder") { app.open($0) }
                    .frame(height: 132)
                Button("Clone Repository…") { app.showClone() }
                    .help("Copy a repository from a server (⇧⌘O)")
            }
            .padding(Spacing.xl)
            .frame(width: 300)

            Hairline(axis: .vertical)
                .ignoresSafeArea(.container, edges: .top)

            VStack(alignment: .leading, spacing: 0) {
                Text("Recent Repositories")
                    .font(.headline)
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, Spacing.l)
                    .padding(.bottom, Spacing.s)
                if app.recents.paths.isEmpty {
                    ContentUnavailableView {
                        Label("No Recent Repositories", systemImage: "clock")
                    } description: {
                        Text("Repositories you open show up here.")
                    } actions: {
                        Button("Open…") { app.chooseRepository() }
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(app.recents.paths, id: \.self) { path in
                            RecentRow(path: path).tag(path)
                        }
                    }
                    .listStyle(.inset)
                    .contextMenu(forSelectionType: String.self) { paths in
                        if let path = paths.first {
                            Button("Open") { app.open(URL(fileURLWithPath: path)) }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                            Divider()
                            Button("Remove from Recents") { app.forgetRecent(path) }
                        }
                    } primaryAction: { paths in
                        if let path = paths.first { app.open(URL(fileURLWithPath: path)) }
                    }
                    .accessibilityLabel("Recent repositories")
                    HStack {
                        Button("Open…") { app.chooseRepository() }
                        Spacer()
                        Button("Open") {
                            if let selection { app.open(URL(fileURLWithPath: selection)) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selection == nil)
                    }
                    .padding(Spacing.m)
                }
            }
            .frame(width: 340)
        }
        .frame(height: 400)
        .onAppear {
            app.windowsAreAvailable(open: openWindow, dismiss: dismissWindow)
            if selection == nil { selection = app.recents.paths.first }
        }
    }

    @ViewBuilder
    private var gitState: some View {
        switch app.installation {
        case nil:
            if app.isReady { EmptyView() } else {
                ProgressView().controlSize(.small).accessibilityLabel("Looking for Git")
            }
        case .found:
            EmptyView()
        default:
            VStack(spacing: Spacing.s) {
                Label(GitMissingView.message(app.installation), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.textOrange)
                    .fixedSize(horizontal: false, vertical: true)
                if case .missing = app.installation {
                    Button("Install Command Line Tools…") { app.installCommandLineTools() }
                }
            }
        }
    }
}

struct RecentRow: View {
    let path: String

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: path)
        HStack(spacing: Spacing.s) {
            Image(systemName: exists ? "folder" : "questionmark.folder")
                .foregroundStyle(exists ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent).lineLimit(1)
                Text(exists ? RecentRow.display(path) : "Missing: \(RecentRow.display(path))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .help(path)
    }

    /// ~/Projects/x, and /tmp rather than /private/tmp.
    static func display(_ path: String) -> String {
        let shown = path.hasPrefix("/private/tmp/") ? String(path.dropFirst("/private".count)) : path
        return (shown as NSString).abbreviatingWithTildeInPath
    }
}
