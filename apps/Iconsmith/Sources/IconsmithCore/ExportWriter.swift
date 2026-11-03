import Foundation

/// Where replaced exports go. The real Trash in the app; a folder in tests and scripted
/// runs (`ICONSMITH_TRASH_DIR`).
public protocol TrashCan: Sendable {
    func trash(_ url: URL) throws
}

public struct SystemTrash: TrashCan {
    public init() {}
    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

public struct FolderTrash: TrashCan {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }

    public func trash(_ url: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appending(path: url.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appending(path: "\(url.deletingPathExtension().lastPathComponent) \(n)")
                .appendingPathExtension(url.pathExtension)
            n += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
    }
}

public enum Trash {
    /// The trash the app uses: the real one unless `ICONSMITH_TRASH_DIR` points elsewhere.
    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> TrashCan {
        if let path = environment["ICONSMITH_TRASH_DIR"], !path.isEmpty {
            return FolderTrash(folder: URL(fileURLWithPath: path))
        }
        return SystemTrash()
    }
}

/// Writes an export plan. Everything is built in a staging folder on the destination's
/// volume and moved into place at the end, so a failure never leaves half an export.
public struct ExportWriter: Sendable {
    public let trash: TrashCan

    public init(trash: TrashCan = SystemTrash()) {
        self.trash = trash
    }

    /// Writes `plan` as `destination` (a file or folder depending on the format). An
    /// existing item there goes to the Trash first: the save panel already asked.
    @discardableResult
    public func write(_ plan: ExportPlan, format: ExportFormat, to destination: URL) throws -> URL {
        let fm = FileManager.default
        let destination = Self.withExtension(destination, format: format)
        let parent = destination.deletingLastPathComponent()
        let staging: URL
        do {
            staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: parent, create: true)
        } catch {
            staging = fm.temporaryDirectory.appending(path: "iconsmith-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: staging) }

        let staged = staging.appending(path: destination.lastPathComponent)
        do {
            switch format {
            case .icns:
                let iconset = staging.appending(path: "icon.iconset")
                try writeFiles(plan.files, into: iconset)
                try Self.compileICNS(iconset: iconset, output: staged)
            case .png, .ico:
                guard let file = plan.files.first else { throw ExportError.renderFailed }
                try file.data.write(to: staged)
            case .iconset, .xcode, .favicons:
                try writeFiles(plan.files, into: staged)
            }
            if fm.fileExists(atPath: destination.path) {
                try trash.trash(destination)
            }
            try fm.moveItem(at: staged, to: destination)
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.write(Self.describe(error))
        }
        return destination
    }

    private func writeFiles(_ files: [ExportFile], into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: folder.appending(path: file.path))
        }
    }

    /// Keeps the extension a format needs (the save panel lets people type over it).
    public static func withExtension(_ url: URL, format: ExportFormat) -> URL {
        guard let ext = format.pathExtension, url.pathExtension.lowercased() != ext else { return url }
        return url.appendingPathExtension(ext)
    }

    static func compileICNS(iconset: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        do { try process.run() } catch { throw ExportError.iconutil(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ExportError.iconutil(message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError: return "the disk is full. Free some space and try again."
            case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError:
                return "you don’t have permission to save there. Choose another folder."
            default: break
            }
        }
        return nsError.localizedDescription
    }
}
