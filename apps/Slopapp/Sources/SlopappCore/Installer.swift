import Foundation

public enum InstallPhase: Sendable, Equatable {
    case downloading(Double)
    case verifying
    case installing
}

/// Why an install or update stopped. Nothing is changed on disk when any of these is thrown.
public enum InstallError: Error, Equatable, Sendable {
    case notInstallable
    case insecureURL
    case requiresNewerMacOS(String)
    case offline
    case downloadFailed(String)
    case notFound
    case checksumMismatch
    case damagedArchive
    case unexpectedContents
    case bundleMismatch
    case versionMismatch(found: String)
    case signature(SignatureRejection)
    case notEnoughSpace
    case notWritable(URL)
    case appWouldNotQuit
    case replaceFailed(String)

    /// One line saying what happened and what to do next (design-system section 5).
    public func message(appName name: String) -> String {
        switch self {
        case .notInstallable:
            "\(name) isn't available to install yet."
        case .insecureURL:
            "\(name)'s download link isn't secure (HTTPS), so it wasn't downloaded."
        case .requiresNewerMacOS(let version):
            "\(name) needs macOS \(version) or later."
        case .offline:
            "Couldn't download \(name). Check your internet connection and try again."
        case .downloadFailed:
            "Couldn't download \(name). Try again in a few minutes."
        case .notFound:
            "\(name)'s download is missing from the server. Check for updates, then try again."
        case .checksumMismatch:
            "The download of \(name) didn't match the catalog's checksum, so it wasn't installed. Try again later."
        case .damagedArchive:
            "The download of \(name) is damaged, so it wasn't installed. Try again later."
        case .unexpectedContents, .bundleMismatch:
            "The download doesn't contain \(name), so nothing was installed. Check for updates, then try again."
        case .versionMismatch(let found):
            "The download is version \(found), not the one the catalog lists, so it wasn't installed. Check for updates, then try again."
        case .signature(let rejection):
            switch rejection {
            case .invalid:
                "\(name)'s code signature is broken or missing, so it wasn't installed. The download may have been tampered with."
            case .wrongIdentifier:
                "\(name)'s code signature belongs to a different app, so it wasn't installed."
            case .wrongTeam, .unsignedNotAllowed:
                "\(name) isn't signed by the Slopapp developer, so it wasn't installed."
            case .teamChanged:
                "This version of \(name) is signed by a different developer than the copy you have, so it wasn't installed."
            }
        case .notEnoughSpace:
            "There isn't enough free space to install \(name). Free up some space and try again."
        case .notWritable(let folder):
            "Slopapp can't write to \(folder.path). Check the folder's permissions, then try again."
        case .appWouldNotQuit:
            "\(name) didn't quit, so it wasn't changed. Quit it yourself, then try again."
        case .replaceFailed:
            "Couldn't put \(name) in place. Your existing copy wasn't changed. Try again."
        }
    }
}

public struct InstallRequest: Sendable, Equatable {
    public var app: FeedApp
    /// The full path of the .app to create or replace.
    public var destination: URL
    /// The copy being replaced, if any (its team ID pins the update's signer).
    public var replacing: InstalledCopy?

    public init(app: FeedApp, destination: URL, replacing: InstalledCopy? = nil) {
        self.app = app
        self.destination = destination
        self.replacing = replacing
    }

    /// Where an install or update of `item` goes: over the copy it replaces when that copy
    /// may be changed, else into the install folder.
    public static func plan(for item: CatalogItem, roots: InstallRoots) -> InstallRequest {
        if let primary = item.primary, primary.location.canModify {
            return InstallRequest(app: item.app, destination: primary.url, replacing: primary)
        }
        let destination = roots.installDirectory.appendingPathComponent("\(item.app.name).app", isDirectory: true)
        return InstallRequest(app: item.app, destination: destination)
    }
}

public struct InstallResult: Sendable, Equatable {
    public var url: URL
    public var verdict: SignatureVerdict
    public var info: BundleInfo
}

/// Download → checksum → unzip → bundle id, version and signature checks → atomic swap.
public struct Installer: Sendable {
    public var downloader: any Downloading
    public var unarchiver: any Unarchiving
    public var files: any FileOperating
    public var signatures: any SignatureChecking
    public var policy: SignaturePolicy
    public var urlPolicy: URLPolicy
    public var system: OperatingSystemVersion
    public var hasher: @Sendable (URL) throws -> String
    public var readInfo: @Sendable (URL) -> BundleInfo?

    public init(
        downloader: any Downloading, unarchiver: any Unarchiving, files: any FileOperating,
        signatures: any SignatureChecking, policy: SignaturePolicy, urlPolicy: URLPolicy,
        system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        hasher: @escaping @Sendable (URL) throws -> String = Checksum.sha256,
        readInfo: @escaping @Sendable (URL) -> BundleInfo? = LocalAppLocator.readInfo
    ) {
        self.downloader = downloader
        self.unarchiver = unarchiver
        self.files = files
        self.signatures = signatures
        self.policy = policy
        self.urlPolicy = urlPolicy
        self.system = system
        self.hasher = hasher
        self.readInfo = readInfo
    }

