import AppKit
import Observation
import SlopappCore

/// App icons: from the installed copy when there is one, else the feed's icon URL (cached
/// on disk per version), else nothing (the view draws a placeholder).
@MainActor
@Observable
final class Icons {
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var menuImages: [String: NSImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private let fetcher: any FeedFetching
    @ObservationIgnored private let urlPolicy: URLPolicy
    @ObservationIgnored private let cacheDirectory: URL?

    init(fetcher: any FeedFetching, urlPolicy: URLPolicy, cacheDirectory: URL?) {
        self.fetcher = fetcher
        self.urlPolicy = urlPolicy
        self.cacheDirectory = cacheDirectory
    }

    func image(for item: CatalogItem) -> NSImage? {
        images[key(item)]
    }

    private func key(_ item: CatalogItem) -> String {
        if let primary = item.primary { return "\(item.id)@\(primary.url.path)#\(primary.info.version)" }
        return "\(item.id)#\(item.app.version ?? "")"
    }

    func load(_ items: [CatalogItem]) {
        for item in items { load(item) }
    }

    func load(_ item: CatalogItem) {
        let key = key(item)
        guard images[key] == nil, !loading.contains(key) else { return }
        if let primary = item.primary {
            images[key] = NSWorkspace.shared.icon(forFile: primary.url.path)
            return
        }
        guard let url = item.app.iconUrl, urlPolicy.allows(url) else { return }
        let cacheFile = cacheDirectory?.appendingPathComponent("\(item.id)-\(item.app.version ?? "0").png")
        if let cacheFile, let image = NSImage(contentsOf: cacheFile) {
            images[key] = image
            return
        }
        loading.insert(key)
        let fetcher = fetcher
        Task {
            defer { self.loading.remove(key) }
            guard let data = try? await fetcher.data(from: url), data.count < 4_000_000,
                  let image = NSImage(data: data) else { return }
            if let cacheFile {
                try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheFile)
            }
            self.images[key] = image
        }
    }

    /// A 16 pt copy for menus, rasterized once (menus drop drawing-handler images and draw
    /// others at their own pixel size).
    func menuImage(for item: CatalogItem) -> NSImage? {
        let key = key(item)
        if let cached = menuImages[key] { return cached }
        guard let image = images[key] else { return nil }
        let side: CGFloat = 16, scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side * scale), pixelsHigh: Int(side * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let small = NSImage(size: rep.size)
        small.addRepresentation(rep)
        menuImages[key] = small
        return small
    }
}
