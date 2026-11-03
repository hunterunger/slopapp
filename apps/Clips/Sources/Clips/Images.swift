import AppKit
import ClipsCore

/// App names and icons by bundle id, looked up once.
@MainActor
enum AppIcons {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        icons[bundleID] = image
        return image
    }

    static func name(for bundleID: String) -> String? {
        if let cached = names[bundleID] { return cached }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName {
            names[bundleID] = running
            return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        names[bundleID] = name
        return name
    }

    private static var fileIcons: [String: NSImage] = [:]

    static func icon(forFile path: String) -> NSImage {
        if let cached = fileIcons[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        if fileIcons.count > 300 { fileIcons.removeAll() }
        fileIcons[path] = image
        return image
    }
}

/// Row thumbnails (stored small PNGs) and preview images (decoded from the payload), cached.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private var thumbnails: [UUID: NSImage] = [:]
    private var previews: [UUID: NSImage] = [:]
    private var previewOrder: [UUID] = []

    func cachedThumbnail(for id: UUID) -> NSImage? { thumbnails[id] }

    func thumbnail(for clip: Clip) async -> NSImage? {
        if let cached = thumbnails[clip.id] { return cached }
        var data = await AppModel.shared.thumbnail(for: clip.id)
        if data == nil, let full = await AppModel.shared.payload(for: clip.id)?.items.first?.first?.data {
            // No stored thumbnail (e.g. restored by undo): make one from the image.
            data = await Task.detached(priority: .utility) { ImageInfo.thumbnailPNG(of: full) }.value
        }
        guard let data, let image = NSImage(data: data) else { return nil }
        if thumbnails.count > 500 { thumbnails.removeAll() }
        thumbnails[clip.id] = image
        return image
    }

    func cachedPreview(for id: UUID) -> NSImage? { previews[id] }

    func preview(for clip: Clip) async -> NSImage? {
        if let cached = previews[clip.id] { return cached }
        guard let payload = await AppModel.shared.payload(for: clip.id),
              let data = payload.items.first?.first?.data else { return nil }
        let cgImage = await Task.detached(priority: .userInitiated) {
            ImageInfo.thumbnail(of: data, maxPixelSize: 1_000)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        previews[clip.id] = image
        previewOrder.append(clip.id)
        if previewOrder.count > 8 { previews[previewOrder.removeFirst()] = nil }
        return image
    }
}
