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
