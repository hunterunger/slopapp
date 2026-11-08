import AppKit
import Observation
import SlopappCore

/// App icons: from the installed copy when there is one (rendered off the main thread and
/// cached on disk), else the feed's icon URL (cached on disk per version), else nothing (the
/// view draws a placeholder).
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
        images[IconSource.memoryKey(for: item)]
    }

    func load(_ items: [CatalogItem]) {
        for item in items { load(item) }
    }

    func load(_ item: CatalogItem) {
        let key = IconSource.memoryKey(for: item)
        guard images[key] == nil, !loading.contains(key) else { return }
        switch IconSource.of(item, allows: urlPolicy.allows) {
        case nil:
            return
        case .installed(let url):
            guard let primary = item.primary else { return }
            let cacheFile = InstalledIcon.cacheFile(slug: item.id, url: url, info: primary.info, cacheDirectory: cacheDirectory)
            // Rendered before: a PNG read (decoded when first drawn), like a feed icon.
            if let cacheFile, let image = NSImage(contentsOf: cacheFile) {
                images[key] = image
                return
            }
            loading.insert(key)
            let slug = item.id, cacheDirectory = cacheDirectory
            Task {
                defer { self.loading.remove(key) }
                // Drawing a system icon the first time costs ~15 ms each; keep it off the main thread.
                let data = await Task.detached(priority: .utility) {
                    InstalledIcon.renderAndCache(slug: slug, url: url, to: cacheFile, in: cacheDirectory)
                }.value
                guard let data, let image = NSImage(data: data) else { return }
                self.images[key] = image
            }
        case .remote(let url, let cacheName):
            let cacheFile = cacheDirectory?.appendingPathComponent(cacheName)
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
    }

    /// A 16 pt copy for menus, rasterized once (menus drop drawing-handler images and draw
    /// others at their own pixel size).
    func menuImage(for item: CatalogItem) -> NSImage? {
        let key = IconSource.memoryKey(for: item)
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

/// An installed copy's icon as PNG data, rendered once and cached next to the feed icons.
/// Runs off the main thread.
enum InstalledIcon {
    /// 512 px covers the largest use (148 pt on the app page, at 2x).
    static let pixels = 512

    /// Where this copy's render is (or will be) cached: keyed by path, version and the
    /// bundle's modification date, so a rebuilt copy at the same version renders afresh.
    nonisolated static func cacheFile(slug: String, url: URL, info: BundleInfo, cacheDirectory: URL?) -> URL? {
        guard let cacheDirectory else { return nil }
        let modified = (try? url.appendingPathComponent("Contents/Info.plist").resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        return cacheDirectory.appendingPathComponent(
            IconSource.installedCacheName(slug: slug, url: url, version: info.version, build: info.build, modified: modified))
    }

    /// Renders the icon and writes it to `cacheFile`, sweeping older renders of the same app.
    nonisolated static func renderAndCache(slug: String, url: URL, to cacheFile: URL?, in cacheDirectory: URL?) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path), let data = render(url) else { return nil }
        if let cacheDirectory, let cacheFile {
            let files = FileManager.default
            try? files.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let prefix = IconSource.installedCachePrefix(slug)
            for old in (try? files.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
            where old.hasPrefix(prefix) && old != cacheFile.lastPathComponent {
                try? files.removeItem(at: cacheDirectory.appendingPathComponent(old))
            }
            try? data.write(to: cacheFile, options: .atomic)
        }
        return data
    }

    /// What Finder shows for the bundle (its AppIcon), drawn into a bitmap.
    nonisolated private static func render(_ url: URL) -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
