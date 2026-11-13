import Foundation
@testable import SpecimenCore

/// An in-memory font registry.
final class FakeFontSystem: FontSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var faces: [SystemFace]
    private var detailsByID: [String: FaceDetails]
    private(set) var detailsCalls = 0
    private(set) var enableCalls: [(names: [String], enabled: Bool)] = []
    var dates: [String: Date] = [:]
    /// Faces whose state the "system" refuses to change.
    var stuck: Set<String> = []

    init(_ faces: [SystemFace], details: [String: FaceDetails] = [:]) {
        self.faces = faces
        self.detailsByID = details
    }

    func listFaces() -> [SystemFace] { lock.withLock { faces } }

    func details(for face: SystemFace) -> FaceDetails {
        lock.withLock {
            detailsCalls += 1
            return detailsByID[face.id] ?? FaceDetails()
        }
    }

    func modificationDate(path: String) -> Date? { lock.withLock { dates[path] } }

    func setEnabled(_ targets: [FontFace], enabled: Bool) {
        lock.withLock {
            enableCalls.append((targets.map(\.postScriptName), enabled))
            let ids = Set(targets.map(\.id))
            for index in faces.indices where ids.contains(faces[index].id) && !stuck.contains(faces[index].id) {
                faces[index].isEnabled = enabled
            }
        }
    }
}

func face(_ name: String, family: String, style: String = "Regular", path: String? = nil, enabled: Bool = true,
          weight: Double = 0, italic: Bool = false, category: FontCategory = .sansSerif, variable: Bool = false) -> FontFace {
    FontFace(postScriptName: name, familyName: family, styleName: style,
             path: path ?? "/Users/test/Library/Fonts/\(name).otf", isEnabled: enabled, weight: weight,
             isItalic: italic, isVariable: variable, category: category)
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("specimen-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// An in-memory folder tree of font files.
final class FakeLibraryFileSystem: LibraryFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: (stamp: FileStamp, faces: [SystemFace])] = [:]
    private var directories: Set<String> = []
    private(set) var reads: [String] = []
    private(set) var listings = 0

    /// Adds a font file (and its folders) with one face per PostScript name.
    func add(_ path: String, names: [String]? = nil, modified: Double = 1, family: String? = nil) {
        lock.withLock {
            let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let faces = (names ?? [base]).map {
                SystemFace(postScriptName: $0, familyName: family ?? base, styleName: "Regular", path: path, isEnabled: false)
            }
            files[path] = (FileStamp(path: path, modified: Date(timeIntervalSince1970: modified), size: 100), faces)
            var directory = (path as NSString).deletingLastPathComponent
            while directory.count > 1 { directories.insert(directory); directory = (directory as NSString).deletingLastPathComponent }
        }
    }

    func remove(_ path: String) { lock.withLock { _ = files.removeValue(forKey: path) } }

    func removeDirectory(_ path: String) {
        lock.withLock {
            files = files.filter { !LibraryPaths.isInside($0.key, folder: path) }
            directories = directories.filter { $0 != path && !LibraryPaths.isInside($0, folder: path) }
        }
    }

    func touch(_ path: String, modified: Double) {
        lock.withLock {
            guard var file = files[path] else { return }
            file.stamp.modified = Date(timeIntervalSince1970: modified)
            files[path] = file
        }
    }

    func resetCounters() { lock.withLock { reads = []; listings = 0 } }

    func fontFiles(under root: String) -> [FileStamp] {
        lock.withLock {
            listings += 1
            return files.values.map(\.stamp).filter { LibraryPaths.isInside($0.path, folder: root) && !LibraryPaths.isHidden($0.path, below: root) }
                .sorted { $0.path < $1.path }
        }
    }

    func stamp(of path: String) -> FileStamp? { lock.withLock { files[path]?.stamp } }
    func directoryExists(_ path: String) -> Bool { lock.withLock { directories.contains(path) } }

    func readFaces(_ paths: [String]) -> [String: [SystemFace]] {
        lock.withLock {
            reads += paths
            return Dictionary(uniqueKeysWithValues: paths.map { ($0, files[$0]?.faces ?? []) })
        }
    }
}

/// Records registrations; "registers" by remembering paths and scopes.
final class FakeRegistrar: FontRegistrar, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var scopes: [String: RegistrationScope] = [:]
    private(set) var calls: [String] = []
    var failing: Set<String> = []

    func register(_ paths: [String], scope: RegistrationScope) -> [RegistrationError] {
        lock.withLock {
            calls.append("register \(scope.rawValue) \(paths.joined(separator: ","))")
            var errors: [RegistrationError] = []
            for path in paths {
                if failing.contains(path) || scopes[path] != nil {
                    errors.append(RegistrationError(path: path, message: "already registered"))
                } else {
                    scopes[path] = scope
                }
            }
            return errors
        }
    }

    func unregister(_ paths: [String]) -> [RegistrationError] {
        lock.withLock {
            calls.append("unregister \(paths.joined(separator: ","))")
            for path in paths { scopes[path] = nil }
            return []
        }
    }

    func scope(of path: String) -> RegistrationScope? { lock.withLock { scopes[path] } }
}

enum Fixtures {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    static let regular = folder.appendingPathComponent("Silkscreen-Regular.ttf")
    static let bold = folder.appendingPathComponent("Silkscreen-Bold.ttf")
}