    /// - Parameter beforeReplace: runs after every check passed, right before the swap
    ///   (the place to quit the running copy). Throwing stops the install untouched.
    public func install(
        _ request: InstallRequest,
        beforeReplace: @Sendable () async throws -> Void = {},
        progress: @escaping @Sendable (InstallPhase) -> Void = { _ in }
    ) async throws -> InstallResult {
        let app = request.app
        guard app.isInstallable, let url = app.downloadUrl, let expectedSHA = app.sha256,
              let bundleID = app.bundleId, let version = app.version
        else { throw InstallError.notInstallable }
        guard urlPolicy.allows(url) else { throw InstallError.insecureURL }
        guard meetsMinimum(app.minimumMacOS, system: system) else {
            throw InstallError.requiresNewerMacOS(app.minimumMacOS ?? "")
        }

        let folder = request.destination.deletingLastPathComponent()
        do { try files.createDirectory(folder) } catch { throw InstallError.notWritable(folder) }
        guard files.isWritable(folder) else { throw InstallError.notWritable(folder) }
        if let free = files.availableSpace(at: folder) {
            let needed = (app.size ?? 0) + (app.installedSize ?? 0) * 2
            if needed > 0, free < needed { throw InstallError.notEnoughSpace }
        }

        let scratch: URL
        do { scratch = try files.scratchDirectory(near: folder) } catch { throw InstallError.notWritable(folder) }
        defer { try? files.remove(scratch) }

        // 1. Download.
        progress(.downloading(0))
        let zip = scratch.appendingPathComponent("download.zip")
        do {
            try await downloader.download(url, to: zip) { progress(.downloading(min(max($0, 0), 1))) }
        } catch let error as NetworkError {
            switch error {
            case .offline: throw InstallError.offline
            case .notFound: throw InstallError.notFound
            case .server(let code): throw InstallError.downloadFailed("HTTP \(code)")
            case .other(let text): throw InstallError.downloadFailed(text)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw InstallError.downloadFailed(String(describing: error))
        }
        try Task.checkCancellation()

        // 2. Checksum: the zip must be byte-for-byte the one the feed describes.
        progress(.verifying)
        guard let actual = try? hasher(zip), actual == expectedSHA else { throw InstallError.checksumMismatch }

        // 3. Unzip and find exactly the app we expect.
        let extracted = scratch.appendingPathComponent("extracted", isDirectory: true)
        do { try await unarchiver.extract(zip, to: extracted) } catch { throw InstallError.damagedArchive }
        let apps = files.contents(of: extracted).filter { $0.pathExtension == "app" }
        guard apps.count == 1, let newApp = apps.first else { throw InstallError.unexpectedContents }
        guard let info = readInfo(newApp) else {
            throw InstallError.unexpectedContents
        }
        guard info.bundleID == bundleID else { throw InstallError.bundleMismatch }
        guard AppVersion(info.version) == AppVersion(version) else { throw InstallError.versionMismatch(found: info.version) }

        // 4. Code signature, pinned to the team of the copy we're replacing.
        let signature = signatures.signature(at: newApp)
        let pinnedTeam = request.replacing?.signature?.verifiedTeamID
        let verdict = policy.evaluate(signature, bundleID: bundleID, installedTeamID: pinnedTeam)
        if case .rejected(let reason) = verdict { throw InstallError.signature(reason) }
        try Task.checkCancellation()

        // 5. Swap atomically: old copy aside, new copy in, old copy removed; roll back on failure.
        try await beforeReplace()
        progress(.installing)
        files.clearQuarantine(newApp)
        let destination = request.destination
        let backup = scratch.appendingPathComponent("previous.app", isDirectory: true)
        let hadOld = files.exists(destination)
        if hadOld {
            do { try files.move(destination, to: backup) } catch { throw InstallError.replaceFailed(String(describing: error)) }
        }
        do {
            try files.move(newApp, to: destination)
        } catch {
            if hadOld { try? files.move(backup, to: destination) }
            throw InstallError.replaceFailed(String(describing: error))
        }
        return InstallResult(url: destination, verdict: verdict, info: info)
    }
}

/// Moves an app (and optionally its settings and data) to the Trash.
public struct Uninstaller: Sendable {
    public var files: any FileOperating
    /// ~/Library (SLOPAPP_LIBRARY_DIR in tests).
    public var library: URL

    public init(files: any FileOperating, library: URL) {
        self.files = files
        self.library = library
    }

    /// Where an app keeps settings and data, by bundle id. Only existing paths are touched.
    public static func dataPaths(bundleID: String, library: URL) -> [URL] {
        [
            library.appendingPathComponent("Application Support/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("Preferences/\(bundleID).plist"),
            library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState", isDirectory: true),
        ]
    }

    public struct Result: Sendable, Equatable {
        /// Original location → where it went in the Trash (for Put Back).
        public var moved: [(from: URL, to: URL)]
        public var removedPreferences: Bool

        public static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.moved.map(\.from) == rhs.moved.map(\.from) && lhs.moved.map(\.to) == rhs.moved.map(\.to)
                && lhs.removedPreferences == rhs.removedPreferences
        }
    }

    public func uninstall(_ copy: InstalledCopy, removeData: Bool) throws -> Result {
        var moved: [(from: URL, to: URL)] = []
        let trashedApp = try files.trash(copy.url)
        moved.append((copy.url, trashedApp))
        var removedPreferences = false
        if removeData {
            for path in Self.dataPaths(bundleID: copy.info.bundleID, library: library) where files.exists(path) {
                if let to = try? files.trash(path) {
                    moved.append((path, to))
                    if path.pathExtension == "plist" { removedPreferences = true }
                }
            }
        }
        return Result(moved: moved, removedPreferences: removedPreferences)
    }

    /// Moves everything back where it was (Undo).
    public func putBack(_ result: Result) throws {
        for item in result.moved.reversed() where !files.exists(item.from) {
            try files.createDirectory(item.from.deletingLastPathComponent())
            try files.move(item.to, to: item.from)
        }
    }
}
