import Foundation

/// An archive on disk: one file, or the ordered parts of a split set.
public struct ArchiveSource: Sendable, Hashable {
    /// Every part in reading order (one URL for ordinary archives).
    public let parts: [URL]
    /// The file that stands for the set: the one dropped for single files, the first part
    /// otherwise (the `.zip` for `.z01` sets).
    public let displayURL: URL

    public init(parts: [URL], displayURL: URL? = nil) {
        precondition(!parts.isEmpty)
        self.parts = parts
        self.displayURL = displayURL ?? parts[0]
    }

    public init(file: URL) {
        self.init(parts: [file])
    }

    public var isMultiPart: Bool { parts.count > 1 }
    /// "photos.zip", or "photos.7z (3 parts)".
    public var name: String {
        isMultiPart ? "\(displayURL.lastPathComponent) (\(parts.count) parts)" : displayURL.lastPathComponent
    }
    public var fileName: String { displayURL.lastPathComponent }
    /// What the contents are called: "photos" for "photos.tar.gz" or "photos.7z.001".
    public var baseName: String { ArchiveTypes.baseName(of: displayURL.lastPathComponent) }
    /// The folder the archive sits in.
    public var folder: URL { displayURL.deletingLastPathComponent() }
    /// A key that's the same for every part of one set.
    public var identity: String { parts[0].standardizedFileURL.path }
}

/// Finds the other parts of a split archive, whichever part was dropped.
///
/// Supported: `name.7z.001`… (any `.NNN`), `name.partN.rar`, `name.rar` + `name.r00`…,
/// `name.z01`… + `name.zip`. A gap in the numbering is reported as the missing part.
public enum VolumeSet {
    enum Pattern: Equatable {
        case numbered(base: String)            // base.001, base.002…
        case rarPart(base: String, width: Int) // base.part01.rar…
        case rarOld(base: String)              // base.rar, base.r00…
        case zipSpan(base: String)             // base.z01…, base.zip
    }

