import ClipsCore
import Foundation
import ImageIO
import Vision

/// Reads the text in an image with Vision, on this Mac (no network). The image is decoded at
/// most 2,400 px on its longer side, which keeps screenshot text legible to Vision and the
/// memory for one image bounded.
///
/// Vision's text models take ~150 MB while they work and keep a good part of it, so this never
/// runs inside Clips: `HelperTextRecognizer` starts a helper (Clips' own binary with
/// `--recognize-text`) that does the work and quits when there's nothing left, and Clips stays
/// at its usual size.
enum VisionText {
    static let maxPixelSize = 2_400

    enum Failure: Error { case unreadableImage, helperFailed }

    static func recognize(_ imageData: Data) throws -> [String] {
        try autoreleasepool {
            guard let image = ImageInfo.thumbnail(of: imageData, maxPixelSize: maxPixelSize) else {
                throw Failure.unreadableImage
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
    }
}

/// What the helper answers for one image.
struct TextHelperReply: Codable {
    /// The lines found; nil when the image couldn't be read.
    var lines: [String]?
    /// The clip (or its image) isn't in the history file any more.
    var missing = false
}

/// The helper's side: one request per line on stdin, "<history file path>\t<clip id>"; one
/// JSON reply per line on stdout. It reads the image from the history file itself (read-only),
/// so Clips never holds the image for this. Ends when stdin closes.
enum TextHelper {
    static let argument = "--recognize-text"

    static func run() -> Never {
        let reader = LineReader(FileHandle.standardInput)
        let output = FileHandle.standardOutput
        while let line = reader.nextLine() {
            let parts = String(decoding: line, as: UTF8.self).split(separator: "\t", maxSplits: 1).map(String.init)
            var reply = TextHelperReply(lines: nil, missing: true)
            if parts.count == 2, let id = UUID(uuidString: parts[1]),
               let image = ClipDatabase.imageData(inFile: URL(fileURLWithPath: parts[0]), clipID: id) {
                reply = TextHelperReply(lines: try? VisionText.recognize(image), missing: false)
            }
            var data = (try? JSONEncoder().encode(reply)) ?? Data("{}".utf8)
            data.append(0x0A)
            output.write(data)
        }
        exit(0)
    }
}

/// Clips' side: asks the helper about one clip at a time, starting it when needed and
/// quitting it after a few idle seconds.
actor HelperTextRecognizer: TextRecognizer {
    static let idleQuit: Duration = .seconds(10)

    private let historyFile: URL
    private var process: Process?
    private var toHelper: FileHandle?
    private var fromHelper: LineReader?
    private var idleTask: Task<Void, Never>?

    init(historyFile: URL) {
        self.historyFile = historyFile
    }

    func recognizeText(inClip id: UUID) async throws -> [String]? {
        idleTask?.cancel()
        let (input, reader) = try running()
        let request = Data("\(historyFile.path)\t\(id.uuidString)\n".utf8)
        let reply: Data? = await Task.detached(priority: .utility) {
            do { try input.write(contentsOf: request) } catch { return nil }
            return reader.nextLine()
        }.value
        scheduleIdleQuit()
        guard let reply else {
            stop()
            throw VisionText.Failure.helperFailed
        }
        guard let decoded = try? JSONDecoder().decode(TextHelperReply.self, from: reply) else {
            throw VisionText.Failure.helperFailed
        }
        if decoded.missing { return nil }
        guard let lines = decoded.lines else { throw VisionText.Failure.unreadableImage }
        return lines
    }
    private func running() throws -> (FileHandle, LineReader) {
        if let process, process.isRunning, let toHelper, let fromHelper { return (toHelper, fromHelper) }
        stop()
        guard let executable = Bundle.main.executableURL else { throw VisionText.Failure.helperFailed }
        let process = Process()
        process.executableURL = executable
        process.arguments = [TextHelper.argument]
        process.qualityOfService = .utility
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        toHelper = input.fileHandleForWriting
        let reader = LineReader(output.fileHandleForReading)
        fromHelper = reader
        return (input.fileHandleForWriting, reader)
    }

    private func scheduleIdleQuit() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleQuit)
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    /// Closing its input ends the helper.
    private func stop() {
        try? toHelper?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        toHelper = nil
        fromHelper = nil
    }
}

/// Reads newline-ended lines from a pipe (blocking; used off the main thread, one at a time).
final class LineReader: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func nextLine() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
