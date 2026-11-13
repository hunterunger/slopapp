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
    /// Activate Temporarily on an installed font: it's installed, so it's on or off for good.
    case notTemporary
    /// Another copy with this PostScript name is on, and the two are switched differently
    /// (one installed, one in a library folder), so Specimen can't swap them safely.
    case otherCopyActive

    public var title: String {
        switch self {
        case .system: "macOS font"
        case .computer: "Installed for all users"
        case .testMode: "Locked in test mode"
        case .missingFile: "File missing"
        case .sharedName: "Shares a name with a protected font"
        case .notTemporary: "Installed font"
        case .otherCopyActive: "Another copy is active"
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
        case .notTemporary: "Only fonts in your library folders can be activated temporarily. Installed fonts are turned on or off for good."
        case .otherCopyActive: "Another copy of this font is active from a different place. Only one copy of a font can be active: deactivate that copy first."
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
    /// Activate for this session only (ends when Specimen quits).
    public var temporary = false
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
    /// `temporary`: activate for this session only (library-folder fonts, `inPlace`). A
    /// temporary face activated normally is kept on for good.
    public static func plan(targets: [FontFace], enable: Bool, library: [FontFace], testRoot: URL?,
                            temporary: Bool = false, inPlace: (FontFace) -> Bool = { _ in false },
                            fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> ActivationPlan {
        var plan = ActivationPlan(enable: enable, temporary: enable && temporary)
        var activeByName: [String: FontFace] = [:]
        for face in library where face.isEnabled { activeByName[face.postScriptName] = face }
        var seen = Set<String>()
        for face in targets where seen.insert(face.id).inserted {
            let keepsTemporaryOn = enable && !temporary && face.isEnabled && face.isTemporary
            if face.isEnabled == enable && !keepsTemporaryOn {
                plan.alreadyDone.append(face)
                continue
            }
            if enable, temporary, !inPlace(face) {
                plan.locked.append(face)
                if !plan.lockReasons.contains(.notTemporary) { plan.lockReasons.append(.notTemporary) }
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
                var lock = lockReason(for: active, testRoot: testRoot, fileExists: fileExists)
                // Swapping across mechanisms (switch vs registration) isn't safe: macOS's
                // switch works by name and could catch the other copy too.
                if lock == nil, inPlace(face) != inPlace(active) { lock = .otherCopyActive }
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