    static func pattern(of name: String) -> Pattern? {
        let ns = name as NSString
        let ext = ns.pathExtension
        let lower = ext.lowercased()
        let stem = ns.deletingPathExtension
        if ext.count == 3, ext.allSatisfy(\.isASCIIDigit) {
            return .numbered(base: stem)
        }
        if lower == "rar" {
            let stemNS = stem as NSString
            let partExt = stemNS.pathExtension
            if partExt.lowercased().hasPrefix("part") {
                let digits = partExt.dropFirst(4)
                if !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) {
                    return .rarPart(base: stemNS.deletingPathExtension, width: digits.count)
                }
            }
            return .rarOld(base: stem)
        }
        if lower.count == 3, lower.first == "r", lower.dropFirst().allSatisfy(\.isASCIIDigit) {
            return .rarOld(base: stem)
        }
        if lower == "zip" { return .zipSpan(base: stem) }
        if lower.count == 3, lower.first == "z", lower.dropFirst().allSatisfy(\.isASCIIDigit), lower != "z00" {
            return .zipSpan(base: stem)
        }
        return nil
    }

    /// True for names that can only be a part of a split set (`.001`, `.r00`, `.z01`,
    /// `.part2.rar`). A plain `.rar` or `.zip` isn't counted here.
    public static func isPartName(_ name: String) -> Bool {
        let lower = (name as NSString).pathExtension.lowercased()
        switch pattern(of: name) {
        case .numbered: return true
        case .rarPart: return true
        case .rarOld: return lower != "rar"
        case .zipSpan: return lower != "zip"
        case nil: return false
        }
    }

    /// The set's name without part numbering ("big.7z" for "big.7z.001", "movie.rar" for
    /// "movie.part1.rar"), or nil when the name isn't a part name.
    static func setBaseName(of name: String) -> String? {
        let lower = (name as NSString).pathExtension.lowercased()
        switch pattern(of: name) {
        case .numbered(let base): return base
        case .rarPart(let base, _): return base + ".rar"
        case .rarOld(let base): return lower == "rar" ? nil : base + ".rar"
        case .zipSpan(let base): return lower == "zip" ? nil : base + ".zip"
        case nil: return nil
        }
    }

    /// Resolves `file` to its whole set, using the names in its folder.
    public static func resolve(_ file: URL, fileManager: FileManager = .default) throws -> ArchiveSource {
        let folder = file.deletingLastPathComponent()
        let siblings = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return try resolve(name: file.lastPathComponent, in: folder, siblings: Set(siblings))
    }

    /// Pure version of `resolve`: `siblings` are the file names in `folder`.
    public static func resolve(name: String, in folder: URL, siblings: Set<String>) throws -> ArchiveSource {
        let single = ArchiveSource(file: folder.appendingPathComponent(name))
        guard let pattern = pattern(of: name) else { return single }
        // Case-insensitive lookup that returns the real sibling name.
        var byLower: [String: String] = [:]
        for sibling in siblings { byLower[sibling.lowercased()] = sibling }
        func url(_ n: String) -> URL { folder.appendingPathComponent(n) }
        func missing(_ part: String) -> CrateError {
            .missingPart(archive: setBaseName(of: name) ?? name, part: part)
        }

        switch pattern {
        case .numbered(let base):
            var names: [String] = []
            var index = 1
            while let found = byLower[(base + "." + String(format: "%03d", index)).lowercased()] {
                names.append(found)
                index += 1
            }
            // Parts beyond a gap mean the gap is missing.
            let higher = siblings.compactMap { sibling -> Int? in
                let ns = sibling as NSString
                guard ns.deletingPathExtension.lowercased() == base.lowercased() else { return nil }
                let ext = ns.pathExtension
                guard ext.count == 3, ext.allSatisfy(\.isASCIIDigit) else { return nil }
                return Int(ext)
            }.max() ?? 0
            if names.count < higher || names.isEmpty {
                throw missing(base + "." + String(format: "%03d", names.count + 1))
            }
            if names.count == 1 { return ArchiveSource(file: url(names[0])) }
            return ArchiveSource(parts: names.map(url))

        case .rarPart(let base, let width):
            let prefix = (base + ".part").lowercased()
            let numbers = siblings.compactMap { sibling -> Int? in
                let lower = sibling.lowercased()
                guard lower.hasPrefix(prefix), lower.hasSuffix(".rar") else { return nil }
                let digits = lower.dropFirst(prefix.count).dropLast(4)
                guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
                return Int(digits)
            }
            let highest = max(numbers.max() ?? 1, 1)
            var names: [String] = []
            for number in 1...highest {
                let padded = String(format: "%0\(width)d", number)
                let candidates = [padded, String(number)].map { "\(base).part\($0).rar".lowercased() }
                guard let found = candidates.lazy.compactMap({ byLower[$0] }).first else {
                    throw missing("\(base).part\(padded).rar")
                }
                names.append(found)
            }
            return ArchiveSource(parts: names.map(url))

        case .rarOld(let base):
            guard let first = byLower[(base + ".rar").lowercased()] else { throw missing(base + ".rar") }
            var names = [first]
            let numbers = siblings.compactMap { sibling -> Int? in
                let ns = sibling as NSString
                let ext = ns.pathExtension.lowercased()
                guard ns.deletingPathExtension.lowercased() == base.lowercased(), ext.count == 3, ext.first == "r",
                      ext.dropFirst().allSatisfy(\.isASCIIDigit) else { return nil }
                return Int(ext.dropFirst())
            }
            if let highest = numbers.max() {
                for number in 0...highest {
                    let part = base + ".r" + String(format: "%02d", number)
                    guard let found = byLower[part.lowercased()] else { throw missing(part) }
                    names.append(found)
                }
            }
            if names.count == 1 { return ArchiveSource(file: url(first)) }
            return ArchiveSource(parts: names.map(url))

        case .zipSpan(let base):
            let numbers = siblings.compactMap { sibling -> Int? in
                let ns = sibling as NSString
                let ext = ns.pathExtension.lowercased()
                guard ns.deletingPathExtension.lowercased() == base.lowercased(), ext.count == 3, ext.first == "z",
                      ext.dropFirst().allSatisfy(\.isASCIIDigit) else { return nil }
                return Int(ext.dropFirst())
            }.filter { $0 > 0 }
            guard let highest = numbers.max() else {
                // A plain zip with no spanned parts.
                if let zip = byLower[(base + ".zip").lowercased()] { return ArchiveSource(file: url(zip)) }
                throw missing(base + ".zip")
            }
            var names: [String] = []
            for number in 1...highest {
                let part = base + ".z" + String(format: "%02d", number)
                guard let found = byLower[part.lowercased()] else { throw missing(part) }
                names.append(found)
            }
            guard let zip = byLower[(base + ".zip").lowercased()] else { throw missing(base + ".zip") }
            names.append(zip)
            return ArchiveSource(parts: names.map(url), displayURL: url(zip))
        }
    }
}

extension Character {
    /// 0-9 only (not other scripts' digits).
    var isASCIIDigit: Bool { isASCII && isNumber }
}
