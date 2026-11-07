import Darwin
import Foundation

/// Byte-level splitting and joining in 7-Zip's `.001`, `.002`… convention, which 7-Zip,
/// Keka, The Unarchiver and Crate open as a set. Splitting a zip or 7z keeps it an archive
/// (open any part); splitting any other file needs Join to put it back together.
public enum FileSplitter {
    /// Units for the part-size field.
    public enum Unit: String, CaseIterable, Codable, Sendable, Identifiable {
        case kb = "KB", mb = "MB", gb = "GB"
        public var id: String { rawValue }
        public var bytes: Int64 {
            switch self {
            case .kb: 1000
            case .mb: 1_000_000
            case .gb: 1_000_000_000
            }
        }
    }

    /// The smallest part allowed (smaller sets get absurdly many files).
    public static let minimumPartSize: Int64 = 100_000

    /// Splits `file` into `name.001`, `name.002`… in `folder` (next to it by default). The set
    /// gets a free name ("name 2.001") if parts already exist. Never touches the original.
    public static func split(_ file: URL, partSize: Int64, in folder: URL? = nil,
                             progress: (@Sendable (Double) -> Void)? = nil) throws -> [URL] {
        guard partSize >= minimumPartSize else { throw CrateError.partTooSmall(minimum: minimumPartSize) }
        let folder = folder ?? file.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw CrateError.destinationNotWritable(folder: folder.lastPathComponent)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? -1
        guard size >= 0 else { throw CrateError.unreadableSource(name: file.lastPathComponent) }
        guard size > partSize else { throw CrateError.nothingToSplit(name: file.lastPathComponent) }
        let work = try Naming.makeWorkFolder(in: folder)
        defer { Naming.removeWorkFolder(work) }
        let temps = try writeParts(of: file, size: size, partSize: partSize, into: work, progress: progress)
        return try placeParts(temps, setName: file.lastPathComponent, in: folder)
    }

    /// Joins an ordered `.001` set into one file named after the set ("movie.mkv" for
    /// "movie.mkv.001") in `folder`, under a free name. Never touches the parts.
    public static func join(_ parts: [URL], in folder: URL? = nil, progress: (@Sendable (Double) -> Void)? = nil) throws -> URL {
        guard let first = parts.first else { throw CrateError.nothingToArchive }
        guard case .numbered(let base)? = VolumeSet.pattern(of: first.lastPathComponent) else {
            throw CrateError.notASplitSet(name: first.lastPathComponent)
        }
        let folder = folder ?? (TrashLocation.contains(first.deletingLastPathComponent())
            ? TrashLocation.fallbackFolder : first.deletingLastPathComponent())
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw CrateError.destinationNotWritable(folder: folder.lastPathComponent)
        }
        let total = max(1, parts.reduce(Int64(0)) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) })
        if let free = SystemFileSystem().availableCapacity(at: folder), total + (64 << 20) > free {
            throw CrateError.notEnoughSpace(name: base, needed: total, available: free)
        }
        let work = try Naming.makeWorkFolder(in: folder)
        defer { Naming.removeWorkFolder(work) }
        let temp = work.appendingPathComponent("joined")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
            throw CrateError.destinationNotWritable(folder: folder.lastPathComponent)
        }
        let output = try FileHandle(forWritingTo: temp)
        var done: Int64 = 0
        do {
            for part in parts {
                guard let input = try? FileHandle(forReadingFrom: part) else {
                    throw CrateError.missingPart(archive: base, part: part.lastPathComponent)
                }
                defer { try? input.close() }
                while let data = try input.read(upToCount: 4 << 20), !data.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: data)
                    done += Int64(data.count)
                    progress?(min(0.99, Double(done) / Double(total)))
                }
            }
            try output.close()
        } catch let error as CrateError {
            try? output.close()
            throw error
        } catch is CancellationError {
            try? output.close()
            throw CancellationError()
        } catch {
            try? output.close()
            throw CrateError.writeFailed(name: base, detail: error.localizedDescription)
        }
        if let quarantine = SystemFileSystem().quarantine(of: first) {
            SystemFileSystem().setQuarantine(quarantine, on: temp)
        }
        let result = try Naming.moveIntoPlace(temp, named: base, in: folder, isFolder: false)
        progress?(1)
        return result
    }

    /// True for a `.001`-style set (the kind Join can put together).
    public static func isNumberedSet(_ url: URL) -> Bool {
        if case .numbered? = VolumeSet.pattern(of: url.lastPathComponent) { return true }
        return false
    }

    // MARK: Shared with ArchiveCreator

    static func writeParts(of file: URL, size: Int64, partSize: Int64, into work: URL,
                           progress: (@Sendable (Double) -> Void)?) throws -> [URL] {
        let count = Int((size + partSize - 1) / partSize)
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var temps: [URL] = []
        var done: Int64 = 0
        for index in 1...count {
            try Task.checkCancellation()
            let part = work.appendingPathComponent(String(format: "part.%03d", index))
            FileManager.default.createFile(atPath: part.path, contents: nil)
            let output = try FileHandle(forWritingTo: part)
            var remaining = min(partSize, size - Int64(index - 1) * partSize)
            while remaining > 0 {
                let data = try input.read(upToCount: Int(min(remaining, 4 << 20))) ?? Data()
                guard !data.isEmpty else { break }
                try output.write(contentsOf: data)
                remaining -= Int64(data.count)
                done += Int64(data.count)
                progress?(min(0.99, Double(done) / Double(max(size, 1))))
            }
            try output.close()
            temps.append(part)
        }
        return temps
    }

    /// Picks a set name with no existing parts, then moves every part in without replacing.
    /// `avoidingBase`: also skip names whose unsplit file exists (new archives: "x.zip"
    /// beside "x.zip.001" would look like the same thing).
    static func placeParts(_ temps: [URL], setName: String, in folder: URL, avoidingBase: Bool = false) throws -> [URL] {
        var number = 1
        while true {
            let base = Naming.candidate(setName, number: number, isFolder: false)
            let names = (1...temps.count).map { base + String(format: ".%03d", $0) }
            if (avoidingBase || number > 1) && Naming.exists(folder.appendingPathComponent(base))
                || names.contains(where: { Naming.exists(folder.appendingPathComponent($0)) }) {
                number += 1
                continue
            }
            var placed: [URL] = []
            do {
                for (temp, name) in zip(temps, names) {
                    let target = folder.appendingPathComponent(name)
                    try moveExclusive(temp, to: target)
                    placed.append(target)
                }
                return placed
            } catch {
                placed.forEach { try? FileManager.default.removeItem(at: $0) }
                throw error
            }
        }
    }

    private static func moveExclusive(_ from: URL, to: URL) throws {
        let result = from.withUnsafeFileSystemRepresentation { a in
            to.withUnsafeFileSystemRepresentation { b in renamex_np(a!, b!, UInt32(RENAME_EXCL)) }
        }
        if result != 0 { throw CrateError.writeFailed(name: to.lastPathComponent, detail: String(cString: strerror(errno))) }
    }
}
