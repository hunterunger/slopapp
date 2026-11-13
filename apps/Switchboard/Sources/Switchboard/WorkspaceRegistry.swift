import AppKit
import SwitchboardCore
import UniformTypeIdentifiers

/// macOS's real default-app settings. Used only outside dry runs; the only code in the app
/// that changes which app opens links or files, and only when the user asks in Settings.
@MainActor
final class WorkspaceRegistry: DefaultAppRegistry {
    func defaultApp(forScheme scheme: String) -> AppRef? {
        guard let probe = Self.probe(scheme), let url = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return AppRef(path: url.path, bundleID: Bundle(url: url)?.bundleIdentifier)
    }

    func defaultApp(forContentType type: String) -> AppRef? {
        guard let uti = UTType(type), let url = NSWorkspace.shared.urlForApplication(toOpen: uti) else { return nil }
        return AppRef(path: url.path, bundleID: Bundle(url: url)?.bundleIdentifier)
    }

    func setDefaultApp(_ app: AppRef, forScheme scheme: String) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: app.path), toOpenURLsWithScheme: scheme)
    }

    func setDefaultApp(_ app: AppRef, forContentType type: String) async throws {
        guard let uti = UTType(type) else { return }
        try await NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: app.path), toOpen: uti)
    }

    /// A link of this scheme to ask LaunchServices about.
    static func probe(_ scheme: String) -> URL? {
        switch scheme {
        case "http", "https": URL(string: "\(scheme)://example.com")
        case "mailto": URL(string: "mailto:someone@example.com")
        default: URL(string: "\(scheme):")
        }
    }

    /// The dry-run stand-in: starts from the real settings (read, never written), plus the
    /// "already the default browser" state when `SWITCHBOARD_ASSUME_DEFAULT=1`.
    static func dryRunCopy(own: AppRef) -> MemoryAppRegistry {
        let real = WorkspaceRegistry()
        var schemes: [String: AppRef] = [:]
        for scheme in ["http", "https", "mailto"] { schemes[scheme] = real.defaultApp(forScheme: scheme) }
        var types: [String: AppRef] = [:]
        for type in ["public.html"] + FileType.presets.flatMap(\.typeIdentifiers) { types[type] = real.defaultApp(forContentType: type) }
        if Diagnostics.assumesDefault {
            schemes["http"] = own
            schemes["https"] = own
            types["public.html"] = own
        }
        let registry = MemoryAppRegistry(schemes: schemes, types: types)
        registry.onChange = { Diagnostics.record("dry-run set default \($0)") }
        return registry
    }
}
