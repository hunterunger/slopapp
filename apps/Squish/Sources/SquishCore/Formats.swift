import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What this Mac's ImageIO can write. Injected so tests can pretend (e.g. that WebP is
/// writable), and so a future macOS that can write WebP gets it with no code change.
public struct EncoderCapabilities: Sendable, Equatable {
    public let writableTypes: Set<String>

    public init(writableTypes: Set<String>) {
        self.writableTypes = writableTypes
    }

    public static let system = EncoderCapabilities(
        writableTypes: Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    )

    public func canWrite(_ type: UTType) -> Bool {
        writableTypes.contains(type.identifier)
    }

    /// The format choices worth showing on this Mac.
    public var formatChoices: [OutputFormat] {
        OutputFormat.allCases.filter { format in
            guard let type = format.type else { return true }
            return canWrite(type)
        }
    }
}

/// The kinds of file Squish takes.
public enum InputKind: Equatable, Sendable {
    case image(UTType)
    case pdf
}

public enum SquishTypes {
    /// What the drop zone and file chooser accept.
    public static let accepted: [UTType] = [.image, .pdf]

    public static func kind(of url: URL) -> InputKind? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image(type) }
        return nil
    }

    /// Preferred file extension for a type we write: "jpg", not "jpeg".
    public static func fileExtension(for type: UTType, keeping original: String) -> String {
        // Keep the user's spelling when the type doesn't change ("JPEG", "jpeg", "heif").
        if let originalType = UTType(filenameExtension: original), originalType == type {
            return original
        }
        switch type {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        default: return type.preferredFilenameExtension ?? "img"
        }
    }
}
