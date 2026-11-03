import Foundation
import Observation
import PaperCore
import SlopKit

/// The app's saved signatures, in Application Support (or `PAPER_DATA_DIR` for tests).
@Observable
@MainActor
final class SignatureLibraryStore {
    static let shared = SignatureLibraryStore()
    private var library: SignatureLibrary

    private init() {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["PAPER_DATA_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = (try? AppPaths.applicationSupport) ?? FileManager.default.temporaryDirectory
        }
        library = SignatureLibrary(store: FileSignatureStore(url: directory.appendingPathComponent("signatures.json")))
    }

    var signatures: [Signature] { library.signatures }

    func add(_ signature: Signature) {
        try? library.add(signature)
    }

    func remove(id: UUID) {
        try? library.remove(id: id)
    }
}
