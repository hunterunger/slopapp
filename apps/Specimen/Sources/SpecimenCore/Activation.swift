import Foundation

/// Why a face can't be turned on or off from Specimen.
public enum LockReason: Equatable, Sendable {
    /// Ships with macOS. Protected; apps and macOS itself rely on it.
    case system
    /// Installed for all users in /Library/Fonts. Changing it can need an administrator.
    case computer
    /// Test mode: only fonts in the test folder may change.
    case testMode
    /// The file is gone (moved, deleted, or on a disconnected disk).
    case missingFile
    /// Another copy with the same PostScript name is protected. macOS turns fonts off by
    /// name, so turning this one off would turn that one off too.
    case sharedName

    public var title: String {
        switch self {
        case .system: "macOS font"
        case .computer: "Installed for all users"
        case .testMode: "Locked in test mode"
        case .missingFile: "File missing"
        case .sharedName: "Shares a name with a protected font"
        }
    }

    /// One sentence for tooltips and refusals.
    public var explanation: String {
        switch self {
        case .system: "macOS needs this font, so it can't be turned off."
        case .computer: "This font is installed for all users of this Mac. Turn it on or off in Font Book, which can ask for an administrator."
        case .testMode: "In test mode, only fonts in the test folder can be turned on or off."
        case .missingFile: "The font file is missing. It may have been moved, deleted, or be on a disconnected disk."
        case .sharedName: "Another copy of this font belongs to macOS or all users. macOS turns fonts off by name, so turning this one off would turn that one off too."
        }
    }
}

/// Turning faces on can clash: only one copy of a PostScript name can be active.
public struct ActivationConflict: Equatable, Sendable {
    /// The face the user wants on.
    public var face: FontFace
    /// The copy that's on now.
    public var activeCopy: FontFace
    /// Set when the active copy can't be turned off, so there's no swap.
    public var activeCopyLock: LockReason?
}

public struct ActivationPlan: Equatable, Sendable {
    public var enable: Bool
    /// Faces that will change.
    public var changes: [FontFace] = []
    public var alreadyDone: [FontFace] = []
    public var locked: [FontFace] = []
    public var lockReasons: [LockReason] = []
    public var conflicts: [ActivationConflict] = []

    public var isEmpty: Bool { changes.isEmpty && conflicts.isEmpty }
    /// Faces to turn off first if the user accepts the swap.
    public var swapOffs: [FontFace] { conflicts.filter { $0.activeCopyLock == nil }.map(\.activeCopy) }
    public var swapOns: [FontFace] { conflicts.filter { $0.activeCopyLock == nil }.map(\.face) }

    /// Above this many faces, ask first: lots of active fonts slow every app's font menu.
    public static let confirmationThreshold = 100
    public var needsConfirmation: Bool { enable && changes.count > ActivationPlan.confirmationThreshold }
}

public enum ActivationPlanner {
    public static func lockReason(for face: FontFace, testRoot: URL?, fileExists: (String) -> Bool) -> LockReason? {
        if let testRoot {
            let root = testRoot.standardizedFileURL.path + "/"
            guard let path = face.path, path.hasPrefix(root) || ("/private" + path).hasPrefix(root)
                || path.hasPrefix("/private" + root) else { return .testMode }
        }
        switch face.location {
        case .system: return .system
        case .computer: return .computer
        case .user, .other: break
        }
        guard let path = face.path, fileExists(path) else { return .missingFile }
        return nil
    }

    /// What turning `targets` on (or off) would do, given every face in the library.
    public static func plan(targets: [FontFace], enable: Bool, library: [FontFace], testRoot: URL?,
                            fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> ActivationPlan {
        var plan = ActivationPlan(enable: enable)
        var activeByName: [String: FontFace] = [:]
        for face in library where face.isEnabled { activeByName[face.postScriptName] = face }
        var seen = Set<String>()
        for face in targets where seen.insert(face.id).inserted {
            if face.isEnabled == enable {
                plan.alreadyDone.append(face)
                continue
            }
            if let reason = lockReason(for: face, testRoot: testRoot, fileExists: fileExists) {
                plan.locked.append(face)
                if !plan.lockReasons.contains(reason) { plan.lockReasons.append(reason) }
                continue
            }
            if !enable, library.contains(where: { $0.postScriptName == face.postScriptName && $0.id != face.id
                && lockReason(for: $0, testRoot: testRoot, fileExists: fileExists) != nil }) {
                plan.locked.append(face)
                if !plan.lockReasons.contains(.sharedName) { plan.lockReasons.append(.sharedName) }
                continue
            }
            if enable, let active = activeByName[face.postScriptName], active.id != face.id {
                let lock = lockReason(for: active, testRoot: testRoot, fileExists: fileExists)
                plan.conflicts.append(ActivationConflict(face: face, activeCopy: active, activeCopyLock: lock))
                continue
            }
            if enable { activeByName[face.postScriptName] = face }
            plan.changes.append(face)
        }
        return plan
    }

    /// Faces whose state didn't end up as requested (CoreText has no error return).
    public static func failures(requested: [FontFace], enable: Bool, after library: [FontFace]) -> [FontFace] {
        let states = Dictionary(library.map { ($0.id, $0.isEnabled) }, uniquingKeysWith: { a, _ in a })
        return requested.filter { states[$0.id] != enable }
    }
}
