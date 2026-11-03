import Foundation

/// Crate's preferences. Stored as JSON in UserDefaults by the app.
public struct CrateSettings: Codable, Equatable, Sendable {
    public enum Destination: Codable, Equatable, Sendable {
        case nextToArchive
        case ask
        case folder(String)
    }

    public enum AfterExtracting: String, Codable, CaseIterable, Sendable {
        case keep, trash
    }

    public enum OpenBehavior: String, Codable, CaseIterable, Sendable {
        /// Show the contents first (⌥ extracts right away).
        case browse
        /// Extract right away (⌥ shows the contents).
        case extract
    }

    public var destination: Destination = .nextToArchive
    public var afterExtracting: AfterExtracting = .keep
    public var revealAfterExtracting = false
    public var openBehavior: OpenBehavior = .browse
    public var leaveOutMacFiles = true
    // Remembered choices from the create view.
    public var createFormat: CreateFormat = .zip
    public var compression: CompressionLevel = .normal
    public var zipEncryption: ZipEncryption = .aes256

    public init() {}

    /// Missing keys fall back to defaults, so older saved settings keep working.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CrateSettings()
        destination = (try? c.decode(Destination.self, forKey: .destination)) ?? d.destination
        afterExtracting = (try? c.decode(AfterExtracting.self, forKey: .afterExtracting)) ?? d.afterExtracting
        revealAfterExtracting = (try? c.decode(Bool.self, forKey: .revealAfterExtracting)) ?? d.revealAfterExtracting
        openBehavior = (try? c.decode(OpenBehavior.self, forKey: .openBehavior)) ?? d.openBehavior
        leaveOutMacFiles = (try? c.decode(Bool.self, forKey: .leaveOutMacFiles)) ?? d.leaveOutMacFiles
        createFormat = (try? c.decode(CreateFormat.self, forKey: .createFormat)) ?? d.createFormat
        compression = (try? c.decode(CompressionLevel.self, forKey: .compression)) ?? d.compression
        zipEncryption = (try? c.decode(ZipEncryption.self, forKey: .zipEncryption)) ?? d.zipEncryption
    }

    /// Whether a drop extracts right away, given whether ⌥ is held.
    public func extractsRightAway(optionHeld: Bool) -> Bool {
        (openBehavior == .extract) != optionHeld
    }

    /// The folder to extract into, or nil when the user must be asked. Never a Trash:
    /// an archive sitting in the Trash extracts into `fallback` (~/Downloads).
    public func extractionFolder(for source: ArchiveSource, isInTrash: (URL) -> Bool = TrashLocation.contains,
                                 fallback: @autoclosure () -> URL = TrashLocation.fallbackFolder) -> URL? {
        switch destination {
        case .nextToArchive: isInTrash(source.folder) ? fallback() : source.folder
        case .ask: nil
        case .folder(let path): URL(fileURLWithPath: path, isDirectory: true)
        }
    }
}

/// Split presets for the create view.
public enum SplitSize: Hashable, Sendable, Identifiable {
    case off
    case megabytes(Int)

    public static let presets: [SplitSize] = [.off, .megabytes(25), .megabytes(100), .megabytes(1000), .megabytes(4095)]

    public var id: String { title }
    public var bytes: Int64? {
        switch self {
        case .off: nil
        case .megabytes(let mb): Int64(mb) * 1_000_000
        }
    }
    public var title: String {
        switch self {
        case .off: "Don't Split"
        case .megabytes(4095): "4 GB (FAT32 drives)"
        case .megabytes(let mb) where mb >= 1000 && mb % 1000 == 0: "\(mb / 1000) GB"
        case .megabytes(let mb): "\(mb) MB"
        }
    }
}
