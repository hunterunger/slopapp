import Foundation

/// Everything that can go wrong, each with a sentence that says what happened and what to
/// do next (design system §5).
public enum CrateError: Error, Equatable, Sendable, LocalizedError {
    case notAnArchive(name: String)
    case passwordRequired(name: String)
    case wrongPassword(name: String)
    /// Encrypted 7z or RAR: the system libarchive can't decrypt them.
    case unsupportedEncryption(name: String, format: String)
    case missingPart(archive: String, part: String)
    case damaged(name: String, detail: String)
    case truncated(name: String)
    /// Unpacks to far more than its size: a likely zip bomb.
    case suspiciousSize(name: String, limit: Int64)
    case notEnoughSpace(name: String, needed: Int64, available: Int64)
    case destinationNotWritable(folder: String)
    case unreadableSource(name: String)
    case passwordNotSupported(format: String)
    case nothingToArchive
    case writeFailed(name: String, detail: String)
    case partTooSmall(minimum: Int64)
    case nothingToSplit(name: String)
    case notASplitSet(name: String)

    public var errorDescription: String? {
        switch self {
        case .notAnArchive(let name):
            "“\(name)” isn't an archive Crate can read."
        case .passwordRequired(let name):
            "“\(name)” needs a password."
        case .wrongPassword(let name):
            "That password didn't open “\(name)”."
        case .unsupportedEncryption(let name, let format):
            "“\(name)” is a password-protected \(format) archive, which Crate can't open yet."
        case .missingPart(let archive, let part) where archive == part:
            "The first part of this archive, “\(part)”, is missing."
        case .missingPart(let archive, let part):
            "“\(archive)” is missing a part: “\(part)”."
        case .damaged(let name, _):
            "“\(name)” is damaged or incomplete."
        case .truncated(let name):
            "“\(name)” ends early. It may still be downloading or be missing its last part."
        case .suspiciousSize(let name, let limit):
            "Stopped unpacking “\(name)”: it grows to more than \(Self.bytes(limit)), far more than its own size."
        case .notEnoughSpace(let name, let needed, let available):
            "There isn't enough space to unpack “\(name)”: it needs \(Self.bytes(needed)) and \(Self.bytes(available)) is free."
        case .destinationNotWritable(let folder):
            "Crate can't save into “\(folder)”."
        case .unreadableSource(let name):
            "Couldn't read “\(name)”."
        case .passwordNotSupported(let format):
            "\(format) archives can't have a password in Crate."
        case .nothingToArchive:
            "There's nothing to put in the archive."
        case .writeFailed(let name, _):
            "Couldn't save “\(name)”."
        case .partTooSmall(let minimum):
            "Parts must be at least \(Self.bytes(minimum))."
        case .nothingToSplit(let name):
            "“\(name)” is already smaller than one part."
        case .notASplitSet(let name):
            "“\(name)” isn't a numbered part (.001, .002…)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notAnArchive:
            "Check that the download finished, or open it in the app that made it."
        case .passwordRequired:
            "Enter the password to unpack it."
        case .wrongPassword:
            "Check the password and try again. Passwords are case-sensitive."
        case .unsupportedEncryption:
            "Try Keka or The Unarchiver, which can open it."
        case .missingPart:
            "Put every part in the same folder, then open it again."
        case .damaged:
            "Try downloading it again."
        case .truncated:
            "Wait for the download to finish, or download it again."
        case .suspiciousSize:
            "This is how zip bombs behave, so nothing was kept. Only unpack it if you trust where it came from, with another tool."
        case .notEnoughSpace:
            "Free up some space or choose another destination, then try again."
        case .destinationNotWritable:
            "Choose another folder in Settings, or move the archive somewhere you can write to."
        case .unreadableSource:
            "It may have been moved or deleted. Nothing was saved."
        case .passwordNotSupported:
            "Choose Zip or 7z to protect it with a password."
        case .nothingToArchive:
            "Add some files or folders, then try again."
        case .partTooSmall:
            "Enter a larger part size."
        case .nothingToSplit:
            "Choose a smaller part size, or keep it as one file."
        case .notASplitSet:
            "Choose the first part of a set made by Crate, 7‑Zip or Keka."
        case .writeFailed(_, let detail):
            Self.plain(detail).map { "\($0). Check that the disk has space, then try again." }
                ?? "Check that the disk has space, then try again."
        }
    }

    /// A short message for a queue row, which already shows the archive's name: no names
    /// repeated, one line, and what to do.
    public var rowMessage: String {
        switch self {
        case .notAnArchive: "Not an archive Crate can read. Check that the download finished."
        case .passwordRequired: "Needs a password. Click Extract Again to enter it."
        case .wrongPassword: "That password didn't work. Click Extract Again to try another."
        case .unsupportedEncryption(_, let format): "A password-protected \(format) archive. Try Keka or The Unarchiver."
        case .missingPart(let archive, let part) where archive == part: "The first part is missing. Put every part in one folder."
        case .missingPart(_, let part): "Part “\(part)” is missing. Put every part in one folder."
        case .damaged: "Damaged or incomplete. Try downloading it again."
        case .truncated: "Ends early. Wait for the download to finish, or download it again."
        case .suspiciousSize: "Stopped: it grows far beyond its size, like a zip bomb. Nothing was kept."
        case .notEnoughSpace(_, let needed, _): "Not enough space: needs \(Self.bytes(needed)). Free up some space and try again."
        case .destinationNotWritable(let folder): "Can't save into “\(folder)”. Choose another folder in Settings."
        case .unreadableSource: "Couldn't read it. It may have been moved or deleted."
        case .passwordNotSupported(let format): "\(format) archives can't have a password. Choose Zip or 7z."
        case .nothingToArchive: "Nothing to put in the archive."
        case .writeFailed: "Couldn't save. Check that the disk has space, then try again."
        case .partTooSmall(let minimum): "Parts must be at least \(Self.bytes(minimum))."
        case .nothingToSplit: "Already smaller than one part."
        case .notASplitSet: "Not a numbered part (.001, .002…)."
        }
    }

    /// True when trying the same archive again can't help (a password, space or a new
    /// download can).
    public var isFinal: Bool {
        switch self {
        case .notAnArchive, .unsupportedEncryption, .damaged, .suspiciousSize: true
        default: false
        }
    }

    /// The whole message, for rows and alerts.
    public var message: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }

    public var isTruncated: Bool {
        if case .truncated = self { return true }
        return false
    }

    /// True for the errors a password can fix.
    public var needsPassword: Bool {
        switch self {
        case .passwordRequired, .wrongPassword: true
        default: false
        }
    }

    /// A system detail worth showing ("No space left on device"), without internal codes.
    static func plain(_ detail: String) -> String? {
        let cleaned = detail.replacingOccurrences(of: #"\s*\(?-?\d+\)?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count < 80, !cleaned.contains("("), !cleaned.lowercased().contains("archive_") else { return nil }
        return cleaned
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
