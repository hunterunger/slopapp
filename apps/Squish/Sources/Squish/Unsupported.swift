import Foundation
import SquishCore
import UniformTypeIdentifiers

/// Files dropped or opened that Squish can't take, for an honest message.
enum Unsupported {
    /// Non-folder files that aren't images or PDFs.
    static func files(in urls: [URL]) -> [URL] {
        urls.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
            return SquishTypes.kind(of: url) == nil
        }
    }

    /// "Squish can't compress plain text files." Names the kind when there's one.
    static func message(_ urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        let kinds = Set(urls.map(kind))
        if kinds.count == 1, let kind = kinds.first {
            return "Squish can't compress \(kind) files. It takes images and PDFs."
        }
        return "Squish can't compress \(urls.count) of these files. It takes images and PDFs."
    }

    private static func kind(_ url: URL) -> String {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        var description = type?.localizedDescription?.lowercased()
        for ending in [" document", " file"] where description?.hasSuffix(ending) == true {
            description = String(description!.dropLast(ending.count))
        }
        return description ?? (url.pathExtension.isEmpty ? "these" : url.pathExtension.uppercased())
    }
}
