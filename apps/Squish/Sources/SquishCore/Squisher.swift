import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// How one file ended.
public enum SquishResult: Equatable, Sendable {
    case saved(URL, bytes: Int64)
    /// Nothing written: the result wouldn't have been (meaningfully) smaller.
    case keptOriginal(String)
    /// Nothing written on purpose (GIFs, animations, formats this Mac can't write).
    case skipped(String)
}

/// Compresses one file with the given settings and writes the result safely:
/// never over the original unless asked (and then the original goes to the Trash),
/// never a file that isn't smaller.
public struct Squisher: Sendable {
    public var settings: SquishSettings
    public var files: any FileStore
    public var capabilities: EncoderCapabilities
    public var memory: MemoryBudget
    /// Originals moved to the Trash by Replace Originals. When asked to compress a file that
    /// is one of their stand-ins, Squish starts again from the original instead.
    public var replacements: ReplacementRegistry
    /// Called after an original was replaced (moved to the Trash), so it can be put back.
    public var onReplace: (@Sendable (Replacement) -> Void)?

    /// A result must save at least this fraction, or we keep the original.
    public static let minimumSaving = 0.02

    public init(settings: SquishSettings, files: any FileStore = SystemFileStore.app,
                capabilities: EncoderCapabilities = .system, memory: MemoryBudget = .shared,
                replacements: ReplacementRegistry = ReplacementRegistry(),
                onReplace: (@Sendable (Replacement) -> Void)? = nil) {
        self.settings = settings
        self.files = files
        self.capabilities = capabilities
        self.memory = memory
        self.replacements = replacements
        self.onReplace = onReplace
    }

