import AppKit
import ClipsCore
import UniformTypeIdentifiers

/// What an image card puts on the drag: a file promise, so the Desktop and Finder windows get
/// an image file, plus the image data itself for apps that take images (Mail, Messages, Pages).
final class ImageDragProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let clipID: UUID
    private let name: String
    /// The image, when the card had already loaded it. Without it only the file is offered,
    /// and the image is read from the database when the file is written.
    private let image: Representation?

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(clip: Clip, image: Representation?) {
        clipID = clip.id
        name = ImageExport.fileName(created: clip.created, type: image?.type)
        self.image = image
        super.init()
        let ext = ImageExport.fileExtension(forType: image?.type)
        fileType = (UTType(filenameExtension: ext) ?? .png).identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if let image { types.append(NSPasteboard.PasteboardType(image.type)) }
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if let image, type.rawValue == image.type { return image.data }
        return super.pasteboardPropertyList(forType: type)
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { name }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { Self.queue }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        let done = Completion(call: completionHandler)
        if let image {
            done.call(Self.write(image, to: url))
            return
        }
        let id = clipID
        Task { @MainActor in
            let image = await AppModel.shared.payload(for: id)?.items.first.flatMap(ImageExport.image(in:))
            Task.detached(priority: .userInitiated) {
                done.call(image.map { Self.write($0, to: url) } ?? CocoaError(.fileReadNoSuchFile))
            }
        }
    }

    private static func write(_ image: Representation, to url: URL) -> Error? {
        guard let data = ImageExport.fileData(for: image, fileExtension: url.pathExtension.lowercased()) else {
            return CocoaError(.fileWriteUnknown)
        }
        do {
            try data.write(to: url)
            return nil
        } catch {
            return error
        }
    }

    /// AppKit's completion handler, carried across the hop to the main actor and back.
    private struct Completion: @unchecked Sendable {
        let call: (Error?) -> Void
    }
}
