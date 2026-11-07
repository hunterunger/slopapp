import AppKit
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ File Types: which archive types open in Crate by double-click. Nothing changes
/// until the user clicks; Crate never asks on its own. `CRATE_DRY_DEFAULTS=1` makes it
/// pretend (for tests), so LaunchServices is never touched.
@MainActor
protocol DefaultApps {
    func handler(for type: UTType) -> URL?
    func makeDefault(_ app: URL, for type: UTType) async throws
}

struct SystemDefaultApps: DefaultApps {
    func handler(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func makeDefault(_ app: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
    }
}

/// Records instead of changing anything.
@MainActor
final class DryRunDefaultApps: DefaultApps {
    private var chosen: [String: URL] = [:]
    func handler(for type: UTType) -> URL? {
        chosen[type.identifier] ?? NSWorkspace.shared.urlForApplication(toOpen: type)
    }
    func makeDefault(_ app: URL, for type: UTType) async throws {
        chosen[type.identifier] = app
    }
}

enum ArchiveFileTypes {
    struct Entry: Identifiable {
        let title: String
        let type: UTType
        var id: String { type.identifier }
    }

    static let all: [Entry] = [
        ("Zip", "public.zip-archive"), ("7z", "org.7-zip.7-zip-archive"), ("RAR", "public.rar-archive"),
        ("Tar", "public.tar-archive"), ("Tar.gz", "org.gnu.gnu-zip-tar-archive"), ("Gzip", "org.gnu.gnu-zip-archive"),
        ("Bzip2", "public.bzip2-archive"), ("Tar.bz2", "public.tar-bzip2-archive"), ("Xz", "org.tukaani.xz-archive"),
        ("Tar.xz", "org.tukaani.tar-xz-archive"), ("cpio", "public.cpio-archive"), ("xar", "com.apple.xar-archive"),
        ("Cabinet", "com.microsoft.cab"),
    ].compactMap { title, identifier in UTType(identifier).map { Entry(title: title, type: $0) } }
}

@MainActor
@Observable
final class FileTypesModel {
    let apps: any DefaultApps
    let crate = Bundle.main.bundleURL
    private(set) var handlers: [String: URL] = [:]
    var problem: String?

    init(apps: any DefaultApps = ProcessInfo.processInfo.environment["CRATE_DRY_DEFAULTS"] == "1"
            ? DryRunDefaultApps() : SystemDefaultApps()) {
        self.apps = apps
        refresh()
    }

    var isDryRun: Bool { apps is DryRunDefaultApps }

    func refresh() {
        handlers = Dictionary(uniqueKeysWithValues: ArchiveFileTypes.all.compactMap { entry in
            apps.handler(for: entry.type).map { (entry.id, $0) }
        })
    }

    func isCrate(_ entry: ArchiveFileTypes.Entry) -> Bool {
        handlers[entry.id].map { $0.standardizedFileURL == crate.standardizedFileURL || Bundle(url: $0)?.bundleIdentifier == Bundle.main.bundleIdentifier } ?? false
    }

    func handlerName(_ entry: ArchiveFileTypes.Entry) -> String {
        guard let url = handlers[entry.id] else { return "None" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func makeDefault(_ entries: [ArchiveFileTypes.Entry]) {
        Task {
            for entry in entries where !isCrate(entry) {
                do {
                    try await apps.makeDefault(crate, for: entry.type)
                } catch {
                    problem = "Couldn't make Crate the default for \(entry.title) files."
                }
            }
            refresh()
        }
    }
}

struct FileTypesSheet: View {
    @State private var model = FileTypesModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Open Archives with Crate")
                .font(.headline)
            Text("Choose the types that open in Crate when you double-click them. To change one back, use Get Info in Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isDryRun {
                Label("Test mode: nothing is changed.", systemImage: "testtube.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List(ArchiveFileTypes.all) { entry in
                HStack {
                    Text(entry.title)
                    Spacer()
                    if model.isCrate(entry) {
                        Label("Crate", systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Opens in Crate")
                    } else {
                        Text(model.handlerName(entry))
                            .foregroundStyle(.secondary)
                        Button("Use Crate") { model.makeDefault([entry]) }
                            .accessibilityLabel("Use Crate for \(entry.title)")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 260)
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.textOrange).font(.callout)
            }
            HStack {
                Button("Use Crate for All") { model.makeDefault(ArchiveFileTypes.all) }
                    .disabled(ArchiveFileTypes.all.allSatisfy(model.isCrate))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 420)
    }
}