    public func run(_ input: URL, previousOutput: URL? = nil,
                    progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> SquishResult {
        // A file that replaced its original earlier: the original (in the Trash) is the
        // only true source. Re-encoding the compressed copy would lose quality each time,
        // and trashing it would bury the real original under look-alikes.
        let replaced = replacements.replacement(outputAt: input)
        let source = replaced?.trashed ?? input
        let name = (replaced?.original ?? input).lastPathComponent
        if let replaced {
            // Never fall back to the compressed copy: if the original can't be read, stop.
            let hash: String
            do { hash = try files.sha256(of: replaced.trashed) } catch { throw OutputError.cantReachTrash(name) }
            guard hash == replaced.originalSHA256 else { throw OutputError.originalChanged(name) }
        }
        guard let kind = SquishTypes.kind(of: source) else { throw SquishError.unreadable(name) }
        let before: Int64
        do { before = try files.size(of: source) } catch { throw SquishError.unreadable(name) }
        guard before > 0 else { throw SquishError.empty(name) }

        let cost = MemoryBudget.estimate(for: source, kind: kind, settings: settings, fileBytes: before)
        await memory.acquire(cost)
        let encoded: Encoded
        do {
            try Task.checkCancellation()
            switch kind {
            case .image(let type):
                encoded = try autoreleasepool {
                    try ImageCompressor.compress(source, inputType: type, settings: settings,
                                                 capabilities: capabilities, progress: progress)
                }
            case .pdf:
                progress(0.05)
                encoded = try autoreleasepool { try PDFCompressor.compressNow(source, settings: settings) }
            }
            await memory.release(cost)
        } catch let skip as Skip {
            await memory.release(cost)
            return .skipped(skip.reason)
        } catch {
            await memory.release(cost)
            throw error
        }
        try Task.checkCancellation()

        let after = Int64(encoded.data.count)
        let notSmaller = after >= before
        if notSmaller || Double(after) > Double(before) * (1 - Self.minimumSaving) {
            if let replaced, settings.destination == .replaceOriginal {
                // The stand-in is no better than the original: put the original back.
                try replaced.putBack(files: files)
                replacements.remove(replaced)
                return .keptOriginal("Couldn't make it smaller with these settings, so the original was put back.")
            }
            return .keptOriginal(notSmaller ? "Couldn't make it smaller, so the original was kept."
                                            : "Already as small as it gets, so the original was kept.")
        }
        let url: URL
        if let replaced {
            url = try rewrite(encoded, replacing: replaced, previousOutput: previousOutput)
        } else {
            url = try write(encoded, for: input, previousOutput: previousOutput)
        }
        files.markAsOutput(url)
        if settings.keepFileDates { files.copyDates(from: source, to: url) }
        progress(1)
        return .saved(url, bytes: after)
    }

    /// Writes a new result made from a replaced original.
    func rewrite(_ encoded: Encoded, replacing replaced: Replacement, previousOutput: URL?) throws -> URL {
        guard settings.destination == .replaceOriginal else {
            // Saving copies now: write one beside (or for) the original's name; the stand-in stays.
            return try write(encoded, for: replaced.original, previousOutput: previousOutput)
        }
        let ext = SquishTypes.fileExtension(for: encoded.type, keeping: replaced.original.pathExtension)
        let preferred = OutputPlanner.preferredURL(for: replaced.original, ext: ext, settings: settings)
        if preferred.standardizedFileURL == replaced.output.standardizedFileURL {
            // Same name: replace our own stand-in in place. The original stays in the Trash.
            try files.overwrite(encoded.data, at: replaced.output)
            replacements.update(replaced, to: replaced.withOutput(replaced.output, sha256: Self.sha256(encoded.data)))
            return replaced.output
        }
        // New format, new name: write it, then delete our old stand-in (it's only ever a
        // copy Squish made; the original is safe in the Trash).
        for candidate in OutputPlanner.candidates(for: preferred) {
            do {
                try files.create(encoded.data, at: candidate)
                files.remove(replaced.output)
                replacements.update(replaced, to: replaced.withOutput(candidate, sha256: Self.sha256(encoded.data)))
                return candidate
            } catch OutputError.exists {
                continue
            }
        }
        throw OutputError.tooManyNames(replaced.original.lastPathComponent)
    }

    func write(_ encoded: Encoded, for input: URL, previousOutput: URL?) throws -> URL {
        let ext = SquishTypes.fileExtension(for: encoded.type, keeping: input.pathExtension)
        let preferred = OutputPlanner.preferredURL(for: input, ext: ext, settings: settings)

        switch settings.destination {
        case .replaceOriginal:
            // Write first, then trash the original, then take its name: if anything fails
            // before the trash step, the original hasn't been touched.
            let hash = try files.sha256(of: input)
            let temp = input.deletingLastPathComponent()
                .appendingPathComponent(".\(input.deletingPathExtension().lastPathComponent).squish-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try files.create(encoded.data, at: temp)
            files.copyDates(from: input, to: temp)
            let trashed: URL
            do {
                trashed = try files.trash(input)
            } catch {
                files.remove(temp)
                throw error
            }
            for candidate in OutputPlanner.candidates(for: preferred) {
                do {
                    try files.move(temp, to: candidate)
                    let replacement = Replacement(original: input, trashed: trashed, output: candidate, originalSHA256: hash,
                                                  outputSHA256: Self.sha256(encoded.data))
                    replacements.record(replacement)
                    onReplace?(replacement)
                    return candidate
                } catch OutputError.exists {
                    continue
                }
            }
            throw OutputError.tooManyNames(input.lastPathComponent)
        case .alongside, .folder, .subfolder:
            if case .folder(let folder) = settings.destination, !files.isDirectory(folder) {
                throw OutputError.noFolder(folder.lastPathComponent)
            }
            if case .subfolder = settings.destination {
                try files.createFolder(preferred.deletingLastPathComponent())
            }
            // Processing the same file again replaces our own earlier output.
            if let previous = previousOutput,
               previous.standardizedFileURL != input.standardizedFileURL,
               previous.deletingLastPathComponent().standardizedFileURL == preferred.deletingLastPathComponent().standardizedFileURL,
               previous.pathExtension == ext,
               files.fileExists(previous) {
                try files.overwrite(encoded.data, at: previous)
                return previous
            }
            for candidate in OutputPlanner.candidates(for: preferred) {
                do {
                    try files.create(encoded.data, at: candidate)
                    removeOrphan(previousOutput, keeping: candidate, input: input)
                    return candidate
                } catch OutputError.exists {
                    // A copy Squish made of this file before (it carries our tag): replace
                    // it rather than piling up "photo-small 2.jpg".
                    if candidate.standardizedFileURL != input.standardizedFileURL, files.isMarkedAsOutput(candidate) {
                        try files.overwrite(encoded.data, at: candidate)
                        removeOrphan(previousOutput, keeping: candidate, input: input)
                        return candidate
                    }
                    continue
                }
            }
            throw OutputError.tooManyNames(input.lastPathComponent)
        }
    }

    /// After a format change, this row's earlier copy (e.g. "photo-small.heic" once
    /// "photo-small.jpg" is written) would be left behind. Remove it, but only if Squish
    /// tagged it as its own output.
    private func removeOrphan(_ previous: URL?, keeping current: URL, input: URL) {
        guard let previous,
              previous.standardizedFileURL != current.standardizedFileURL,
              previous.standardizedFileURL != input.standardizedFileURL,
              files.fileExists(previous), files.isMarkedAsOutput(previous) else { return }
        files.remove(previous)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
