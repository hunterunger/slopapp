import AppKit
import PDFKit

/// A saved signature: strokes normalized so the drawing's width is 1 and its height is
/// `1 / aspect`, origin bottom-left.
public struct Signature: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case signature, initials }

    public var id: UUID
    public var kind: Kind
    public var created: Date
    public var strokes: [[CGPoint]]
    /// width / height of the ink's bounding box.
    public var aspect: CGFloat

    public init(id: UUID = UUID(), kind: Kind = .signature, created: Date = Date(), strokes: [[CGPoint]], aspect: CGFloat) {
        self.id = id
        self.kind = kind
        self.created = created
        self.strokes = strokes
        self.aspect = aspect
    }

    /// Normalizes raw strokes (any coordinate space, y up). Nil when there's nothing drawn
    /// or the ink is a dot.
    public static func from(strokes raw: [[CGPoint]], kind: Kind = .signature, created: Date = Date()) -> Signature? {
        let points = raw.flatMap { $0 }
        guard points.count >= 2 else { return nil }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let width = maxX - minX, height = max(maxY - minY, 1)
        guard width >= 4 || maxY - minY >= 4 else { return nil }
        let scale = max(width, 1)
        let strokes = raw.filter { !$0.isEmpty }.map { stroke in
            stroke.map { CGPoint(x: ($0.x - minX) / scale, y: ($0.y - minY) / scale) }
        }
        return Signature(kind: kind, created: created, strokes: strokes, aspect: max(width, 1) / height)
    }

    /// Strokes scaled into `rect` (keeps the aspect ratio, centered).
    public func strokes(fitting rect: CGRect) -> [[CGPoint]] {
        let fit = Signature.fitted(aspect: aspect, in: rect)
        let scale = fit.width
        return strokes.map { stroke in stroke.map { CGPoint(x: fit.minX + $0.x * scale, y: fit.minY + $0.y * scale) } }
    }

    public static func fitted(aspect: CGFloat, in rect: CGRect) -> CGRect {
        guard aspect > 0, rect.width > 0, rect.height > 0 else { return rect }
        var width = rect.width, height = rect.width / aspect
        if height > rect.height { height = rect.height; width = height * aspect }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    /// The ink annotation for this signature, `width` points wide, centered on `center`.
    public func annotation(centeredAt center: CGPoint, width: CGFloat, color: NSColor, factory: AnnotationFactory) -> PDFAnnotation? {
        let height = width / max(aspect, 0.1)
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let lineWidth = max(1.2, min(2.5, width / 120))
        guard let ink = factory.ink(strokes(fitting: rect), color: color, lineWidth: lineWidth) else { return nil }
        ink.setValue("paper.signature.\(id.uuidString)", forAnnotationKey: .name)
        return ink
    }

    public static func isSignature(_ annotation: PDFAnnotation) -> Bool {
        (annotation.value(forAnnotationKey: .name) as? String)?.hasPrefix("paper.signature.") ?? false
    }
}

/// Where signatures are kept. The real one is a JSON file in Application Support; tests
/// use the in-memory one. Paper never syncs or uploads signatures.
public protocol SignatureStoring: Sendable {
    func load() throws -> [Signature]
    func save(_ signatures: [Signature]) throws
}

public struct FileSignatureStore: SignatureStoring {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> [Signature] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Signature].self, from: Data(contentsOf: url))
    }

    public func save(_ signatures: [Signature]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Data-protection classes (.completeFileProtection) fail with EPERM on macOS volumes;
        // signatures are private, so make the file owner-only instead.
        try JSONEncoder().encode(signatures).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public final class InMemorySignatureStore: SignatureStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Signature]

    public init(_ signatures: [Signature] = []) { stored = signatures }

    public func load() throws -> [Signature] { lock.withLock { stored } }
    public func save(_ signatures: [Signature]) throws { lock.withLock { stored = signatures } }
}

/// The signature list: newest first, capped so the Sign menu stays short.
public struct SignatureLibrary {
    public static let limit = 6
    public let store: any SignatureStoring
    public private(set) var signatures: [Signature]

    public init(store: any SignatureStoring) {
        self.store = store
        signatures = (try? store.load()) ?? []
    }

    public mutating func add(_ signature: Signature) throws {
        signatures.insert(signature, at: 0)
        if signatures.count > Self.limit { signatures.removeLast(signatures.count - Self.limit) }
        try store.save(signatures)
    }

    public mutating func remove(id: UUID) throws {
        signatures.removeAll { $0.id == id }
        try store.save(signatures)
    }
}
