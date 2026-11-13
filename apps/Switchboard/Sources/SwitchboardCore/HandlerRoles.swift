import Foundation

/// An app as macOS's default-app database knows it.
public struct AppRef: Equatable, Hashable, Sendable {
    public var path: String
    public var bundleID: String?

    public init(path: String, bundleID: String?) {
        self.path = path
        self.bundleID = bundleID
    }
}

/// macOS's "which app opens this" settings. The app uses NSWorkspace; tests and dry runs use
/// an in-memory copy, so nothing here ever changes the Mac's real defaults by accident.
@MainActor
public protocol DefaultAppRegistry: AnyObject {
    func defaultApp(forScheme scheme: String) -> AppRef?
    func defaultApp(forContentType type: String) -> AppRef?
    /// macOS asks the user to confirm scheme changes (http, mailto) with its own dialog.
    func setDefaultApp(_ app: AppRef, forScheme scheme: String) async throws
    func setDefaultApp(_ app: AppRef, forContentType type: String) async throws
}

/// The jobs Switchboard can take on. Each is the user's choice, made in Settings.
public enum HandlerRole: Hashable, Sendable {
    /// http and https links, plus web pages (.html).
    case browser
    /// mailto: links.
    case email
    /// Files of one listed type.
    case fileType(FileType)

    public var schemes: [String] {
        switch self {
        case .browser: ["http", "https"]
        case .email: ["mailto"]
        case .fileType: []
        }
    }

    public var contentTypes: [String] {
        switch self {
        case .browser: ["public.html"]
        case .email: []
        case .fileType(let type): type.typeIdentifiers
        }
    }

    /// The scheme or type that says who holds the role now.
    var probe: (scheme: String?, type: String?) {
        if let scheme = schemes.first { return (scheme, nil) }
        return (nil, contentTypes.first)
    }
}

/// Takes on and hands back roles. Pure apart from the registry it's given.
@MainActor
public struct HandlerRoles {
    public let registry: DefaultAppRegistry
    /// Switchboard itself.
    public let own: AppRef

    public init(registry: DefaultAppRegistry, own: AppRef) {
        self.registry = registry
        self.own = own
    }

    /// Who holds the role now.
    public func holder(of role: HandlerRole) -> AppRef? {
        let probe = role.probe
        if let scheme = probe.scheme { return registry.defaultApp(forScheme: scheme) }
        if let type = probe.type { return registry.defaultApp(forContentType: type) }
        return nil
    }

    public func isOurs(_ app: AppRef?) -> Bool {
        guard let app else { return false }
        if let id = app.bundleID, let ownID = own.bundleID { return id.caseInsensitiveCompare(ownID) == .orderedSame }
        return app.path == own.path
    }

    public func holds(_ role: HandlerRole) -> Bool {
        isOurs(holder(of: role))
    }

    /// Makes Switchboard the app for `role`. Returns the app that had it (to fall back on and
    /// to hand back to), or nil if it was already Switchboard or nobody.
    @discardableResult
    public func become(_ role: HandlerRole) async throws -> AppRef? {
        let previous = holder(of: role)
        try await assign(role, to: own)
        return isOurs(previous) ? nil : previous
    }

    /// Gives `role` to `app`.
    public func handBack(_ role: HandlerRole, to app: AppRef) async throws {
        guard !isOurs(app) else { return }
        try await assign(role, to: app)
    }

    private func assign(_ role: HandlerRole, to app: AppRef) async throws {
        for scheme in role.schemes { try await registry.setDefaultApp(app, forScheme: scheme) }
        for type in role.contentTypes { try await registry.setDefaultApp(app, forContentType: type) }
    }
}

/// An in-memory registry: the dry-run copy of macOS's settings and the tests' fake. Every
/// change is recorded, none reaches the system.
@MainActor
public final class MemoryAppRegistry: DefaultAppRegistry {
    public var schemes: [String: AppRef]
    public var types: [String: AppRef]
    /// "mailto → /Applications/Switchboard.app", in order.
    public private(set) var changes: [String] = []
    public var onChange: ((String) -> Void)?

    public init(schemes: [String: AppRef] = [:], types: [String: AppRef] = [:]) {
        self.schemes = schemes
        self.types = types
    }

    public func defaultApp(forScheme scheme: String) -> AppRef? { schemes[scheme.lowercased()] }
    public func defaultApp(forContentType type: String) -> AppRef? { types[type] }

    public func setDefaultApp(_ app: AppRef, forScheme scheme: String) async throws {
        schemes[scheme.lowercased()] = app
        record("\(scheme) → \(app.path)")
    }

    public func setDefaultApp(_ app: AppRef, forContentType type: String) async throws {
        types[type] = app
        record("\(type) → \(app.path)")
    }

    private func record(_ change: String) {
        changes.append(change)
        onChange?(change)
    }
}
