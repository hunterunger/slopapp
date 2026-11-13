import Foundation
import ImageIO

/// Turns an image clip into a file, for dragging a card onto the Desktop or into a Finder window.
public enum ImageExport {
    /// File extensions for the image types Clips stores. TIFF is saved as PNG (smaller, opens everywhere).
    static let extensions = [PasteboardType.png: "png", PasteboardType.jpeg: "jpeg", PasteboardType.heic: "heic"]

    /// The extension the file will get: the stored format's, or PNG for TIFF and anything unknown.
    public static func fileExtension(forType type: String?) -> String {
        type.flatMap { extensions[$0] } ?? "png"
    }

    /// "Image 2026-11-10 at 10.32.15.png", like a screenshot's name. No colons, which Finder shows as slashes.
    public static func fileName(created: Date, type: String?, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Image \(formatter.string(from: created)).\(fileExtension(forType: type))"
    }

    /// The first image representation in a payload item.
    public static func image(in reps: [Representation]) -> Representation? {
        reps.first { PasteboardType.imageTypes.contains($0.type) }
    }

    /// The bytes for a file with extension `fileExtension`: the stored data when its format
    /// already matches, otherwise re-encoded as PNG (TIFF, or a type not known when the file was named).
    public static func fileData(for rep: Representation, fileExtension: String) -> Data? {
        if extensions[rep.type] == fileExtension { return rep.data }
        guard let source = CGImageSourceCreateWithData(rep.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
