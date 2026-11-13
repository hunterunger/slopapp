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

/// The helper's side: images in on stdin (an 8-byte little-endian length, then the bytes),
/// one JSON line out per image (the lines found, or null). Ends when stdin closes.
enum TextHelper {
    static let argument = "--recognize-text"

    static func run() -> Never {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        while true {
            guard let header = read(input, count: 8) else { exit(0) }
            let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
            guard length > 0, length < 200_000_000, let image = read(input, count: Int(length)) else { exit(1) }
            let lines = try? VisionText.recognize(image)
            var reply = (try? JSONEncoder().encode(lines)) ?? Data("null".utf8)
            reply.append(0x0A)
            output.write(reply)
        }
    }

    private static func read(_ handle: FileHandle, count: Int) -> Data? {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let chunk = try? handle.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
            data.append(chunk)
        }
        return data
    }
}

/// Clips' side: hands images to the helper one at a time, starting it when needed and
/// quitting it after a few idle seconds.
actor HelperTextRecognizer: TextRecognizer {
    static let idleQuit: Duration = .seconds(10)

    private var process: Process?
    private var toHelper: FileHandle?
    private var fromHelper: LineReader?
    private var idleTask: Task<Void, Never>?

    func recognizeText(in imageData: Data) async throws -> [String] {
        idleTask?.cancel()
        let (input, reader) = try running()
        let reply: Data? = await Task.detached(priority: .utility) {
            var length = UInt64(imageData.count).littleEndian
            var frame = Data(bytes: &length, count: 8)
            frame.append(imageData)
            do { try input.write(contentsOf: frame) } catch { return nil }
            return reader.nextLine()
        }.value
        scheduleIdleQuit()
        guard let reply else {
            stop()
            throw VisionText.Failure.helperFailed
        }
        // null (the helper couldn't read the image) and bad JSON both come out as nil.
        guard let lines = try? JSONDecoder().decode([String]?.self, from: reply) else {
            throw VisionText.Failure.unreadableImage
        }
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
